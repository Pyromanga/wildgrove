extends Service
class_name SaveSystem

## SaveSystem — Atomic-Write-gesicherter Aggregator für alle ISaveProvider.
##
## SCOPE: GLOBAL (ADR-009) — läuft für die gesamte App-Lifetime.
##   configure()     → nur Verzeichnis sicherstellen, kein Laden
##   begin_session() → lädt Spielstand für den gewählten Charakter (bei Session-Start)
##   end_session()   → leert geladenen State und Providers (bei Session-Ende)
##
## WARUM GLOBAL (nicht session):
##   list_local_saves() und has_save_for() müssen im Hauptmenü ohne
##   aktive Session nutzbar sein (Character-Select-Screen, ADR-009).
##
## MULTI-CHARAKTER-DESIGN (A-10 + ADR-009):
##   - get_save_path(player_id) berechnet den Pfad dynamisch
##   - Lokal: "user://saves/<player_id>.json"
##   - Server-seitig: Pfad kommt vom Session-Token

const LOG_CAT := "SaveSystem"
const SAVE_DIR := "user://saves/"

## Aktive Player-ID der laufenden Session. Leer wenn keine Session aktiv.
var _active_player_id: String = ""

## ADR-029 Phase 1: stabile Spieler-Identität, unabhängig vom flüchtigen
## ENet-`peer_id`. `_active_player_uuid` ist der öffentliche Bezeichner
## (geht über den Join-Handshake ans Netzwerk), `_active_player_secret` ist
## das dazugehörige Trust-on-First-Use-Geheimnis (bleibt lokal + im Save,
## wird nur im Handshake selbst übertragen — siehe `PlayerCredentialStore`).
## Beide werden bei der ersten `begin_session()` eines Saves erzeugt, wenn
## noch keine vorhanden sind (Alt-Saves vor Round 59 haben keine) — danach
## unveränderlich, reisen mit dem Save mit.
var _active_player_uuid: String = ""
var _active_player_secret: String = ""

var _save_providers: Array = []
var _loaded_state: Dictionary = {}
var _bus:          IEventBus

# ─────────────────────────────────────────────
# Phase 4: Configure (Global-Boot)
# ─────────────────────────────────────────────

## configure() läuft beim globalen Boot — nur Infrastruktur, kein Charakter-State.
## begin_session() lädt den tatsächlichen Spielstand wenn der Charakter ausgewählt wird.
func configure(deps: ServiceDeps) -> void:
	_bus = deps.require(ServiceKeys.EVENT_BUS) as IEventBus
	_ensure_save_dir()
	AppLogger.log_info("SaveSystem bereit (Slot-Management aktiv, noch keine Session).", LOG_CAT)

## Phase 7: Globaler Teardown — leert State und Provider-Liste falls end_session()
## nicht sauber durchgelaufen ist (z.B. Crash oder harter App-Exit).
## Sicher idempotent: mehrfacher Aufruf ist korrekt.
func on_cleanup() -> void:
	_save_providers.clear()
	_loaded_state = {}
	_active_player_id = ""
	_active_player_uuid = ""
	_active_player_secret = ""
	AppLogger.log_info("SaveSystem cleanup — State und Providers geleert.", LOG_CAT)

# ─────────────────────────────────────────────
# Session-Lifecycle (ADR-009)
# ─────────────────────────────────────────────

## Wird von ServiceOrchestrator.boot_session() aufgerufen bevor Session-Services booten.
## Lädt den Spielstand für player_id von Disk und hält ihn in _loaded_state.
## Session-Services können danach via get_state_for(key) darauf zugreifen.
func begin_session(player_id: String) -> void:
	if player_id.strip_edges().is_empty():
		AppLogger.log_warn("begin_session: Leere Player-ID — ignoriert.", LOG_CAT)
		return

	# ADR-029 Phase 1 (Round 62): Idempotenz-Guard. MainMenuController ruft
	# begin_session() jetzt schon VOR dem eigentlichen Session-Boot auf, um
	# player_uuid/player_secret für den Join-Handshake zu lesen (siehe dort,
	# _start_join_handshake()) — danach läuft begin_session() für dieselbe
	# player_id ein zweites Mal durch BootPipeline.boot_character() Phase C1.
	# Ohne diesen Guard würde der zweite Aufruf erneut von Disk lesen: bei
	# einem frisch angelegten Charakter (noch kein save_game() dazwischen)
	# stünde player_uuid/player_secret noch gar nicht auf Disk, wodurch eine
	# ZWEITE, andere Zufalls-Identität erzeugt würde als die, die gerade eben
	# im Handshake verschickt wurde — der Client würde mit einer Identität
	# booten, die der Server nie akzeptiert hat. Bei bereits aktiver Session
	# für dieselbe player_id ist ein Reload daher ein No-Op, kein Neuladen.
	if _active_player_id == player_id and has_active_session():
		AppLogger.log_debug(
			"begin_session('%s'): Session bereits aktiv — Reload übersprungen." % player_id,
			LOG_CAT
		)
		return

	_active_player_id = player_id

	if has_save():
		var raw := _read_from_disk()
		_loaded_state = SaveMigrationService.migrate(raw)
		# R14: Downgrade-Schutz — wenn eine neuere Save-Version mit älterer Software
		# geöffnet wird, erstellen wir ein versioniertes Backup bevor der nächste
		# Schreibzugriff die Datei mit dem älteren Schema überschreibt.
		# Der Spieler kann so auf die neuere Software-Version zurückwechseln
		# und seinen Fortschritt wiederherstellen.
		if SaveMigrationService.consume_downgrade_flag():
			_create_downgrade_backup(raw)
		AppLogger.log_info(
			"Session gestartet: '%s' (Schema v%d)." % [
				player_id, _loaded_state.get("schema_version", 0)
			], LOG_CAT
		)
	else:
		_loaded_state = {}
		AppLogger.log_info(
			"Session gestartet: '%s' (kein Spielstand — Neustart)." % player_id, LOG_CAT
		)

	# ADR-029 Phase 1: player_uuid/player_secret aus dem geladenen State
	# übernehmen, oder — bei neuen Saves sowie Alt-Saves von vor Round 59 —
	# einmalig erzeugen. Bewusst NICHT in save_game() generiert: die Identität
	# muss ab dem ersten Moment der Session stehen, nicht erst beim nächsten
	# Speichervorgang (der Join-Handshake braucht sie ggf. vor dem ersten Save).
	var uuid: Variant = _loaded_state.get("player_uuid")
	var secret: Variant = _loaded_state.get("player_secret")
	if uuid is String and not (uuid as String).is_empty() \
			and secret is String and not (secret as String).is_empty():
		_active_player_uuid = uuid
		_active_player_secret = secret
	else:
		_active_player_uuid = UuidGen.generate_v4()
		_active_player_secret = UuidGen.generate_v4()
		AppLogger.log_info(
			"Neue stabile Spieler-Identität erzeugt für '%s' (player_uuid: %s)." % [
				player_id, _active_player_uuid
			], LOG_CAT
		)
	# SICHERHEITSKRITISCH: player_uuid/player_secret dürfen NICHT in _loaded_state
	# verbleiben. get_full_state() gibt _loaded_state ungefiltert an jeden neu
	# verbindenden Client weiter (Sprint-D-Initial-Snapshot, NetworkBridge
	# _rpc_client_requests_initial_state()) — ohne dieses erase() würde das
	# player_secret der Autorität an jeden Joiner verschickt und das gesamte
	# Trust-on-First-Use-Modell (ADR-029, 3a) aushebeln. Die dedizierten
	# _active_player_uuid/_active_player_secret-Felder sind ab hier die einzige
	# Quelle — get_full_state()/apply_remote_state() sehen sie nie.
	_loaded_state.erase("player_uuid")
	_loaded_state.erase("player_secret")

## Wird von ServiceOrchestrator._teardown_session_internal() aufgerufen.
## Leert geladenen State und Provider-Liste — SaveSystem bleibt als Global-Service erhalten.
func end_session() -> void:
	_loaded_state = {}
	_save_providers.clear()
	_active_player_id = ""
	_active_player_uuid = ""
	_active_player_secret = ""
	AppLogger.log_info("Session beendet — State und Providers geleert.", LOG_CAT)

# ─────────────────────────────────────────────
# Player-ID / Pfad-Management
# ─────────────────────────────────────────────

## Berechnet den Save-Pfad für eine Player-ID.
func get_save_path(player_id: String) -> String:
	return SAVE_DIR + player_id + ".json"

func get_active_save_path() -> String:
	return get_save_path(_active_player_id)

func get_active_player_id() -> String:
	return _active_player_id

## ADR-029 Phase 1: öffentlicher, netzwerkfähiger Bezeichner — geht im
## Join-Handshake ans Netzwerk. Leer, wenn keine Session aktiv ist.
func get_active_player_uuid() -> String:
	return _active_player_uuid

## ADR-029 Phase 1: NIE über einen Klartext-Kanal loggen oder anzeigen —
## nur im Join-Handshake als Beweis der Identität verschickt. Leer, wenn
## keine Session aktiv ist.
func get_active_player_secret() -> String:
	return _active_player_secret

func has_active_session() -> bool:
	return not _active_player_id.is_empty()

# ─────────────────────────────────────────────
# Provider Management (ISaveProvider-Pattern)
# ─────────────────────────────────────────────

func register_save_provider(provider: Object) -> void:
	if not provider in _save_providers:
		_save_providers.append(provider)
		AppLogger.log_debug("Provider registriert: %s" % provider.get_save_key(), LOG_CAT)

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

func get_state_for(key: String) -> Dictionary:
	var sub: Variant = _loaded_state.get(key)
	return sub if sub is Dictionary else {}

## Gibt den vollständigen geladenen State zurück — für den Multiplayer-Initial-Snapshot.
## Wird von NetworkBridge.send_initial_state() genutzt um neu joinenden Clients
## den aktuellen Spielstand zu übermitteln (Sprint D).
## Gibt eine flache Kopie zurück; enthält nur den bereits in _loaded_state liegenden
## Stand — kein Pre-Flush. Vor dem Aufruf sollte save_pre_flush emittiert werden.
func get_full_state() -> Dictionary:
	return _loaded_state.duplicate(false)

## Sprint D: Übernimmt einen vom Server empfangenen State-Snapshot.
## Läuft auf Clients nach dem Join — ersetzt den lokal geladenen (leeren) State
## durch den Server-State damit begin_session() der Session-Services darauf zugreifen kann.
## Nur anwendbar wenn noch keine eigene Session aktiv ist (sicherer Guard).
func apply_remote_state(state: Dictionary) -> void:
	# E-4: Client ruft dies nach Session-Boot auf (Phase S8.9) — Session ist bereits
	# aktiv. _loaded_state wird mit dem Server-Stand überschrieben damit Session-Services
	# den korrekten State via get_state_for() lesen können wenn sie ihn nächstes Mal brauchen.
	_loaded_state = state.duplicate(false)
	# Verteidigung in der Tiefe zum erase() in begin_session(): _active_player_uuid/
	# _active_player_secret dieses Prozesses bleiben unverändert, unabhängig davon,
	# was der Server schickt — die eigene Identität wird nie durch eine empfangene
	# ersetzt. Erase hier zusätzlich, falls ein künftiger Code-Pfad diese Keys je
	# doch in einen state hineinschmuggelt (siehe begin_session()-Kommentar).
	_loaded_state.erase("player_uuid")
	_loaded_state.erase("player_secret")
	AppLogger.log_info(
		"Remote-State übernommen (Schema v%d, %d Keys)." % [
			_loaded_state.get("schema_version", 0), _loaded_state.size()
		],
		LOG_CAT
	)

func save_game() -> bool:
	if not has_active_session():
		AppLogger.log_warn("save_game() ohne aktive Session — ignoriert.", LOG_CAT)
		return false

	AppLogger.log_info("Speichervorgang gestartet (Charakter: '%s')..." % _active_player_id, LOG_CAT)
	_bus.persistence().emit_save_started()

	var full_state: Dictionary = {
		"schema_version": SaveMigrationService.CURRENT_VERSION,
		"player_id":      _active_player_id,
		"player_uuid":    _active_player_uuid,
		"player_secret":  _active_player_secret,
		"timestamp":      Time.get_datetime_string_from_system(),
	}

	for provider in _save_providers:
		if is_instance_valid(provider):
			full_state[provider.get_save_key()] = provider.get_save_data()

	var success := _write_to_disk(full_state)
	_bus.persistence().emit_save_completed(success)
	return success

# ─────────────────────────────────────────────
# Slot-Management (für Character-Select-Screen)
# ─────────────────────────────────────────────

func has_save() -> bool:
	if _active_player_id.is_empty():
		return false
	return FileAccess.file_exists(get_active_save_path())

func has_save_for(player_id: String) -> bool:
	return FileAccess.file_exists(get_save_path(player_id))

## Listet alle lokalen Save-Dateien auf.
## Gibt Array[String] mit Player-IDs zurück (ohne .json-Extension).
## Nutzbar auch ohne aktive Session (SaveSystem ist global).
func list_local_saves() -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(SAVE_DIR)
	if not dir:
		return result
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".json") and not fname.ends_with(".bak"):
			result.append(fname.trim_suffix(".json"))
		fname = dir.get_next()
	dir.list_dir_end()
	return result

## Löscht den persistierten State für eine Player-ID inklusive Begleitdateien.
func delete_save_for(player_id: String) -> bool:
	if player_id.strip_edges().is_empty():
		AppLogger.log_warn("delete_save_for: Leere Player-ID — ignoriert.", LOG_CAT)
		return false

	var path := get_save_path(player_id)
	if not FileAccess.file_exists(path):
		AppLogger.log_warn("delete_save_for: Keine Save-Datei für '%s'." % player_id, LOG_CAT)
		return false

	if player_id == _active_player_id:
		AppLogger.log_warn(
			"delete_save_for: Aktiver Spielstand '%s' wird gelöscht." % player_id, LOG_CAT
		)

	var err := DirAccess.remove_absolute(path)
	if err != OK:
		AppLogger.log_error(
			"delete_save_for: Fehler beim Löschen von '%s' (Error %d)." % [path, err], LOG_CAT
		)
		return false

	if FileAccess.file_exists(path + ".bak"):
		DirAccess.remove_absolute(path + ".bak")
	if FileAccess.file_exists(path + ".tmp"):
		DirAccess.remove_absolute(path + ".tmp")

	AppLogger.log_info("Save-Slot '%s' gelöscht." % player_id, LOG_CAT)
	_bus.persistence().emit_save_slot_deleted(player_id)
	return true

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		var err := DirAccess.make_dir_recursive_absolute(SAVE_DIR)
		if err != OK:
			AppLogger.log_error(
				"Konnte Save-Verzeichnis nicht anlegen: %s (Error %d)" % [SAVE_DIR, err], LOG_CAT
			)

## R14: Erstellt ein versioniertes Backup wenn beim Laden ein Downgrade erkannt wird.
## Dateiname: <save_path>.v<version>.bak — eindeutig pro Schema-Version.
## Überschreibt nie ein bestehendes Backup (schützt den "letzten guten Stand" der neueren Version).
## Gibt true zurück wenn das Backup erfolgreich erstellt oder bereits vorhanden war.
func _create_downgrade_backup(raw_data: Dictionary) -> bool:
	var version: int = raw_data.get("schema_version", 0)
	var base_path := get_active_save_path()
	var backup_path := base_path + ".v%d.bak" % version

	if FileAccess.file_exists(backup_path):
		AppLogger.log_info(
			"Downgrade-Backup bereits vorhanden: '%s' — nicht überschrieben." % backup_path, LOG_CAT
		)
		return true

	var err := DirAccess.copy_absolute(base_path, backup_path)
	if err != OK:
		AppLogger.log_warn(
			("Downgrade-Backup fehlgeschlagen: '%s' (Error %d). " +
			"Fortschritt der neueren Software-Version könnte verloren gehen.")
			% [backup_path, err], LOG_CAT
		)
		return false

	AppLogger.log_info(
		"Downgrade erkannt (v%d > v%d): Backup erstellt: '%s'." \
		% [version, SaveMigrationService.CURRENT_VERSION, backup_path], LOG_CAT
	)
	return true

func _write_to_disk(state: Dictionary) -> bool:
	return _atomic_write(get_active_save_path(), state)

func _atomic_write(path: String, data: Dictionary) -> bool:
	var tmp_path := path + ".tmp"

	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if not file:
		AppLogger.log_error("Atomic Write: Konnte tmp-Datei nicht öffnen: %s" % tmp_path, LOG_CAT)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

	if FileAccess.file_exists(path):
		var backup_err := DirAccess.copy_absolute(path, path + ".bak")
		if backup_err != OK:
			AppLogger.log_warn("Backup fehlgeschlagen (Error %d) — fahre fort." % backup_err, LOG_CAT)

	var rename_err := DirAccess.rename_absolute(tmp_path, path)
	if rename_err != OK:
		AppLogger.log_error("Atomic Rename fehlgeschlagen (Error %d)!" % rename_err, LOG_CAT)
		return false

	return true

func _read_from_disk() -> Dictionary:
	var path := get_active_save_path()
	var result: Variant = _try_read_json(path)
	if result != null:
		return result

	# Main file missing or corrupt — attempt .bak recovery.
	var bak_path := path + ".bak"
	if FileAccess.file_exists(bak_path):
		AppLogger.log_warn("Hauptdatei '%s' fehlt/korrupt — versuche .bak-Recovery." % path, LOG_CAT)
		var bak_result: Variant = _try_read_json(bak_path)
		if bak_result != null:
			AppLogger.log_info(".bak-Recovery erfolgreich für '%s'." % path, LOG_CAT)
			return bak_result
		AppLogger.log_error("Auch .bak '%s' ist korrupt — starte ohne Spielstand." % bak_path, LOG_CAT)
	else:
		if FileAccess.file_exists(path):
			AppLogger.log_error("Spielstand '%s' ist korrupt und kein .bak vorhanden — starte ohne Spielstand." % path, LOG_CAT)

	return {}

## Versucht eine JSON-Datei zu lesen. Gibt null zurück wenn Datei fehlt, nicht geöffnet
## werden kann, oder ungültiges JSON enthält. Gibt das geparste Dictionary zurück wenn OK.
func _try_read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return null
	var json_text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(json_text) != OK:
		return null
	return json.data if json.data is Dictionary else null

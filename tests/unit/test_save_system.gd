# res://tests/unit/test_save_system.gd
extends GutTest

## Tests für SaveSystem Slot-Infrastruktur (A-10).
##
## Strategie: SaveSystem direkt instanziieren. configure() wird mit einem MockEventBus
## aufgerufen, da save_game()/delete_save_for() System-Events emittieren — die reine
## Slot-API selbst braucht sonst keine weiteren Dependencies.
##
## A-02 (Session 6): SaveSystem extends jetzt Service (RefCounted) statt ServiceNode.
## Kein add_child_autofree() mehr nötig — RefCounted wird automatisch freigegeben,
## sobald die letzte Referenz (_sys) in after_each() / beim nächsten before_each()
## überschrieben wird. Kein .free()-Aufruf nötig oder zulässig (RefCounted hat keine free()).
##
## WICHTIG: Diese Tests schreiben echte Dateien nach user://saves/ (Godot-User-Dir
## im Test-Environment). Der TEST_PREFIX verhindert Kollisionen mit echten Saves.
##
## Abgedeckte Pfade:
##   get_save_path()         — korrekter Pfad pro Player-ID, keine Kollisionen
##   begin_session()         — Validierung (leer, whitespace), Wechsel, ID-Persistenz
##   get_active_save_path()  — spiegelt aktive ID
##   has_save_for()          — existiert / existiert nicht
##   list_local_saves()      — listet .json, ignoriert .bak
##   delete_save_for()       — löscht Datei + .bak, lehnt Leer-ID ab, kein Cross-Delete
##   Vollständiger Lifecycle  — create → list → switch → delete

const SAVE_DIR   := "user://saves/"
const TEST_PREFIX := "unit_test_"
const PLAYER_A   := "unit_test_alpha"
const PLAYER_B   := "unit_test_beta"

class MinimalSaveProvider:
	## Minimal ISaveProvider-Double — register_save_provider() ruft get_save_key()
	## bereits bei der Registrierung fürs Logging auf, ein bloßes RefCounted.new()
	## erfüllt diesen Teil des Interfaces nicht.
	func get_save_key() -> String: return "minimal_test_provider"
	func get_save_data() -> Dictionary: return {}

var _sys: SaveSystem

func before_each() -> void:
	_sys = SaveSystem.new()
	_sys.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: MockEventBus.new()}))
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func after_each() -> void:
	_cleanup_test_files()
	_sys = null

# ─────────────────────────────────────────────
# get_save_path()
# ─────────────────────────────────────────────

func test_get_save_path_contains_player_id() -> void:
	var path := _sys.get_save_path(PLAYER_A)
	assert_true(path.contains(PLAYER_A), "Pfad muss die Player-ID enthalten")

func test_get_save_path_ends_with_dot_json() -> void:
	var path := _sys.get_save_path(PLAYER_A)
	assert_true(path.ends_with(".json"), "Pfad muss .json-Extension haben")

func test_different_ids_yield_different_paths() -> void:
	var path_a := _sys.get_save_path(PLAYER_A)
	var path_b := _sys.get_save_path(PLAYER_B)
	assert_ne(path_a, path_b, "Unterschiedliche Player-IDs → unterschiedliche Pfade")

func test_same_id_yields_same_path() -> void:
	var path_1 := _sys.get_save_path(PLAYER_A)
	var path_2 := _sys.get_save_path(PLAYER_A)
	assert_eq(path_1, path_2, "Gleiche ID → deterministischer Pfad")

# ─────────────────────────────────────────────
# begin_session() / end_session() / get_active_player_id()  [ADR-009]
# set_active_player_id() wurde durch begin_session() ersetzt.
# ─────────────────────────────────────────────

func test_default_player_id_is_empty_without_session() -> void:
	assert_eq(_sys.get_active_player_id(), "",
		"Frische Instanz ohne Session muss leer sein (ADR-009)")

func test_begin_session_sets_player_id() -> void:
	_sys.begin_session(PLAYER_A)
	assert_eq(_sys.get_active_player_id(), PLAYER_A)

func test_begin_session_empty_string_is_rejected() -> void:
	_sys.begin_session(PLAYER_A)
	_sys.begin_session("")
	assert_eq(_sys.get_active_player_id(), PLAYER_A,
		"Leere ID darf die aktive ID nicht überschreiben")

func test_begin_session_whitespace_only_is_rejected() -> void:
	_sys.begin_session(PLAYER_A)
	_sys.begin_session("   ")
	assert_eq(_sys.get_active_player_id(), PLAYER_A,
		"Whitespace-only ID darf die aktive ID nicht überschreiben")

func test_get_active_save_path_reflects_session_id() -> void:
	_sys.begin_session(PLAYER_A)
	var active := _sys.get_active_save_path()
	var expected := _sys.get_save_path(PLAYER_A)
	assert_eq(active, expected,
		"get_active_save_path() muss auf die aktive Session-ID zeigen")

func test_end_session_clears_player_id() -> void:
	_sys.begin_session(PLAYER_A)
	_sys.end_session()
	assert_eq(_sys.get_active_player_id(), "",
		"end_session() muss aktive Player-ID leeren")

func test_has_active_session_false_without_session() -> void:
	assert_false(_sys.has_active_session(), "Keine Session → has_active_session() false")

func test_has_active_session_true_after_begin() -> void:
	_sys.begin_session(PLAYER_A)
	assert_true(_sys.has_active_session(), "Nach begin_session() → has_active_session() true")

func test_has_active_session_false_after_end() -> void:
	_sys.begin_session(PLAYER_A)
	_sys.end_session()
	assert_false(_sys.has_active_session(), "Nach end_session() → has_active_session() false")

# ─────────────────────────────────────────────
# has_save_for()
# ─────────────────────────────────────────────

func test_has_save_for_returns_false_when_no_file() -> void:
	assert_false(_sys.has_save_for(PLAYER_A), "Nicht-existente Datei → false")

func test_has_save_for_returns_true_after_write() -> void:
	_write_dummy(PLAYER_A)
	assert_true(_sys.has_save_for(PLAYER_A), "Nach Datei-Anlage → true")

func test_has_save_for_is_per_player_id() -> void:
	_write_dummy(PLAYER_A)
	assert_false(_sys.has_save_for(PLAYER_B),
		"has_save_for() darf nur die angefragte ID prüfen")

# ─────────────────────────────────────────────
# list_local_saves()
# ─────────────────────────────────────────────

func test_list_includes_written_save() -> void:
	_write_dummy(PLAYER_A)
	var saves := _sys.list_local_saves()
	assert_true(saves.has(PLAYER_A), "Geschriebener Save muss in der Liste erscheinen")

func test_list_shows_multiple_saves() -> void:
	_write_dummy(PLAYER_A)
	_write_dummy(PLAYER_B)
	var saves := _sys.list_local_saves()
	assert_true(saves.has(PLAYER_A), "PLAYER_A muss gelistet sein")
	assert_true(saves.has(PLAYER_B), "PLAYER_B muss gelistet sein")

func test_list_excludes_bak_files() -> void:
	_write_dummy(PLAYER_A)
	# .bak-Datei manuell anlegen (wie sie atomic_write erzeugt)
	var bak_path := _sys.get_save_path(PLAYER_A) + ".bak"
	var bak_file := FileAccess.open(bak_path, FileAccess.WRITE)
	if bak_file:
		bak_file.store_string("{}")
		bak_file.close()
	var saves := _sys.list_local_saves()
	for entry in saves:
		assert_false(entry.ends_with(".bak"),
			".bak-Einträge dürfen nicht in der Liste erscheinen: " + entry)

func test_list_contains_only_ids_not_filenames() -> void:
	_write_dummy(PLAYER_A)
	var saves := _sys.list_local_saves()
	for entry in saves:
		if entry.begins_with(TEST_PREFIX):
			assert_false(entry.ends_with(".json"),
				"Einträge müssen IDs sein, nicht Dateinamen: " + entry)

# ─────────────────────────────────────────────
# delete_save_for()
# ─────────────────────────────────────────────

func test_delete_nonexistent_returns_false() -> void:
	var result := _sys.delete_save_for(PLAYER_A)
	assert_false(result, "Nicht-existenten Save zu löschen → false")

func test_delete_empty_id_returns_false() -> void:
	var result := _sys.delete_save_for("")
	assert_false(result, "Leere ID → false, kein Crash")

func test_delete_removes_main_file() -> void:
	_write_dummy(PLAYER_A)
	_sys.delete_save_for(PLAYER_A)
	assert_false(_sys.has_save_for(PLAYER_A), "Datei muss nach delete_save_for() fehlen")

func test_delete_returns_true_on_success() -> void:
	_write_dummy(PLAYER_A)
	var result := _sys.delete_save_for(PLAYER_A)
	assert_true(result, "Erfolgreiches Löschen → true")

func test_delete_removes_bak_companion() -> void:
	_write_dummy(PLAYER_A)
	var bak_path := _sys.get_save_path(PLAYER_A) + ".bak"
	var bak_file := FileAccess.open(bak_path, FileAccess.WRITE)
	if bak_file:
		bak_file.store_string("{}")
		bak_file.close()
	_sys.delete_save_for(PLAYER_A)
	assert_false(FileAccess.file_exists(bak_path),
		".bak muss zusammen mit dem Haupt-Save gelöscht werden")

func test_delete_does_not_affect_other_saves() -> void:
	_write_dummy(PLAYER_A)
	_write_dummy(PLAYER_B)
	_sys.delete_save_for(PLAYER_A)
	assert_true(_sys.has_save_for(PLAYER_B),
		"delete_save_for(A) darf save von B nicht berühren")

func test_delete_removes_from_list() -> void:
	_write_dummy(PLAYER_A)
	_sys.delete_save_for(PLAYER_A)
	var saves := _sys.list_local_saves()
	assert_false(saves.has(PLAYER_A), "Gelöschter Save darf nicht mehr in der Liste sein")

# ─────────────────────────────────────────────
# Vollständiger Slot-Lifecycle
# ─────────────────────────────────────────────

func test_full_slot_lifecycle_create_switch_delete() -> void:
	# Phase 1: Kein Save vorhanden
	assert_false(_sys.has_save_for(PLAYER_A),     "Phase 1: kein Save")
	assert_false(_sys.list_local_saves().has(PLAYER_A), "Phase 1: nicht in Liste")

	# Phase 2: Save erzeugen
	_write_dummy(PLAYER_A)
	assert_true(_sys.has_save_for(PLAYER_A),      "Phase 2: Save existiert")
	assert_true(_sys.list_local_saves().has(PLAYER_A),  "Phase 2: in Liste sichtbar")

	# Phase 3: Session starten → aktiver Pfad ändert sich (ADR-009: begin_session statt set_active_player_id)
	_sys.begin_session(PLAYER_A)
	assert_eq(_sys.get_active_save_path(), _sys.get_save_path(PLAYER_A),
		"Phase 3: aktiver Pfad muss auf PLAYER_A zeigen")

	# Phase 4: Löschen → aus allen Abfragen entfernt
	var deleted := _sys.delete_save_for(PLAYER_A)
	assert_true(deleted,                             "Phase 4: Löschen erfolgreich")
	assert_false(_sys.has_save_for(PLAYER_A),        "Phase 4: hat_save_for gibt false")
	assert_false(_sys.list_local_saves().has(PLAYER_A), "Phase 4: nicht mehr in Liste")

# ─────────────────────────────────────────────
# on_cleanup() — OBS-3
# ─────────────────────────────────────────────

func test_on_cleanup_clears_providers() -> void:
	_sys.begin_session(PLAYER_A)
	_sys.register_save_provider(MinimalSaveProvider.new())
	_sys.on_cleanup()
	# Verify: save_game() returns true with no providers (empty list is valid)
	_sys.begin_session(PLAYER_A)
	assert_true(_sys.save_game(), "on_cleanup() muss Provider-Array leeren")

func test_on_cleanup_clears_active_session() -> void:
	_sys.begin_session(PLAYER_A)
	assert_true(_sys.has_active_session(), "Vor cleanup: Session aktiv")
	_sys.on_cleanup()
	assert_false(_sys.has_active_session(),
		"on_cleanup() muss aktive Player-ID leeren")

func test_on_cleanup_is_idempotent() -> void:
	_sys.on_cleanup()
	_sys.on_cleanup()
	assert_false(_sys.has_active_session(),
		"Wiederholtes on_cleanup() darf keinen Fehler verursachen")

# ─────────────────────────────────────────────
# ADR-029 Phase 1: player_uuid / player_secret
# ─────────────────────────────────────────────

func test_new_save_generates_player_uuid_and_secret() -> void:
	_sys.begin_session(PLAYER_A)  # kein Save auf Disk — Neustart-Pfad
	assert_false(_sys.get_active_player_uuid().is_empty(),
		"Neue Session muss eine player_uuid erzeugen.")
	assert_false(_sys.get_active_player_secret().is_empty(),
		"Neue Session muss ein player_secret erzeugen.")

func test_player_uuid_and_secret_are_different_values() -> void:
	_sys.begin_session(PLAYER_A)
	assert_ne(_sys.get_active_player_uuid(), _sys.get_active_player_secret(),
		"player_uuid und player_secret dürfen nicht identisch sein.")

func test_player_uuid_persists_across_sessions() -> void:
	_sys.begin_session(PLAYER_A)
	var uuid_before := _sys.get_active_player_uuid()
	var secret_before := _sys.get_active_player_secret()
	_sys.save_game()
	_sys.end_session()

	_sys.begin_session(PLAYER_A)
	assert_eq(_sys.get_active_player_uuid(), uuid_before,
		"player_uuid muss über einen Save/Load-Zyklus stabil bleiben.")
	assert_eq(_sys.get_active_player_secret(), secret_before,
		"player_secret muss über einen Save/Load-Zyklus stabil bleiben.")

func test_different_characters_get_different_player_uuids() -> void:
	_sys.begin_session(PLAYER_A)
	var uuid_a := _sys.get_active_player_uuid()
	_sys.save_game()
	_sys.end_session()

	_sys.begin_session(PLAYER_B)
	var uuid_b := _sys.get_active_player_uuid()
	assert_ne(uuid_a, uuid_b,
		"Zwei unterschiedliche Charakter-Saves müssen unterschiedliche player_uuids haben.")

func test_legacy_save_without_uuid_gets_one_generated() -> void:
	## Simuliert einen Save von vor Round 59 — kein player_uuid/player_secret-Feld.
	_write_dummy(PLAYER_A)
	_sys.begin_session(PLAYER_A)
	assert_false(_sys.get_active_player_uuid().is_empty(),
		"Alt-Save ohne player_uuid muss beim Laden eine neue bekommen.")
	assert_false(_sys.get_active_player_secret().is_empty(),
		"Alt-Save ohne player_secret muss beim Laden eines bekommen.")

func test_end_session_clears_player_uuid_and_secret() -> void:
	_sys.begin_session(PLAYER_A)
	_sys.end_session()
	assert_true(_sys.get_active_player_uuid().is_empty(),
		"end_session() muss player_uuid leeren.")
	assert_true(_sys.get_active_player_secret().is_empty(),
		"end_session() muss player_secret leeren.")

func test_player_uuid_and_secret_are_not_leaked_via_full_state() -> void:
	## SICHERHEITSKRITISCH: get_full_state() wird per Sprint-D-Snapshot an JEDEN
	## neu verbindenden Client geschickt (NetworkBridge._rpc_client_requests_initial_state()).
	## Würden player_uuid/player_secret hier auftauchen, könnte jeder Joiner die
	## Identität der Autorität stehlen — hebelt das gesamte TOFU-Modell aus (ADR-029, 3a).
	_sys.begin_session(PLAYER_A)
	_sys.save_game()
	var full_state := _sys.get_full_state()
	assert_false(full_state.has("player_uuid"),
		"get_full_state() darf player_uuid NICHT enthalten — Identitätsdiebstahl-Risiko.")
	assert_false(full_state.has("player_secret"),
		"get_full_state() darf player_secret NICHT enthalten — Identitätsdiebstahl-Risiko.")

func test_apply_remote_state_strips_uuid_and_secret_defense_in_depth() -> void:
	_sys.begin_session(PLAYER_A)
	var own_uuid := _sys.get_active_player_uuid()
	var malicious_state := {
		"schema_version": SaveMigrationService.CURRENT_VERSION,
		"player_uuid": "attacker-supplied-uuid",
		"player_secret": "attacker-supplied-secret",
	}
	_sys.apply_remote_state(malicious_state)
	assert_false(_sys.get_full_state().has("player_uuid"),
		"apply_remote_state() muss player_uuid aus dem übernommenen State entfernen.")
	assert_false(_sys.get_full_state().has("player_secret"),
		"apply_remote_state() muss player_secret aus dem übernommenen State entfernen.")
	assert_eq(_sys.get_active_player_uuid(), own_uuid,
		"Die eigene player_uuid darf durch apply_remote_state() nicht überschrieben werden.")

func test_save_game_persists_uuid_and_secret_to_disk() -> void:
	_sys.begin_session(PLAYER_A)
	var uuid := _sys.get_active_player_uuid()
	var secret := _sys.get_active_player_secret()
	_sys.save_game()
	var path := _sys.get_save_path(PLAYER_A)
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "Save-Datei muss existieren nach save_game()")
	var content: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	assert_eq(content.get("player_uuid"), uuid,
		"Save-Datei auf Disk muss player_uuid enthalten (für zukünftige Sessions).")
	assert_eq(content.get("player_secret"), secret,
		"Save-Datei auf Disk muss player_secret enthalten (für zukünftige Sessions).")

# ─────────────────────────────────────────────
# ADR-029 Phase 1 (Round 62): begin_session() Idempotenz-Guard
# ─────────────────────────────────────────────

func test_begin_session_twice_for_new_character_keeps_same_identity() -> void:
	## Reproduziert exakt den Join-Handshake-Bug ohne den Guard: MainMenuController
	## ruft begin_session() für einen frisch angelegten Charakter auf (kein Save
	## auf Disk), danach ruft BootPipeline.boot_character() begin_session() für
	## dieselbe player_id ein zweites Mal auf. Ohne Guard würde der zweite Aufruf
	## (kein Save vorhanden → "Neustart"-Pfad) eine zweite, andere Zufalls-Identität
	## erzeugen — der Client würde mit einer Identität booten, die der Server im
	## Handshake nie gesehen hat.
	_sys.begin_session(PLAYER_A)
	var uuid_first := _sys.get_active_player_uuid()
	var secret_first := _sys.get_active_player_secret()

	_sys.begin_session(PLAYER_A)

	assert_eq(_sys.get_active_player_uuid(), uuid_first,
		"Zweiter begin_session()-Aufruf für dieselbe player_id darf player_uuid nicht neu erzeugen.")
	assert_eq(_sys.get_active_player_secret(), secret_first,
		"Zweiter begin_session()-Aufruf für dieselbe player_id darf player_secret nicht neu erzeugen.")

func test_begin_session_twice_for_same_id_is_noop_when_session_active() -> void:
	_sys.begin_session(PLAYER_A)
	assert_true(_sys.has_active_session())

	_sys.begin_session(PLAYER_A)

	assert_true(_sys.has_active_session(),
		"Guard darf die aktive Session nicht beenden.")
	assert_eq(_sys.get_active_player_id(), PLAYER_A,
		"Guard darf die aktive Player-ID nicht verändern.")

func test_begin_session_twice_does_not_reload_state_from_disk() -> void:
	## Guard muss den zweiten Aufruf komplett überspringen, nicht nur die
	## Identitätserzeugung — sonst würde er den in-memory State mit dem
	## (ggf. veralteten) Disk-Stand überschreiben, obwohl seit dem ersten
	## begin_session() bereits mit dem Provider-State weitergearbeitet wurde.
	_write_dummy(PLAYER_A)
	_sys.begin_session(PLAYER_A)
	_sys.apply_remote_state({
		"schema_version": SaveMigrationService.CURRENT_VERSION,
		"some_provider_key": {"marker": "in_memory_only"},
	})

	_sys.begin_session(PLAYER_A)

	assert_eq(_sys.get_state_for("some_provider_key").get("marker"), "in_memory_only",
		"Zweiter begin_session()-Aufruf für dieselbe player_id darf den in-memory State nicht mit der Disk-Version überschreiben.")

func test_begin_session_guard_does_not_apply_across_different_ids() -> void:
	## Der Guard darf nur greifen, wenn player_id UND Session-Status übereinstimmen —
	## ein Wechsel auf einen anderen Charakter (auch ohne end_session() dazwischen)
	## muss ganz normal laden, nicht stillschweigend übersprungen werden.
	_sys.begin_session(PLAYER_A)
	var uuid_a := _sys.get_active_player_uuid()

	_sys.begin_session(PLAYER_B)

	assert_eq(_sys.get_active_player_id(), PLAYER_B,
		"Wechsel auf eine andere player_id muss die aktive ID aktualisieren, Guard darf das nicht blockieren.")
	assert_ne(_sys.get_active_player_uuid(), uuid_a,
		"Wechsel auf eine andere player_id muss eine eigene Identität laden/erzeugen, nicht die des vorigen Charakters behalten.")

func test_begin_session_guard_does_not_apply_after_end_session() -> void:
	## Nach end_session() ist has_active_session() false — ein erneuter
	## begin_session() für dieselbe player_id (z.B. Re-Join nach Verbindungsabbruch)
	## muss ganz normal neu laden, nicht vom Guard blockiert werden.
	_sys.begin_session(PLAYER_A)
	var uuid_first := _sys.get_active_player_uuid()
	_sys.save_game()
	_sys.end_session()

	_sys.begin_session(PLAYER_A)

	assert_true(_sys.has_active_session(),
		"begin_session() nach end_session() muss wieder eine aktive Session herstellen.")
	assert_eq(_sys.get_active_player_uuid(), uuid_first,
		"Identität muss nach Re-Join wieder von Disk geladen werden (hier zufällig gleich wie vorher, da persistiert).")

# ─────────────────────────────────────────────
# Hilfsfunktionen
# ─────────────────────────────────────────────

## Schreibt eine minimale valide Save-Datei direkt auf Disk (umgeht SaveSystem-Lifecycle).
func _write_dummy(player_id: String) -> void:
	var path := _sys.get_save_path(player_id)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(
			"{\"schema_version\":2,\"player_id\":\"%s\",\"timestamp\":\"2026-06-19\"}" \
			% player_id
		)
		file.close()

## Bereinigt alle Dateien mit TEST_PREFIX aus user://saves/.
## Wird von after_each() aufgerufen.
func _cleanup_test_files() -> void:
	var dir := DirAccess.open(SAVE_DIR)
	if not dir:
		return
	dir.list_dir_begin()
	var to_delete: Array[String] = []
	var fname := dir.get_next()
	while fname != "":
		if fname.begins_with(TEST_PREFIX):
			to_delete.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	for f in to_delete:
		DirAccess.remove_absolute(SAVE_DIR + f)

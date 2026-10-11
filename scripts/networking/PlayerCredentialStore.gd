class_name PlayerCredentialStore
# justified: reines Datei-I/O + In-Memory-Lookup, keine Node-Lifecycle-Anforderungen —
# von SessionManager gehalten und explizit load()/save() aufgerufen, kein DI-Service.

## PlayerCredentialStore — ADR-029 (3a): Trust-on-First-Use-Verifikation für
## `player_uuid`, analog SSH-Host-Keys.
##
## `player_uuid` allein ist keine Authentifizierung — sie ist ein öffentlicher
## Bezeichner, liegt offen in der lokalen Save-Datei und geht unverschlüsselt
## über ENet mit. Diese Klasse merkt sich pro `player_uuid`, mit welchem
## `player_secret` sie zuerst gesehen wurde, und lehnt spätere Verbindungen
## mit abweichendem Secret ab — verhindert, dass ein modifizierter Client eine
## fremde `player_uuid` beansprucht und damit fremdes Inventar/Quest-Fortschritt
## übernimmt.
##
## GEHALTEN VON: SessionManager (app-scoped, ServiceNode, lebt für die gesamte
## App-Laufzeit — NICHT NetworkBridge, siehe ADR-029 "Implementierungsnotizen
## Round 59" für die ursprüngliche Fehlannahme dort).
##
## PERSISTENZ (Entscheidung Round 60): eigene Datei (DEFAULT_SAVE_PATH), UNABHÄNGIG
## von SaveSystem/ISaveProvider/Charakter-Saves. TOFU-Secrets gehören
## inhaltlich zur Server-INSTALLATION (wer hat sich hier schon mal als welche
## player_uuid verbunden), nicht zu einem einzelnen Charakter — ein Host, der
## zwischen zwei eigenen Charakteren wechselt, darf nicht plötzlich alle
## Vertrauensbeziehungen zu seinen Mitspielern verlieren. Löst nebenbei die in
## Round 59 gefundene Tier-2-Race (Client verbindet + handshaked bevor der
## Host selbst einen Charakter gewählt hat) vollständig auf: load() läuft
## einmalig beim SessionManager-Boot, lange bevor ein Client verbinden kann —
## unabhängig davon, ob/welcher Charakter gerade aktiv ist.
##
## Secrets werden gehasht gespeichert (SHA-256), nie im Klartext — auch wenn
## das Risiko-Modell TOFU statt Passwort ist, gibt es keinen Grund, das rohe
## Secret auf Disk zu halten, wenn ein Vergleich per Hash genügt.
##
## Austauschbar: das ist eine Implementierung des in ADR-029 (3a) beschriebenen
## Abstraktionspunkts "beweise, dass diese player_uuid zu diesem Peer gehört".
## Die im ADR skizzierte Account-Token-Prüfung (Ablösung/Option C) würde
## dieselbe Rolle über verify_or_register() hinweg anders füllen, ohne dass
## SessionManager oder der Handshake-Ablauf selbst sich ändern müssten.
##
## Atomic-Write bewusst dupliziert statt SaveSystem._atomic_write() zu teilen:
## andere Datei (kein Schema-Versioning/Migration nötig, keine SaveMigrationService-
## Kopplung), geringes Duplikations-Risiko (10 Zeilen, stabiles Muster) gegen
## unnötige Kopplung an SaveSystem-Interna abgewogen.

const DEFAULT_SAVE_PATH := "user://server_credentials.json"
const LOG_CAT    := "PlayerCredentialStore"

## Überschreibbar für Tests (siehe test_player_credential_store.gd) — Produktionscode
## nutzt immer DEFAULT_SAVE_PATH. Kein Setter zur Laufzeit: nur über den Konstruktor,
## damit nie versehentlich mitten in einer laufenden Session der Pfad wechselt.
var _save_path: String

## player_uuid (String) → secret_hash (String, SHA-256 Hex)
var _secret_hashes: Dictionary = {}

func _init(save_path: String = DEFAULT_SAVE_PATH) -> void:
	_save_path = save_path

## Lädt die Datei von Disk, falls vorhanden. Fehlt sie (frische Installation)
## oder ist sie korrupt, wird mit leerem State weitergemacht — kein Fehlerfall,
## jede player_uuid wird dann beim nächsten Handshake neu per TOFU registriert.
func load() -> void:
	if not FileAccess.file_exists(_save_path):
		AppLogger.log_info("Keine bestehende %s — starte leer." % _save_path, LOG_CAT)
		return
	var file := FileAccess.open(_save_path, FileAccess.READ)
	if not file:
		AppLogger.log_error("%s existiert, konnte aber nicht geöffnet werden." % _save_path, LOG_CAT)
		return
	var json := JSON.new()
	var text := file.get_as_text()
	file.close()
	if json.parse(text) != OK or not json.data is Dictionary:
		AppLogger.log_error("%s ist korrupt — starte leer (TOFU registriert neu)." % _save_path, LOG_CAT)
		return
	_secret_hashes = json.data
	AppLogger.log_info("%s geladen (%d bekannte Identitäten)." % [_save_path, _secret_hashes.size()], LOG_CAT)

## Atomic-Write (tmp + rename), analog SaveSystem._atomic_write() — siehe
## Klassen-Kommentar für die Begründung, warum hier dupliziert statt geteilt.
func save() -> bool:
	var tmp_path := _save_path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if not file:
		AppLogger.log_error("Konnte tmp-Datei für %s nicht öffnen." % _save_path, LOG_CAT)
		return false
	file.store_string(JSON.stringify(_secret_hashes, "\t"))
	file.close()
	var rename_err := DirAccess.rename_absolute(tmp_path, _save_path)
	if rename_err != OK:
		AppLogger.log_error("Atomic Rename für %s fehlgeschlagen (Error %d)." % [_save_path, rename_err], LOG_CAT)
		return false
	return true

## Trust-on-First-Use-Prüfung. Schreibt bei Erst-Registrierung sofort durch
## (save()) — ein Crash zwischen Handshake-Zusage und nächstem regulären
## Speicherpunkt darf die frisch vertraute Identität nicht verlieren, sonst
## würde der nächste Verbindungsversuch fälschlich wieder als "erster
## Kontakt" behandelt (kein Sicherheitsproblem, aber verwirrendes Verhalten).
## - player_uuid unbekannt (erster Kontakt) → registriert den Secret-Hash, akzeptiert.
## - player_uuid bekannt UND Secret stimmt überein → akzeptiert.
## - player_uuid bekannt, Secret stimmt NICHT überein → abgelehnt (möglicher
##   Identitätsdiebstahl-Versuch, wird geloggt).
func verify_or_register(player_uuid: String, presented_secret: String) -> bool:
	if player_uuid.strip_edges().is_empty() or presented_secret.strip_edges().is_empty():
		return false

	var hash := presented_secret.sha256_text()
	if not _secret_hashes.has(player_uuid):
		_secret_hashes[player_uuid] = hash
		AppLogger.log_info("Neue Spieler-Identität registriert (TOFU): %s" % player_uuid, LOG_CAT)
		save()
		return true

	var accepted: bool = _secret_hashes[player_uuid] == hash
	if not accepted:
		AppLogger.log_error(
			"Secret-Mismatch für player_uuid '%s' — Handshake abgelehnt (möglicher Identitätsdiebstahl-Versuch)." % player_uuid,
			LOG_CAT
		)
	return accepted

## Für Tests/Debug: ob eine player_uuid bereits ein registriertes Secret hat.
func has_registered(player_uuid: String) -> bool:
	return _secret_hashes.has(player_uuid)

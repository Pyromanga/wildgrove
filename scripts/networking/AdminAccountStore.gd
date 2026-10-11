class_name AdminAccountStore
# justified: reines Datei-I/O + In-Memory-Lookup, keine Node-Lifecycle-Anforderungen —
# von AdminConsole gehalten und explizit load()/save() aufgerufen, analog
# PlayerCredentialStore (kein DI-Service).

## AdminAccountStore — ADR-040: Mehrkonten-Auth für den Tier-3-Admin-Zugang.
##
## Beantwortet ausschließlich "ist das wirklich Alice" (Authentifizierung).
## Ob Alice etwas darf, entscheidet weiterhin ausschließlich PermissionService
## (Autorisierung) — bewusst dieselbe Trennung wie zwischen
## PlayerCredentialStore und PermissionService, siehe ADR-040 "Entscheidung".
##
## GEHALTEN VON: AdminConsole (transportunabhängige Kernlogik, siehe dort).
##
## PERSISTENZ: eigene Datei (DEFAULT_SAVE_PATH), unabhängig von SaveSystem/
## PlayerCredentialStore — Admin-Konten sind ein Server-Installations-Konzept,
## keine Spieler-Identität.
##
## PASSWÖRTER: nie im Klartext auf Disk. Pro Konto ein zufälliges Salt
## (UuidGen.generate_v4(), rein als Zufallsquelle zweckentfremdet — kein
## Uuid-Verwendungszweck hier) + SHA-256(salt + passwort). Salt verhindert,
## dass zwei Konten mit demselben Passwort denselben Hash zeigen, und macht
## vorab berechnete Rainbow-Tables gegen diese Datei wertlos.
##
## must_rotate: solange gesetzt, darf AdminConsole für dieses Konto
## ausschließlich den Passwort-Ändern-Befehl durchlassen — erzwungen dort,
## nicht hier (dieser Store kennt keine Befehle, nur Konten).
##
## BOOTSTRAP: existiert die Datei beim ersten load() noch nicht, wird
## automatisch ein `root`-Konto mit zufälligem Passwort angelegt und dieses
## Passwort einmalig über AppLogger ausgegeben (einzige Stelle, an der ein
## Klartext-Passwort je sichtbar wird) — siehe ensure_bootstrap_account().

const DEFAULT_SAVE_PATH := "user://admin_accounts.json"
const LOG_CAT := "AdminAccountStore"
const BOOTSTRAP_USERNAME := "root"
const BOOTSTRAP_PASSWORD_LENGTH := 20
const _PASSWORD_ALPHABET := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

## Überschreibbar für Tests (siehe test_admin_account_store.gd). Kein Setter
## zur Laufzeit — nur über den Konstruktor, analog PlayerCredentialStore.
var _save_path: String

## username (String) → {"salt": String, "password_hash": String, "must_rotate": bool}
var _accounts: Dictionary = {}

func _init(save_path: String = DEFAULT_SAVE_PATH) -> void:
	_save_path = save_path

## Lädt die Datei von Disk, falls vorhanden. Fehlt sie, wird mit leerem State
## weitergemacht — kein Fehlerfall, ensure_bootstrap_account() legt danach das
## root-Konto an.
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
		AppLogger.log_error("%s ist korrupt — starte leer." % _save_path, LOG_CAT)
		return
	_accounts = json.data
	AppLogger.log_info("%s geladen (%d Admin-Konten)." % [_save_path, _accounts.size()], LOG_CAT)

## Atomic-Write (tmp + rename), analog PlayerCredentialStore/SettingsService.
func save() -> bool:
	var tmp_path := _save_path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if not file:
		AppLogger.log_error("Konnte tmp-Datei für %s nicht öffnen." % _save_path, LOG_CAT)
		return false
	file.store_string(JSON.stringify(_accounts, "\t"))
	file.close()
	var rename_err := DirAccess.rename_absolute(tmp_path, _save_path)
	if rename_err != OK:
		AppLogger.log_error("Atomic Rename für %s fehlgeschlagen (Error %d)." % [_save_path, rename_err], LOG_CAT)
		return false
	return true

## Legt bei einer frischen Installation (keine Konten vorhanden) automatisch
## das root-Bootstrap-Konto an. Idempotent — ein Aufruf, wenn bereits Konten
## existieren (egal ob root oder andere), ist ein No-Op und ändert nichts.
## Gibt das Klartext-Passwort zurück, wenn ein neues Konto angelegt wurde,
## sonst einen leeren String.
func ensure_bootstrap_account() -> String:
	if not _accounts.is_empty():
		return ""
	var password := _generate_random_password()
	_create_account_internal(BOOTSTRAP_USERNAME, password, true)
	save()
	AppLogger.log_warn(
		"Bootstrap-Admin-Konto '%s' angelegt. EINMALIGES Passwort: %s — bitte sofort per 'passwd' ändern, dieses Passwort wird nie wieder angezeigt." % [BOOTSTRAP_USERNAME, password],
		LOG_CAT
	)
	return password

func has_account(username: String) -> bool:
	return _accounts.has(username)

func list_usernames() -> Array[String]:
	var names: Array[String] = []
	for username in _accounts:
		names.append(username)
	return names

## Legt ein neues Konto mit Zufallspasswort an (für `admin create <username>`).
## Gibt das Klartext-Passwort zurück, oder "" falls der Username bereits existiert.
func create_account(username: String) -> String:
	if username.strip_edges().is_empty():
		AppLogger.log_warn("create_account() mit leerem Username ignoriert.", LOG_CAT)
		return ""
	if has_account(username):
		AppLogger.log_warn("create_account('%s') — Konto existiert bereits, ignoriert." % username, LOG_CAT)
		return ""
	var password := _generate_random_password()
	_create_account_internal(username, password, true)
	save()
	return password

## Entfernt ein Konto (für `admin revoke <username>`). root kann sich nicht
## selbst entfernen, wenn es das letzte verbleibende Konto wäre — sonst wäre
## der Server nach einem einzigen Fehlbefehl dauerhaft unadministrierbar.
func revoke_account(username: String) -> bool:
	if not has_account(username):
		return false
	if _accounts.size() <= 1:
		AppLogger.log_warn(
			"revoke_account('%s') abgelehnt — letztes verbleibendes Admin-Konto darf nicht entfernt werden." % username,
			LOG_CAT
		)
		return false
	_accounts.erase(username)
	return save()

## Prüft Username/Passwort. Gibt false zurück bei unbekanntem Username oder
## falschem Passwort — bewusst ohne zu unterscheiden, welcher der beiden
## Fälle vorliegt (verhindert Username-Enumeration über die Fehlerantwort).
func verify_password(username: String, presented_password: String) -> bool:
	if not has_account(username):
		return false
	var account: Dictionary = _accounts[username]
	var hash := _hash_password(account.get("salt", ""), presented_password)
	return hash == account.get("password_hash", "")

func must_rotate(username: String) -> bool:
	if not has_account(username):
		return false
	return _accounts[username].get("must_rotate", false)

## Setzt ein neues Passwort für ein bestehendes Konto und löscht das
## must_rotate-Flag. Gibt false zurück, wenn das Konto nicht existiert.
func set_password(username: String, new_password: String) -> bool:
	if not has_account(username):
		return false
	if new_password.strip_edges().is_empty():
		AppLogger.log_warn("set_password('%s') mit leerem Passwort ignoriert." % username, LOG_CAT)
		return false
	var salt := UuidGen.generate_v4()
	_accounts[username] = {
		"salt": salt,
		"password_hash": _hash_password(salt, new_password),
		"must_rotate": false,
	}
	return save()

func _create_account_internal(username: String, password: String, force_rotate: bool) -> void:
	var salt := UuidGen.generate_v4()
	_accounts[username] = {
		"salt": salt,
		"password_hash": _hash_password(salt, password),
		"must_rotate": force_rotate,
	}

func _hash_password(salt: String, password: String) -> String:
	return (salt + password).sha256_text()

func _generate_random_password() -> String:
	var result := ""
	for _i in range(BOOTSTRAP_PASSWORD_LENGTH):
		result += _PASSWORD_ALPHABET[randi() % _PASSWORD_ALPHABET.length()]
	return result

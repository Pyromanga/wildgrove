extends Service
class_name PermissionService

## PermissionService — Rollenbasiertes Permission-System (ADR-031).
##
## SCOPE: GLOBAL (wie SaveSystem/SettingsService) — Rollen gelten account-weit,
## nicht pro Welt/Charakter (siehe ADR-009/ADR-031 "Entscheidung").
##
## Verwechslungsgefahr vermeiden: das hier sind KEINE Interaktions-Guards
## (ADR-020). Guards prüfen "ist diese Aktion autoritativ gültig" (Besitz
## etc.), PermissionService prüft "darf dieser Spieler etwas, das andere
## Spieler nicht dürfen". Zwei verschiedene Fragen, zwei verschiedene Stellen.
##
## has_capability() ist die EINZIGE Stelle, die diese Frage beantwortet —
## ausschließlich serverautoritativ zu prüfen, nie clientseitig vertraut
## (gleiches Muster wie Inventar-/Movement-Validierung, siehe ADR-024/Round 45).
##
## PERSISTENZ: Rollen werden `player_uuid`-verschachtelt gespeichert (analog
## zum Rekeying aus ADR-029), NICHT `peer_id`-verschachtelt — Rollen müssen
## Reconnects überleben. Eigene Datei (user://roles.json), atomic write
## (tmp → rename), gleiches Muster wie SettingsService — bewusst nicht
## geteilt, siehe dortiger Kommentar zur Nicht-Kopplung.
##
## ROLLENZUWEISUNG NACH TIER (ADR-031 "Rollenzuweisung nach Tier"):
##   Tier 1 (Solo) und Tier 2-Host sind automatisch Admin, Tier-3-
##   Dedicated-Server-Betrieb braucht ein Root-Konto mit Pflicht-Passwort-
##   Rotation vor erstem Start. ensure_default_role() (idempotent — vergibt
##   nur beim allerersten Sehen einer player_uuid eine Rolle, überschreibt nie
##   eine bereits gesetzte) ist seit Round 82 an ServiceOrchestrator
##   ._on_session_requested() angeschlossen (dort: _ensure_default_role_for_tier()
##   / _should_get_default_admin(), abhängig von SessionManager.is_server() und
##   SessionManager.is_dedicated_server()) — kein separater Aufruf mehr nötig.
##   Weiterhin offen: ein tatsächliches Passwort-basiertes Root-Konto für
##   Tier 3 existiert im Projekt noch nicht (aktuell nur TOFU-Secrets über
##   PlayerCredentialStore, kein Username/Passwort-Login) — die
##   "Pflicht-Rotation vor erstem Start" aus dem ADR braucht dafür erst eine
##   Auth-Schicht, die es heute nicht gibt. Siehe TODO-offene-probleme.md.

const LOG_CAT := "PermissionService"
const ROLES_PATH := "user://roles.json"
const DEFAULT_ROLE_ID := "player"

## Einzige Quelle der Wahrheit für bekannte Rollen — datengetrieben (ADR-031
## Option B). preload() statt dynamischem load()-über-Pfad-Array: DataManifest
## existiert genau wegen dieser Falle (siehe dortiger Klassenkommentar) — der
## Godot-Exporter mit export_filter="all_resources" erkennt nur Ressourcen,
## die im SceneTree ODER via preload() referenziert sind, kein DirAccess-Scan
## und kein dynamisches load(path_variable). Neue Rolle: .tres-Datei anlegen,
## hier preloaden + in configure() in _roles aufnehmen.
const ROLE_PLAYER:    Role = preload("res://data/roles/player.tres")
const ROLE_MODERATOR: Role = preload("res://data/roles/moderator.tres")
const ROLE_ADMIN:     Role = preload("res://data/roles/admin.tres")

## Test-Override für den Persistenz-Pfad, analog SettingsService. Leer = Produktionspfad.
var _path_override: String = ""

## role_id (String) → Role
var _roles: Dictionary = {}

## player_uuid (String) → role_id (String)
var _assignments: Dictionary = {}

# ─────────────────────────────────────────────
# Phase 4: Configure
# ─────────────────────────────────────────────

func configure(_deps: ServiceDeps) -> void:
	_roles = _load_roles()
	if not _roles.has(DEFAULT_ROLE_ID):
		AppLogger.log_error(
			"'%s' (Default-Rolle) fehlt unter den preloadeten Rollen — Spieler ohne Zuweisung hätten keine gültige Rolle." % DEFAULT_ROLE_ID,
			LOG_CAT
		)
	_assignments = _read_from_disk()
	AppLogger.log_info(
		"PermissionService bereit (%d Rollen, %d gespeicherte Zuweisungen)." % [_roles.size(), _assignments.size()],
		LOG_CAT
	)

func _load_roles() -> Dictionary:
	var loaded: Dictionary = {}
	for role: Role in [ROLE_PLAYER, ROLE_MODERATOR, ROLE_ADMIN]:
		if not is_instance_valid(role):
			AppLogger.log_error("Eine preloadete Rolle ist ungültig.", LOG_CAT)
			continue
		if role.id.is_empty():
			AppLogger.log_error("Rolle mit leerer id übersprungen.", LOG_CAT)
			continue
		loaded[role.id] = role
	return loaded

# ─────────────────────────────────────────────
# Öffentliche API — Abfrage
# ─────────────────────────────────────────────

## Serverautoritative Capability-Prüfung — die einzige Stelle, die diese
## Frage beantworten darf. player_id ist die stabile player_uuid (ADR-029),
## nicht peer_id (siehe Klassenkommentar).
func has_capability(player_id: String, capability: StringName) -> bool:
	var role := _get_role_for(player_id)
	if not is_instance_valid(role):
		return false
	return capability in role.capabilities

func is_admin(player_id: String) -> bool:
	return has_capability(player_id, &"full_access")

func get_role_id(player_id: String) -> String:
	return _assignments.get(player_id, DEFAULT_ROLE_ID)

func get_capabilities(player_id: String) -> Array[StringName]:
	var role := _get_role_for(player_id)
	if not is_instance_valid(role):
		return []
	return role.capabilities.duplicate()

func list_role_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in _roles:
		ids.append(id)
	return ids

func is_known_role(role_id: String) -> bool:
	return _roles.has(role_id)

func _get_role_for(player_id: String) -> Role:
	var role_id: String = get_role_id(player_id)
	if _roles.has(role_id):
		return _roles[role_id]
	# Zugewiesene Rolle existiert nicht mehr (z.B. nach Entfernen einer
	# Custom-Rolle) — fail-safe auf DEFAULT_ROLE_ID statt zu crashen oder
	# stillschweigend alle Capabilities zu gewähren.
	if role_id != DEFAULT_ROLE_ID:
		AppLogger.log_warn(
			"Zugewiesene Rolle '%s' für '%s' unbekannt — falle zurück auf '%s'." % [role_id, player_id, DEFAULT_ROLE_ID],
			LOG_CAT
		)
	return _roles.get(DEFAULT_ROLE_ID)

# ─────────────────────────────────────────────
# Öffentliche API — Zuweisung
# ─────────────────────────────────────────────

## Weist einer player_uuid explizit eine Rolle zu und persistiert sofort.
## Gibt false zurück (kein Write) wenn role_id unbekannt ist — verhindert,
## dass ein Tippfehler eine Rolle zuweist, die nie gültig war.
func assign_role(player_id: String, role_id: String) -> bool:
	if player_id.is_empty():
		AppLogger.log_warn("assign_role() mit leerer player_id ignoriert.", LOG_CAT)
		return false
	if not is_known_role(role_id):
		AppLogger.log_warn("assign_role('%s', '%s') — unbekannte role_id, ignoriert." % [player_id, role_id], LOG_CAT)
		return false
	_assignments[player_id] = role_id
	return _write_to_disk()

## Setzt eine player_uuid zurück auf die Default-Rolle (entfernt die
## explizite Zuweisung) und persistiert.
func revoke_role(player_id: String) -> bool:
	if not _assignments.has(player_id):
		return true
	_assignments.erase(player_id)
	return _write_to_disk()

## Idempotente Erstzuweisung — vergibt default_role_id NUR, wenn für diese
## player_uuid noch nie eine Rolle gespeichert wurde. Überschreibt nie eine
## bereits (auch manuell) gesetzte Rolle, z.B. eine nachträgliche
## Moderator-Beförderung. Gedacht für den Tier-basierten Default aus
## ADR-031 "Rollenzuweisung nach Tier" — siehe Klassenkommentar zum
## Aufrufer, der hier bewusst noch nicht existiert.
## Gibt true zurück, wenn dadurch tatsächlich eine neue Zuweisung entstanden ist.
func ensure_default_role(player_id: String, default_role_id: String) -> bool:
	if _assignments.has(player_id):
		return false
	return assign_role(player_id, default_role_id)

## Test-Only: überschreibt den Persistenz-Pfad. Muss vor configure() gesetzt werden.
func set_path_override(p: String) -> void:
	_path_override = p

func _get_path() -> String:
	return _path_override if not _path_override.is_empty() else ROLES_PATH

# ─────────────────────────────────────────────
# Intern — Atomic Write (tmp → rename), analog SettingsService/SaveSystem
# ─────────────────────────────────────────────

func _write_to_disk() -> bool:
	var path := _get_path()
	var tmp_path := path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if not file:
		AppLogger.log_error("Konnte tmp-Datei nicht öffnen: %s" % tmp_path, LOG_CAT)
		return false
	file.store_string(JSON.stringify(_assignments, "\t"))
	file.close()

	var rename_err := DirAccess.rename_absolute(tmp_path, path)
	if rename_err != OK:
		AppLogger.log_error("Atomic Rename fehlgeschlagen (Error %d)!" % rename_err, LOG_CAT)
		return false
	return true

func _read_from_disk() -> Dictionary:
	var path := _get_path()
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		AppLogger.log_warn("'%s' existiert, konnte aber nicht geöffnet werden." % path, LOG_CAT)
		return {}
	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		AppLogger.log_error("'%s' ist korrupt — starte ohne gespeicherte Zuweisungen." % path, LOG_CAT)
		return {}

	# Nur Zuweisungen auf bekannte Rollen übernehmen — analog zu SettingsService,
	# das unbekannte Keys beim Laden verwirft statt sie stillschweigend durchzureichen.
	var result: Dictionary = {}
	for player_id in json.data:
		var role_id: Variant = json.data[player_id]
		if role_id is String and _roles.has(role_id):
			result[player_id] = role_id
		else:
			AppLogger.log_warn(
				"Gespeicherte Zuweisung für '%s' verweist auf unbekannte Rolle '%s' — ignoriert." % [player_id, role_id],
				LOG_CAT
			)
	return result

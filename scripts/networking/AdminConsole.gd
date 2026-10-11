class_name AdminConsole
# justified: reine Kommando-/Auth-Logik ohne Node-Lifecycle-Anforderungen — von den
# beiden Transport-Frontends (stdin-Reader, TCP-Listener) gehalten und aufgerufen,
# analog SessionManager._handle_join_handshake() (Kernlogik von Transport-Hülle
# getrennt, siehe ADR-029 "Implementierungsnotizen Round 61").

## AdminConsole — ADR-040: transportunabhängige Kernlogik für den
## Tier-3-Admin-Zugang.
##
## Bewusst NICHT von SimpleTerminal (scripts/debug/) abgeleitet oder mit ihm
## geteilt — unterschiedlicher Zweck: SimpleTerminal ist lokale,
## auth-freie Introspektion auf JEDEM Client/Host (nur im Debug-Build),
## AdminConsole ist Remote-Zugriff mit Login auf dem Tier-3-Server (auch im
## Release-Build aktiv, siehe DedicatedServerBootstrap). Das
## Callable-basierte Befehls-Registry-Muster ist bewusst übernommen (hat
## sich dort bewährt), aber beide Klassen bleiben komplett unabhängig.
##
## MEHRERE GLEICHZEITIGE VERBINDUNGEN: jede Verbindung (stdin ODER eine
## TCP-Verbindung) bekommt über new_session() eine eigene AdminConsoleSession
## mit eigenem Login-Zustand — kein geteilter globaler "bin ich eingeloggt"-Flag,
## sonst würde ein zweiter Admin automatisch im Login-Zustand des ersten landen.
##
## AUTH-FLUSS pro Session:
##   1. "login <username> <password>" — erst danach sind andere Befehle erlaubt.
##   2. Ist must_rotate für dieses Konto gesetzt (Bootstrap/frisch angelegt),
##      wird JEDER Befehl außer "passwd"/"help"/"logout" abgelehnt, bis das
##      Passwort geändert wurde — siehe ADR-040 "Entscheidung".
##
## RATE-LIMITING: einfacher Login-Versuchszähler pro Username (nicht pro
## Session/IP — bewusst simpel für die erste Version, siehe ADR-040
## "Mitigationen"). Nach MAX_LOGIN_ATTEMPTS Fehlversuchen in Folge wird der
## Username für LOCKOUT_SECONDS gesperrt, unabhängig davon, über welche
## Session/Verbindung die Versuche kamen — verhindert Brute-Force auch über
## mehrere parallele TCP-Verbindungen hinweg.
##
## NUR AKTIV AUF TIER 3: der jeweilige Aufrufer (stdin-Reader/TCP-Listener)
## ist dafür verantwortlich, sich nur zu starten, wenn
## SessionManager.is_dedicated_server() true ist — AdminConsole selbst prüft
## das nicht, um in Tests ohne gebootete App instanziierbar zu bleiben
## (gleiches Muster wie ServiceOrchestrator._should_get_default_admin()).

const LOG_CAT := "AdminConsole"
const MAX_LOGIN_ATTEMPTS := 5
const LOCKOUT_SECONDS := 30.0

var _account_store: AdminAccountStore
var _permission_service: PermissionService
var _session_manager: SessionManager

## username (String) → {"count": int, "locked_until_unix": float}
var _login_attempts: Dictionary = {}

## Injizierte Zeitquelle für Tests (Time.get_unix_time_from_system() ist in
## echten Tests unpraktisch zeitgesteuert zu treiben) — Standardimplementierung
## nutzt die echte Systemzeit.
var _time_source: Callable = Time.get_unix_time_from_system

func _init(account_store: AdminAccountStore, permission_service: PermissionService = null, session_manager: SessionManager = null) -> void:
	_account_store = account_store
	_permission_service = permission_service
	_session_manager = session_manager

## Test-Only: eigene Zeitquelle für deterministische Lockout-Tests.
func set_time_source_for_testing(source: Callable) -> void:
	_time_source = source

func new_session() -> AdminConsoleSession:
	return AdminConsoleSession.new(self)

# ─────────────────────────────────────────────
# Von AdminConsoleSession aufgerufen — Auth
# ─────────────────────────────────────────────

func _is_locked_out(username: String) -> bool:
	if not _login_attempts.has(username):
		return false
	var locked_until: float = _login_attempts[username].get("locked_until_unix", 0.0)
	return _time_source.call() < locked_until

func _record_failed_login(username: String) -> void:
	var entry: Dictionary = _login_attempts.get(username, {"count": 0, "locked_until_unix": 0.0})
	entry["count"] = int(entry.get("count", 0)) + 1
	if entry["count"] >= MAX_LOGIN_ATTEMPTS:
		entry["locked_until_unix"] = _time_source.call() + LOCKOUT_SECONDS
		AppLogger.log_warn(
			"Admin-Login für '%s' nach %d Fehlversuchen für %.0fs gesperrt." % [username, entry["count"], LOCKOUT_SECONDS],
			LOG_CAT
		)
	_login_attempts[username] = entry

func _clear_failed_logins(username: String) -> void:
	_login_attempts.erase(username)

## Gibt "" bei Erfolg zurück, sonst eine Fehlermeldung für den Nutzer.
func _try_login(username: String, password: String) -> String:
	if _is_locked_out(username):
		return "Konto '%s' ist wegen zu vieler Fehlversuche vorübergehend gesperrt." % username
	if not _account_store.verify_password(username, password):
		_record_failed_login(username)
		return "Login fehlgeschlagen."
	_clear_failed_logins(username)
	return ""

# ─────────────────────────────────────────────
# Von AdminConsoleSession aufgerufen — Befehle (bereits eingeloggt)
# ─────────────────────────────────────────────

## Führt einen Befehl im Kontext eines bereits eingeloggten Kontos aus.
## Gibt die Ausgabezeile(n) für den Nutzer zurück.
func _dispatch(username: String, cmd: String, args: Array) -> String:
	match cmd:
		"help":
			return _cmd_help()
		"logout":
			return "Ausgeloggt."
		"passwd":
			return _cmd_passwd(username, args)
		"admin":
			return _cmd_admin(args)
		"role":
			return _cmd_role(args)
		"players":
			return _cmd_players()
		"kick":
			return _cmd_kick(args)
		_:
			return "Unbekannter Befehl: '%s'. Tippe 'help'." % cmd

func _cmd_help() -> String:
	return "\n".join([
		"Verfügbare Befehle:",
		"  passwd <neues_passwort>          — eigenes Passwort ändern",
		"  admin create <username>          — neues Admin-Konto anlegen",
		"  admin list                       — alle Admin-Konten anzeigen",
		"  admin revoke <username>          — Admin-Konto entfernen",
		"  role assign <player_uuid> <role> — Spieler-Rolle setzen",
		"  role revoke <player_uuid>        — Spieler-Rolle auf Default zurücksetzen",
		"  players                          — aktuell verbundene Spieler anzeigen",
		"  kick <player_uuid>               — Spieler vom Server trennen",
		"  logout                           — Session beenden",
	])

func _cmd_passwd(username: String, args: Array) -> String:
	if args.is_empty():
		return "Verwendung: passwd <neues_passwort>"
	var new_password: String = args[0]
	var ok := _account_store.set_password(username, new_password)
	if not ok:
		return "Passwort konnte nicht geändert werden."
	return "Passwort geändert."

func _cmd_admin(args: Array) -> String:
	if args.is_empty():
		return "Verwendung: admin create|list|revoke ..."
	match args[0]:
		"create":
			if args.size() < 2:
				return "Verwendung: admin create <username>"
			var new_username: String = args[1]
			var password := _account_store.create_account(new_username)
			if password.is_empty():
				return "Konnte Konto '%s' nicht anlegen (existiert bereits?)." % new_username
			return "Konto '%s' angelegt. Temp-Passwort: %s (muss beim ersten Login geändert werden)." % [new_username, password]
		"list":
			var names := _account_store.list_usernames()
			names.sort()
			return "Admin-Konten (%d): %s" % [names.size(), str(names)]
		"revoke":
			if args.size() < 2:
				return "Verwendung: admin revoke <username>"
			var target: String = args[1]
			var ok := _account_store.revoke_account(target)
			return "Konto '%s' entfernt." % target if ok else "Konnte Konto '%s' nicht entfernen (letztes Konto oder unbekannt)." % target
		_:
			return "Unbekannter Unterbefehl: '%s'. Verwendung: admin create|list|revoke ..." % args[0]

func _cmd_role(args: Array) -> String:
	if not is_instance_valid(_permission_service):
		return "PermissionService nicht verfügbar."
	if args.is_empty():
		return "Verwendung: role assign <player_uuid> <role_id> | role revoke <player_uuid>"
	match args[0]:
		"assign":
			if args.size() < 3:
				return "Verwendung: role assign <player_uuid> <role_id>"
			var player_id: String = args[1]
			var role_id: String = args[2]
			var ok: bool = _permission_service.assign_role(player_id, role_id)
			return "Rolle '%s' für '%s' gesetzt." % [role_id, player_id] if ok else "Konnte Rolle nicht setzen (unbekannte role_id oder leere player_id)."
		"revoke":
			if args.size() < 2:
				return "Verwendung: role revoke <player_uuid>"
			var player_id: String = args[1]
			var ok: bool = _permission_service.revoke_role(player_id)
			return "Rolle für '%s' auf Default zurückgesetzt." % player_id if ok else "Konnte Rolle nicht zurücksetzen."
		_:
			return "Unbekannter Unterbefehl: '%s'. Verwendung: role assign|revoke ..." % args[0]

func _cmd_players() -> String:
	if not is_instance_valid(_session_manager):
		return "SessionManager nicht verfügbar."
	var slots: Dictionary = _session_manager.get_all_slots()
	if slots.is_empty():
		return "Keine Spieler verbunden."
	var lines: Array[String] = ["Verbundene Spieler (%d):" % slots.size()]
	for peer_id in slots:
		lines.append("  peer=%d → %s" % [peer_id, slots[peer_id]])
	return "\n".join(lines)

func _cmd_kick(args: Array) -> String:
	if not is_instance_valid(_session_manager):
		return "SessionManager nicht verfügbar."
	if args.is_empty():
		return "Verwendung: kick <player_uuid>"
	var player_id: String = args[0]
	var ok: bool = _session_manager.kick_player(player_id)
	return "Spieler '%s' getrennt." % player_id if ok else "Konnte '%s' nicht trennen (nicht verbunden?)." % player_id


## AdminConsoleSession — Login-Zustand EINER Verbindung (stdin ODER eine
## TCP-Verbindung). Vom jeweiligen Transport-Frontend gehalten, eine Instanz
## pro Verbindung — siehe Klassenkommentar oben ("Mehrere gleichzeitige
## Verbindungen").
class AdminConsoleSession:
	extends RefCounted

	var _console: AdminConsole
	var _username: String = ""

	func _init(console: AdminConsole) -> void:
		_console = console

	func is_logged_in() -> bool:
		return not _username.is_empty()

	func logged_in_username() -> String:
		return _username

	## Verarbeitet eine einzelne Eingabezeile und gibt die Antwort zurück, die
	## das Frontend an die jeweilige Verbindung zurückschicken soll.
	func handle_line(raw_input: String) -> String:
		var trimmed := raw_input.strip_edges()
		if trimmed.is_empty():
			return ""
		var parts := trimmed.split(" ", false)
		var cmd := parts[0].to_lower()
		var args := parts.slice(1)

		if cmd == "logout":
			_username = ""
			return "Ausgeloggt."

		if not is_logged_in():
			if cmd != "login":
				return "Bitte zuerst einloggen: login <username> <passwort>"
			if args.size() < 2:
				return "Verwendung: login <username> <passwort>"
			var username: String = args[0]
			var password: String = args[1]
			var error := _console._try_login(username, password)
			if not error.is_empty():
				return error
			_username = username
			if _console._account_store.must_rotate(username):
				return "Login OK. Passwort muss geändert werden — bitte 'passwd <neues_passwort>' ausführen."
			return "Login OK."

		if cmd == "login":
			return "Bereits eingeloggt als '%s'. 'logout' zum Wechseln." % _username

		# Eingeloggt, aber must_rotate gesperrt bis auf passwd/help.
		if _console._account_store.must_rotate(_username) and cmd != "passwd" and cmd != "help":
			return "Passwort muss zuerst geändert werden: 'passwd <neues_passwort>'."

		return _console._dispatch(_username, cmd, args)

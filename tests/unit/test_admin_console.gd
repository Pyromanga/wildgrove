# res://tests/unit/test_admin_console.gd
extends GutTest

## Tests für AdminConsole (ADR-040) — transportunabhängige Kernlogik für den
## Tier-3-Admin-Zugang: Login-Fluss, must_rotate-Sperre, Rate-Limiting,
## Befehle. Jede Session (AdminConsoleSession) hat eigenen Login-Zustand —
## siehe Klassenkommentar "Mehrere gleichzeitige Verbindungen".

const ACCOUNTS_TEST_PATH := "user://unit_test_admin_console_accounts.json"
const ROLES_TEST_PATH := "user://unit_test_admin_console_roles.json"

var _accounts: AdminAccountStore
var _permissions: PermissionService
var _sm: SessionManager
var _console: AdminConsole

func before_each() -> void:
	_accounts = AdminAccountStore.new(ACCOUNTS_TEST_PATH)
	_accounts.create_account("alice")
	_accounts.set_password("alice", "alice-pass")  # löscht must_rotate für die meisten Tests

	_permissions = PermissionService.new()
	_permissions.set_path_override(ROLES_TEST_PATH)
	_permissions.configure(ServiceDeps.from_dict({}))

	_sm = SessionManager.new()
	_sm.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: MockEventBus.new()}))
	add_child_autofree(_sm)

	_console = AdminConsole.new(_accounts, _permissions, _sm)

func after_each() -> void:
	_sm.on_cleanup()
	_console = null
	for p in [ACCOUNTS_TEST_PATH, ROLES_TEST_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
		if FileAccess.file_exists(p + ".tmp"):
			DirAccess.remove_absolute(p + ".tmp")

# ─────────────────────────────────────────────
# Login-Fluss
# ─────────────────────────────────────────────

func test_commands_rejected_before_login() -> void:
	var session := _console.new_session()
	var response := session.handle_line("players")
	assert_string_contains(response, "einloggen",
		"Ohne Login muss jeder Befehl außer login abgelehnt werden.")
	assert_false(session.is_logged_in())

func test_login_with_correct_password_succeeds() -> void:
	var session := _console.new_session()
	var response := session.handle_line("login alice alice-pass")
	assert_string_contains(response, "OK")
	assert_true(session.is_logged_in())
	assert_eq(session.logged_in_username(), "alice")

func test_login_with_wrong_password_fails() -> void:
	var session := _console.new_session()
	session.handle_line("login alice wrong-password")
	assert_false(session.is_logged_in())

func test_login_unknown_username_fails_without_revealing_that() -> void:
	var session := _console.new_session()
	var response := session.handle_line("login never-created whatever")
	assert_string_contains(response, "fehlgeschlagen")
	assert_false(session.is_logged_in())

func test_logout_clears_login_state() -> void:
	var session := _console.new_session()
	session.handle_line("login alice alice-pass")
	session.handle_line("logout")
	assert_false(session.is_logged_in())

func test_two_sessions_have_independent_login_state() -> void:
	var session_a := _console.new_session()
	var session_b := _console.new_session()
	session_a.handle_line("login alice alice-pass")
	assert_true(session_a.is_logged_in())
	assert_false(session_b.is_logged_in(),
		"Eine zweite Session darf durch den Login der ersten nicht automatisch eingeloggt sein.")

# ─────────────────────────────────────────────
# must_rotate-Sperre
# ─────────────────────────────────────────────

func test_must_rotate_blocks_players_command() -> void:
	var temp_password := _accounts.create_account("bob")
	var session := _console.new_session()
	session.handle_line("login bob %s" % temp_password)
	assert_true(session.is_logged_in())
	var response := session.handle_line("players")
	assert_string_contains(response, "passwd",
		"Solange must_rotate gesetzt ist, muss jeder Befehl außer passwd/help/logout abgelehnt werden.")

func test_must_rotate_allows_passwd() -> void:
	var temp_password := _accounts.create_account("bob")
	var session := _console.new_session()
	session.handle_line("login bob %s" % temp_password)
	var response := session.handle_line("passwd new-bob-password")
	assert_string_contains(response, "geändert")
	assert_false(_accounts.must_rotate("bob"),
		"Nach erfolgreichem passwd muss must_rotate gelöscht sein.")

func test_must_rotate_allows_help() -> void:
	var temp_password := _accounts.create_account("bob")
	var session := _console.new_session()
	session.handle_line("login bob %s" % temp_password)
	var response := session.handle_line("help")
	assert_string_contains(response, "passwd")

func test_after_rotating_password_other_commands_work() -> void:
	var temp_password := _accounts.create_account("bob")
	var session := _console.new_session()
	session.handle_line("login bob %s" % temp_password)
	session.handle_line("passwd new-bob-password")
	var response := session.handle_line("players")
	assert_string_contains(response, "Keine Spieler verbunden.")

# ─────────────────────────────────────────────
# Rate-Limiting / Lockout
# ─────────────────────────────────────────────

func test_lockout_after_max_failed_attempts() -> void:
	var session := _console.new_session()
	for _i in range(AdminConsole.MAX_LOGIN_ATTEMPTS):
		session.handle_line("login alice wrong-password")
	var response := session.handle_line("login alice alice-pass")
	assert_string_contains(response, "gesperrt",
		"Nach MAX_LOGIN_ATTEMPTS Fehlversuchen muss auch das korrekte Passwort abgelehnt werden.")
	assert_false(session.is_logged_in())

func test_lockout_applies_across_different_sessions() -> void:
	var session_a := _console.new_session()
	for _i in range(AdminConsole.MAX_LOGIN_ATTEMPTS):
		session_a.handle_line("login alice wrong-password")

	var session_b := _console.new_session()
	var response := session_b.handle_line("login alice alice-pass")
	assert_string_contains(response, "gesperrt",
		"Lockout ist pro Username, nicht pro Session — muss auch über eine andere Verbindung greifen.")

func test_lockout_expires_after_time_source_advances() -> void:
	# GDScript-Lambdas erfassen lokale Variablen by value, nicht by reference —
	# ein primitives "var fake_now := 1000.0" würde beim Erzeugen der Lambda
	# eingefroren und spätere Änderungen unten würden nicht ankommen. Ein
	# Array als mutable Box umgeht das (Arrays sind Referenztypen).
	var fake_now := [1000.0]
	_console.set_time_source_for_testing(func() -> float: return fake_now[0])

	var session := _console.new_session()
	for _i in range(AdminConsole.MAX_LOGIN_ATTEMPTS):
		session.handle_line("login alice wrong-password")

	fake_now[0] += AdminConsole.LOCKOUT_SECONDS + 1.0
	var response := session.handle_line("login alice alice-pass")
	assert_string_contains(response, "OK", "Nach Ablauf der Lockout-Zeit muss ein korrekter Login wieder möglich sein.")

func test_successful_login_clears_failed_attempt_counter() -> void:
	var session := _console.new_session()
	session.handle_line("login alice wrong-password")
	session.handle_line("login alice wrong-password")
	session.handle_line("logout")  # falls handle_line login bereits eingeloggt hätte, sauber trennen
	var ok_response := session.handle_line("login alice alice-pass")
	assert_string_contains(ok_response, "OK")

	# Danach wieder von vorn zählen können, ohne dass alte Fehlversuche übrig sind.
	session.handle_line("logout")
	for _i in range(AdminConsole.MAX_LOGIN_ATTEMPTS - 1):
		session.handle_line("login alice wrong-password")
	var still_ok := session.handle_line("login alice alice-pass")
	assert_string_contains(still_ok, "OK",
		"Nach einem erfolgreichen Login muss der Fehlversuch-Zähler zurückgesetzt sein.")

# ─────────────────────────────────────────────
# admin create/list/revoke
# ─────────────────────────────────────────────

func test_admin_create_new_account() -> void:
	var session := _console.new_session()
	session.handle_line("login alice alice-pass")
	var response := session.handle_line("admin create charlie")
	assert_string_contains(response, "angelegt")
	assert_true(_accounts.has_account("charlie"))

func test_admin_create_duplicate_rejected() -> void:
	var session := _console.new_session()
	session.handle_line("login alice alice-pass")
	var response := session.handle_line("admin create alice")
	assert_string_contains(response, "nicht anlegen")

func test_admin_list_shows_accounts() -> void:
	var session := _console.new_session()
	session.handle_line("login alice alice-pass")
	var response := session.handle_line("admin list")
	assert_string_contains(response, "alice")

func test_admin_revoke_removes_account() -> void:
	_accounts.create_account("charlie")
	var session := _console.new_session()
	session.handle_line("login alice alice-pass")
	var response := session.handle_line("admin revoke charlie")
	assert_string_contains(response, "entfernt")
	assert_false(_accounts.has_account("charlie"))

func test_admin_revoke_last_account_fails_gracefully() -> void:
	# _accounts hat zu diesem Zeitpunkt nur 'alice'.
	var session := _console.new_session()
	session.handle_line("login alice alice-pass")
	var response := session.handle_line("admin revoke alice")
	assert_string_contains(response, "nicht entfernen")
	assert_true(_accounts.has_account("alice"))

# ─────────────────────────────────────────────
# role assign/revoke — echte PermissionService-Integration
# ─────────────────────────────────────────────

func test_role_assign_calls_permission_service() -> void:
	var session := _console.new_session()
	session.handle_line("login alice alice-pass")
	var response := session.handle_line("role assign some-player-uuid admin")
	assert_string_contains(response, "gesetzt")
	assert_eq(_permissions.get_role_id("some-player-uuid"), "admin")

func test_role_assign_unknown_role_rejected() -> void:
	var session := _console.new_session()
	session.handle_line("login alice alice-pass")
	var response := session.handle_line("role assign some-player-uuid not-a-real-role")
	assert_string_contains(response, "Konnte Rolle nicht setzen")

func test_role_revoke_resets_to_default() -> void:
	_permissions.assign_role("some-player-uuid", "moderator")
	var session := _console.new_session()
	session.handle_line("login alice alice-pass")
	session.handle_line("role revoke some-player-uuid")
	assert_eq(_permissions.get_role_id("some-player-uuid"), PermissionService.DEFAULT_ROLE_ID)

# ─────────────────────────────────────────────
# players / kick — echte SessionManager-Integration (headless, Tier 1)
# ─────────────────────────────────────────────

func test_players_lists_registered_slots() -> void:
	_sm.register_player_slot(2, "player-uuid-2")
	var session := _console.new_session()
	session.handle_line("login alice alice-pass")
	var response := session.handle_line("players")
	assert_string_contains(response, "player-uuid-2")

func test_players_empty_message_without_slots() -> void:
	var session := _console.new_session()
	session.handle_line("login alice alice-pass")
	var response := session.handle_line("players")
	assert_string_contains(response, "Keine Spieler verbunden.")

func test_kick_unknown_player_fails_gracefully() -> void:
	var session := _console.new_session()
	session.handle_line("login alice alice-pass")
	var response := session.handle_line("kick never-connected-uuid")
	assert_string_contains(response, "nicht trennen")

# ─────────────────────────────────────────────
# help / unbekannte Befehle
# ─────────────────────────────────────────────

func test_help_lists_commands() -> void:
	var session := _console.new_session()
	session.handle_line("login alice alice-pass")
	var response := session.handle_line("help")
	assert_string_contains(response, "kick")
	assert_string_contains(response, "role assign")

func test_unknown_command_after_login() -> void:
	var session := _console.new_session()
	session.handle_line("login alice alice-pass")
	var response := session.handle_line("frobnicate")
	assert_string_contains(response, "Unbekannter Befehl")

func test_empty_line_returns_empty_response() -> void:
	var session := _console.new_session()
	session.handle_line("login alice alice-pass")
	var response := session.handle_line("   ")
	assert_eq(response, "")

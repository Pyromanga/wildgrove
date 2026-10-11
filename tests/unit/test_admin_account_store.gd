# res://tests/unit/test_admin_account_store.gd
extends GutTest

## Tests für AdminAccountStore (ADR-040) — Mehrkonten-Auth für den
## Tier-3-Admin-Zugang.
##
## WICHTIG: Diese Tests schreiben echte Dateien nach user:// (Test-Environment).
## TEST_PATH ist eigens für diese Tests, kollidiert nicht mit DEFAULT_SAVE_PATH.

const TEST_PATH := "user://unit_test_admin_accounts.json"

var _store: AdminAccountStore

func before_each() -> void:
	_store = AdminAccountStore.new(TEST_PATH)

func after_each() -> void:
	_store = null
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)
	if FileAccess.file_exists(TEST_PATH + ".tmp"):
		DirAccess.remove_absolute(TEST_PATH + ".tmp")

# ─────────────────────────────────────────────
# ensure_bootstrap_account()
# ─────────────────────────────────────────────

func test_bootstrap_creates_root_account_on_empty_store() -> void:
	var password := _store.ensure_bootstrap_account()
	assert_false(password.is_empty(), "Bootstrap muss ein Klartext-Passwort zurückgeben.")
	assert_true(_store.has_account("root"), "Bootstrap muss ein 'root'-Konto anlegen.")

func test_bootstrap_sets_must_rotate() -> void:
	_store.ensure_bootstrap_account()
	assert_true(_store.must_rotate("root"),
		"Frisch angelegtes Bootstrap-Konto muss must_rotate=true haben.")

func test_bootstrap_password_actually_verifies() -> void:
	var password := _store.ensure_bootstrap_account()
	assert_true(_store.verify_password("root", password),
		"Das von ensure_bootstrap_account() zurückgegebene Passwort muss gegen den Store verifizieren.")

func test_bootstrap_is_idempotent_when_accounts_exist() -> void:
	_store.ensure_bootstrap_account()
	var second_call := _store.ensure_bootstrap_account()
	assert_true(second_call.is_empty(),
		"Ein zweiter ensure_bootstrap_account()-Aufruf bei bestehenden Konten darf kein neues Passwort erzeugen.")

func test_bootstrap_skipped_if_any_account_already_exists() -> void:
	_store.create_account("alice")
	var password := _store.ensure_bootstrap_account()
	assert_true(password.is_empty(),
		"Bootstrap darf nicht laufen, wenn bereits (irgend)ein Konto existiert.")
	assert_false(_store.has_account("root"),
		"Ohne Bootstrap darf kein root-Konto entstehen.")

# ─────────────────────────────────────────────
# create_account()
# ─────────────────────────────────────────────

func test_create_account_returns_password_and_registers_account() -> void:
	var password := _store.create_account("alice")
	assert_false(password.is_empty())
	assert_true(_store.has_account("alice"))

func test_create_account_sets_must_rotate() -> void:
	_store.create_account("alice")
	assert_true(_store.must_rotate("alice"),
		"Neu angelegtes Konto muss must_rotate=true haben (Temp-Passwort).")

func test_create_account_duplicate_username_rejected() -> void:
	_store.create_account("alice")
	var second := _store.create_account("alice")
	assert_true(second.is_empty(), "Doppelter Username darf kein zweites Konto anlegen.")

func test_create_account_empty_username_rejected() -> void:
	var password := _store.create_account("")
	assert_true(password.is_empty(), "Leerer Username muss abgelehnt werden.")

# ─────────────────────────────────────────────
# verify_password()
# ─────────────────────────────────────────────

func test_verify_password_correct_accepts() -> void:
	var password := _store.create_account("alice")
	assert_true(_store.verify_password("alice", password))

func test_verify_password_wrong_rejects() -> void:
	_store.create_account("alice")
	assert_false(_store.verify_password("alice", "definitely-wrong"))

func test_verify_password_unknown_username_rejects() -> void:
	assert_false(_store.verify_password("never-created", "anything"))

# ─────────────────────────────────────────────
# set_password()
# ─────────────────────────────────────────────

func test_set_password_changes_credential() -> void:
	_store.create_account("alice")
	_store.set_password("alice", "new-secure-password")
	assert_true(_store.verify_password("alice", "new-secure-password"))

func test_set_password_clears_must_rotate() -> void:
	_store.create_account("alice")
	_store.set_password("alice", "new-secure-password")
	assert_false(_store.must_rotate("alice"),
		"set_password() muss must_rotate löschen — sonst könnte sich niemand jemals 'freischalten'.")

func test_set_password_old_password_no_longer_works() -> void:
	var old_password := _store.create_account("alice")
	_store.set_password("alice", "new-secure-password")
	assert_false(_store.verify_password("alice", old_password),
		"Nach set_password() darf das alte Passwort nicht mehr funktionieren.")

func test_set_password_unknown_username_returns_false() -> void:
	assert_false(_store.set_password("never-created", "whatever"))

func test_set_password_empty_password_rejected() -> void:
	_store.create_account("alice")
	var ok := _store.set_password("alice", "")
	assert_false(ok, "Leeres Passwort darf nicht akzeptiert werden.")

# ─────────────────────────────────────────────
# revoke_account()
# ─────────────────────────────────────────────

func test_revoke_account_removes_it() -> void:
	_store.create_account("alice")
	_store.create_account("bob")
	var ok := _store.revoke_account("alice")
	assert_true(ok)
	assert_false(_store.has_account("alice"))
	assert_true(_store.has_account("bob"))

func test_revoke_account_unknown_username_returns_false() -> void:
	assert_false(_store.revoke_account("never-created"))

func test_revoke_last_remaining_account_rejected() -> void:
	_store.create_account("alice")
	var ok := _store.revoke_account("alice")
	assert_false(ok, "Das letzte verbleibende Admin-Konto darf nicht entfernt werden können.")
	assert_true(_store.has_account("alice"))

func test_revoke_allowed_when_multiple_accounts_remain_down_to_last() -> void:
	_store.create_account("alice")
	_store.create_account("bob")
	assert_true(_store.revoke_account("alice"))
	# Jetzt ist "bob" das letzte Konto — darf nicht mehr entfernt werden.
	assert_false(_store.revoke_account("bob"))

# ─────────────────────────────────────────────
# list_usernames()
# ─────────────────────────────────────────────

func test_list_usernames_reflects_created_accounts() -> void:
	_store.create_account("alice")
	_store.create_account("bob")
	var names := _store.list_usernames()
	assert_true(names.has("alice"))
	assert_true(names.has("bob"))
	assert_eq(names.size(), 2)

func test_list_usernames_empty_for_fresh_store() -> void:
	assert_eq(_store.list_usernames().size(), 0)

# ─────────────────────────────────────────────
# Persistenz (load/save)
# ─────────────────────────────────────────────

func test_create_account_persists_immediately() -> void:
	_store.create_account("alice")
	assert_true(FileAccess.file_exists(TEST_PATH),
		"Ein neu angelegtes Konto muss sofort auf Disk persistiert werden.")

func test_accounts_survive_reload() -> void:
	var password := _store.create_account("alice")

	var reloaded := AdminAccountStore.new(TEST_PATH)
	reloaded.load()
	assert_true(reloaded.has_account("alice"))
	assert_true(reloaded.verify_password("alice", password))

func test_must_rotate_survives_reload() -> void:
	_store.create_account("alice")
	var reloaded := AdminAccountStore.new(TEST_PATH)
	reloaded.load()
	assert_true(reloaded.must_rotate("alice"))

func test_password_change_survives_reload() -> void:
	_store.create_account("alice")
	_store.set_password("alice", "new-secure-password")

	var reloaded := AdminAccountStore.new(TEST_PATH)
	reloaded.load()
	assert_true(reloaded.verify_password("alice", "new-secure-password"))
	assert_false(reloaded.must_rotate("alice"))

func test_load_with_missing_file_starts_empty() -> void:
	assert_false(FileAccess.file_exists(TEST_PATH), "Testvoraussetzung: Datei existiert nicht.")
	_store.load()  # darf nicht crashen
	assert_eq(_store.list_usernames().size(), 0)

func test_load_with_corrupt_file_starts_empty_without_crash() -> void:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("{ not valid json ][")
	file.close()

	_store.load()  # darf nicht crashen
	assert_eq(_store.list_usernames().size(), 0,
		"Korrupte Datei muss zu leerem State führen, nicht zum Absturz.")

func test_password_stored_as_hash_not_plaintext_on_disk() -> void:
	var password := _store.create_account("alice")
	var file := FileAccess.open(TEST_PATH, FileAccess.READ)
	var content := file.get_as_text()
	file.close()
	assert_false(content.contains(password),
		"Das rohe Passwort darf NIE im Klartext auf Disk landen — nur Salt + Hash.")

func test_two_accounts_with_same_password_have_different_hashes() -> void:
	_store.create_account("alice")
	_store.set_password("alice", "identical-password")
	_store.create_account("bob")
	_store.set_password("bob", "identical-password")

	var file := FileAccess.open(TEST_PATH, FileAccess.READ)
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	json.parse(text)
	var data: Dictionary = json.data
	assert_ne(data["alice"]["password_hash"], data["bob"]["password_hash"],
		"Unterschiedliche Salts müssen bei identischem Passwort zu unterschiedlichen Hashes führen.")

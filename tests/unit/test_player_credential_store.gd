# res://tests/unit/test_player_credential_store.gd
extends GutTest

## Tests für PlayerCredentialStore (ADR-029, 3a) — Trust-on-First-Use-Verifikation.
##
## WICHTIG: Diese Tests schreiben echte Dateien nach user:// (Test-Environment).
## TEST_PATH ist eigens für diese Tests, kollidiert nicht mit DEFAULT_SAVE_PATH
## (siehe PlayerCredentialStore._init()-Parameter).

const TEST_PATH := "user://unit_test_server_credentials.json"

var _store: PlayerCredentialStore

func before_each() -> void:
	_store = PlayerCredentialStore.new(TEST_PATH)

func after_each() -> void:
	_store = null
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)
	if FileAccess.file_exists(TEST_PATH + ".tmp"):
		DirAccess.remove_absolute(TEST_PATH + ".tmp")

# ─────────────────────────────────────────────
# verify_or_register() — TOFU-Kernverhalten
# ─────────────────────────────────────────────

func test_first_contact_accepts_and_registers() -> void:
	var ok := _store.verify_or_register("uuid-a", "secret-a")
	assert_true(ok, "Erster Kontakt für eine player_uuid muss akzeptiert werden.")
	assert_true(_store.has_registered("uuid-a"),
		"Nach erstem Kontakt muss die player_uuid registriert sein.")

func test_matching_secret_on_reconnect_accepts() -> void:
	_store.verify_or_register("uuid-a", "secret-a")
	var ok := _store.verify_or_register("uuid-a", "secret-a")
	assert_true(ok, "Erneuter Kontakt mit demselben Secret muss akzeptiert werden.")

func test_mismatched_secret_rejects() -> void:
	_store.verify_or_register("uuid-a", "secret-a")
	var ok := _store.verify_or_register("uuid-a", "attacker-secret")
	assert_false(ok, "Abweichendes Secret für eine bekannte player_uuid muss abgelehnt werden.")

func test_mismatched_secret_does_not_overwrite_registered_hash() -> void:
	_store.verify_or_register("uuid-a", "secret-a")
	_store.verify_or_register("uuid-a", "attacker-secret")
	var ok := _store.verify_or_register("uuid-a", "secret-a")
	assert_true(ok,
		"Ein fehlgeschlagener Versuch darf das ursprünglich registrierte Secret nicht überschreiben.")

func test_different_uuids_are_independent() -> void:
	_store.verify_or_register("uuid-a", "secret-a")
	var ok := _store.verify_or_register("uuid-b", "secret-b")
	assert_true(ok, "Eine andere player_uuid ist ein eigener erster Kontakt, unabhängig von uuid-a.")

func test_empty_uuid_rejected() -> void:
	assert_false(_store.verify_or_register("", "secret-a"),
		"Leere player_uuid muss abgelehnt werden.")

func test_empty_secret_rejected() -> void:
	assert_false(_store.verify_or_register("uuid-a", ""),
		"Leeres Secret muss abgelehnt werden.")

# ─────────────────────────────────────────────
# has_registered()
# ─────────────────────────────────────────────

func test_has_registered_false_for_unknown_uuid() -> void:
	assert_false(_store.has_registered("never-seen"),
		"Unbekannte player_uuid darf nicht als registriert gelten.")

func test_has_registered_true_after_first_contact() -> void:
	_store.verify_or_register("uuid-a", "secret-a")
	assert_true(_store.has_registered("uuid-a"))

# ─────────────────────────────────────────────
# Persistenz (load/save, eigene Datei — Entscheidung Round 60)
# ─────────────────────────────────────────────

func test_verify_or_register_persists_immediately_on_first_contact() -> void:
	## Kommentar in der Klasse: "Ein Crash zwischen Handshake-Zusage und
	## nächstem regulären Speicherpunkt darf die frisch vertraute Identität
	## nicht verlieren" — save() muss also SOFORT bei Erst-Registrierung laufen,
	## nicht erst bei einem späteren expliziten save()-Aufruf.
	_store.verify_or_register("uuid-a", "secret-a")
	assert_true(FileAccess.file_exists(TEST_PATH),
		"Erst-Registrierung muss sofort auf Disk persistiert werden.")

func test_credentials_survive_reload() -> void:
	_store.verify_or_register("uuid-a", "secret-a")

	var reloaded := PlayerCredentialStore.new(TEST_PATH)
	reloaded.load()
	var ok := reloaded.verify_or_register("uuid-a", "secret-a")
	assert_true(ok,
		"Nach load() muss eine zuvor registrierte player_uuid weiterhin ihr Secret verlangen.")

	var rejected := reloaded.verify_or_register("uuid-a", "wrong-secret")
	assert_false(rejected,
		"Nach load() muss ein falsches Secret für eine bekannte player_uuid weiterhin abgelehnt werden.")

func test_load_with_missing_file_starts_empty() -> void:
	assert_false(FileAccess.file_exists(TEST_PATH), "Testvoraussetzung: Datei existiert nicht.")
	_store.load()  # darf nicht crashen
	assert_false(_store.has_registered("uuid-a"),
		"Ohne bestehende Datei darf keine player_uuid als registriert gelten.")

func test_load_with_corrupt_file_starts_empty_without_crash() -> void:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("{ not valid json ][")
	file.close()

	_store.load()  # darf nicht crashen
	assert_false(_store.has_registered("uuid-a"),
		"Korrupte Datei muss zu leerem State führen, nicht zum Absturz.")

func test_secret_stored_as_hash_not_plaintext_on_disk() -> void:
	_store.verify_or_register("uuid-a", "super-secret-value")
	var file := FileAccess.open(TEST_PATH, FileAccess.READ)
	var content := file.get_as_text()
	file.close()
	assert_false(content.contains("super-secret-value"),
		"Das rohe Secret darf NIE im Klartext auf Disk landen — nur der SHA-256-Hash.")

func test_different_store_instances_with_same_path_share_state_after_reload() -> void:
	var store_a := PlayerCredentialStore.new(TEST_PATH)
	store_a.verify_or_register("uuid-a", "secret-a")

	var store_b := PlayerCredentialStore.new(TEST_PATH)
	store_b.load()
	assert_true(store_b.has_registered("uuid-a"),
		"Eine zweite Instanz mit demselben Pfad muss nach load() denselben Stand sehen (Server-Neustart-Fall).")

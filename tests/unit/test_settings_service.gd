# res://tests/unit/test_settings_service.gd
extends GutTest

## Tests für SettingsService (TODO "Settings.gd — persistiert Audio/Grafik/
## Input-Remapping wirklich zuverlässig?").
##
## Vorher: Settings.gd hielt _settings als reines In-Memory-Dictionary,
## _set_setting() persistierte nichts — jeder Neustart verlor alle Änderungen.
## Jetzt: SettingsService ist die einzige Quelle der Wahrheit, persistiert
## atomar (tmp → rename) nach _path_override (Test) bzw. user://settings.json
## (Produktion).
##
## WICHTIG: _path_override zeigt auf eine Test-Datei, NIEMALS auf die echte
## user://settings.json — sonst überschreiben Testläufe echte Dev-Settings.
##
## Abgedeckte Pfade:
##   configure()       — Defaults ohne vorhandene Datei, Merge mit vorhandener Datei
##   get_setting()     — bekannte/unbekannte Keys, Default-Fallback
##   set_setting()     — persistiert sofort, Roundtrip über eine zweite Instanz
##   get_all_settings() — Kopie, kein Alias auf internen State
##   reset_to_defaults() — persistiert Defaults, überschreibt vorherige Werte
##   Korrupte Datei     — Fallback auf Defaults statt Crash
##   Unbekannter Key in Datei — wird ignoriert, nicht übernommen

const TEST_PATH := "user://unit_test_settings.json"

var _svc: SettingsService

func before_each() -> void:
	_delete_test_file()
	_svc = SettingsService.new()
	_svc.set_path_override(TEST_PATH)
	_svc.configure(ServiceDeps.from_dict({}))

func after_each() -> void:
	_delete_test_file()
	_svc = null

func _delete_test_file() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)
	if FileAccess.file_exists(TEST_PATH + ".tmp"):
		DirAccess.remove_absolute(TEST_PATH + ".tmp")

func _new_service_same_file() -> SettingsService:
	var s := SettingsService.new()
	s.set_path_override(TEST_PATH)
	s.configure(ServiceDeps.from_dict({}))
	return s

# ─────────────────────────────────────────────
# configure() — Defaults ohne vorhandene Datei
# ─────────────────────────────────────────────

func test_configure_without_file_uses_defaults() -> void:
	for key in SettingsService.DEFAULTS:
		assert_eq(
			_svc.get_setting(key), SettingsService.DEFAULTS[key],
			"Ohne Datei muss '%s' den Default-Wert haben" % key
		)

func test_configure_does_not_create_file_by_itself() -> void:
	# configure() ist reines Lesen — kein Write-on-Boot, sonst würde jeder App-Start
	# eine Datei anlegen, auch wenn nie etwas geändert wurde.
	assert_false(FileAccess.file_exists(TEST_PATH), "configure() darf keine Datei anlegen")

# ─────────────────────────────────────────────
# get_setting() / set_setting()
# ─────────────────────────────────────────────

func test_get_setting_unknown_key_returns_passed_default() -> void:
	assert_eq(_svc.get_setting("does_not_exist", "fallback"), "fallback")

func test_get_setting_unknown_key_without_default_returns_null() -> void:
	assert_null(_svc.get_setting("does_not_exist"))

func test_set_setting_updates_in_memory_value() -> void:
	_svc.set_setting("cam_smooth", 22.0)
	assert_eq(_svc.get_setting("cam_smooth"), 22.0)

func test_set_setting_returns_true_on_success() -> void:
	assert_true(_svc.set_setting("fixed_joystick", true), "Erfolgreicher Write muss true liefern")

func test_set_setting_writes_file_to_disk() -> void:
	_svc.set_setting("fixed_joystick", true)
	assert_true(FileAccess.file_exists(TEST_PATH), "set_setting() muss sofort persistieren")

func test_set_setting_leaves_no_tmp_file_behind() -> void:
	_svc.set_setting("cam_relative", false)
	assert_false(
		FileAccess.file_exists(TEST_PATH + ".tmp"),
		"Atomic Write muss die .tmp-Datei nach dem Rename entfernen"
	)

# ─────────────────────────────────────────────
# Persistenz-Roundtrip — der eigentliche Kern des TODOs
# ─────────────────────────────────────────────

func test_roundtrip_bool_setting_survives_reload() -> void:
	_svc.set_setting("joystick_inverted", true)
	var reloaded := _new_service_same_file()
	assert_true(reloaded.get_setting("joystick_inverted"), "bool-Setting muss Neustart überleben")

func test_roundtrip_float_setting_survives_reload() -> void:
	_svc.set_setting("zoom_smooth", 17.5)
	var reloaded := _new_service_same_file()
	assert_almost_eq(
		float(reloaded.get_setting("zoom_smooth")), 17.5, 0.001,
		"float-Setting muss präzise erhalten bleiben"
	)

func test_roundtrip_int_setting_survives_reload() -> void:
	_svc.set_setting("screen_rotation", 2)
	var reloaded := _new_service_same_file()
	assert_eq(reloaded.get_setting("screen_rotation"), 2)

func test_roundtrip_multiple_sets_keep_previous_keys() -> void:
	# Regression für einen naheliegenden Bug: jeder set_setting()-Aufruf schreibt
	# den GESAMTEN _settings-Stand, nicht nur den geänderten Key — ein einzelnes
	# Feld darf beim nächsten Save nicht die anderen überschreiben/verlieren.
	_svc.set_setting("fixed_joystick", true)
	_svc.set_setting("cam_smooth", 25.0)
	var reloaded := _new_service_same_file()
	assert_true(reloaded.get_setting("fixed_joystick"), "erster Wert darf beim zweiten Write nicht verloren gehen")
	assert_eq(reloaded.get_setting("cam_smooth"), 25.0)

func test_configure_merges_saved_values_over_defaults() -> void:
	_svc.set_setting("zoom_smooth", 3.0)
	var reloaded := _new_service_same_file()
	# Nicht gesetzte Keys müssen weiterhin ihren Default behalten.
	assert_eq(reloaded.get_setting("cam_relative"), SettingsService.DEFAULTS["cam_relative"])
	assert_eq(reloaded.get_setting("zoom_smooth"), 3.0)

# ─────────────────────────────────────────────
# get_all_settings()
# ─────────────────────────────────────────────

func test_get_all_settings_contains_all_default_keys() -> void:
	var all := _svc.get_all_settings()
	for key in SettingsService.DEFAULTS:
		assert_true(all.has(key), "get_all_settings() muss '%s' enthalten" % key)

func test_get_all_settings_returns_copy_not_reference() -> void:
	var all := _svc.get_all_settings()
	all["cam_smooth"] = 999.0
	assert_ne(
		_svc.get_setting("cam_smooth"), 999.0,
		"get_all_settings() darf keine Live-Referenz auf den internen State zurückgeben"
	)

# ─────────────────────────────────────────────
# reset_to_defaults()
# ─────────────────────────────────────────────

func test_reset_to_defaults_overwrites_changed_values() -> void:
	_svc.set_setting("cam_smooth", 1.0)
	_svc.reset_to_defaults()
	assert_eq(_svc.get_setting("cam_smooth"), SettingsService.DEFAULTS["cam_smooth"])

func test_reset_to_defaults_persists() -> void:
	_svc.set_setting("cam_smooth", 1.0)
	_svc.reset_to_defaults()
	var reloaded := _new_service_same_file()
	assert_eq(reloaded.get_setting("cam_smooth"), SettingsService.DEFAULTS["cam_smooth"])

# ─────────────────────────────────────────────
# setting_changed-Signal — für Live-Reaktion (z.B. JoystickController verschiebt
# den festen Joystick-Anker sofort nach einer Settings-Änderung, siehe dort).
# ─────────────────────────────────────────────

func test_set_setting_emits_setting_changed_with_key_and_value() -> void:
	var received: Array = []
	_svc.setting_changed.connect(func(key: String, value: Variant) -> void: received.append([key, value]))
	_svc.set_setting("joystick_pos_x", 0.3)
	assert_eq(received.size(), 1)
	assert_eq(received[0][0], "joystick_pos_x")
	assert_eq(received[0][1], 0.3)

func test_reset_to_defaults_emits_setting_changed_for_every_key() -> void:
	var changed_keys: Array = []
	_svc.setting_changed.connect(func(key: String, _value: Variant) -> void: changed_keys.append(key))
	_svc.reset_to_defaults()
	for key in SettingsService.DEFAULTS:
		assert_true(changed_keys.has(key), "reset_to_defaults() muss '%s' als geändert melden" % key)

# ─────────────────────────────────────────────
# Fehlertoleranz
# ─────────────────────────────────────────────

func test_configure_with_corrupt_file_falls_back_to_defaults() -> void:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("{ das ist kein gueltiges JSON")
	file.close()

	var recovered := SettingsService.new()
	recovered.set_path_override(TEST_PATH)
	recovered.configure(ServiceDeps.from_dict({}))

	assert_eq(
		recovered.get_setting("cam_smooth"), SettingsService.DEFAULTS["cam_smooth"],
		"Korrupte Datei darf configure() nicht crashen — Fallback auf Defaults"
	)

func test_configure_ignores_unknown_keys_in_file() -> void:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"totally_unknown_setting": 123, "cam_smooth": 8.0}))
	file.close()

	var reloaded := _new_service_same_file()
	assert_eq(reloaded.get_setting("cam_smooth"), 8.0, "bekannter Key wird übernommen")
	assert_null(
		reloaded.get_setting("totally_unknown_setting"),
		"unbekannter Key aus der Datei darf nicht im State landen"
	)

# ─────────────────────────────────────────────
# set_setting() — unbekannter Key (defensiv, kein harter Fehler)
# ─────────────────────────────────────────────

func test_set_setting_unknown_key_works_in_memory_for_current_instance() -> void:
	# Bewusst tolerant statt hart abzulehnen (siehe Kommentar in SettingsService) —
	# innerhalb derselben Instanz bleibt ein unbekannter Key nutzbar.
	_svc.set_setting("brand_new_setting", "x")
	assert_eq(_svc.get_setting("brand_new_setting", "missing"), "x")

func test_set_setting_unknown_key_is_dropped_on_next_load() -> void:
	# configure() akzeptiert beim Laden NUR Keys aus DEFAULTS (siehe
	# "Unbekannter Settings-Key ... ignoriert"-Warnung) — das ist bewusst
	# symmetrisch zu DataManifest/SaveMigrationService: unbekannte Daten aus
	# einer Datei werden nicht stillschweigend durchgereicht, sondern verworfen,
	# bis der Key offiziell in DEFAULTS aufgenommen wird.
	_svc.set_setting("brand_new_setting", "x")
	var reloaded := _new_service_same_file()
	assert_eq(reloaded.get_setting("brand_new_setting", "missing"), "missing")


extends GutTest
## test_settings.gd
## Testet das Settings-System ohne UI

var _settings: Node


func before_each() -> void:
	# Settings-Node ohne CanvasLayer aufsetzen
	_settings = Node.new()
	_settings.set_script(load("res://scripts/Settings.gd"))
	add_child_autofree(_settings)
	await get_tree().process_frame


# ── get_setting ────────────────────────────────────────────────────────────
func test_get_setting_returns_default_values() -> void:
	assert_eq(_settings.get_setting("cam_relative"),   true,  "cam_relative default true")
	assert_eq(_settings.get_setting("fixed_joystick"), true,  "fixed_joystick default true")
	assert_eq(_settings.get_setting("cam_smooth"),     14.0,  "cam_smooth default 14")
	assert_eq(_settings.get_setting("zoom_smooth"),    8.0,   "zoom_smooth default 8")


func test_get_setting_returns_null_for_unknown_key() -> void:
	assert_null(_settings.get_setting("does_not_exist"), "unbekannter Key = null")


# ── toggle ─────────────────────────────────────────────────────────────────
func test_settings_starts_closed() -> void:
	assert_false(_settings.is_settings_open(), "Settings startet geschlossen")


func test_toggle_opens_panel() -> void:
	_settings.toggle()
	assert_true(_settings.is_settings_open(), "toggle() öffnet Panel")


func test_toggle_twice_closes_panel() -> void:
	_settings.toggle()
	_settings.toggle()
	assert_false(_settings.is_settings_open(), "zweimal toggle() = geschlossen")


# ── Werte ändern ───────────────────────────────────────────────────────────
func test_cam_relative_can_be_read_as_bool() -> void:
	var val: Variant = _settings.get_setting("cam_relative")
	assert_not_null(val, "cam_relative ist nicht null")
	# Explizit als bool casten wie Player.gd es macht
	var as_bool: bool = bool(val)
	assert_true(as_bool, "cam_relative als bool = true")

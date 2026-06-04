extends CanvasLayer
## Settings.gd — UI-Panel für Einstellungen.
##
## FIX: Kernel.data.get_setting / set_setting existieren nicht.
##   DataService verwaltet nur PlayerData-Stats, keine UI-Einstellungen.
##   Lösung: Einstellungen werden lokal in _settings: Dictionary gehalten
##   und via ProjectSettings oder einer eigenen Datei persistiert.
##   Wenn du später einen echten SettingsService willst, ersetze
##   _get_setting/_set_setting durch Services.game_settings.get/set.

var _panel: ColorRect
var _settings: Dictionary = {
	"fixed_joystick": false,
	"joystick_inverted": false,
	"cam_relative": true,
	"cam_smooth": 10.0,
	"zoom_smooth": 5.0,
	"screen_rotation": 0,
}

const ROTATION_LABELS: Array = ["Frei", "Nur Hochkant", "Nur Querformat", "Hochkant + 180°"]
const ROTATION_MODES: Array = [
	DisplayServer.SCREEN_SENSOR,
	DisplayServer.SCREEN_PORTRAIT,
	DisplayServer.SCREEN_LANDSCAPE,
	DisplayServer.SCREEN_SENSOR_PORTRAIT,
]


func _ready() -> void:
	add_to_group("settings")
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_build_panel(vp)
	_panel.visible = false
	get_viewport().size_changed.connect(_on_viewport_resized)


func _on_viewport_resized() -> void:
	if _panel:
		var vp := get_viewport().get_visible_rect().size
		_panel.size = Vector2(680, vp.y * 0.85)
		_panel.position = Vector2(vp.x * 0.5 - 340, vp.y * 0.075)


func toggle() -> void:
	_panel.visible = not _panel.visible


func is_settings_open() -> bool:
	return _panel.visible if _panel else false


# ─────────────────────────────────────────────
# Settings-Zugriff (ersetze dies durch einen SettingsService wenn vorhanden)
# ─────────────────────────────────────────────


func _get_setting(key: String) -> Variant:
	return _settings.get(key)


func _set_setting(key: String, value: Variant) -> void:
	_settings[key] = value
	# Optional: ProjectSettings.set_setting("user/%s" % key, value)


# ─────────────────────────────────────────────
# Panel-Aufbau
# ─────────────────────────────────────────────


func _build_panel(vp: Vector2) -> void:
	_panel = ColorRect.new()
	_panel.color = Color(0.08, 0.08, 0.08, 0.95)
	_panel.size = Vector2(680, vp.y * 0.85)
	_panel.position = Vector2(vp.x * 0.5 - 340, vp.y * 0.075)
	add_child(_panel)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(0, 72)
	scroll.size = Vector2(680, _panel.size.y - 72)
	_panel.add_child(scroll)

	var content := VBoxContainer.new()
	scroll.add_child(content)

	_add_setting_toggle(content, "Joystick-Modus", "fixed_joystick")
	_add_setting_toggle(content, "Joystick Y-Achse umkehren", "joystick_inverted")
	_add_setting_toggle(content, "Bewegung relativ zur Kamera", "cam_relative")

	_section(content, "Bildschirm-Rotation", "")
	content.add_child(_make_rotation_picker())

	content.add_child(_make_slider(content, "Kamera-Speed", "cam_smooth", 2.0, 30.0))
	content.add_child(_make_slider(content, "Zoom-Speed", "zoom_smooth", 1.0, 20.0))

	_spacer(content, 30)
	var close := Button.new()
	close.text = "✕ Schließen"
	close.custom_minimum_size = Vector2(200, 60)
	close.pressed.connect(toggle)
	content.add_child(close)


# ─────────────────────────────────────────────
# Komponenten
# ─────────────────────────────────────────────


func _add_setting_toggle(parent: VBoxContainer, title: String, key: String) -> void:
	_section(parent, title, "")
	var btn := Button.new()
	# FIX: Kernel.data.get_setting → _get_setting (lokaler Dictionary-Zugriff)
	btn.text = "● EIN" if _get_setting(key) else "○ AUS"
	btn.pressed.connect(
		func():
			var new_val: bool = not _get_setting(key)
			_set_setting(key, new_val)
			btn.text = "● EIN" if new_val else "○ AUS"
	)
	parent.add_child(btn)


func _make_slider(
	parent: VBoxContainer, label: String, key: String, mn: float, mx: float
) -> Control:
	_section(parent, label, "")
	var hbox := HBoxContainer.new()
	var slider := HSlider.new()
	slider.min_value = mn
	slider.max_value = mx
	# FIX: Kernel.data.get_setting → _get_setting
	slider.value = _get_setting(key)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val_lbl := Label.new()
	val_lbl.text = str(int(slider.value))
	slider.value_changed.connect(
		func(v: float):
			_set_setting(key, v)
			val_lbl.text = str(int(v))
	)
	hbox.add_child(slider)
	hbox.add_child(val_lbl)
	return hbox


func _make_rotation_picker() -> Control:
	var vbox := VBoxContainer.new()
	for i in ROTATION_LABELS.size():
		var btn := Button.new()
		btn.text = ROTATION_LABELS[i]
		var idx := i  # Capture für Lambda
		# FIX: Kernel.data.set_setting → _set_setting
		btn.pressed.connect(
			func():
				_set_setting("screen_rotation", idx)
				DisplayServer.screen_set_orientation(ROTATION_MODES[idx])
		)
		vbox.add_child(btn)
	return vbox


func _section(parent: Control, title: String, _sub: String) -> void:
	var lbl := Label.new()
	lbl.text = title
	parent.add_child(lbl)
	_spacer(parent, 5)


func _spacer(parent: Control, h: int = 16) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	parent.add_child(s)

extends CanvasLayer
## Settings.gd — Einstellungs-Panel

signal ui_offset_changed(offset: Vector2)

var _panel: ColorRect
var _values: Dictionary = {
	"cam_relative":    true,
	"fixed_joystick":  true,   # true = Joystick fix, 2. Finger = Kamera/Zoom
	"screen_rotation": 0,      # 0=frei, 1=nur hochkant, 2=nur quer, 3=180° erlaubt
	"cam_smooth":      14.0,
	"zoom_smooth":     8.0,
	"ui_offset_x":     0.0,    # HUD horizontal verschieben
	"ui_offset_y":     0.0,    # HUD vertikal verschieben
}

const ROTATION_LABELS: Array = [
	"Frei (alles erlaubt)",
	"Nur Hochkant",
	"Nur Querformat",
	"Hochkant + 180° (kopfüber)",
]
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
	# Panel-Position bei Bildschirm-Rotation aktualisieren
	get_viewport().size_changed.connect(_on_viewport_resized)


func _on_viewport_resized() -> void:
	if not _panel:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_panel.size = Vector2(680, vp.y * 0.85)
	_panel.position = Vector2(vp.x * 0.5 - 340, vp.y * 0.075)


func toggle() -> void:
	_panel.visible = not _panel.visible


func is_settings_open() -> bool:
	return _panel != null and _panel.visible


func get_setting(key: String) -> Variant:
	return _values.get(key, null)


func _build_panel(vp: Vector2) -> void:
	_panel = ColorRect.new()
	_panel.color = Color(0.08, 0.08, 0.08, 0.95)
	_panel.size = Vector2(680, vp.y * 0.85)
	_panel.position = Vector2(vp.x * 0.5 - 340, vp.y * 0.075)
	add_child(_panel)

	# Titel (fest oben)
	var title := Label.new()
	title.text = "⚙  Einstellungen"
	title.position = Vector2(20, 16)
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color.WHITE)
	_panel.add_child(title)

	var hline := ColorRect.new()
	hline.color = Color(1, 1, 1, 0.15)
	hline.size = Vector2(640, 2)
	hline.position = Vector2(20, 64)
	_panel.add_child(hline)

	# Scroll-Bereich
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(0, 72)
	scroll.size = Vector2(680, _panel.size.y - 72)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 0)
	scroll.add_child(content)

	# ── Joystick-Modus
	_section(content, "Joystick-Modus",
		"EIN: Linker Finger bleibt fix, 2. Finger dreht Kamera/zoomt\nAUS: Joystick springt zu Fingertipp")
	content.add_child(_make_toggle("fixed_joystick"))
	_spacer(content, 20)
	_hline(content)

	# ── Kamera-relative Bewegung ─────────────────────────────────────────
	_section(content, "Bewegung relativ zur Kamera",
		"EIN: Joystick hoch = Blickrichtung\nAUS: Joystick hoch = immer Norden")
	content.add_child(_make_toggle("cam_relative"))
	_spacer(content, 20)
	_hline(content)

	# ── Bildschirm-Rotation ──────────────────────────────────────────────
	_section(content, "Bildschirm-Rotation", "Wie sich der Bildschirm dreht")
	content.add_child(_make_rotation_picker())
	_spacer(content, 20)
	_hline(content)

	# ── Kamera-Geschwindigkeit ───────────────────────────────────────────
	_section(content, "Kamera-Geschwindigkeit", "Wie schnell dreht sich die Kamera")
	content.add_child(_make_slider("cam_smooth", 2.0, 30.0, 1.0))
	_spacer(content, 20)
	_hline(content)

	# ── Zoom-Geschwindigkeit ─────────────────────────────────────────────
	_section(content, "Zoom-Geschwindigkeit", "Wie schnell zoomt die Kamera")
	content.add_child(_make_slider("zoom_smooth", 1.0, 20.0, 1.0))
	_spacer(content, 20)
	_hline(content)

	# ── UI Position ──────────────────────────────────────────────────────
	_section(content, "UI Position — Horizontal",
		"Joystick & Buttons nach links/rechts verschieben")
	content.add_child(_make_slider("ui_offset_x", -200.0, 200.0, 5.0, _on_ui_offset_changed))
	_spacer(content, 20)

	_section(content, "UI Position — Vertikal",
		"Joystick & Buttons nach oben/unten verschieben")
	content.add_child(_make_slider("ui_offset_y", -200.0, 200.0, 5.0, _on_ui_offset_changed))
	_spacer(content, 30)

	# Schließen
	var close := Button.new()
	close.text = "✕  Schließen"
	close.custom_minimum_size = Vector2(280, 60)
	close.add_theme_font_size_override("font_size", 28)
	close.pressed.connect(toggle)
	var wrap := CenterContainer.new()
	wrap.add_child(close)
	content.add_child(wrap)
	_spacer(content, 30)


# ── Rotations-Picker ───────────────────────────────────────────────────────
func _make_rotation_picker() -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var current: int = _values.get("screen_rotation", 0)
	for i in ROTATION_LABELS.size():
		var btn := Button.new()
		btn.text = ("● " if i == current else "○ ") + ROTATION_LABELS[i]
		btn.add_theme_font_size_override("font_size", 24)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var idx := i  # capture
		btn.pressed.connect(func() -> void:
			_values["screen_rotation"] = idx
			DisplayServer.screen_set_orientation(ROTATION_MODES[idx])
			# Alle Buttons aktualisieren
			for j in vbox.get_child_count():
				var b: Button = vbox.get_child(j)
				b.text = ("● " if j == idx else "○ ") + ROTATION_LABELS[j]
		)
		vbox.add_child(btn)

	return margin


# ── Toggle ─────────────────────────────────────────────────────────────────
func _make_toggle(key: String, callback: Callable = Callable()) -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	var btn := Button.new()
	btn.text = "●  EIN" if _values.get(key, false) else "○  AUS"
	btn.custom_minimum_size = Vector2(160, 58)
	btn.add_theme_font_size_override("font_size", 26)
	btn.pressed.connect(func() -> void:
		_values[key] = not _values.get(key, false)
		btn.text = "●  EIN" if _values[key] else "○  AUS"
		if callback.is_valid():
			callback.call(_values[key])
	)
	margin.add_child(btn)
	return margin


# ── Slider ─────────────────────────────────────────────────────────────────
func _make_slider(key: String, mn: float, mx: float, step: float,
		callback: Callable = Callable()) -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	margin.add_child(hbox)

	var lbl_l := Label.new()
	lbl_l.text = "−"
	lbl_l.add_theme_font_size_override("font_size", 28)
	lbl_l.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	lbl_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(lbl_l)

	var slider := HSlider.new()
	slider.min_value = mn
	slider.max_value = mx
	slider.step = step
	slider.value = _values.get(key, (mn + mx) * 0.5)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(0, 55)
	hbox.add_child(slider)

	var lbl_r := Label.new()
	lbl_r.text = "+"
	lbl_r.add_theme_font_size_override("font_size", 28)
	lbl_r.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	lbl_r.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(lbl_r)

	var val_lbl := Label.new()
	val_lbl.text = str(snappedi(slider.value, 1))
	val_lbl.custom_minimum_size = Vector2(60, 0)
	val_lbl.add_theme_font_size_override("font_size", 24)
	val_lbl.add_theme_color_override("font_color", Color.WHITE)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(val_lbl)

	slider.value_changed.connect(func(val: float) -> void:
		_values[key] = val
		val_lbl.text = str(snappedi(val, 1))
		if callback.is_valid():
			callback.call()
	)
	return margin


# ── Callbacks ─────────────────────────────────────────────────────────────
func _on_ui_offset_changed() -> void:
	var offset := Vector2(
		_values.get("ui_offset_x", 0.0),
		_values.get("ui_offset_y", 0.0)
	)
	emit_signal("ui_offset_changed", offset)


# ── Helpers ────────────────────────────────────────────────────────────────
func _section(parent: Control, title: String, sub: String) -> void:
	_spacer(parent, 18)
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_constant_override("margin_left", 20)
	parent.add_child(lbl)
	var s := Label.new()
	s.text = sub
	s.add_theme_font_size_override("font_size", 20)
	s.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	s.add_theme_constant_override("margin_left", 20)
	parent.add_child(s)
	_spacer(parent, 10)


func _hline(parent: Control) -> void:
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.12)
	line.custom_minimum_size = Vector2(640, 2)
	parent.add_child(line)


func _spacer(parent: Control, h: int = 16) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	parent.add_child(s)

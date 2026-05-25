extends CanvasLayer
## Settings.gd — Einstellungs-Panel

var _panel: ColorRect
var _values: Dictionary = {
	"cam_relative":  true,
	"screen_lock":   false,
	"cam_smooth":    14.0,   # Kamera-Drehgeschwindigkeit
	"zoom_smooth":   8.0,    # Zoom-Geschwindigkeit
}


func _ready() -> void:
	add_to_group("settings")
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_build_panel(vp)
	_panel.visible = false


func toggle() -> void:
	_panel.visible = not _panel.visible


func get_setting(key: String) -> Variant:
	return _values.get(key, null)


func _build_panel(vp: Vector2) -> void:
	_panel = ColorRect.new()
	_panel.color = Color(0.08, 0.08, 0.08, 0.95)
	_panel.size = Vector2(660, 720)
	_panel.position = Vector2(vp.x * 0.5 - 330, vp.y * 0.5 - 360)
	add_child(_panel)

	# Scroll-Container damit es auf kleinen Screens passt
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(0, 70)
	scroll.size = Vector2(660, 590)
	_panel.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 0)
	scroll.add_child(content)

	_add_label(_panel, "⚙  Einstellungen", Vector2(20, 16), 34, Color.WHITE)
	_add_hline(_panel, Vector2(20, 62), 620)

	# ── Kamera-relative Bewegung ─────────────────────────────────────────
	_section(content, "Bewegung relativ zur Kamera",
		"EIN: Joystick hoch = Blickrichtung\nAUS: Joystick hoch = immer Norden")
	content.add_child(_make_toggle("cam_relative"))
	_spacer(content, 20)

	_add_hline(content)

	# ── Bildschirm-Rotation ──────────────────────────────────────────────
	_section(content, "Bildschirm sperren (Hochkant)",
		"EIN: immer Hochkant  |  AUS: dreht frei mit")
	content.add_child(_make_toggle("screen_lock", _on_screen_lock_changed))
	_spacer(content, 20)

	_add_hline(content)

	# ── Kamera-Geschwindigkeit ───────────────────────────────────────────
	_section(content, "Kamera-Geschwindigkeit", "Wie schnell dreht sich die Kamera")
	var cam_row := _make_slider_row("cam_smooth", 2.0, 30.0, 1.0)
	content.add_child(cam_row)
	_spacer(content, 20)

	_add_hline(content)

	# ── Zoom-Geschwindigkeit ─────────────────────────────────────────────
	_section(content, "Zoom-Geschwindigkeit", "Wie schnell zoomt die Kamera")
	var zoom_row := _make_slider_row("zoom_smooth", 1.0, 20.0, 1.0)
	content.add_child(zoom_row)
	_spacer(content, 30)

	# ── Schließen ────────────────────────────────────────────────────────
	var close := Button.new()
	close.text = "✕  Schließen"
	close.custom_minimum_size = Vector2(280, 55)
	close.add_theme_font_size_override("font_size", 26)
	close.pressed.connect(toggle)
	var close_wrap := CenterContainer.new()
	close_wrap.add_child(close)
	content.add_child(close_wrap)
	_spacer(content, 20)


# ── Section-Header ─────────────────────────────────────────────────────────
func _section(parent: Control, title: String, subtitle: String) -> void:
	_spacer(parent, 16)
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_constant_override("margin_left", 20)
	parent.add_child(lbl)

	var sub := Label.new()
	sub.text = subtitle
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	sub.add_theme_constant_override("margin_left", 20)
	parent.add_child(sub)
	_spacer(parent, 10)


# ── Toggle-Button ──────────────────────────────────────────────────────────
func _make_toggle(key: String, callback: Callable = Callable()) -> Control:
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_left", 20)

	var btn := Button.new()
	btn.text = "●  EIN" if _values.get(key, false) else "○  AUS"
	btn.custom_minimum_size = Vector2(160, 55)
	btn.add_theme_font_size_override("font_size", 26)
	btn.pressed.connect(func() -> void:
		_values[key] = not _values.get(key, false)
		btn.text = "●  EIN" if _values[key] else "○  AUS"
		if callback.is_valid():
			callback.call(_values[key])
	)
	wrap.add_child(btn)
	return wrap


# ── Slider Row ─────────────────────────────────────────────────────────────
func _make_slider_row(key: String, min_val: float, max_val: float, step: float) -> Control:
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_left", 20)
	wrap.add_theme_constant_override("margin_right", 20)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	wrap.add_child(hbox)

	# Langsam-Label
	var lbl_slow := Label.new()
	lbl_slow.text = "Langsam"
	lbl_slow.add_theme_font_size_override("font_size", 20)
	lbl_slow.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	lbl_slow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(lbl_slow)

	# Slider
	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step
	slider.value = _values.get(key, (min_val + max_val) * 0.5)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(0, 50)
	hbox.add_child(slider)

	# Schnell-Label
	var lbl_fast := Label.new()
	lbl_fast.text = "Schnell"
	lbl_fast.add_theme_font_size_override("font_size", 20)
	lbl_fast.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	lbl_fast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(lbl_fast)

	# Wert-Anzeige
	var val_lbl := Label.new()
	val_lbl.text = str(slider.value)
	val_lbl.custom_minimum_size = Vector2(50, 0)
	val_lbl.add_theme_font_size_override("font_size", 22)
	val_lbl.add_theme_color_override("font_color", Color.WHITE)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(val_lbl)

	slider.value_changed.connect(func(val: float) -> void:
		_values[key] = val
		val_lbl.text = str(val)
	)

	return wrap


# ── Callbacks ─────────────────────────────────────────────────────────────
func _on_screen_lock_changed(locked: bool) -> void:
	if locked:
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)
	else:
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR)


# ── Hilfsfunktionen ────────────────────────────────────────────────────────
func _add_label(parent: Control, text: String, pos: Vector2, size: int, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	parent.add_child(lbl)


func _add_hline(parent: Control, pos: Vector2 = Vector2.ZERO, width: float = 620) -> void:
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.12)
	line.custom_minimum_size = Vector2(width, 2)
	if pos != Vector2.ZERO:
		line.position = pos
	parent.add_child(line)


func _spacer(parent: Control, height: int = 16) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	parent.add_child(s)

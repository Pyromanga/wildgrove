extends CanvasLayer
## Settings.gd — Einstellungs-Panel

var _panel: ColorRect
var _values: Dictionary = {
	"cam_relative":    true,
	"screen_lock":     false,  # false = frei drehen, true = Portrait lock
}


func _ready() -> void:
	add_to_group("settings")
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_build_panel(vp)
	_panel.visible = false  # Panel verstecken, nicht CanvasLayer


func toggle() -> void:
	_panel.visible = not _panel.visible


func get_setting(key: String) -> Variant:
	return _values.get(key, null)


func _build_panel(vp: Vector2) -> void:
	_panel = ColorRect.new()
	_panel.color = Color(0.08, 0.08, 0.08, 0.95)
	_panel.size = Vector2(620, 520)
	_panel.position = Vector2(vp.x * 0.5 - 310, vp.y * 0.5 - 260)
	add_child(_panel)

	_add_label("⚙  Einstellungen", Vector2(20, 16), 34, Color.WHITE)
	_add_line(Vector2(20, 64))

	# ── Kamera-relative Bewegung ─────────────────────────────────────────
	_add_label("Bewegung relativ zur Kamera", Vector2(20, 85), 28, Color.WHITE)
	_add_label(
		"EIN: Joystick hoch = Blickrichtung\nAUS: Joystick hoch = immer Norden",
		Vector2(20, 122), 20, Color(0.65, 0.65, 0.65, 1)
	)
	_panel.add_child(_add_toggle("cam_relative", Vector2(20, 185)))

	_add_line(Vector2(20, 255))

	# ── Bildschirm-Rotation ──────────────────────────────────────────────
	_add_label("Bildschirm sperren (Hochkant)", Vector2(20, 270), 28, Color.WHITE)
	_add_label(
		"EIN: immer Hochkant\nAUS: dreht sich mit dem Gerät",
		Vector2(20, 307), 20, Color(0.65, 0.65, 0.65, 1)
	)
	_panel.add_child(_add_toggle("screen_lock", Vector2(20, 370), _on_screen_lock_changed))

	_add_line(Vector2(20, 438))

	# ── Zoom-Info ────────────────────────────────────────────────────────
	_add_label("Zoom: Zwei Finger Pinch / Mausrad", Vector2(20, 452), 20, Color(0.65, 0.65, 0.65, 1))

	# Schließen
	var close := Button.new()
	close.text = "✕  Schließen"
	close.position = Vector2(170, 455)
	close.size = Vector2(280, 52)
	close.add_theme_font_size_override("font_size", 26)
	close.pressed.connect(toggle)
	_panel.add_child(close)


func _on_screen_lock_changed(locked: bool) -> void:
	if locked:
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)
	else:
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR)


# ── Hilfsfunktionen ────────────────────────────────────────────────────────
func _add_label(text: String, pos: Vector2, size: int, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	_panel.add_child(lbl)


func _add_line(pos: Vector2) -> void:
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.15)
	line.size = Vector2(580, 2)
	line.position = pos
	_panel.add_child(line)


# Optionaler Callback wenn sich der Wert ändert
func _add_toggle(key: String, pos: Vector2, callback: Callable = Callable()) -> Button:
	var btn := Button.new()
	btn.text = "●  EIN" if _values.get(key, false) else "○  AUS"
	btn.position = pos
	btn.size = Vector2(160, 52)
	btn.add_theme_font_size_override("font_size", 26)
	btn.pressed.connect(func() -> void:
		_values[key] = not _values.get(key, false)
		btn.text = "●  EIN" if _values[key] else "○  AUS"
		if callback.is_valid():
			callback.call(_values[key])
	)
	return btn

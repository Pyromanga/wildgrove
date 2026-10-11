extends CanvasLayer
## Settings.gd — UI-Panel für Einstellungen.
##
## Reiner Pull/Push auf SettingsService — hält selbst keinen persistenten State.
## Ohne injizierten SettingsService (siehe setup()) läuft das Panel in einem
## degradierten Nur-RAM-Modus mit SettingsService.DEFAULTS als Ausgangswerte:
## Eingaben wirken dann nur für die laufende Szene und gehen beim Neustart
## verloren. Das ist ein bewusster Fallback nach demselben Muster wie
## ServiceDeps.get_optional() (Service kann seinen Job eingeschränkt ohne die
## Dependency erledigen) — kein stiller Datenverlust, aber auch kein Crash,
## wenn das Panel in einem Kontext ohne Service-Registry landet (z.B. Editor-Preview).

const LOG_CAT := "Settings"

var _panel: ColorRect
var _settings_service: SettingsService = null

const ROTATION_LABELS: Array[String] = ["Frei", "Nur Hochkant", "Nur Querformat", "Hochkant + 180°"]
const ROTATION_MODES: Array[int] = [
	DisplayServer.SCREEN_SENSOR,
	DisplayServer.SCREEN_PORTRAIT,
	DisplayServer.SCREEN_LANDSCAPE,
	DisplayServer.SCREEN_SENSOR_PORTRAIT,
]

## Injektion — MUSS vor add_child() aufgerufen werden, da _ready() den
## Panel-Inhalt bereits aus den aktuellen Settings-Werten aufbaut.
func setup(ctx: IUIContext) -> void:
	_settings_service = ctx.get_settings() if ctx != null else null
	if _settings_service == null:
		AppLogger.log_warn(
			"Kein SettingsService verfügbar — Panel läuft im Nur-RAM-Fallback.", LOG_CAT
		)

func _ready() -> void:
	add_to_group("settings")
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_build_panel(vp)
	_panel.visible = false
	# Zentrales Fenster: schließt Seitenfenster/Pause-Menü, blendet die Toolbar aus (PanelDock).
	PanelDock.register_in(get_parent(), &"settings", _panel, PanelDock.Kind.MODAL)
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
# Settings-Zugriff — delegiert an SettingsService (Fallback: DEFAULTS)
# ─────────────────────────────────────────────

func _get_setting(key: String) -> Variant:
	if _settings_service != null:
		return _settings_service.get_setting(key)
	return SettingsService.DEFAULTS.get(key)

func _set_setting(key: String, value: Variant) -> void:
	if _settings_service != null:
		_settings_service.set_setting(key, value)
	# Ohne Service bleibt der neue Wert nur im jeweiligen Control (Slider/Button-Text) —
	# es gibt bewusst keinen zweiten lokalen Dictionary-Cache, der mit dem Service
	# auseinanderlaufen könnte.

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

	_add_setting_toggle(content, "Joystick fest positioniert", "fixed_joystick")
	_section(content, "Joystick-Position", "")
	content.add_child(_make_joystick_position_pad())
	_add_setting_toggle(content, "Joystick Y-Achse umkehren", "joystick_inverted")
	_add_setting_toggle(content, "Bewegung relativ zur Kamera", "cam_relative")

	_section(content, "Bildschirm-Rotation", "")
	content.add_child(_make_rotation_picker())

	_section(content, "Gelände-Werkzeug", "")
	_add_setting_toggle(content, "Vorschau beim Graben", "dig_preview")
	_add_setting_toggle(content, "Vorschau beim Füllen", "fill_preview")

	content.add_child(_make_slider(content, "Kamera-Speed", "cam_smooth", 2.0, 30.0))
	content.add_child(_make_slider(content, "Zoom-Speed", "zoom_smooth", 1.0, 20.0))

	_section(content, "Grafik (experimentell)", "")
	_add_setting_toggle(content, "Lichtschächte im Wald", "volumetric_fog")
	var warn := Label.new()
	warn.text = "Kostet spürbar mehr Leistung als der Rest der Optik — bei Rucklern wieder ausschalten."
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD
	warn.modulate = Color(0.75, 0.75, 0.75)
	content.add_child(warn)

	_spacer(content, 30)
	var close := Button.new()
	close.text = "✕ Schließen"
	close.custom_minimum_size = Vector2(240, 72)
	close.pressed.connect(toggle)
	content.add_child(close)

	# FIX (Wunsch "Scrollen geht häufig nicht"): siehe UIMetrics.allow_scroll_through()
	# — Toggle-/Slider-/Rotations-Buttons haben sonst STOP und blockieren jede
	# Wisch-Geste, die auf ihnen startet, statt sie an den ScrollContainer weiterzugeben.
	UIMetrics.allow_scroll_through(content)

# ─────────────────────────────────────────────
# Komponenten
# ─────────────────────────────────────────────

func _add_setting_toggle(parent: VBoxContainer, title: String, key: String) -> void:
	_section(parent, title, "")
	var btn := Button.new()
	btn.text = "● EIN" if _get_setting(key) else "○ AUS"
	btn.custom_minimum_size = Vector2(0, UIMetrics.TAP_MIN)
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
	slider.value = _get_setting(key)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(0, UIMetrics.FIELD_MIN)
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

## Miniatur-Vorschau des Bildschirms mit verschiebbarem Punkt für die feste
## Joystick-Position (nur wirksam wenn "Joystick fest positioniert" aktiv ist,
## aber jederzeit einstellbar — man kann die Stelle vorbereiten, bevor man
## umschaltet). Tippen/Klicken IRGENDWO im Rahmen setzt die Position direkt
## dorthin, Ziehen verschiebt sie live — beides schreibt in Bruchteilen
## (0..1) der echten Bildschirmgröße, nicht in Pixeln der Miniatur.
func _make_joystick_position_pad() -> Control:
	const PAD_SIZE := Vector2(320, 200)
	const DOT_SIZE := Vector2(28, 28)

	var frame := ColorRect.new()
	frame.color = Color(0.03, 0.03, 0.03, 1.0)
	frame.custom_minimum_size = PAD_SIZE
	frame.size = PAD_SIZE
	frame.mouse_filter = Control.MOUSE_FILTER_STOP

	var dot := ColorRect.new()
	dot.color = Color(0.85, 0.85, 0.3, 0.9)
	dot.size = DOT_SIZE
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(dot)

	var place_dot := func(fx: float, fy: float) -> void:
		dot.position = Vector2(PAD_SIZE.x * fx, PAD_SIZE.y * fy) - (DOT_SIZE / 2)

	place_dot.call(
		clampf(_get_setting("joystick_pos_x"), 0.05, 0.95),
		clampf(_get_setting("joystick_pos_y"), 0.05, 0.95)
	)

	var apply_pos := func(local_pos: Vector2) -> void:
		var fx := clampf(local_pos.x / PAD_SIZE.x, 0.05, 0.95)
		var fy := clampf(local_pos.y / PAD_SIZE.y, 0.05, 0.95)
		place_dot.call(fx, fy)
		_set_setting("joystick_pos_x", fx)
		_set_setting("joystick_pos_y", fy)

	frame.gui_input.connect(
		func(event: InputEvent) -> void:
			if event is InputEventScreenTouch and event.pressed:
				apply_pos.call(event.position)
			elif event is InputEventScreenDrag:
				apply_pos.call(event.position)
			elif event is InputEventMouseButton and event.pressed \
					and event.button_index == MOUSE_BUTTON_LEFT:
				apply_pos.call(event.position)
			elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				apply_pos.call(event.position)
	)

	var wrap := CenterContainer.new()
	wrap.add_child(frame)
	return wrap

func _make_rotation_picker() -> Control:
	var vbox := VBoxContainer.new()
	for i in ROTATION_LABELS.size():
		var btn := Button.new()
		btn.text = ROTATION_LABELS[i]
		btn.custom_minimum_size = Vector2(0, UIMetrics.TAP_MIN)
		var idx := i  # Capture für Lambda
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

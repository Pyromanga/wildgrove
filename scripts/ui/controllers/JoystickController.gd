# scripts/ui/controllers/joystick_controller.gd
class_name JoystickController

## JoystickController — bewegt die Joystick-Visuals passend zu den vom
## EventBus gemeldeten Touch-Events UND, im fixed_joystick-Modus, zeigt einen
## permanenten (gedimmten) Anker an der in den Settings konfigurierten Stelle
## (siehe JoystickVisuals.set_idle_anchor()). Rein visuell — TouchInput.gd hat
## seine eigene, unabhängige Kopie derselben Settings-Lektüre für die
## tatsächliche Finger-Erkennung (siehe dortiger Klassenkommentar); beide
## lesen denselben SettingsService, können also nie auseinanderlaufen.

var _visuals: JoystickVisuals
var _settings: SettingsService = null

# Injection: Wir übergeben den Event-Bus explizit
func setup(visuals: JoystickVisuals, event_bus: Object, settings: SettingsService = null) -> void:
	_visuals = visuals
	_settings = settings
	event_bus.joystick_toggled.connect(_on_toggled)
	event_bus.joystick_moved.connect(_on_moved)

	if is_instance_valid(_settings):
		_settings.setting_changed.connect(_on_setting_changed)

	var vp := _visuals.base.get_viewport()
	if is_instance_valid(vp):
		vp.size_changed.connect(_refresh_idle_anchor)
	_refresh_idle_anchor()

func _on_toggled(active: bool, origin: Vector2) -> void:
	_visuals.set_visible(active)
	if active:
		# origin ist in Viewport-Koordinaten — in CanvasLayer ist position == Viewport-Position
		_visuals.base.position = origin - (_visuals.base.size / 2)
		# Knob startet in der Mitte der Base
		_visuals.knob.position = origin - (_visuals.knob.size / 2)
	else:
		_refresh_idle_anchor()  # Nach Loslassen: im fixed-Modus bleibt der gedimmte Anker sichtbar.

func _on_moved(origin: Vector2, offset: Vector2) -> void:
	# Knob-Position: Mitte der Base + Offset, geclampt auf Base-Radius
	var base_center := _visuals.base.position + (_visuals.base.size / 2)
	var max_radius := (_visuals.base.size.x / 2) - (_visuals.knob.size.x / 2)
	var clamped_offset := offset.limit_length(max_radius)
	_visuals.knob.position = base_center + clamped_offset - (_visuals.knob.size / 2)

func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "fixed_joystick" or key == "joystick_pos_x" or key == "joystick_pos_y":
		_refresh_idle_anchor()

func _get_setting(key: String) -> Variant:
	if is_instance_valid(_settings):
		return _settings.get_setting(key)
	return SettingsService.DEFAULTS.get(key)

func _refresh_idle_anchor() -> void:
	var fixed: bool = _get_setting("fixed_joystick")
	if not fixed:
		_visuals.set_idle_anchor(Vector2.ZERO, false)
		return
	var vp := _visuals.base.get_viewport()
	var vp_size: Vector2 = vp.get_visible_rect().size if is_instance_valid(vp) else Vector2(1280, 720)
	var fx: float = clampf(_get_setting("joystick_pos_x"), 0.05, 0.95)
	var fy: float = clampf(_get_setting("joystick_pos_y"), 0.05, 0.95)
	_visuals.set_idle_anchor(Vector2(vp_size.x * fx, vp_size.y * fy), true)

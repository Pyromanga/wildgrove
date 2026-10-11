extends Node
class_name TouchInput

## TouchInput — Input-Adapter für Mobile + Desktop.
## Kein Service — direktes Child des Player-Nodes.
## Gibt js_vec, cam_delta und zoom_delta als Output-State heraus.
## Player liest diese Werte in _physics_process.
##
## IEventBus wird via inject_bus() von Player.on_spawn() injiziert — kein AutoLoad
## mehr (vgl. ADR-014, mittlerweile obsolet). JoystickController lauscht auf
## _bus.ui() für joystick_toggled/moved — die Bridge-Calls in _handle_touch()/
## _handle_drag() laufen über den injizierten Bus, nicht über AutoLoad.
##
## FIX (2026-09-21, "Joystick blockiert komplette linke Bildschirmhälfte"):
## Vorher beanspruchte JEDE Berührung der linken Bildschirmhälfte automatisch
## den Joystick (der dann dort, wo der Daumen aufsetzte, erschien) — Kamera-
## Drehung/Zoom war links dadurch unmöglich, man musste zwingend rechts drehen.
## Jetzt (SettingsService.fixed_joystick == true, neuer Default): der Joystick
## sitzt an einer FESTEN, in den Settings verschiebbaren Stelle
## (joystick_pos_x/y, Bruchteile der Viewport-Größe). Nur eine Berührung
## INNERHALB des Joystick-Radius um diese Stelle beansprucht ihn — jede andere
## Berührung, links wie rechts, geht in den allgemeinen "Welt-Finger"-Pool
## (Kamera-Drehung, Pinch-Zoom, Tap-Auswahl). fixed_joystick == false erhält
## das alte Verhalten (schwebender Joystick, linke Hälfte reserviert) als
## bewusst gepflegte Alternative für Spieler, die das bevorzugen.

# ─────────────────────────────────────────────
# Output-State (vom Player gelesen)
# ─────────────────────────────────────────────
var js_vec: Vector2 = Vector2.ZERO
var cam_delta: Vector2 = Vector2.ZERO
var zoom_delta: float = 0.0

# ─────────────────────────────────────────────
# Interner State
# ─────────────────────────────────────────────

## Radius, innerhalb dessen der Joystick-Knob den Ausschlag anzeigt (== halbe
## Breite der sichtbaren Basis, siehe JoystickVisuals: 180px Basis → 90px Radius).
const JS_RADIUS: float = 90.0

## Fang-Radius um die feste Joystick-Position: etwas großzügiger als JS_RADIUS
## (fetter Finger trifft die sichtbare Basis nicht immer exakt mittig).
const JS_CATCH_RADIUS: float = 110.0

## Bewegung/Zeit-Grenzen für "Tap" vs. "Drag" — nur ein Tap löst world_tap_requested
## aus (siehe _maybe_emit_world_tap()). Über diesen Grenzen war es eine Kamera-Drehung.
const TAP_MAX_DIST: float = 24.0
const TAP_MAX_TIME_MSEC: int = 350

var _js_finger: int = -1
var _js_origin: Vector2 = Vector2.ZERO

## Alle Finger, die NICHT der Joystick sind — Kamera-Drehung, Pinch-Zoom, Tap.
## { finger_index: Vector2 (aktuelle Position) }
var _world_fingers: Dictionary = {}
var _pinch_last_dist: float = 0.0
var _cam_finger: int = -1
var _cam_last: Vector2 = Vector2.ZERO

## Tap-Erkennung pro Welt-Finger: Startposition/-zeit, um am Ende zu prüfen,
## ob es ein Tap war (kurz, kaum Bewegung) statt einer Kamera-Drehung.
var _tap_start_pos: Dictionary = {}    # { finger_index: Vector2 }
var _tap_start_msec: Dictionary = {}   # { finger_index: int }

## Desktop-Äquivalent zu _tap_start_pos/_tap_start_msec für Linksklick.
var _mouse_tap_start_pos: Vector2 = Vector2.ZERO
var _mouse_tap_start_msec: int = 0
var _mouse_tap_active: bool = false

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
	pass  # Bus-Connect erfolgt in inject_bus(), aufgerufen von Player.on_spawn().

## Injiziert von Player.inject_player_states() → von EntityOrchestrator nach on_spawn().
## Kein Services-Locator, kein EventBus-Polling.
var _player_states: PlayerStateService = null
var _bus: IEventBus = null

## SettingsService — optional (siehe IEntityContext.get_settings()). Ohne sie
## (Server-Kontext, Test-Kontext) fällt _fixed_joystick()/_joystick_anchor()
## auf SettingsService.DEFAULTS zurück, exakt wie Settings.gd es für das Panel tut.
var _settings: SettingsService = null

## Wird von Player.inject_player_states() aufgerufen — einziger Injection-Punkt.
func inject_player_states(svc: PlayerStateService) -> void:
	_player_states = svc

## Wird von Player.on_spawn() aufgerufen, unmittelbar nach inject_bus().
## Optional — bei fehlendem SettingsService gelten DEFAULTS (siehe oben).
func inject_settings(svc: SettingsService) -> void:
	_settings = svc

## Wird von Player.on_spawn() unmittelbar nach add_child(input) aufgerufen.
## Ersetzt das frühere connect_to_event_bus() — kein AutoLoad mehr, Pflicht-Dep.
func inject_bus(bus: IEventBus) -> void:
	_bus = bus
	reset_input()  # Push initial joystick-off state to EventBus.ui listeners.
	_bus.player().input_reset_requested.connect(reset_input)

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

## Zurücksetzen — aufgerufen von PlayerStateService wenn State wechselt.
func reset_input() -> void:
	js_vec = Vector2.ZERO
	cam_delta = Vector2.ZERO
	zoom_delta = 0.0
	_js_finger = -1
	_cam_finger = -1
	_pinch_last_dist = 0.0
	_world_fingers.clear()
	_tap_start_pos.clear()
	_tap_start_msec.clear()
	_mouse_tap_active = false
	# Joystick-Visuals ausblenden wenn Input resettet wird
	_bus.ui().emit_joystick_toggled(false, Vector2.ZERO)

# ─────────────────────────────────────────────
# Settings-Zugriff (mit Fallback auf DEFAULTS, analog Settings.gd._get_setting())
# ─────────────────────────────────────────────

func _get_setting(key: String) -> Variant:
	if is_instance_valid(_settings):
		return _settings.get_setting(key)
	return SettingsService.DEFAULTS.get(key)

func _fixed_joystick() -> bool:
	return _get_setting("fixed_joystick")

## Feste Joystick-Position in Viewport-Koordinaten, aus den (0..1)-Bruchteilen
## in den Settings berechnet. Wird bei jedem Touch-Down neu berechnet statt
## gecacht — Settings ändern sich selten, ein Viewport-Resize soll die Position
## aber sofort korrekt widerspiegeln, ohne separate resize-Listener hier.
func _joystick_anchor(vp_size: Vector2) -> Vector2:
	var fx: float = clampf(_get_setting("joystick_pos_x"), 0.05, 0.95)
	var fy: float = clampf(_get_setting("joystick_pos_y"), 0.05, 0.95)
	return Vector2(vp_size.x * fx, vp_size.y * fy)

# ─────────────────────────────────────────────
# Input
# ─────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if _bus == null:
		return  # inject_bus() noch nicht aufgerufen — Player baut Subsysteme noch auf
	if is_instance_valid(_player_states) and _player_states.is_in_menu():
		js_vec = Vector2.ZERO
		cam_delta = Vector2.ZERO
		return

	var vp_size := get_viewport().get_visible_rect().size

	if event is InputEventScreenTouch:
		_handle_touch(event as InputEventScreenTouch, vp_size)
	elif event is InputEventScreenDrag:
		_handle_drag(event as InputEventScreenDrag)
	elif event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			cam_delta += (event as InputEventMouseMotion).relative
		if _mouse_tap_active:
			# Genug Bewegung während gedrückter linker Maustaste → kein Tap mehr,
			# sondern z.B. ein Drag-Select über ein UI-Element. Verhindert, dass
			# das Loslassen nach einem Drag fälschlich als Welt-Tap gilt.
			var mp: Vector2 = get_viewport().get_mouse_position()
			if mp.distance_to(_mouse_tap_start_pos) > TAP_MAX_DIST:
				_mouse_tap_active = false
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			match mb.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					zoom_delta -= 1.0
				MOUSE_BUTTON_WHEEL_DOWN:
					zoom_delta += 1.0
				MOUSE_BUTTON_LEFT:
					if _mouse_tap_is_redundant(mb):
						return
					_mouse_tap_active = true
					_mouse_tap_start_pos = mb.position
					_mouse_tap_start_msec = Time.get_ticks_msec()
		elif mb.button_index == MOUSE_BUTTON_LEFT and _mouse_tap_active:
			_mouse_tap_active = false
			if mb.position.distance_to(_mouse_tap_start_pos) <= TAP_MAX_DIST \
					and Time.get_ticks_msec() - _mouse_tap_start_msec <= TAP_MAX_TIME_MSEC:
				_bus.world().emit_world_tap_requested(mb.position)

## FIX (2026-09-21, "Anklicken von Bäumen tut nichts"): project.godot aktiviert
## emulate_touch_from_mouse UND emulate_mouse_from_touch. Ein einzelner Klick/Tipp
## erzeugt dadurch ZWEI Events (ScreenTouch + MouseButton) — beide lösten
## world_tap_requested aus. Der erste Tap wählte das Ziel an, der zweite (gleiche
## Stelle) schaltete es sofort wieder ab → nie eine sichtbare Auswahl.
## Regel: Taps kommen ausschließlich aus dem ScreenTouch-Pfad. Der Maus-Pfad zählt nur,
## wenn er die EINZIGE Quelle ist (echte Maus, Touch-Emulation aus).
func _mouse_tap_is_redundant(mb: InputEventMouseButton) -> bool:
	if mb.device == InputEvent.DEVICE_ID_EMULATION:
		return true  # aus einem Touch emuliert → der ScreenTouch-Pfad hat ihn schon.
	return bool(ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse", false))

# ─────────────────────────────────────────────
# Touch-Handler
# ─────────────────────────────────────────────

func _handle_touch(event: InputEventScreenTouch, vp_size: Vector2) -> void:
	if event.pressed:
		_handle_touch_pressed(event, vp_size)
	else:
		_handle_touch_released(event)

func _handle_touch_pressed(event: InputEventScreenTouch, vp_size: Vector2) -> void:
	if _fixed_joystick():
		# Neuer Default: Joystick sitzt fest an einer konfigurierbaren Stelle.
		# Nur ein Finger, der INNERHALB des Fang-Radius um diese Stelle aufsetzt,
		# beansprucht ihn — alles andere (auch auf der linken Seite!) ist ein
		# Welt-Finger (Kamera/Zoom/Tap). Das gibt den Rest des Bildschirms frei.
		var anchor := _joystick_anchor(vp_size)
		if _js_finger < 0 and event.position.distance_to(anchor) <= JS_CATCH_RADIUS:
			_js_finger = event.index
			_js_origin = anchor  # Basis bleibt an der festen Stelle, nicht am Tap-Punkt.
			_bus.ui().emit_joystick_toggled(true, _js_origin)
			_bus.ui().emit_joystick_moved(_js_origin, Vector2.ZERO)
			return
		_add_world_finger(event.index, event.position)
	else:
		# Altes Verhalten: linke Hälfte = schwebender Joystick, rechte = Kamera/Pinch.
		if event.position.x < vp_size.x * 0.5:
			if _js_finger < 0:
				_js_finger = event.index
				_js_origin = event.position
				_bus.ui().emit_joystick_toggled(true, _js_origin)
				_bus.ui().emit_joystick_moved(_js_origin, Vector2.ZERO)
		else:
			_add_world_finger(event.index, event.position)

func _add_world_finger(index: int, pos: Vector2) -> void:
	_world_fingers[index] = pos
	_tap_start_pos[index] = pos
	_tap_start_msec[index] = Time.get_ticks_msec()
	if _world_fingers.size() == 1:
		_cam_finger = index
		_cam_last = pos
	elif _world_fingers.size() == 2:
		_cam_finger = -1  # Zwei Finger → Pinch-Zoom statt Drehung, siehe _handle_drag().
		var keys := _world_fingers.keys()
		_pinch_last_dist = (_world_fingers[keys[0]] as Vector2).distance_to(
			_world_fingers[keys[1]]
		)
	else:
		# Dritter+ Finger auf der Welt-Seite: kein definiertes Gesture-Ziel mehr
		# (kein Tap-Kandidat, keine neue Pinch-Basislinie) — wird nur noch als
		# aktiver Finger mitgeführt, bis er wieder losgelassen wird.
		_cam_finger = -1

func _handle_touch_released(event: InputEventScreenTouch) -> void:
	if event.index == _js_finger:
		_js_finger = -1
		js_vec = Vector2.ZERO
		_bus.ui().emit_joystick_toggled(false, Vector2.ZERO)
		return

	if not _world_fingers.has(event.index):
		return

	_maybe_emit_world_tap(event.index, event.position)

	_world_fingers.erase(event.index)
	_tap_start_pos.erase(event.index)
	_tap_start_msec.erase(event.index)

	if _world_fingers.size() == 1:
		_cam_finger = _world_fingers.keys()[0]
		_cam_last = _world_fingers[_cam_finger]
	else:
		_cam_finger = -1
	_pinch_last_dist = 0.0

## Ein losgelassener Welt-Finger zählt als Tap (→ world_tap_requested, siehe
## InteractionTargetPicker), wenn er der EINZIGE Welt-Finger war (kein Pinch),
## sich kaum bewegt hat und schnell genug losgelassen wurde. Sonst war es eine
## Kamera-Drehung oder ein beendeter Pinch — kein Tap.
func _maybe_emit_world_tap(index: int, release_pos: Vector2) -> void:
	if _world_fingers.size() != 1 or not _tap_start_pos.has(index):
		return
	var start_pos: Vector2 = _tap_start_pos[index]
	var start_msec: int = _tap_start_msec[index]
	if release_pos.distance_to(start_pos) > TAP_MAX_DIST:
		return
	if Time.get_ticks_msec() - start_msec > TAP_MAX_TIME_MSEC:
		return
	_bus.world().emit_world_tap_requested(release_pos)

func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index == _js_finger:
		var delta_pos := event.position - _js_origin
		var clamped := delta_pos.limit_length(JS_RADIUS)
		js_vec = clamped / JS_RADIUS
		_bus.ui().emit_joystick_moved(_js_origin, clamped)
		return

	if not _world_fingers.has(event.index):
		return

	_world_fingers[event.index] = event.position
	# Genug Bewegung → kein Tap-Kandidat mehr (verhindert, dass eine schnelle
	# kurze Drehung am Ende fälschlich als Tap gewertet wird).
	if _tap_start_pos.has(event.index) \
			and event.position.distance_to(_tap_start_pos[event.index]) > TAP_MAX_DIST:
		_tap_start_pos.erase(event.index)

	if _world_fingers.size() == 2:
		var keys := _world_fingers.keys()
		var new_dist: float = (_world_fingers[keys[0]] as Vector2).distance_to(
			_world_fingers[keys[1]]
		)
		if _pinch_last_dist > 0.0:
			zoom_delta += (_pinch_last_dist - new_dist) * 0.05
		_pinch_last_dist = new_dist

	elif event.index == _cam_finger:
		cam_delta += event.position - _cam_last
		_cam_last = event.position

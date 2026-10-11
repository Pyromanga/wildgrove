# res://tests/unit/test_terminal_controller.gd
extends GutTest

## Regression: InputEventScreenTouch/-Drag haben kein 'global_position' (nur
## Maus-Events haben das) — handle_button_input() griff trotzdem einheitlich
## darauf zu und crashte bei jedem Touch auf mobilen Geräten.

var _logic: Node
var _ui: CanvasLayer
var _controller: TerminalController
var _button: Button

func before_each() -> void:
	var mock_script := GDScript.new()
	mock_script.source_code = "extends Node\nfunc toggle() -> void:\n\tpass\nfunc execute(_t: String) -> void:\n\tpass\n"
	mock_script.reload()
	_logic = Node.new()
	_logic.set_script(mock_script)
	add_child_autofree(_logic)
	_ui = CanvasLayer.new()
	add_child_autofree(_ui)
	_button = Button.new()
	add_child_autofree(_button)
	_button.global_position = Vector2(100, 100)
	_controller = TerminalController.new(_logic, _ui)

func test_screen_touch_press_does_not_crash_and_sets_drag_offset() -> void:
	AppLogger.flush_log_buffer()
	var touch := InputEventScreenTouch.new()
	touch.position = Vector2(110, 110)
	touch.pressed = true
	_controller.handle_button_input(touch, _button)
	assert_eq(AppLogger.get_errors().size(), 0, "Touch-Press darf keinen Engine-Fehler auslösen")

func test_screen_drag_moves_button_without_crash() -> void:
	AppLogger.flush_log_buffer()
	var touch := InputEventScreenTouch.new()
	touch.position = Vector2(110, 110)
	touch.pressed = true
	_controller.handle_button_input(touch, _button)

	var drag := InputEventScreenDrag.new()
	drag.position = Vector2(150, 160)
	_controller.handle_button_input(drag, _button)

	assert_eq(AppLogger.get_errors().size(), 0, "Screen-Drag darf keinen Engine-Fehler auslösen")
	assert_ne(_button.global_position, Vector2(100, 100), "Button sollte der Drag-Bewegung folgen")

func test_screen_touch_release_within_threshold_toggles() -> void:
	AppLogger.flush_log_buffer()
	var press := InputEventScreenTouch.new()
	press.position = Vector2(110, 110)
	press.pressed = true
	_controller.handle_button_input(press, _button)

	var release := InputEventScreenTouch.new()
	release.position = Vector2(112, 111)  # kaum bewegt -> Toggle statt Drag
	release.pressed = false
	_controller.handle_button_input(release, _button)

	assert_eq(AppLogger.get_errors().size(), 0, "Touch-Release darf keinen Engine-Fehler auslösen")

func test_mouse_events_still_use_global_position() -> void:
	AppLogger.flush_log_buffer()
	var press := InputEventMouseButton.new()
	press.global_position = Vector2(200, 200)
	press.pressed = true
	_controller.handle_button_input(press, _button)
	assert_eq(AppLogger.get_errors().size(), 0, "Maus-Events bleiben unverändert funktionsfähig")

func test_emulated_mouse_motion_during_touch_drag_is_ignored() -> void:
	# BUG-25: project.godot hat emulate_mouse_from_touch=true — echte Geräte
	# liefern parallel zu jedem InputEventScreenDrag ein emuliertes
	# InputEventMouseMotion für dieselbe Bewegung. Ohne Familien-Sperre wurde
	# die Verschiebung doppelt angewendet.
	var touch := InputEventScreenTouch.new()
	touch.position = Vector2(110, 110)
	touch.pressed = true
	_controller.handle_button_input(touch, _button)

	var drag := InputEventScreenDrag.new()
	drag.position = Vector2(150, 110)  # +40 in x
	_controller.handle_button_input(drag, _button)
	var pos_after_real_drag := _button.global_position

	# Emuliertes Maus-Motion-Event für dieselbe physische Bewegung — darf
	# NICHT nochmal angewendet werden, solange die Touch-Geste aktiv ist.
	var emulated_motion := InputEventMouseMotion.new()
	emulated_motion.global_position = Vector2(150, 110)
	_controller.handle_button_input(emulated_motion, _button)

	assert_eq(_button.global_position, pos_after_real_drag,
		"Emuliertes Maus-Motion während aktivem Touch-Drag darf die Position nicht nochmal verändern.")

func test_emulated_mouse_press_during_touch_drag_is_ignored() -> void:
	var touch := InputEventScreenTouch.new()
	touch.position = Vector2(110, 110)
	touch.pressed = true
	_controller.handle_button_input(touch, _button)
	var offset_after_touch_press := _button.global_position

	# Emulierter Maus-Press für denselben physischen Touch — darf den
	# Drag-Offset/-Start NICHT überschreiben.
	var emulated_press := InputEventMouseButton.new()
	emulated_press.global_position = Vector2(110, 110)
	emulated_press.pressed = true
	_controller.handle_button_input(emulated_press, _button)

	var drag := InputEventScreenDrag.new()
	drag.position = Vector2(150, 160)
	_controller.handle_button_input(drag, _button)

	assert_ne(_button.global_position, offset_after_touch_press,
		"Echtes Touch-Drag muss trotz emuliertem Maus-Press dazwischen weiter funktionieren.")

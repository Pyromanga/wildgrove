# res://tests/unit/test_draggable_toggle_controller.gd
extends GutTest

## Unit-Tests für DraggableToggleController — extrahiert aus TerminalController (BUGFIX
## 2026-09-27, "Admin-Button soll wie der Log-Button verschiebbar sein"), damit
## AdminPanelUI dieselbe (BUG-25-gehärtete) Drag-Erkennung nutzen kann wie SimpleTerminalUIs
## LOG-Button. test_terminal_controller.gd deckt bereits Mouse/Touch-Robustheit über den
## TerminalController-Wrapper ab (unverändert, da dessen öffentliche API gleich blieb) —
## diese Datei testet zusätzlich das eine, was TerminalControllers Tests NIE geprüft haben:
## dass on_tap tatsächlich (und nur bei einem echten Tap, nicht bei einem Drag) aufgerufen wird.

var _controller: DraggableToggleController
var _button: Button
var _tap_count: int

func before_each() -> void:
	_tap_count = 0
	_button = Button.new()
	add_child_autofree(_button)
	_button.global_position = Vector2(100, 100)
	_controller = DraggableToggleController.new(func() -> void: _tap_count += 1)

func _press(pos: Vector2) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.position = pos
	e.pressed = true
	return e

func _release(pos: Vector2) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.position = pos
	e.pressed = false
	return e

func test_tap_within_threshold_calls_on_tap() -> void:
	_controller.handle_button_input(_press(Vector2(110, 110)), _button)
	_controller.handle_button_input(_release(Vector2(112, 111)), _button)  # kaum bewegt
	assert_eq(_tap_count, 1, "Ein Tap (Bewegung < Threshold) muss on_tap genau einmal auslösen.")

func test_drag_beyond_threshold_does_not_call_on_tap() -> void:
	_controller.handle_button_input(_press(Vector2(110, 110)), _button)
	var drag := InputEventScreenDrag.new()
	drag.position = Vector2(300, 300)
	_controller.handle_button_input(drag, _button)
	_controller.handle_button_input(_release(Vector2(300, 300)), _button)
	assert_eq(_tap_count, 0, "Ein echtes Drag darf on_tap NICHT auslösen.")

func test_drag_moves_button_to_follow_pointer() -> void:
	_controller.handle_button_input(_press(Vector2(110, 110)), _button)
	var drag := InputEventScreenDrag.new()
	drag.position = Vector2(150, 160)
	_controller.handle_button_input(drag, _button)
	assert_ne(_button.global_position, Vector2(100, 100), "Button muss der Drag-Bewegung folgen.")

func test_multiple_taps_call_on_tap_each_time() -> void:
	for i in 3:
		_controller.handle_button_input(_press(Vector2(110, 110)), _button)
		_controller.handle_button_input(_release(Vector2(111, 110)), _button)
	assert_eq(_tap_count, 3, "Mehrere unabhängige Taps müssen on_tap jeweils einzeln auslösen.")

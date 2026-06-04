extends Node
class_name TerminalController

var _logic: Node  # SimpleTerminal
var _ui: CanvasLayer  # SimpleTerminalUI

var _is_dragging := false
var _drag_offset := Vector2.ZERO
var _drag_start_pos := Vector2.ZERO


func _init(logic_node: Node, ui_node: CanvasLayer) -> void:
	_logic = logic_node
	_ui = ui_node


func handle_button_input(event: InputEvent, button: Button) -> void:
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		if event.pressed:
			_is_dragging = true
			_drag_start_pos = event.global_position
			_drag_offset = button.global_position - event.global_position
		else:
			_is_dragging = false
			# Klick-Erkennung: Wenn kaum bewegt, dann Toggle
			if event.global_position.distance_to(_drag_start_pos) < 15:
				_logic.toggle()

	if (event is InputEventMouseMotion or event is InputEventScreenDrag) and _is_dragging:
		button.global_position = event.global_position + _drag_offset


func submit_command(text: String) -> void:
	_logic.execute(text)

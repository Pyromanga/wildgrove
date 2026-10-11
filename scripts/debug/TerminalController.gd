extends RefCounted
class_name TerminalController

## TerminalController — Verbindet SimpleTerminalUI mit SimpleTerminal-Logik.
##
## Leitet Eingaben weiter; die eigentliche Drag-Logik des Toggle-Buttons sitzt seit BUGFIX
## 2026-09-27 ("Admin-Button soll wie der Log-Button verschiebbar sein") in
## DraggableToggleController (siehe dort) — AdminPanelUI nutzt exakt dieselbe Klasse für
## seinen eigenen Button, statt die (nicht ganz triviale, BUG-25-gehärtete) Drag-Erkennung
## ein zweites Mal zu implementieren. Öffentliche API dieser Klasse unverändert, damit
## SimpleTerminalUI und die bestehenden Tests (test_terminal_controller.gd) unangetastet bleiben.
## Extends RefCounted (nicht Node) damit _init() Argumente annehmen kann.

var _logic: Node       # SimpleTerminal (AutoLoad)
var _ui: CanvasLayer   # SimpleTerminalUI
var _drag: DraggableToggleController

func _init(logic_node: Node, ui_node: CanvasLayer) -> void:
	_logic = logic_node
	_ui    = ui_node
	_drag  = DraggableToggleController.new(_logic.toggle)

func handle_button_input(event: InputEvent, button: Button) -> void:
	_drag.handle_button_input(event, button)

func submit_command(text: String) -> void:
	_logic.execute(text)

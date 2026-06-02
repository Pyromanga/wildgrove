extends CanvasLayer
class_name SimpleTerminalUI

## SimpleTerminalUI — View-Schicht der In-Game Debug-Konsole.
## Wird als Kind von SimpleTerminal geladen.
## Kommuniziert nur über den typisierten _terminal-Verweis und TerminalController.

# ─────────────────────────────────────────────
# Layout-Konstanten (kein Magic-Number-Chaos)
# ─────────────────────────────────────────────
const LAYER_ORDER       := 128
const PANEL_BOTTOM_GAP  := -150  # Platz für den Floating Toggle-Button
const PANEL_PADDING     := 20
const TOOLBAR_HEIGHT    := 80
const COPY_BTN_SIZE     := Vector2(220, 70)
const INPUT_HEIGHT      := 90
const TOGGLE_BTN_SIZE   := Vector2(160, 100)
const TOGGLE_BTN_START  := Vector2(40, 40)
const DRAG_THRESHOLD    := 15.0   # Pixel-Distanz unter der ein Touch als Klick gilt

# ─────────────────────────────────────────────
# Nodes
# ─────────────────────────────────────────────
var _panel:      Panel
var _output:     RichTextLabel
var _input:      LineEdit
var _btn_toggle: Button

# ─────────────────────────────────────────────
# Referenzen
# ─────────────────────────────────────────────
var _terminal: Node
var _controller: TerminalController

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
	layer = LAYER_ORDER

	# Typisierte Parent-Referenz — crasht früh mit klarer Meldung wenn Hierarchie falsch ist
	_terminal = get_parent() as SimpleTerminal
	assert(_terminal != null, "SimpleTerminalUI MUSS ein Kind von SimpleTerminal sein!")

	_controller = TerminalController.new(_terminal, self)

	_setup_ui()

	_terminal.toggled.connect(_update_visibility)
	_terminal.entry_added.connect(_on_entry_added)
	_update_visibility(_terminal.is_visible)

# ─────────────────────────────────────────────
# UI Setup
# ─────────────────────────────────────────────

func _setup_ui() -> void:
	_build_panel()
	_build_toggle_button()

func _build_panel() -> void:
	_panel = Panel.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.offset_bottom = PANEL_BOTTOM_GAP
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT,
		Control.PRESET_MODE_MINSIZE,
		PANEL_PADDING
	)
	_panel.add_child(vbox)

	vbox.add_child(_build_toolbar())

	_output = RichTextLabel.new()
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.bbcode_enabled      = true
	_output.scroll_following    = true
	vbox.add_child(_output)

	_input = _build_input()
	vbox.add_child(_input)

func _build_toolbar() -> HBoxContainer:
	var toolbar := HBoxContainer.new()
	toolbar.custom_minimum_size.y = TOOLBAR_HEIGHT

	var btn_copy := Button.new()
	btn_copy.text                = "COPY ALL"
	btn_copy.custom_minimum_size = COPY_BTN_SIZE
	btn_copy.pressed.connect(_on_copy_pressed)
	toolbar.add_child(btn_copy)

	return toolbar

func _build_input() -> LineEdit:
	var input := LineEdit.new()
	input.custom_minimum_size.y = INPUT_HEIGHT
	input.placeholder_text      = "Command..."
	# FOCUS_CLICK verhindert dass das Keyboard auf Mobile automatisch aufpoppt
	input.focus_mode            = Control.FOCUS_CLICK
	input.text_submitted.connect(_on_input_submitted)
	return input

func _build_toggle_button() -> void:
	_btn_toggle = Button.new()
	_btn_toggle.text                = "LOG"
	_btn_toggle.z_index             = 100
	_btn_toggle.custom_minimum_size = TOGGLE_BTN_SIZE
	_btn_toggle.gui_input.connect(_on_toggle_input)
	add_child(_btn_toggle)
	_btn_toggle.global_position = TOGGLE_BTN_START

# ─────────────────────────────────────────────
# Signal-Handler
# ─────────────────────────────────────────────

func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(_terminal.get_all_text())

func _on_input_submitted(text: String) -> void:
	_controller.submit_command(text)
	_input.clear()
	_input.release_focus()  # Keyboard auf Mobile schließen

func _on_toggle_input(event: InputEvent) -> void:
	_controller.handle_button_input(event, _btn_toggle)

func _update_visibility(visible: bool) -> void:
	_panel.visible      = visible
	_btn_toggle.text    = "CLOSE" if visible else "LOG"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP if visible else Control.MOUSE_FILTER_IGNORE

	if visible:
		_output.text = _terminal.get_all_text()
		_input.release_focus()

func _on_entry_added(entry: SimpleTerminal.LogEntry) -> void:
	if entry == null:
		_output.text = ""
		return
	if _panel.visible:
		_output.append_text(entry.formatted + "\n")
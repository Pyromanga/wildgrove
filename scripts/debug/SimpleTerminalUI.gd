extends CanvasLayer

var _panel: Panel
var _output: RichTextLabel
var _input: LineEdit
var _btn_toggle: Button
var _controller: TerminalController

func _ready() -> void:
	layer = 125
	_controller = TerminalController.new(get_parent(), self)
	_setup_ui()
	
	# Signale von der Logik
	get_parent().toggled.connect(_update_visibility)
	get_parent().entry_added.connect(_on_entry_added)
	_update_visibility(get_parent().is_visible)

func _setup_ui() -> void:
	# Panel Setup
	_panel = Panel.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.offset_bottom = -150
	add_child(_panel)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 20)
	_panel.add_child(vbox)

	_output = RichTextLabel.new()
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.bbcode_enabled = true
	vbox.add_child(_output)

	_input = LineEdit.new()
	_input.custom_minimum_size.y = 80
	_input.text_submitted.connect(func(t): 
		_controller.submit_command(t)
		_input.clear()
	)
	vbox.add_child(_input)

	# Button Setup
	_btn_toggle = Button.new()
	_btn_toggle.text = "LOG"
	_btn_toggle.z_index = 999 # IMMER GANZ OBEN
	_btn_toggle.custom_minimum_size = Vector2(160, 100)
	_btn_toggle.gui_input.connect(func(ev): _controller.handle_button_input(ev, _btn_toggle))
	add_child(_btn_toggle)
	_btn_toggle.global_position = Vector2(50, 50)

func _update_visibility(v: bool) -> void:
	_panel.visible = v
	_btn_toggle.text = "CLOSE" if v else "LOG"
	# Vordergrund-Fix: Das Panel darf nur Input fangen, wenn es offen ist
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP if v else Control.MOUSE_FILTER_IGNORE
	if v: 
		_input.grab_focus()
		_output.text = get_parent().get_all_text()

func _on_entry_added(entry) -> void:
	if entry == null: _output.text = ""
	elif _panel.visible: _output.append_text(entry.formatted + "\n")
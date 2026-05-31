extends CanvasLayer
class_name SimpleTerminalUI

var _panel: Panel
var _output: RichTextLabel
var _input: LineEdit
var _btn_toggle: Button

func _ready() -> void:
	layer = 128
	_setup_ui()
	
	var logic = get_parent()
	logic.toggled.connect(_on_toggled)
	logic.entry_added.connect(_on_entry_added)
	_on_toggled(logic.is_visible)

func _setup_ui() -> void:
	# Floating Button (Groß & Mobil-freundlich)
	_btn_toggle = Button.new()
	_btn_toggle.text = "LOG"
	_btn_toggle.custom_minimum_size = Vector2(140, 80)
	_btn_toggle.anchor_left = 1.0; _btn_toggle.anchor_top = 1.0
	_btn_toggle.anchor_right = 1.0; _btn_toggle.anchor_bottom = 1.0
	_btn_toggle.offset_left = -160; _btn_toggle.offset_top = -100
	_btn_toggle.pressed.connect(func(): get_parent().toggle())
	add_child(_btn_toggle)

	# Panel
	_panel = Panel.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.offset_bottom = -110
	add_child(_panel)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(vbox)

	# Toolbar
	var toolbar = HBoxContainer.new()
	vbox.add_child(toolbar)

	var btn_copy = Button.new()
	btn_copy.text = " COPY ALL "
	btn_copy.custom_minimum_size.y = 60
	btn_copy.pressed.connect(func(): DisplayServer.clipboard_set(get_parent().get_all_text()))
	toolbar.add_child(btn_copy)

	# Output
	_output = RichTextLabel.new()
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.bbcode_enabled = true
	_output.scroll_following = true
	vbox.add_child(_output)

	# Command Input
	_input = LineEdit.new()
	_input.custom_minimum_size.y = 70
	_input.placeholder_text = "Befehl eingeben..."
	_input.text_submitted.connect(_on_submit)
	vbox.add_child(_input)

func _on_submit(txt: String) -> void:
	get_parent().execute(txt)
	_input.clear()

func _on_toggled(v: bool) -> void:
	_panel.visible = v
	_btn_toggle.text = "CLOSE" if v else "LOG"
	if v: 
		_input.grab_focus()
		_output.text = get_parent().get_all_text()

func _on_entry_added(entry) -> void:
	if entry == null: # Clear-Event
		_output.text = ""
		return
	if _panel.visible:
		_output.append_text(entry.formatted + "\n")
extends CanvasLayer
class_name SimpleTerminalUI

var _panel: Panel
var _output: RichTextLabel
var _input: LineEdit
var _btn_toggle: Button

var _is_dragging: bool = false
var _drag_offset: Vector2
var _drag_start_pos: Vector2

func _ready() -> void:
	layer = 128
	_setup_ui()
	
	var logic = get_parent()
	logic.toggled.connect(_on_toggled)
	logic.entry_added.connect(_on_entry_added)
	_on_toggled(logic.is_visible)

func _setup_ui() -> void:
	# 1. DER DRAGBARE BUTTON
	_btn_toggle = Button.new()
	_btn_toggle.text = "LOG"
	_btn_toggle.custom_minimum_size = Vector2(140, 80)
	
	# Start-Position unten rechts
	_btn_toggle.anchor_left = 1.0
	_btn_toggle.anchor_top = 1.0
	_btn_toggle.anchor_right = 1.0
	_btn_toggle.anchor_bottom = 1.0
	_btn_toggle.offset_left = -160
	_btn_toggle.offset_top = -100
	
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.15, 0.15, 0.15, 0.9)
	btn_style.set_border_width_all(2)
	btn_style.border_color = Color(0.3, 0.6, 1.0)
	btn_style.set_corner_radius_all(10)
	_btn_toggle.add_theme_stylebox_override("normal", btn_style)
	
	_btn_toggle.gui_input.connect(_handle_drag)
	add_child(_btn_toggle)

	# 2. DAS TERMINAL PANEL
	_panel = Panel.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.offset_bottom = -120 # Platz für den Button lassen
	add_child(_panel)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 10; vbox.offset_right = -10
	vbox.offset_top = 10; vbox.offset_bottom = -10
	_panel.add_child(vbox)

	# Toolbar mit Copy-Button
	var toolbar = HBoxContainer.new()
	vbox.add_child(toolbar)

	var btn_copy = Button.new()
	btn_copy.text = "📋 COPY ALL"
	btn_copy.custom_minimum_size = Vector2(160, 60)
	btn_copy.pressed.connect(func(): DisplayServer.clipboard_set(get_parent().get_all_text()))
	toolbar.add_child(btn_copy)

	# Output Bereich
	_output = RichTextLabel.new()
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.bbcode_enabled = true
	_output.scroll_following = true
	_output.add_theme_font_size_override("normal_font_size", 12)
	vbox.add_child(_output)

	# Input Bereich
	_input = LineEdit.new()
	_input.custom_minimum_size.y = 70
	_input.placeholder_text = "Command eingeben..."
	_input.text_submitted.connect(func(txt): 
		get_parent().execute(txt)
		_input.clear()
	)
	vbox.add_child(_input)

func _handle_drag(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		if event.pressed:
			_is_dragging = true
			_drag_start_pos = event.global_position
			_drag_offset = _btn_toggle.global_position - event.global_position
		else:
			_is_dragging = false
			# Wenn der Finger sich kaum bewegt hat, war es ein Klick -> Toggle
			if event.global_position.distance_to(_drag_start_pos) < 10:
				get_parent().toggle()
	
	if (event is InputEventMouseMotion or event is InputEventScreenDrag) and _is_dragging:
		_btn_toggle.global_position = event.global_position + _drag_offset

func _on_toggled(v: bool) -> void:
	_panel.visible = v
	_btn_toggle.text = "CLOSE" if v else "LOG"
	if v: 
		_input.grab_focus()
		_output.text = get_parent().get_all_text()

func _on_entry_added(entry) -> void:
	if entry == null:
		_output.text = ""
		return
	if _panel.visible:
		_output.append_text(entry.formatted + "\n")
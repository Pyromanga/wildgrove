extends CanvasLayer
class_name SimpleTerminalUI

var _panel: Panel
var _output: RichTextLabel
var _input: LineEdit
var _btn_toggle: Button

func _ready() -> void:
	layer = 128 # Immer ganz oben
	_setup_ui()
	
	# Signale von der Logik verbinden
	var logic = get_parent()
	logic.toggled.connect(_on_toggled)
	logic.updated.connect(_update_display)
	
	_on_toggled(logic.is_visible)

func _setup_ui() -> void:
	# 1. Der "Notfall-Knopf" (Immer sichtbar!)
	_btn_toggle = Button.new()
	_btn_toggle.text = "LOG"
	_btn_toggle.custom_minimum_size = Vector2(80, 50)
	# Position: Unten Rechts
	_btn_toggle.anchor_left = 1.0
	_btn_toggle.anchor_top = 1.0
	_btn_toggle.anchor_right = 1.0
	_btn_toggle.anchor_bottom = 1.0
	_btn_toggle.offset_left = -90
	_btn_toggle.offset_top = -60
	_btn_toggle.pressed.connect(func(): get_parent().toggle())
	add_child(_btn_toggle)

	# 2. Das Haupt-Panel
	_panel = Panel.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_panel.anchor_bottom = 0.5
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.85) # Fast schwarz, transparent
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(vbox)

	# Log Output
	_output = RichTextLabel.new()
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.bbcode_enabled = true
	_output.scroll_following = true
	_output.add_theme_font_size_override("normal_font_size", 12)
	vbox.add_child(_output)

	# Eingabe Zeile
	var hbox = HBoxContainer.new()
	vbox.add_child(hbox)

	_input = LineEdit.new()
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.placeholder_text = "Command..."
	_input.text_submitted.connect(_on_cmd_submit)
	hbox.add_child(_input)

	var btn_clear = Button.new()
	btn_clear.text = "CLR"
	btn_clear.pressed.connect(func(): get_parent().clear())
	hbox.add_child(btn_clear)

func _on_toggled(visible: bool) -> void:
	_panel.visible = visible
	if visible:
		_input.grab_focus()
		_update_display()

func _update_display() -> void:
	if not _panel.visible: return
	_output.text = "\n".join(get_parent().entries)

func _on_cmd_submit(txt: String) -> void:
	if txt.is_empty(): return
	Logger.log_info("Executing: " + txt, "Terminal") # Test-Log
	_input.clear()
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
	logic.updated.connect(_update_display)
	_on_toggled(logic.is_visible)

func _setup_ui() -> void:
	# --- 1. DER FLOATING LOG BUTTON ---
	_btn_toggle = Button.new()
	_btn_toggle.text = "LOG"
	
	# Design: Dunkel & Auffällig
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	btn_style.set_corner_radius_all(10)
	btn_style.set_border_width_all(2)
	btn_style.border_color = Color(0.3, 0.6, 1.0) # Blaues Leuchten
	_btn_toggle.add_theme_stylebox_override("normal", btn_style)
	
	# Größe für dicke Daumen
	_btn_toggle.custom_minimum_size = Vector2(120, 70) 
	
	# Position: Unten Rechts mit Abstand zum Rand (Safe Area)
	_btn_toggle.anchor_left = 1.0
	_btn_toggle.anchor_top = 1.0
	_btn_toggle.anchor_right = 1.0
	_btn_toggle.anchor_bottom = 1.0
	_btn_toggle.offset_left = -140
	_btn_toggle.offset_top = -90
	_btn_toggle.offset_right = -20
	_btn_toggle.offset_bottom = -20
	
	_btn_toggle.pressed.connect(func(): get_parent().toggle())
	add_child(_btn_toggle)

	# --- 2. DAS HAUPT-PANEL ---
	_panel = Panel.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT) # Vollbild für Mobile besser
	_panel.offset_bottom = -100 # Platz für den Button lassen
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0, 0, 0, 0.9)
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 10; vbox.offset_right = -10; vbox.offset_top = 10; vbox.offset_bottom = -10
	_panel.add_child(vbox)

	# Toolbar für Buttons (Copy, Clear, Close)
	var toolbar = HBoxContainer.new()
	vbox.add_child(toolbar)

	# NEU: COPY BUTTON
	var btn_copy = Button.new()
	btn_copy.text = " COPY ALL "
	btn_copy.custom_minimum_size.y = 50
	btn_copy.pressed.connect(_on_copy_pressed)
	toolbar.add_child(btn_copy)

	var btn_clear = Button.new()
	btn_clear.text = " CLEAR "
	btn_clear.custom_minimum_size.y = 50
	btn_clear.pressed.connect(func(): get_parent().clear())
	toolbar.add_child(btn_clear)

	# Log Output
	_output = RichTextLabel.new()
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.bbcode_enabled = true
	_output.scroll_following = true
	vbox.add_child(_output)

	# Input
	_input = LineEdit.new()
	_input.custom_minimum_size.y = 60
	_input.placeholder_text = "Command..."
	_input.text_submitted.connect(_on_cmd_submit)
	vbox.add_child(_input)

func _on_copy_pressed() -> void:
	var full_text = get_parent().get_all_text()
	DisplayServer.clipboard_set(full_text)
	Logger.log_info("Log in Zwischenablage kopiert!", "Terminal")

func _on_toggled(visible: bool) -> void:
	_panel.visible = visible
	# Button Text ändern wenn offen/zu
	_btn_toggle.text = "CLOSE" if visible else "LOG"

func _update_display() -> void:
	if not _panel.visible: return
	_output.text = get_parent().get_all_text()

func _on_cmd_submit(txt: String) -> void:
	if txt.is_empty(): return
	_input.clear()
	# Hier könnte man Befehle verarbeiten
extends CanvasLayer
class_name SimpleTerminalUI

## VIEW: Erstellt die UI-Elemente und zeigt Daten an.
var _panel: Panel
var _output: RichTextLabel
var _input: LineEdit
var _btn_toggle: Button
var _controller: TerminalController

func _ready() -> void:
	layer = 128
	# Controller initialisieren
	_controller = TerminalController.new(get_parent(), self)
	_setup_ui()
	
	# Signale verbinden
	get_parent().toggled.connect(_update_visibility)
	get_parent().entry_added.connect(_on_entry_added)
	_update_visibility(get_parent().is_visible)

func _setup_ui() -> void:
	# 1. Haupt-Panel
	_panel = Panel.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.offset_bottom = -150 # Platz lassen für den Floating Button
	add_child(_panel)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 20)
	_panel.add_child(vbox)

	# Toolbar mit Copy-Button
	var toolbar := HBoxContainer.new()
	toolbar.custom_minimum_size.y = 80
	vbox.add_child(toolbar)

	var btn_copy := Button.new()
	btn_copy.text = "📋 COPY ALL"
	btn_copy.custom_minimum_size = Vector2(220, 70)
	btn_copy.pressed.connect(func(): DisplayServer.clipboard_set(get_parent().get_all_text()))
	toolbar.add_child(btn_copy)

	# Log-Output
	_output = RichTextLabel.new()
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.bbcode_enabled = true
	_output.scroll_following = true
	vbox.add_child(_output)

	# Befehls-Eingabe
	_input = LineEdit.new()
	_input.custom_minimum_size.y = 90
	_input.placeholder_text = "Command..."
	_input.focus_mode = Control.FOCUS_CLICK # Verhindert automatisches Keyboard-Öffnen
	_input.text_submitted.connect(func(t): 
		_controller.submit_command(t)
		_input.clear()
		_input.release_focus() # Schließt Keyboard nach Senden
	)
	vbox.add_child(_input)

	# 2. Schwebender Button (Floating)
	_btn_toggle = Button.new()
	_btn_toggle.text = "LOG"
	_btn_toggle.z_index = 100 # Über dem Panel
	_btn_toggle.custom_minimum_size = Vector2(160, 100)
	_btn_toggle.gui_input.connect(func(ev): _controller.handle_button_input(ev, _btn_toggle))
	add_child(_btn_toggle)
	_btn_toggle.global_position = Vector2(40, 40)

func _update_visibility(v: bool) -> void:
	_panel.visible = v
	_btn_toggle.text = "CLOSE" if v else "LOG"
	# Input-Blockierung nur wenn sichtbar
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP if v else Control.MOUSE_FILTER_IGNORE
	
	if v:
		_output.text = get_parent().get_all_text()
		# Sicherstellen, dass das Keyboard NICHT aufpoppt
		_input.release_focus() 

func _on_entry_added(entry) -> void:
	if entry == null:
		_output.text = ""
		return
	if _panel.visible:
		_output.append_text(entry.formatted + "\n")
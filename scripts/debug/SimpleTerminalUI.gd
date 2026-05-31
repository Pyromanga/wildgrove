extends CanvasLayer

## UI-KLASSE
## Verwaltet das Panel und den schwebenden Button.

var _panel: Panel
var _output: RichTextLabel
var _input: LineEdit
var _btn_toggle: Button

var _is_dragging := false
var _drag_offset := Vector2.ZERO
var _drag_start_pos := Vector2.ZERO

func _ready() -> void:
	layer = 120 # Hoher Layer für Overlay
	_setup_ui()
	
	var logic = get_parent()
	logic.toggled.connect(_on_logic_toggled)
	logic.entry_added.connect(_on_entry_added)
	_on_logic_toggled(logic.is_visible)

func _setup_ui() -> void:
	# 1. DAS PANEL
	_panel = Panel.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.offset_bottom = -150 # WICHTIG: Damit der untere Bereich für Klicks frei bleibt!
	add_child(_panel)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	_panel.add_child(vbox)

	_output = RichTextLabel.new()
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.bbcode_enabled = true
	_output.scroll_following = true
	vbox.add_child(_output)

	_input = LineEdit.new()
	_input.custom_minimum_size.y = 80
	_input.text_submitted.connect(func(t): get_parent().execute(t); _input.clear())
	vbox.add_child(_input)

	# 2. DER BUTTON (Eigene Node-Ebene für Z-Order)
	_btn_toggle = Button.new()
	_btn_toggle.text = "LOG"
	_btn_toggle.custom_minimum_size = Vector2(160, 100)
	# Damit der Button IMMER klickbar ist, setzen wir ihn ans Ende des Trees 
	# oder geben ihm einen hohen Z-Index
	_btn_toggle.z_index = 10 
	_btn_toggle.gui_input.connect(_handle_drag)
	add_child(_btn_toggle)
	
	# Initialposition
	_btn_toggle.global_position = Vector2(50, 50)

func _handle_drag(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		if event.pressed:
			_is_dragging = true
			_drag_start_pos = event.global_position
			_drag_offset = _btn_toggle.global_position - event.global_position
		else:
			_is_dragging = false
			if event.global_position.distance_to(_drag_start_pos) < 15:
				get_parent().toggle()
	
	if (event is InputEventMouseMotion or event is InputEventScreenDrag) and _is_dragging:
		_btn_toggle.global_position = event.global_position + _drag_offset

func _on_logic_toggled(v: bool) -> void:
	_panel.visible = v
	_btn_toggle.text = "CLOSE" if v else "LOG"
	# Fix für den Vordergrund: Wenn Panel an, blockiert es Input.
	# Wenn aus, ignorieren wir es komplett.
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP if v else Control.MOUSE_FILTER_IGNORE
	if v: _input.grab_focus()

func _on_entry_added(entry) -> void:
	if entry == null: _output.text = ""; return
	if _panel.visible: _output.append_text(entry.formatted + "\n")
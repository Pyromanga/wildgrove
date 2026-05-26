extends CanvasLayer
## HUD.gd — Zentrale UI mit Joystick, Buttons und Globalem Debugging

signal settings_requested

const JS_RADIUS: float = 90.0

# UI Elemente
var _js_base: ColorRect
var _js_knob: ColorRect
var _settings_btn: Button
var _interact_btn: Button
var _inventory_btn: Button
var _ui_offset: Vector2 = Vector2.ZERO

# Debug Konsole
var _debug_panel: ColorRect
var _debug_label: Label
var _debug_lines: Array[String] = []
var _debug_visible: bool = true

# Inventar
var _inventory_panel: ColorRect
var _inventory_visible: bool = false

func _ready() -> void:
	# WICHTIG: Die Gruppe "hud_layer" muss exakt so heißen wie im Interactable-Script
	add_to_group("hud_layer")
	
	_build_joystick()
	_build_interact_button()
	_build_top_buttons()
	_build_debug_console()
	_build_inventory_panel()
	
	# Systeme verbinden
	_connect_touch_input()
	_connect_event_bus()
	
	get_viewport().size_changed.connect(_on_viewport_resized)
	log_msg("HUD Initialisiert")

# --- Event-Bus Verbindung ---
func _connect_event_bus() -> void:
	# Prüft ob GameEvents als Autoload existiert
	var ge = get_node_or_null("/root/GameEvents")
	if ge:
		ge.debug_log.connect(log_msg)
		log_msg("Event-Bus verbunden.")
	else:
		push_warning("GameEvents Autoload nicht gefunden!")

# --- UI Bau-Funktionen ---
func _build_joystick() -> void:
	_js_base = ColorRect.new()
	_js_base.size = Vector2(JS_RADIUS * 2, JS_RADIUS * 2)
	_js_base.color = Color(1, 1, 1, 0.15)
	_js_base.anchor_left = 0.0; _js_base.anchor_top = 1.0; _js_base.anchor_bottom = 1.0
	_js_base.offset_left = 40; _js_base.offset_top = -(JS_RADIUS * 2 + 60)
	add_child(_js_base)

	_js_knob = ColorRect.new()
	_js_knob.size = Vector2(60, 60)
	_js_knob.color = Color(1, 1, 1, 0.8)
	_js_knob.anchor_left = 0.0; _js_knob.anchor_top = 1.0; _js_knob.anchor_bottom = 1.0
	_js_knob.offset_left = 40 + JS_RADIUS - 30; _js_knob.offset_top = -(JS_RADIUS + 60)
	add_child(_js_knob)

func _build_interact_button() -> void:
	_interact_btn = Button.new()
	_interact_btn.text = "⚡"
	_interact_btn.custom_minimum_size = Vector2(120, 120)
	_interact_btn.anchor_left = 1.0; _interact_btn.anchor_top = 1.0; _interact_btn.anchor_right = 1.0; _interact_btn.anchor_bottom = 1.0
	_interact_btn.offset_left = -240; _interact_btn.offset_top = -200
	_interact_btn.add_theme_font_size_override("font_size", 50)
	_interact_btn.visible = false
	_interact_btn.pressed.connect(_on_interact_pressed)
	add_child(_interact_btn)

func _build_top_buttons() -> void:
	_settings_btn = Button.new()
	_settings_btn.text = "⚙"
	_settings_btn.custom_minimum_size = Vector2(90, 90)
	_settings_btn.anchor_left = 1.0; _settings_btn.anchor_right = 1.0
	_settings_btn.offset_left = -110; _settings_btn.offset_top = 40
	_settings_btn.pressed.connect(func(): settings_requested.emit())
	add_child(_settings_btn)

func _build_debug_console() -> void:
	_debug_panel = ColorRect.new()
	_debug_panel.color = Color(0, 0, 0, 0.5)
	_debug_panel.anchor_right = 1.0; _debug_panel.offset_bottom = 300
	add_child(_debug_panel)

	_debug_label = Label.new()
	_debug_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	_debug_label.add_theme_font_size_override("font_size", 20)
	_debug_label.add_theme_color_override("font_color", Color.GREEN)
	_debug_panel.add_child(_debug_label)

func _build_inventory_panel() -> void:
	_inventory_panel = ColorRect.new()
	_inventory_panel.color = Color(0.1, 0.1, 0.1, 0.9)
	_inventory_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_inventory_panel.custom_minimum_size = Vector2(600, 800)
	_inventory_panel.visible = false
	add_child(_inventory_panel)

# --- Interaktions-Logik ---
func _on_interact_pressed() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		players[0].try_interact()

func show_interact_button(label: String) -> void:
	_interact_btn.visible = true
	# Optional: Beschriftung ändern wenn gewünscht
	log_msg("Aktion verfügbar: " + label)

func hide_interact_button() -> void:
	_interact_btn.visible = false

# --- Debug Logging ---
func log_msg(msg: String) -> void:
	print("[HUD] " + msg)
	_debug_lines.append(msg)
	if _debug_lines.size() > 10:
		_debug_lines.remove_at(0)
	if _debug_label:
		_debug_label.text = "\n".join(_debug_lines)

# --- Hilfsfunktionen ---
func _connect_touch_input() -> void:
	var ti = get_tree().get_first_node_in_group("touch_input")
	if ti:
		ti.register_joystick_visuals(_js_base, _js_knob)

func _on_viewport_resized() -> void:
	apply_ui_offset(_ui_offset)

func apply_ui_offset(offset: Vector2) -> void:
	_ui_offset = offset
	# Hier können die Offsets für Mobile-Notches angepasst werden
	_js_base.position += offset
	_interact_btn.position += offset

func _toggle_inventory() -> void:
	_inventory_visible = !_inventory_visible
	_inventory_panel.visible = _inventory_visible
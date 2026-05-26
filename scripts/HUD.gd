extends CanvasLayer
## HUD.gd — Joystick, Buttons, Debug-Console, Inventar-Panel

signal settings_requested

const JS_RADIUS: float = 90.0

var _js_base: ColorRect
var _js_knob: ColorRect
var _settings_btn: Button
var _interact_btn: Button
var _inventory_btn: Button
var _ui_offset: Vector2 = Vector2.ZERO

# Debug console
var _debug_panel: ColorRect
var _debug_label: Label
var _debug_lines: Array[String] = []
var _debug_visible: bool = true

# Inventar-Panel
var _inventory_panel: ColorRect
var _inventory_visible: bool = false


func _ready() -> void:
	add_to_group("hud_layer")
	_build_joystick()
	_build_interact_button()
	_build_top_buttons()
	_build_debug_console()
	_build_inventory_panel()
	_connect_touch_input()
	_connect_systems()
	get_viewport().size_changed.connect(_on_viewport_resized)


func _build_joystick() -> void:
	_js_base = ColorRect.new()
	_js_base.size = Vector2(JS_RADIUS * 2, JS_RADIUS * 2)
	_js_base.color = Color(1, 1, 1, 0.15)
	_js_base.anchor_left   = 0.0
	_js_base.anchor_right  = 0.0
	_js_base.anchor_top    = 1.0
	_js_base.anchor_bottom = 1.0
	_js_base.offset_left   = 40
	_js_base.offset_right  = 40 + JS_RADIUS * 2
	_js_base.offset_top    = -(JS_RADIUS * 2 + 60)
	_js_base.offset_bottom = -60
	add_child(_js_base)

	_js_knob = ColorRect.new()
	_js_knob.size = Vector2(60, 60)
	_js_knob.color = Color(1, 1, 1, 0.8)
	_js_knob.anchor_left   = 0.0
	_js_knob.anchor_right  = 0.0
	_js_knob.anchor_top    = 1.0
	_js_knob.anchor_bottom = 1.0
	_js_knob.offset_left   = 40 + JS_RADIUS - 30
	_js_knob.offset_right  = 40 + JS_RADIUS + 30
	_js_knob.offset_top    = -(JS_RADIUS + 60)
	_js_knob.offset_bottom = -(JS_RADIUS + 60) + 60
	add_child(_js_knob)


func _build_interact_button() -> void:
	_interact_btn = Button.new()
	_interact_btn.text = "⚡"
	_interact_btn.custom_minimum_size = Vector2(100, 100)
	_interact_btn.anchor_left   = 1.0
	_interact_btn.anchor_right  = 1.0
	_interact_btn.anchor_top    = 1.0
	_interact_btn.anchor_bottom = 1.0
	_interact_btn.offset_left   = -220
	_interact_btn.offset_right  = -120
	_interact_btn.offset_top    = -180
	_interact_btn.offset_bottom = -80
	_interact_btn.add_theme_font_size_override("font_size", 44)
	_interact_btn.visible = false
	_interact_btn.pressed.connect(_on_interact_pressed)
	add_child(_interact_btn)


func _build_top_buttons() -> void:
	# Settings ⚙ oben rechts
	_settings_btn = Button.new()
	_settings_btn.text = "⚙"
	_settings_btn.custom_minimum_size = Vector2(90, 90)
	_settings_btn.anchor_left   = 1.0
	_settings_btn.anchor_right  = 1.0
	_settings_btn.anchor_top    = 0.0
	_settings_btn.anchor_bottom = 0.0
	_settings_btn.offset_left   = -110
	_settings_btn.offset_right  = -20
	_settings_btn.offset_top    = 40
	_settings_btn.offset_bottom = 130
	_settings_btn.add_theme_font_size_override("font_size", 44)
	_settings_btn.pressed.connect(func() -> void: emit_signal("settings_requested"))
	add_child(_settings_btn)

	# Inventar 🎒 oben rechts unter Settings
	_inventory_btn = Button.new()
	_inventory_btn.text = "🎒"
	_inventory_btn.custom_minimum_size = Vector2(90, 90)
	_inventory_btn.anchor_left   = 1.0
	_inventory_btn.anchor_right  = 1.0
	_inventory_btn.anchor_top    = 0.0
	_inventory_btn.anchor_bottom = 0.0
	_inventory_btn.offset_left   = -110
	_inventory_btn.offset_right  = -20
	_inventory_btn.offset_top    = 140
	_inventory_btn.offset_bottom = 230
	_inventory_btn.add_theme_font_size_override("font_size", 44)
	_inventory_btn.pressed.connect(_toggle_inventory)
	add_child(_inventory_btn)

	# Debug toggle oben links
	var dbg_btn := Button.new()
	dbg_btn.text = "🐛"
	dbg_btn.custom_minimum_size = Vector2(70, 70)
	dbg_btn.anchor_left   = 0.0
	dbg_btn.anchor_right  = 0.0
	dbg_btn.anchor_top    = 0.0
	dbg_btn.anchor_bottom = 0.0
	dbg_btn.offset_left   = 20
	dbg_btn.offset_right  = 90
	dbg_btn.offset_top    = 20
	dbg_btn.offset_bottom = 90
	dbg_btn.add_theme_font_size_override("font_size", 32)
	dbg_btn.pressed.connect(_toggle_debug)
	add_child(dbg_btn)


func _build_debug_console() -> void:
	_debug_panel = ColorRect.new()
	_debug_panel.color = Color(0, 0, 0, 0.65)
	_debug_panel.anchor_left   = 0.0
	_debug_panel.anchor_right  = 1.0
	_debug_panel.anchor_top    = 0.0
	_debug_panel.anchor_bottom = 0.0
	_debug_panel.offset_left   = 0
	_debug_panel.offset_right  = 0
	_debug_panel.offset_top    = 100
	_debug_panel.offset_bottom = 380
	add_child(_debug_panel)

	_debug_label = Label.new()
	_debug_label.position = Vector2(10, 8)
	_debug_label.size = Vector2(1060, 270)
	_debug_label.add_theme_font_size_override("font_size", 22)
	_debug_label.add_theme_color_override("font_color", Color.GREEN)
	_debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_debug_panel.add_child(_debug_label)

	log_msg("=== WildGrove Debug ===")


func _build_inventory_panel() -> void:
	_inventory_panel = ColorRect.new()
	_inventory_panel.color = Color(0.08, 0.08, 0.08, 0.95)
	_inventory_panel.anchor_left   = 0.5
	_inventory_panel.anchor_right  = 0.5
	_inventory_panel.anchor_top    = 0.5
	_inventory_panel.anchor_bottom = 0.5
	_inventory_panel.offset_left   = -320
	_inventory_panel.offset_right  = 320
	_inventory_panel.offset_top    = -400
	_inventory_panel.offset_bottom = 400
	_inventory_panel.visible = false
	add_child(_inventory_panel)

	var title := Label.new()
	title.text = "🎒  Inventar"
	title.position = Vector2(20, 16)
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color.WHITE)
	_inventory_panel.add_child(title)

	var close := Button.new()
	close.text = "✕"
	close.position = Vector2(570, 16)
	close.size = Vector2(60, 60)
	close.add_theme_font_size_override("font_size", 30)
	close.pressed.connect(_toggle_inventory)
	_inventory_panel.add_child(close)

	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.15)
	line.size = Vector2(600, 2)
	line.position = Vector2(20, 80)
	_inventory_panel.add_child(line)

	# Skill-Leiste oben
	var skill_lbl := Label.new()
	skill_lbl.name = "SkillLabel"
	skill_lbl.text = "Skills: Holzfällen Lv.1"
	skill_lbl.position = Vector2(20, 90)
	skill_lbl.size = Vector2(600, 60)
	skill_lbl.add_theme_font_size_override("font_size", 22)
	skill_lbl.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 1))
	skill_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	_inventory_panel.add_child(skill_lbl)

	var line2 := ColorRect.new()
	line2.color = Color(1, 1, 1, 0.15)
	line2.size = Vector2(600, 2)
	line2.position = Vector2(20, 155)
	_inventory_panel.add_child(line2)

	# Inventar-Grid (4x7 = 28 Slots)
	var grid := GridContainer.new()
	grid.name = "ItemGrid"
	grid.columns = 4
	grid.position = Vector2(20, 165)
	grid.size = Vector2(600, 560)
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_inventory_panel.add_child(grid)

	for i in 28:
		var slot := ColorRect.new()
		slot.custom_minimum_size = Vector2(130, 100)
		slot.color = Color(0.15, 0.15, 0.15, 1)
		var slot_lbl := Label.new()
		slot_lbl.name = "SlotLabel"
		slot_lbl.text = ""
		slot_lbl.add_theme_font_size_override("font_size", 20)
		slot_lbl.add_theme_color_override("font_color", Color.WHITE)
		slot_lbl.position = Vector2(6, 6)
		slot_lbl.size = Vector2(118, 88)
		slot_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		slot_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot.add_child(slot_lbl)
		grid.add_child(slot)


# ── Inventar aktualisieren ─────────────────────────────────────────────────
func refresh_inventory() -> void:
	var inv_nodes: Array = get_tree().get_nodes_in_group("inventory_system")
	var grid: Node = _inventory_panel.get_node_or_null("ItemGrid")
	if not grid:
		return

	# Alle Slots leeren
	for slot in grid.get_children():
		var lbl: Label = slot.get_node_or_null("SlotLabel")
		if lbl:
			lbl.text = ""

	if inv_nodes.size() == 0:
		return

	var inv: Node = inv_nodes[0]
	var items: Array = inv.get_all_items()
	var slot_idx: int = 0
	for item in items:
		if slot_idx >= grid.get_child_count():
			break
		var slot: Node = grid.get_child(slot_idx)
		var lbl: Label = slot.get_node_or_null("SlotLabel")
		if lbl:
			var info: Dictionary = inv.get_item_info(item.get("item_id", ""))
			lbl.text = "%s\n×%d" % [info.get("name", "?"), item.get("quantity", 0)]
		slot_idx += 1

	# Skill-Anzeige aktualisieren
	_refresh_skill_display()


func _refresh_skill_display() -> void:
	var ss_nodes: Array = get_tree().get_nodes_in_group("skill_system")
	var lbl: Label = _inventory_panel.get_node_or_null("SkillLabel")
	if not lbl or ss_nodes.size() == 0:
		return
	var ss: Node = ss_nodes[0]
	var text: String = ""
	var skills: Array[String] = ["woodcutting", "fishing", "mining", "farming", "foraging", "cooking"]
	for skill in skills:
		var lvl: int = ss.get_level(skill)
		var xp_next: int = ss.get_xp_to_next(skill)
		text += "%s Lv.%d (%d XP)   " % [ss.get_label(skill), lvl, xp_next]
	lbl.text = text


# ── Debug Console ──────────────────────────────────────────────────────────
func log_msg(msg: String) -> void:
	print(msg)
	_debug_lines.append(msg)
	if _debug_lines.size() > 12:
		_debug_lines.remove_at(0)
	if _debug_label:
		_debug_label.text = "\n".join(_debug_lines)


func _toggle_debug() -> void:
	_debug_visible = not _debug_visible
	_debug_panel.visible = _debug_visible


func _toggle_inventory() -> void:
	_inventory_visible = not _inventory_visible
	_inventory_panel.visible = _inventory_visible
	if _inventory_visible:
		refresh_inventory()


# ── Interact Button ────────────────────────────────────────────────────────
func _on_interact_pressed() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0].has_method("try_interact"):
		players[0].try_interact()


func show_interact_button(label: String) -> void:
	_interact_btn.text = "⚡"
	_interact_btn.tooltip_text = label
	_interact_btn.visible = true
	log_msg("Aktion: " + label)


func hide_interact_button() -> void:
	_interact_btn.visible = false


# ── Systems verbinden ──────────────────────────────────────────────────────
func _connect_systems() -> void:
	call_deferred("_deferred_connect")


func _deferred_connect() -> void:
	# SkillSystem → Log
	var ss_nodes: Array = get_tree().get_nodes_in_group("skill_system")
	if ss_nodes.size() > 0:
		ss_nodes[0].xp_gained.connect(func(skill: String, amt: int, _t: int) -> void:
			log_msg("+%d %s XP" % [amt, skill])
		)
		ss_nodes[0].level_up.connect(func(skill: String, lvl: int) -> void:
			log_msg("🎉 LEVEL UP! %s → %d" % [skill, lvl])
		)

	# InventorySystem → Inventar-Panel auto-refresh
	var inv_nodes: Array = get_tree().get_nodes_in_group("inventory_system")
	if inv_nodes.size() > 0:
		inv_nodes[0].inventory_changed.connect(func() -> void:
			if _inventory_visible:
				refresh_inventory()
			log_msg("Inventar geändert")
		)


func _on_viewport_resized() -> void:
	apply_ui_offset(_ui_offset)


func apply_ui_offset(offset: Vector2) -> void:
	_ui_offset = offset
	_js_base.offset_left   = 40 + offset.x
	_js_base.offset_right  = 40 + JS_RADIUS * 2 + offset.x
	_js_base.offset_top    = -(JS_RADIUS * 2 + 60) + offset.y
	_js_base.offset_bottom = -60 + offset.y
	_js_knob.offset_left   = 40 + JS_RADIUS - 30 + offset.x
	_js_knob.offset_right  = 40 + JS_RADIUS + 30 + offset.x
	_js_knob.offset_top    = -(JS_RADIUS + 60) + offset.y
	_js_knob.offset_bottom = -(JS_RADIUS + 60) + 60 + offset.y
	_settings_btn.offset_left   = -110 + offset.x
	_settings_btn.offset_right  = -20  + offset.x
	_settings_btn.offset_top    = 40   + offset.y
	_settings_btn.offset_bottom = 130  + offset.y
	_inventory_btn.offset_left   = -110 + offset.x
	_inventory_btn.offset_right  = -20  + offset.x
	_inventory_btn.offset_top    = 140  + offset.y
	_inventory_btn.offset_bottom = 230  + offset.y
	_interact_btn.offset_left   = -220 + offset.x
	_interact_btn.offset_right  = -120 + offset.x
	_interact_btn.offset_top    = -180 + offset.y
	_interact_btn.offset_bottom = -80  + offset.y


func _connect_touch_input() -> void:
	var nodes: Array = get_tree().get_nodes_in_group("touch_input")
	if nodes.size() > 0:
		nodes[0].register_joystick_visuals(_js_base, _js_knob)

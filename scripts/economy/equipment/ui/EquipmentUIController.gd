class_name EquipmentUIController

## EquipmentUIController — verwaltet das Equipment-Panel mit Slot-UI.
##
## Zeigt alle Equipment-Slots, verbindet Item-Taps im Inventar mit "Anlegen"-Dialog.
## Verdrahtet EquipmentService ↔ InventorySystem ↔ HUD.
##
## Aufgerufen von HUDBuilder via EquipmentComponent.build(hud, ctx).

const LOG_CAT := "EquipmentUI"

const SLOT_ICONS := {
	"weapon":  "🗡️",
	"tool":    "🪓",
	"offhand": "🛡",
	"helmet":  "⛑",
	"chest":   "🥋",
	"legs":    "👖",
	"boots":   "👟",
	"ring":    "💍",
	"amulet":  "📿",
	# Kleidung (WearableCatalog.SLOTS)
	"hat":       "🎩",
	"glasses":   "👓",
	"scarf":     "🧣",
	"shoulders": "🛡",
	"back":      "🎒",
	"shirt":     "👕",
	"belt":      "🪢",
	"pouch":     "👛",
	"pants":     "👖",
	"shoes":     "👞",
}

const SLOT_LABELS := {
	"weapon":  "Waffe",
	"tool":    "Werkzeug",
	"offhand": "Nebenhand",
	"helmet":  "Helm",
	"chest":   "Brust",
	"legs":    "Beine",
	"boots":   "Stiefel",
	"ring":    "Ring",
	"amulet":  "Amulett",
	# Kleidung (WearableCatalog.SLOTS)
	"hat":       "Kopfbedeckung",
	"glasses":   "Brille",
	"scarf":     "Schal",
	"shoulders": "Schulter",
	"back":      "Rücken",
	"shirt":     "Oberteil",
	"belt":      "Gürtel",
	"pouch":     "Beutel",
	"pants":     "Hose",
	"shoes":     "Schuhe",
}

var _equipment: EquipmentService
var _inventory: InventorySystem
var _data: DataService
var _ctx: IUIContext

var _panel: PanelContainer
var _tab_bar: HBoxContainer
var _inv_tab: Button
var _equip_tab: Button
var _inventory_list: VBoxContainer
var _equipment_slots: VBoxContainer
var _stats_label: Label
var _dialog: PanelContainer
var _toggle_button: Button
var _hud: CanvasLayer

## Welcher Tab aktiv ist
var _active_tab: String = "inventory"

## BUGFIX (entdeckt im Zuge von Bug #2, gleiche Root Cause): kein `extends Node`
## (RefCounted) — ohne teardown() bleibt dieser Controller nach jedem
## HUD-Rebuild (world_scene_ready) als Zombie-Listener auf equipment_changed/
## inventory_changed am Leben, siehe FloatingTextController für die
## ausführliche Erklärung desselben Musters. Die eigenen UI-Nodes (_panel etc.)
## werden zwar über hud.get_children() beim Rebuild mit freigegeben, der
## Zombie-Controller selbst (RefCounted, kein Node) aber nicht — er ruft bei
## der nächsten Änderung _refresh_equipment_tab()/_refresh_inventory_tab() auf
## bereits freigegebenen Nodes auf.
var _is_setup: bool = false
var _inventory_changed_callable: Callable

func setup(hud: HUD, ctx: IUIContext) -> void:
	if _is_setup:
		teardown()
	_hud = hud
	_ctx = ctx
	_equipment = ctx.get_equipment()
	_inventory  = ctx.get_inventory()
	_data        = ctx.get_data()

	_build_ui(hud)

	if is_instance_valid(_equipment):
		_equipment.equipment_changed.connect(_on_equipment_changed)
	# R-7 (ADR-022): war hartcodiert auf Spieler 1 — jetzt gegen die stabile
	# player_id dieses Clients geprüft (ADR-029 Plan-Schritt 4, Round 63:
	# InventorySystem ist migriert, Key ist jetzt String/player_uuid).
	if is_instance_valid(_inventory):
		_inventory_changed_callable = func(player_id: String, _items) -> void:
			if player_id == _local_player_id():
				_refresh_inventory_tab()
		_inventory.inventory_changed.connect(_inventory_changed_callable)

	_refresh_inventory_tab()
	_refresh_equipment_tab()
	_is_setup = true

## MUSS von HUDManager vor dem Verwerfen dieses Controllers aufgerufen werden
## (siehe HUDManager._on_world_scene_ready()) — sonst bleibt dieser Controller
## als Zombie-Listener am Leben.
func teardown() -> void:
	if is_instance_valid(_equipment) and _equipment.equipment_changed.is_connected(_on_equipment_changed):
		_equipment.equipment_changed.disconnect(_on_equipment_changed)
	if is_instance_valid(_inventory) and _inventory_changed_callable.is_valid():
		if _inventory.inventory_changed.is_connected(_inventory_changed_callable):
			_inventory.inventory_changed.disconnect(_inventory_changed_callable)
	_is_setup = false

## R-7 (ADR-022): zentraler Zugriffspunkt für "wer ist der lokale Spieler
## dieses Clients" — Default 1 nur wenn kein IUIContext injiziert wurde.
func _local_peer_id() -> int:
	return _ctx.get_local_peer_id() if is_instance_valid(_ctx) else 1

## ADR-029 Plan-Schritt 4 (Round 63): String-Pendant zu _local_peer_id(), für
## Aufrufe in InventorySystem (migriert, player_id: String) — siehe
## InventoryUIController._local_player_id() für dieselbe Begründung.
func _local_player_id() -> String:
	return _ctx.get_local_player_id() if is_instance_valid(_ctx) else ""

func toggle() -> void:
	_panel.visible = !_panel.visible

# ─────────────────────────────────────────────
# UI-Aufbau
# ─────────────────────────────────────────────

func _build_ui(parent: CanvasLayer) -> void:
	# Toggle-Button in der PanelDock-Toolbar. Icon 🛡 statt ⚔: ⚔ gehört dem Skill-Panel
	# (vorher hatten beide dasselbe Symbol und lagen zusätzlich übereinander).
	_toggle_button = Button.new()
	_toggle_button.name = "EquipToggleButton"
	_toggle_button.text = "🛡"
	_toggle_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_toggle_button.pressed.connect(toggle)

	# Haupt-Panel
	_panel = PanelContainer.new()
	_panel.name = "EquipmentPanel"
	_panel.visible = false

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.08, 0.93)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", sb)

	UIMetrics.place_sheet(_panel, 420)
	parent.add_child(_panel)
	PanelDock.register_in(parent, &"equipment", _panel, PanelDock.Kind.SHEET, _toggle_button)

	var vbox := VBoxContainer.new()
	_panel.add_child(vbox)

	# Tab-Leiste
	_tab_bar = HBoxContainer.new()
	_tab_bar.add_theme_constant_override("separation", 4)
	vbox.add_child(_tab_bar)

	_inv_tab = _make_tab_button("🎒 Inventar",   "inventory")
	_equip_tab = _make_tab_button("⚔ Ausrüstung", "equipment")
	_tab_bar.add_child(_inv_tab)
	_tab_bar.add_child(_equip_tab)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Scrollbarer Inhalt
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vbar := scroll.get_v_scroll_bar()
	if is_instance_valid(vbar):
		vbar.custom_minimum_size = Vector2(20, 0)
	vbox.add_child(scroll)

	# Inventar-Liste (Tab 1)
	_inventory_list = VBoxContainer.new()
	_inventory_list.name = "InventoryList"
	_inventory_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_inventory_list)

	# Equipment-Slots (Tab 2)
	_equipment_slots = VBoxContainer.new()
	_equipment_slots.name = "EquipmentSlots"
	_equipment_slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_equipment_slots.visible = false
	scroll.add_child(_equipment_slots)

	# Stats-Zusammenfassung
	var stats_panel := PanelContainer.new()
	var stats_sb := StyleBoxFlat.new()
	stats_sb.bg_color = Color(0.08, 0.08, 0.12, 0.9)
	stats_sb.set_corner_radius_all(6)
	stats_sb.set_content_margin_all(8)
	stats_panel.add_theme_stylebox_override("panel", stats_sb)
	stats_panel.name = "StatsPanel"
	vbox.add_child(stats_panel)

	_stats_label = Label.new()
	_stats_label.name = "StatsLabel"
	_stats_label.text = ""
	_stats_label.add_theme_font_size_override("font_size", 14)
	_stats_label.self_modulate = Color(0.8, 0.9, 1.0)
	stats_panel.add_child(_stats_label)

	_switch_tab("inventory")

func _make_tab_button(label: String, tab_id: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(150, UIMetrics.TAP_MIN)
	btn.pressed.connect(func() -> void: _switch_tab(tab_id))
	return btn

func _switch_tab(tab_id: String) -> void:
	_active_tab = tab_id
	_inventory_list.visible  = (tab_id == "inventory")
	_equipment_slots.visible = (tab_id == "equipment")
	_inv_tab.modulate   = Color.WHITE if tab_id == "inventory"  else Color(0.6, 0.6, 0.6)
	_equip_tab.modulate = Color.WHITE if tab_id == "equipment" else Color(0.6, 0.6, 0.6)
	if tab_id == "equipment":
		_refresh_equipment_tab()

# ─────────────────────────────────────────────
# Inventar-Tab
# ─────────────────────────────────────────────

func _refresh_inventory_tab() -> void:
	for child in _inventory_list.get_children():
		child.queue_free()

	if not is_instance_valid(_inventory):
		var lbl := Label.new()
		lbl.text = "(Inventar nicht verfügbar)"
		_inventory_list.add_child(lbl)
		return

	var items := _inventory.get_all_items(_local_player_id())
	if items.is_empty():
		var lbl := Label.new()
		lbl.text = "(Leer)"
		_inventory_list.add_child(lbl)
		return

	for item_dict in items:
		var item_id: String = item_dict.get("id", item_dict.get("item_id", ""))
		var item_name: String = item_dict.get("name", item_dict.get("display_name", item_id))
		var qty: int = item_dict.get("quantity", 1)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_inventory_list.add_child(row)

		var name_lbl := Label.new()
		name_lbl.text = "%s ×%d" % [item_name, qty]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 16)
		row.add_child(name_lbl)

		# Prüfen ob Item equipbar ist
		var item_def: ItemDefinition = null
		if is_instance_valid(_data):
			item_def = _data.get_item(item_id)

		if item_def is WeaponDefinition:
			var equip_btn := Button.new()
			equip_btn.text = "⚔ Anlegen"
			equip_btn.custom_minimum_size = Vector2(110, UIMetrics.TAP_MIN)
			var captured_def: WeaponDefinition = item_def as WeaponDefinition
			equip_btn.pressed.connect(func() -> void: _on_equip_weapon(captured_def))
			row.add_child(equip_btn)
		elif item_def is ToolDefinition:
			var equip_tool_btn := Button.new()
			equip_tool_btn.text = "🪓 Anlegen"
			equip_tool_btn.custom_minimum_size = Vector2(110, UIMetrics.TAP_MIN)
			var captured_tool: ToolDefinition = item_def as ToolDefinition
			equip_tool_btn.pressed.connect(func() -> void: _on_equip_tool(captured_tool))
			row.add_child(equip_tool_btn)
		elif item_def is ArmorDefinition:
			var equip_armor_btn := Button.new()
			equip_armor_btn.text = "🛡 Anlegen"
			equip_armor_btn.custom_minimum_size = Vector2(110, UIMetrics.TAP_MIN)
			var captured_armor: ArmorDefinition = item_def as ArmorDefinition
			equip_armor_btn.pressed.connect(func() -> void: _on_equip_armor(captured_armor))
			row.add_child(equip_armor_btn)
		elif item_def is WearableDefinition:
			var equip_wear_btn := Button.new()
			equip_wear_btn.text = "👕 Anziehen"
			equip_wear_btn.custom_minimum_size = Vector2(110, UIMetrics.TAP_MIN)
			var captured_wear: WearableDefinition = item_def as WearableDefinition
			equip_wear_btn.pressed.connect(func() -> void: _on_equip_wearable(captured_wear))
			row.add_child(equip_wear_btn)

	# FIX (Wunsch "Scrollen geht häufig nicht"): siehe UIMetrics.allow_scroll_through()
	# — die Anlegen-Buttons haben sonst STOP und blockieren jede Wisch-Geste,
	# die auf ihnen startet, statt sie an den ScrollContainer weiterzugeben.
	UIMetrics.allow_scroll_through(_inventory_list)

# ─────────────────────────────────────────────
# Equipment-Tab
# ─────────────────────────────────────────────

func _refresh_equipment_tab() -> void:
	for child in _equipment_slots.get_children():
		child.queue_free()

	# Waffen/Werkzeug, Rüstung, dann Kleidung (echte, an- und ausziehbare Items).
	var slots_to_show: Array = ["weapon", "tool", "offhand", "helmet", "chest", "legs", "boots"]
	slots_to_show.append_array(WearableCatalog.SLOT_ORDER)

	for slot_id in slots_to_show:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_equipment_slots.add_child(row)

		var icon_lbl := Label.new()
		icon_lbl.text = SLOT_ICONS.get(slot_id, "?")
		icon_lbl.custom_minimum_size = Vector2(36, 36)
		icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(icon_lbl)

		var slot_lbl := Label.new()
		slot_lbl.text = SLOT_LABELS.get(slot_id, slot_id)
		slot_lbl.custom_minimum_size = Vector2(80, 0)
		slot_lbl.add_theme_font_size_override("font_size", 14)
		slot_lbl.self_modulate = Color(0.7, 0.7, 0.8)
		row.add_child(slot_lbl)

		var item_lbl := Label.new()
		item_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_lbl.add_theme_font_size_override("font_size", 16)

		if is_instance_valid(_equipment) and _equipment.is_equipped(slot_id, _local_player_id()):
			var equipped := _equipment.get_equipped(slot_id, _local_player_id())
			item_lbl.text = equipped.display_name
			item_lbl.self_modulate = Color(1.0, 0.95, 0.5)

			var unequip_btn := Button.new()
			unequip_btn.text = "❌"
			unequip_btn.custom_minimum_size = Vector2(UIMetrics.TAP_MIN, UIMetrics.TAP_MIN)
			var captured_slot: String = slot_id
			unequip_btn.pressed.connect(func() -> void: _on_unequip(captured_slot))
			row.add_child(item_lbl)
			row.add_child(unequip_btn)
		else:
			item_lbl.text = "(leer)"
			item_lbl.self_modulate = Color(0.4, 0.4, 0.4)
			row.add_child(item_lbl)

	UIMetrics.allow_scroll_through(_equipment_slots)
	_refresh_stats()

func _refresh_stats() -> void:
	if not is_instance_valid(_equipment):
		_stats_label.text = ""
		return

	# ADR-029 Round 66: get_equipped_weapon() erwartet jetzt player_id (String)
	# vor slot (Parameter-Reihenfolge getauscht, siehe EquipmentService-Kommentar).
	var weapon := _equipment.get_equipped_weapon(_local_player_id(), EquipmentService.SLOT_WEAPON)
	var lines: Array[String] = []
	if is_instance_valid(weapon):
		lines.append("⚔ Schaden +%.0f" % weapon.damage_bonus)
		if weapon.on_hit_effect >= 0:
			lines.append("☠ Gift: %.0f/s × %d Ticks" % [weapon.on_hit_damage_per_tick, weapon.on_hit_ticks])
	var armor_total := 0.0
	for armor_slot in ArmorDefinition.all_slot_ids():
		var worn := _equipment.get_equipped(armor_slot, _local_player_id())
		if worn is ArmorDefinition:
			armor_total += (worn as ArmorDefinition).armor_value
	if armor_total > 0.0:
		lines.append("🛡 Rüstung −%d %% physischer Schaden" % roundi(armor_total * 100.0))
	if lines.is_empty():
		_stats_label.text = "Keine aktiven Boni"
	else:
		_stats_label.text = "\n".join(lines)

# ─────────────────────────────────────────────
# Aktions-Handler
# ─────────────────────────────────────────────

## ADR-027: request_equip() statt equip() direkt — die Autorität löst
## PlayerVisuals jetzt selbst über WorldService.get_player_visuals(peer_id)
## auf (siehe EquipmentService.on_equip_confirmed()), deshalb entfällt die
## bisherige lokale PlayerVisuals-Suche hier komplett.
func _on_equip_weapon(weapon_def: WeaponDefinition) -> void:
	if not is_instance_valid(_equipment):
		return

	var player_id := _local_player_id()
	_equipment.request_equip("weapon", weapon_def.id, player_id)
	_ctx.bus().ui().emit_floating_loot_text_requested("⚔ %s angelegt!" % weapon_def.display_name)
	_refresh_equipment_tab()
	_refresh_inventory_tab()

## Round 88: Analog _on_equip_weapon(), Slot "tool" statt "weapon".
func _on_equip_armor(armor_def: ArmorDefinition) -> void:
	if not is_instance_valid(_equipment):
		return
	_equipment.request_equip(armor_def.get_slot_id(), armor_def.id, _local_player_id())
	_ctx.bus().ui().emit_floating_loot_text_requested("🛡 %s angelegt!" % armor_def.display_name)
	_refresh_equipment_tab()
	_refresh_inventory_tab()

## Kleidung anziehen: Slot aus der Definition, EquipmentService prüft serverseitig erneut.
func _on_equip_wearable(wear_def: WearableDefinition) -> void:
	if not is_instance_valid(_equipment):
		return
	_equipment.request_equip(wear_def.wear_slot, wear_def.id, _local_player_id())
	_ctx.bus().ui().emit_floating_loot_text_requested("👕 %s angezogen!" % wear_def.display_name)
	_refresh_equipment_tab()
	_refresh_inventory_tab()

func _on_equip_tool(tool_def: ToolDefinition) -> void:
	if not is_instance_valid(_equipment):
		return

	var player_id := _local_player_id()
	_equipment.request_equip(EquipmentService.SLOT_TOOL, tool_def.id, player_id)
	_ctx.bus().ui().emit_floating_loot_text_requested("🪓 %s angelegt!" % tool_def.display_name)
	_refresh_equipment_tab()
	_refresh_inventory_tab()

## ADR-027: request_unequip() statt unequip() direkt — derselbe Mutationspfad
## wie beim Equip, statt eine zweite, ungated Abkürzung offenzuhalten.
func _on_unequip(slot: String) -> void:
	if not is_instance_valid(_equipment):
		return
	var player_id := _local_player_id()
	var item := _equipment.get_equipped(slot, player_id)
	_equipment.request_unequip(slot, player_id)
	if is_instance_valid(item):
		_ctx.bus().ui().emit_floating_loot_text_requested("🔄 %s abgelegt." % item.display_name)
	_refresh_equipment_tab()

## ADR-029 Round 66: player_id jetzt String — equipment_changed feuert weiterhin
## für JEDEN Spieler, Filter auf den lokalen Client jetzt gegen die stabile
## player_id statt der peer_id (R-7/ADR-022-Begründung unverändert).
func _on_equipment_changed(_slot: String, _item_def: ItemDefinition, player_id: String) -> void:
	if player_id != _local_player_id():
		return
	if _active_tab == "equipment":
		_refresh_equipment_tab()

# ─────────────────────────────────────────────
# Zusatz: CombatSystem-Verdrahtung für Waffen-Schaden
# ─────────────────────────────────────────────
## Wird von CombatSystem.player_melee_damage() genutzt.

class_name PetBattleVisuals

## PetBattleVisuals — Kampf-Fenster der Pet-Kämpfe (Modal, mittig). Drei Ansichten im selben Fenster:
##   1. TEAMWAHL  — alle eigenen Pets mit Kopf-Icon, Typ und Level; Haken = im Kampfteam (max. 10).
##   2. KAMPF     — Gegner oben, eigenes Pet unten (Name, Typ, Level, LP-Balken), Kampf-Log, Attacken-
##                  Knöpfe (mit Typ-Hinweis ×2/×½), "Wechseln" und "Aufgeben". Nach einem Besiegen
##                  ersetzt die Wechsel-Liste die Attacken.
##   3. ERGEBNIS  — Sieg/Niederlage mit Belohnungszeilen.
##
## Bewusst zustandslos bzgl. Spiellogik: Klicks werden nur als Signale gemeldet, ob/wie sie wirken
## entscheidet PetBattleController (er besitzt die PetBattleEngine). Gezeichnet wird immer aus der
## Engine, die set/refresh bekommen — nie aus eigener Kopie.

signal team_toggled(pet_id: int, selected: bool)
signal start_pressed
signal move_pressed(index: int)
signal switch_chosen(index: int)
signal forfeit_pressed
signal close_requested

const PANEL_WIDTH: float = 480.0
const ICON_PX: float = 56.0
const LOG_LINES: int = 6
const TEAM_SCROLL_HEIGHT: float = 380.0

const COLOR_HP_HIGH := Color(0.35, 0.85, 0.40)
const COLOR_HP_MID := Color(0.95, 0.80, 0.30)
const COLOR_HP_LOW := Color(0.90, 0.30, 0.25)

var panel: PanelContainer

var _title: Label
var _team_view: VBoxContainer
var _battle_view: VBoxContainer
var _result_view: VBoxContainer

# Teamwahl
var _team_subtitle: Label
var _team_rows: VBoxContainer
var _team_count: Label
var _start_button: Button
var _team_checks: Dictionary = {}  ## pet_id (int) → CheckButton

# Kampf
var _enemy_box: Dictionary = {}
var _player_box: Dictionary = {}
var _log_label: Label
var _log_lines: Array[String] = []
var _moves_grid: GridContainer
var _action_row: HBoxContainer
var _switch_box: VBoxContainer
var _switch_open: bool = false
## Zuletzt gezeichnete Engine — das Wechsel-Menü (🔄) baut seine Liste daraus auf.
var _engine_ref: PetBattleEngine = null

# Ergebnis
var _result_title: Label
var _result_text: Label

func _init(parent: CanvasLayer) -> void:
	panel = PanelContainer.new()
	panel.name = "PetBattlePanel"
	panel.visible = false
	panel.add_theme_stylebox_override("panel", UIMetrics.panel_style())
	UIMetrics.place_modal(panel, PANEL_WIDTH)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	vbox.add_child(_build_header())

	_team_view = _build_team_view()
	_battle_view = _build_battle_view()
	_result_view = _build_result_view()
	vbox.add_child(_team_view)
	vbox.add_child(_battle_view)
	vbox.add_child(_result_view)
	_show_view(_team_view)

	parent.add_child(panel)
	PanelDock.register_in(parent, &"pet_battle", panel, PanelDock.Kind.MODAL)

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

## Teamwahl öffnen. rows: [{id:int, name:String, level:int, type_id:int, appearance:Dictionary, selected:bool}]
func open_team_select(subtitle: String, rows: Array[Dictionary], max_team: int) -> void:
	_title.text = "⚔ Pet-Kampf"
	_team_subtitle.text = subtitle
	_clear_children(_team_rows)
	_team_checks.clear()
	var selected_count: int = 0
	for row in rows:
		_team_rows.add_child(_build_team_row(row))
		if bool(row.get("selected", false)):
			selected_count += 1
	UIMetrics.allow_scroll_through(_team_rows)
	set_team_count(selected_count, max_team)
	_show_view(_team_view)
	panel.visible = true

func set_team_count(count: int, max_team: int) -> void:
	_team_count.text = "Kampfteam: %d / %d" % [count, max_team]
	_start_button.disabled = count <= 0

func set_team_check(pet_id: int, selected: bool) -> void:
	var check: CheckButton = _team_checks.get(pet_id) as CheckButton
	if is_instance_valid(check):
		check.set_pressed_no_signal(selected)

func show_battle(engine: PetBattleEngine, enemy_name: String) -> void:
	_title.text = "⚔ Pet-Kampf gegen %s" % enemy_name
	_log_lines.clear()
	_switch_open = false
	_enemy_box["key"] = ""
	_player_box["key"] = ""
	_show_view(_battle_view)
	panel.visible = true
	refresh_battle(engine, engine.get_log())

## Zeichnet den Kampf neu. new_lines = die seit dem letzten Aufruf neu entstandenen Log-Zeilen.
func refresh_battle(engine: PetBattleEngine, new_lines: Array[String]) -> void:
	_engine_ref = engine
	for line in new_lines:
		_log_lines.append(line)
	while _log_lines.size() > LOG_LINES:
		_log_lines.remove_at(0)
	_log_label.text = "\n".join(_log_lines)

	var enemy: PetBattleMon = engine.active_enemy()
	var me: PetBattleMon = engine.active_player()
	_update_box(_enemy_box, enemy, "Noch %d Gegner" % engine.enemies_left())
	_update_box(_player_box, me, "%d von %d Pets kampfbereit" % [engine.alive_player_indices().size(), engine.player_team.size()])

	var over: bool = engine.is_over()
	var forced: bool = engine.needs_switch()
	_moves_grid.visible = not over and not forced and not _switch_open
	_action_row.visible = not over and not forced and not _switch_open
	_switch_box.visible = not over and (forced or _switch_open)
	if _moves_grid.visible:
		_populate_moves(engine)
	if _switch_box.visible:
		_populate_switch(engine, forced)

func show_result(title: String, lines: Array[String]) -> void:
	_title.text = "⚔ Pet-Kampf"
	_result_title.text = title
	_result_text.text = "\n".join(lines)
	_show_view(_result_view)
	panel.visible = true

func close() -> void:
	panel.visible = false

# ─────────────────────────────────────────────
# Aufbau
# ─────────────────────────────────────────────

func _build_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.name = "Header"
	_title = Label.new()
	_title.text = "⚔ Pet-Kampf"
	_title.add_theme_font_size_override("font_size", UIMetrics.FONT_TITLE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(_title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	UIMetrics.tap(close_btn, 44.0)
	close_btn.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(close_btn)
	return header

func _build_team_view() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "TeamView"
	box.add_theme_constant_override("separation", 8)
	_team_subtitle = Label.new()
	_team_subtitle.add_theme_font_size_override("font_size", UIMetrics.FONT_SUB)
	_team_subtitle.modulate = Color(1, 1, 1, 0.7)
	_team_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_team_subtitle)

	_team_rows = VBoxContainer.new()
	_team_rows.add_theme_constant_override("separation", 6)
	box.add_child(UIMetrics.make_scrollable(_team_rows, TEAM_SCROLL_HEIGHT))

	_team_count = Label.new()
	_team_count.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW)
	box.add_child(_team_count)

	_start_button = Button.new()
	_start_button.text = "⚔ Kampf starten"
	_start_button.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW)
	UIMetrics.tap(_start_button)
	_start_button.pressed.connect(func() -> void: start_pressed.emit())
	box.add_child(_start_button)
	return box

func _build_team_row(row: Dictionary) -> PanelContainer:
	var holder := PanelContainer.new()
	holder.add_theme_stylebox_override("panel", UIMetrics.row_style())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	holder.add_child(h)
	h.add_child(PetHeadIcon.create(row.get("appearance", {}) as Dictionary, ICON_PX))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := Label.new()
	name_label.text = "%s  Lv.%d" % [String(row.get("name", "Pet")), int(row.get("level", 1))]
	name_label.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW)
	info.add_child(name_label)
	var type_id: int = int(row.get("type_id", PetBattleTypes.Type.NORMAL))
	var type_label := Label.new()
	type_label.text = PetBattleTypes.label_for(type_id)
	type_label.add_theme_font_size_override("font_size", UIMetrics.FONT_SUB)
	type_label.modulate = PetBattleTypes.color_for(type_id)
	info.add_child(type_label)
	h.add_child(info)

	var check := CheckButton.new()
	check.button_pressed = bool(row.get("selected", false))
	UIMetrics.tap(check, 80.0)
	var pet_id: int = int(row.get("id", 0))
	check.toggled.connect(func(on: bool) -> void: team_toggled.emit(pet_id, on))
	h.add_child(check)
	_team_checks[pet_id] = check
	return holder

func _build_battle_view() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "BattleView"
	box.add_theme_constant_override("separation", 8)

	_enemy_box = _make_mon_box()
	box.add_child(_enemy_box["root"] as Control)

	_log_label = Label.new()
	_log_label.custom_minimum_size = Vector2(0, 120)
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.add_theme_font_size_override("font_size", UIMetrics.FONT_SUB + 2)
	_log_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(_log_label)

	_player_box = _make_mon_box()
	box.add_child(_player_box["root"] as Control)

	_moves_grid = GridContainer.new()
	_moves_grid.columns = 2
	_moves_grid.add_theme_constant_override("h_separation", 8)
	_moves_grid.add_theme_constant_override("v_separation", 8)
	box.add_child(_moves_grid)

	_switch_box = VBoxContainer.new()
	_switch_box.add_theme_constant_override("separation", 6)
	box.add_child(_switch_box)

	_action_row = HBoxContainer.new()
	_action_row.add_theme_constant_override("separation", 8)
	var switch_btn := Button.new()
	switch_btn.text = "🔄 Wechseln"
	switch_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIMetrics.tap(switch_btn)
	switch_btn.pressed.connect(_on_switch_menu_pressed)
	_action_row.add_child(switch_btn)
	var forfeit_btn := Button.new()
	forfeit_btn.text = "🏳 Aufgeben"
	forfeit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIMetrics.tap(forfeit_btn)
	forfeit_btn.pressed.connect(func() -> void: forfeit_pressed.emit())
	_action_row.add_child(forfeit_btn)
	box.add_child(_action_row)
	return box

## Eine Kämpfer-Zeile: Kopf-Icon + Name/Typ + LP-Balken + Zusatzzeile. Rückgabe: Dictionary mit den
## Controls (root, icon_holder, name, type, bar, hp, extra, key).
func _make_mon_box() -> Dictionary:
	var holder := PanelContainer.new()
	holder.add_theme_stylebox_override("panel", UIMetrics.row_style())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	holder.add_child(h)
	var icon_holder := Control.new()
	icon_holder.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	h.add_child(icon_holder)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW)
	v.add_child(name_label)
	var type_label := Label.new()
	type_label.add_theme_font_size_override("font_size", UIMetrics.FONT_SUB)
	v.add_child(type_label)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 18)
	v.add_child(bar)
	var hp_label := Label.new()
	hp_label.add_theme_font_size_override("font_size", UIMetrics.FONT_SUB)
	v.add_child(hp_label)
	var extra := Label.new()
	extra.add_theme_font_size_override("font_size", UIMetrics.FONT_SUB)
	extra.modulate = Color(1, 1, 1, 0.55)
	v.add_child(extra)
	return {
		"root": holder, "icon_holder": icon_holder, "name": name_label, "type": type_label,
		"bar": bar, "hp": hp_label, "extra": extra, "key": "",
	}

func _build_result_view() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "ResultView"
	box.add_theme_constant_override("separation", 12)
	_result_title = Label.new()
	_result_title.add_theme_font_size_override("font_size", UIMetrics.FONT_TITLE + 6)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_title)
	_result_text = Label.new()
	_result_text.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW)
	_result_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_text)
	var close_btn := Button.new()
	close_btn.text = "Schließen"
	UIMetrics.tap(close_btn)
	close_btn.pressed.connect(func() -> void: close_requested.emit())
	box.add_child(close_btn)
	return box

# ─────────────────────────────────────────────
# Aktualisieren
# ─────────────────────────────────────────────

## Entfernt alle Kinder SOFORT aus dem Baum (und gibt sie frei) — nur queue_free() ließe die alten Knöpfe
## bis zum Frame-Ende neben den neuen stehen (kurzes Flackern, doppelte Knöpfe beim Zählen/Klicken).
static func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _show_view(view: Control) -> void:
	_team_view.visible = view == _team_view
	_battle_view.visible = view == _battle_view
	_result_view.visible = view == _result_view

func _update_box(box: Dictionary, mon: PetBattleMon, extra_text: String) -> void:
	if String(box["key"]) != mon.key:
		box["key"] = mon.key
		var holder: Control = box["icon_holder"] as Control
		_clear_children(holder)
		holder.add_child(PetHeadIcon.create(mon.appearance, ICON_PX))
	(box["name"] as Label).text = "%s  Lv.%d" % [mon.display_name, mon.level]
	var type_label: Label = box["type"] as Label
	type_label.text = PetBattleTypes.label_for(mon.type_id) + ("  ☠ vergiftet" if mon.poisoned else "")
	type_label.modulate = PetBattleTypes.color_for(mon.type_id)
	var bar: ProgressBar = box["bar"] as ProgressBar
	bar.max_value = float(mon.max_hp)
	bar.value = float(mon.hp)
	var fill := StyleBoxFlat.new()
	fill.bg_color = _hp_color(mon.hp_fraction())
	fill.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("fill", fill)
	(box["hp"] as Label).text = "LP %d / %d" % [mon.hp, mon.max_hp]
	(box["extra"] as Label).text = extra_text

static func _hp_color(fraction: float) -> Color:
	if fraction > 0.5:
		return COLOR_HP_HIGH
	if fraction > 0.2:
		return COLOR_HP_MID
	return COLOR_HP_LOW

func _populate_moves(engine: PetBattleEngine) -> void:
	_clear_children(_moves_grid)
	var me: PetBattleMon = engine.active_player()
	var enemy: PetBattleMon = engine.active_enemy()
	for i in range(me.moves.size()):
		var move: Dictionary = PetBattleMoves.get_move(me.moves[i])
		var btn := Button.new()
		btn.text = _move_text(move, enemy)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 84)
		btn.add_theme_font_size_override("font_size", UIMetrics.FONT_SUB + 2)
		var move_index: int = i
		btn.pressed.connect(func() -> void: move_pressed.emit(move_index))
		_moves_grid.add_child(btn)

## "Biss\nRaubtier · Stärke 55 · ×2" — der Hinweis ×2/×½ zeigt die Wirkung gegen das aktive Gegner-Pet.
static func _move_text(move: Dictionary, enemy: PetBattleMon) -> String:
	var type_id: int = int(move.get("type", PetBattleTypes.Type.NORMAL))
	var detail: String = PetBattleTypes.label_for(type_id)
	if PetBattleMoves.is_attack(move):
		detail += " · Stärke %d" % int(move.get("power", 0))
		var eff: float = PetBattleTypes.effectiveness(type_id, enemy.type_id)
		if eff > 1.0:
			detail += " · ×2"
		elif eff < 1.0:
			detail += " · ×½"
	else:
		detail += " · Hilfe"
	return "%s\n%s" % [String(move.get("name", "?")), detail]

func _populate_switch(engine: PetBattleEngine, forced: bool) -> void:
	_clear_children(_switch_box)
	var header := Label.new()
	header.text = "Wähle dein nächstes Pet" if forced else "Pet wechseln (kostet die Runde)"
	header.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW)
	_switch_box.add_child(header)
	for i in engine.alive_player_indices():
		if i == engine.player_active:
			continue
		var mon: PetBattleMon = engine.player_team[i]
		var btn := Button.new()
		btn.text = "%s  Lv.%d · %s · LP %d/%d" % [mon.display_name, mon.level, PetBattleTypes.label_for(mon.type_id), mon.hp, mon.max_hp]
		UIMetrics.tap(btn)
		var team_index: int = i
		btn.pressed.connect(func() -> void:
			_switch_open = false
			switch_chosen.emit(team_index))
		_switch_box.add_child(btn)
	if not forced:
		var back := Button.new()
		back.text = "↩ Zurück"
		UIMetrics.tap(back)
		back.pressed.connect(func() -> void:
			_switch_open = false
			_switch_box.visible = false
			_moves_grid.visible = true
			_action_row.visible = true)
		_switch_box.add_child(back)

func _on_switch_menu_pressed() -> void:
	if _engine_ref == null:
		return
	_switch_open = true
	_populate_switch(_engine_ref, false)
	_moves_grid.visible = false
	_action_row.visible = false
	_switch_box.visible = true

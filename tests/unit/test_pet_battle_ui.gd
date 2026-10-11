# res://tests/unit/test_pet_battle_ui.gd
extends GutTest

## Kampf-Fenster (PetBattleVisuals) und Dorfbewohner-Herausforderung (VillagerNPC).

func _mon(p_name: String, type_id: int, level: int, hp: int, key: String) -> PetBattleMon:
	return PetBattleMon.create(p_name, type_id, level, {"max_hp": hp, "atk": 20, "def": 20, "spd": 20}, key)

func _visuals() -> PetBattleVisuals:
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	return PetBattleVisuals.new(layer)

func _engine() -> PetBattleEngine:
	var me: Array[PetBattleMon] = [_mon("Wolf", PetBattleTypes.Type.PREDATOR, 6, 60, "a"), _mon("Fuchs", PetBattleTypes.Type.PREDATOR, 6, 60, "b")]
	var enemy: Array[PetBattleMon] = [_mon("Hirsch", PetBattleTypes.Type.HOOFED, 6, 60, "e1")]
	return PetBattleEngine.new(me, enemy, 5)

func _count_buttons(root: Node) -> int:
	var n := 0
	for child in root.get_children():
		if child is Button:
			n += 1
	return n

func test_panel_starts_hidden() -> void:
	assert_false(_visuals().panel.visible)

func test_team_select_lists_every_pet_and_sets_count() -> void:
	var v := _visuals()
	var rows: Array[Dictionary] = []
	for i in range(4):
		rows.append({"id": 100 + i, "name": "Pet %d" % i, "level": 3, "type_id": PetBattleTypes.Type.PREDATOR, "appearance": {}, "selected": i < 2})
	v.open_team_select("Test", rows, 10)
	assert_true(v.panel.visible)
	assert_eq(v._team_rows.get_child_count(), 4)
	assert_eq(v._team_count.text, "Kampfteam: 2 / 10")
	assert_false(v._start_button.disabled)

func test_start_is_disabled_without_team() -> void:
	var v := _visuals()
	var rows: Array[Dictionary] = [{"id": 1, "name": "A", "level": 1, "type_id": 0, "appearance": {}, "selected": false}]
	v.open_team_select("Test", rows, 10)
	assert_true(v._start_button.disabled)

func test_toggling_a_team_row_emits_signal() -> void:
	var v := _visuals()
	var rows: Array[Dictionary] = [{"id": 7, "name": "A", "level": 1, "type_id": 0, "appearance": {}, "selected": false}]
	v.open_team_select("Test", rows, 10)
	watch_signals(v)
	(v._team_checks[7] as CheckButton).button_pressed = true
	assert_signal_emitted_with_parameters(v, "team_toggled", [7, true])

func test_set_team_check_does_not_emit() -> void:
	var v := _visuals()
	var rows: Array[Dictionary] = [{"id": 7, "name": "A", "level": 1, "type_id": 0, "appearance": {}, "selected": true}]
	v.open_team_select("Test", rows, 10)
	watch_signals(v)
	v.set_team_check(7, false)
	assert_signal_not_emitted(v, "team_toggled")
	assert_false((v._team_checks[7] as CheckButton).button_pressed)

func test_battle_view_shows_one_button_per_move_with_type_hint() -> void:
	var v := _visuals()
	var eng := _engine()
	v.show_battle(eng, "Bauer Emil")
	assert_true(v._battle_view.visible)
	assert_false(v._team_view.visible)
	assert_eq(v._moves_grid.get_child_count(), eng.active_player().moves.size())
	# Wolf (Raubtier) gegen Hirsch (Huftier): Biss ist ×2.
	var texts: Array[String] = []
	for b in v._moves_grid.get_children():
		texts.append((b as Button).text)
	var has_hint := false
	for t in texts:
		if t.begins_with("Biss") and t.contains("×2"):
			has_hint = true
	assert_true(has_hint, "Biss zeigt ×2 gegen ein Huftier: %s" % str(texts))

func test_pressing_a_move_emits_its_index() -> void:
	var v := _visuals()
	v.show_battle(_engine(), "X")
	watch_signals(v)
	(v._moves_grid.get_child(1) as Button).pressed.emit()
	assert_signal_emitted_with_parameters(v, "move_pressed", [1])

func test_hp_bars_follow_the_engine() -> void:
	var v := _visuals()
	var eng := _engine()
	v.show_battle(eng, "X")
	var bar: ProgressBar = v._player_box["bar"]
	assert_eq(bar.max_value, float(eng.active_player().max_hp))
	eng.active_player().take_damage(20)
	v.refresh_battle(eng, [] as Array[String])
	assert_eq(bar.value, float(eng.active_player().hp))

func test_log_keeps_only_the_last_lines() -> void:
	var v := _visuals()
	var eng := _engine()
	v.show_battle(eng, "X")
	var lines: Array[String] = []
	for i in range(20):
		lines.append("Zeile %d" % i)
	v.refresh_battle(eng, lines)
	var shown := v._log_label.text.split("\n")
	assert_eq(shown.size(), PetBattleVisuals.LOG_LINES)
	assert_eq(shown[shown.size() - 1], "Zeile 19")

func test_switch_list_replaces_moves_after_faint() -> void:
	var v := _visuals()
	var eng := _engine()
	v.show_battle(eng, "X")
	eng.active_player().hp = 0
	eng.awaiting_switch = true
	v.refresh_battle(eng, [] as Array[String])
	assert_false(v._moves_grid.visible)
	assert_true(v._switch_box.visible)
	assert_eq(_count_buttons(v._switch_box), 1, "ein Wechsel-Knopf für den Fuchs, kein Zurück bei Zwang")

func test_switch_menu_has_back_button_when_voluntary() -> void:
	var v := _visuals()
	v.show_battle(_engine(), "X")
	v._on_switch_menu_pressed()
	assert_true(v._switch_box.visible)
	assert_eq(_count_buttons(v._switch_box), 2, "Fuchs + Zurück")

func test_result_view_shows_title_and_lines() -> void:
	var v := _visuals()
	var lines: Array[String] = ["+30 Gold", "Neues Pet: Zahmes Wolf"]
	v.show_result("🏆 Sieg!", lines)
	assert_true(v._result_view.visible)
	assert_eq(v._result_title.text, "🏆 Sieg!")
	assert_true(v._result_text.text.contains("+30 Gold"))

func test_hp_color_changes_with_fraction() -> void:
	assert_eq(PetBattleVisuals._hp_color(0.9), PetBattleVisuals.COLOR_HP_HIGH)
	assert_eq(PetBattleVisuals._hp_color(0.4), PetBattleVisuals.COLOR_HP_MID)
	assert_eq(PetBattleVisuals._hp_color(0.1), PetBattleVisuals.COLOR_HP_LOW)

# ── Dorfbewohner ────────────────────────────────

func test_villager_has_pet_battle_action() -> void:
	var npc := VillagerNPC.new()
	add_child_autofree(npc)
	var comp := npc.find_child("PetBattleInteractable", true, false) as InteractableComponent
	assert_not_null(comp)
	assert_eq(comp.data.id, VillagerNPC.ACTION_PET_BATTLE)

func test_roles_prefer_matching_types() -> void:
	assert_eq(autofree(VillagerNPC.new())._battle_bias_type(), -1)
	assert_eq(autofree(FarmerNPC.new())._battle_bias_type(), PetBattleTypes.Type.HOOFED)
	assert_eq(autofree(WaterCarrierNPC.new())._battle_bias_type(), PetBattleTypes.Type.AQUA)

func test_defeated_villager_advances_round_and_rests() -> void:
	var npc := VillagerNPC.new()
	add_child_autofree(npc)
	var key := String(npc.name)
	npc._on_pet_battle_finished("anderer", true)
	assert_eq(npc._battle_round, 0, "fremder Schlüssel ignoriert")
	npc._on_pet_battle_finished(key, false)
	assert_eq(npc._battle_round, 0, "Niederlage des Spielers ändert nichts")
	npc._on_pet_battle_finished(key, true)
	assert_eq(npc._battle_round, 1)
	assert_gt(npc._battle_rest_until_msec, Time.get_ticks_msec())

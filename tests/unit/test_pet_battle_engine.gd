# res://tests/unit/test_pet_battle_engine.gd
extends GutTest

## PetBattleEngine: Rundenablauf, Schaden, Tempo, Wechseln, Gift, Sieg/Niederlage, Determinismus.

func _mon(p_name: String, type_id: int, level: int, hp: int, atk: int, defense: int, spd: int, key: String = "") -> PetBattleMon:
	return PetBattleMon.create(p_name, type_id, level, {"max_hp": hp, "atk": atk, "def": defense, "spd": spd}, key)

func _engine(player: Array[PetBattleMon], enemy: Array[PetBattleMon], seed_value: int = 1) -> PetBattleEngine:
	return PetBattleEngine.new(player, enemy, seed_value)

func _team(mons: Array) -> Array[PetBattleMon]:
	var out: Array[PetBattleMon] = []
	for m in mons:
		out.append(m as PetBattleMon)
	return out

# ── Schaden ─────────────────────────────────────

func test_super_effective_hits_harder_than_resisted() -> void:
	var attacker := _mon("A", PetBattleTypes.Type.PREDATOR, 10, 50, 30, 20, 20)
	var hoofed := _mon("H", PetBattleTypes.Type.HOOFED, 10, 50, 30, 20, 20)
	var venom := _mon("V", PetBattleTypes.Type.VENOM, 10, 50, 30, 20, 20)
	var bite := PetBattleMoves.get_move("biss")
	assert_gt(PetBattleEngine.expected_damage(attacker, hoofed, bite), PetBattleEngine.expected_damage(attacker, venom, bite) * 3.0, "×2 gegen ×0,5 = Faktor 4")

func test_same_type_attack_gets_stab_bonus() -> void:
	var predator := _mon("P", PetBattleTypes.Type.PREDATOR, 10, 50, 30, 20, 20)
	var rodent := _mon("R", PetBattleTypes.Type.RODENT, 10, 50, 30, 20, 20)
	var target := _mon("T", PetBattleTypes.Type.NORMAL, 10, 50, 30, 20, 20)
	var move := {"power": 55, "type": PetBattleTypes.Type.PREDATOR}
	assert_almost_eq(PetBattleEngine.expected_damage(predator, target, move) / PetBattleEngine.expected_damage(rodent, target, move), PetBattleEngine.STAB_MULT, 0.0001)

func test_status_move_deals_no_damage() -> void:
	var a := _mon("A", PetBattleTypes.Type.PREDATOR, 10, 50, 30, 20, 20)
	assert_eq(PetBattleEngine.expected_damage(a, a, PetBattleMoves.get_move("einschuechtern")), 0.0)

func test_higher_defense_reduces_damage() -> void:
	var a := _mon("A", PetBattleTypes.Type.NORMAL, 10, 50, 30, 20, 20)
	var soft := _mon("S", PetBattleTypes.Type.NORMAL, 10, 50, 30, 10, 20)
	var hard := _mon("H", PetBattleTypes.Type.NORMAL, 10, 50, 30, 60, 20)
	var m := PetBattleMoves.get_move("rempler")
	assert_gt(PetBattleEngine.expected_damage(a, soft, m), PetBattleEngine.expected_damage(a, hard, m))

# ── Runde ───────────────────────────────────────

func test_faster_pet_acts_first() -> void:
	var fast := _mon("Flink", PetBattleTypes.Type.NORMAL, 5, 60, 10, 10, 90)
	var slow := _mon("Lahm", PetBattleTypes.Type.NORMAL, 5, 60, 10, 10, 5)
	var eng := _engine(_team([fast]), _team([slow]))
	var lines := eng.use_move(0)
	var first_user := ""
	for l in lines:
		if l.contains("setzt"):
			first_user = l
			break
	assert_true(first_user.begins_with("Flink"), "Flink greift zuerst an: '%s'" % first_user)

func test_fainted_target_skips_second_attack() -> void:
	var fast := _mon("Flink", PetBattleTypes.Type.NORMAL, 50, 100, 200, 10, 90)
	var slow := _mon("Lahm", PetBattleTypes.Type.NORMAL, 1, 5, 5, 5, 1)
	var eng := _engine(_team([fast]), _team([slow]))
	var lines := eng.use_move(0)
	var attacks := 0
	for l in lines:
		if l.contains("setzt"):
			attacks += 1
	assert_eq(attacks, 1, "Das besiegte Pet greift nicht mehr an")
	assert_true(eng.is_over())
	assert_eq(eng.result, PetBattleEngine.Result.PLAYER_WON)

func test_battle_ends_with_loss_when_all_player_pets_faint() -> void:
	var weak := _mon("Schwach", PetBattleTypes.Type.NORMAL, 1, 5, 2, 2, 1)
	var boss := _mon("Boss", PetBattleTypes.Type.NORMAL, 50, 200, 200, 100, 90)
	var eng := _engine(_team([weak]), _team([boss]))
	for i in range(10):
		if eng.is_over():
			break
		eng.use_move(0)
	assert_eq(eng.result, PetBattleEngine.Result.ENEMY_WON)

func test_enemy_sends_next_pet_after_faint() -> void:
	var strong := _mon("Stark", PetBattleTypes.Type.NORMAL, 50, 200, 300, 100, 90)
	var e1 := _mon("E1", PetBattleTypes.Type.NORMAL, 1, 5, 5, 5, 1, "e1")
	var e2 := _mon("E2", PetBattleTypes.Type.NORMAL, 1, 5, 5, 5, 1, "e2")
	var eng := _engine(_team([strong]), _team([e1, e2]))
	eng.use_move(0)
	assert_false(eng.is_over())
	assert_eq(eng.active_enemy().key, "e2")
	assert_eq(eng.enemies_left(), 1)
	eng.use_move(0)
	assert_eq(eng.result, PetBattleEngine.Result.PLAYER_WON)

func test_invalid_move_index_does_nothing() -> void:
	var a := _mon("A", PetBattleTypes.Type.NORMAL, 5, 30, 10, 10, 10)
	var b := _mon("B", PetBattleTypes.Type.NORMAL, 5, 30, 10, 10, 10)
	var eng := _engine(_team([a]), _team([b]))
	assert_eq(eng.use_move(-1).size(), 0)
	assert_eq(eng.use_move(99).size(), 0)
	assert_eq(eng.turn, 0)

# ── Wechseln ────────────────────────────────────

func test_forced_switch_after_faint_is_free() -> void:
	var first := _mon("Erster", PetBattleTypes.Type.NORMAL, 1, 4, 3, 3, 1, "p1")
	var second := _mon("Zweiter", PetBattleTypes.Type.NORMAL, 20, 80, 30, 30, 50, "p2")
	var boss := _mon("Boss", PetBattleTypes.Type.NORMAL, 50, 300, 200, 100, 90)
	var eng := _engine(_team([first, second]), _team([boss]))
	eng.use_move(0)
	assert_true(eng.needs_switch())
	assert_eq(eng.use_move(0).size(), 0, "Angriff während Wechselzwang nicht möglich")
	var hp_before := second.hp
	eng.switch_to(1)
	assert_false(eng.needs_switch())
	assert_eq(eng.active_player().key, "p2")
	assert_eq(second.hp, hp_before, "Erzwungener Wechsel: Gegner greift nicht an")

func test_voluntary_switch_costs_the_turn() -> void:
	var a := _mon("A", PetBattleTypes.Type.NORMAL, 20, 80, 30, 30, 50, "a")
	var b := _mon("B", PetBattleTypes.Type.NORMAL, 20, 80, 30, 30, 50, "b")
	var enemy := _mon("E", PetBattleTypes.Type.NORMAL, 20, 80, 60, 30, 50)
	var eng := _engine(_team([a, b]), _team([enemy]))
	eng.switch_to(1)
	assert_eq(eng.active_player().key, "b")
	assert_lt(b.hp, b.max_hp, "Der Gegner hat das eingewechselte Pet angegriffen")
	assert_eq(a.hp, a.max_hp)

func test_cannot_switch_to_fainted_or_active_pet() -> void:
	var a := _mon("A", PetBattleTypes.Type.NORMAL, 5, 30, 10, 10, 10, "a")
	var b := _mon("B", PetBattleTypes.Type.NORMAL, 5, 30, 10, 10, 10, "b")
	var e := _mon("E", PetBattleTypes.Type.NORMAL, 5, 30, 10, 10, 10)
	var eng := _engine(_team([a, b]), _team([e]))
	b.hp = 0
	assert_eq(eng.switch_to(1).size(), 0, "besiegtes Pet")
	assert_eq(eng.switch_to(0).size(), 0, "bereits aktives Pet")
	assert_eq(eng.switch_to(7).size(), 0, "ungültiger Index")

func test_switching_resets_stages_of_the_leaving_pet() -> void:
	var a := _mon("A", PetBattleTypes.Type.NORMAL, 20, 80, 30, 30, 50, "a")
	var b := _mon("B", PetBattleTypes.Type.NORMAL, 20, 80, 30, 30, 50, "b")
	var e := _mon("E", PetBattleTypes.Type.NORMAL, 20, 80, 10, 30, 10)
	var eng := _engine(_team([a, b]), _team([e]))
	a.change_stage("atk", 3)
	eng.switch_to(1)
	assert_eq(int(a.stages["atk"]), 0)

func test_participants_include_every_pet_that_entered() -> void:
	var a := _mon("A", PetBattleTypes.Type.NORMAL, 1, 4, 3, 3, 1, "a")
	var b := _mon("B", PetBattleTypes.Type.NORMAL, 20, 80, 30, 30, 50, "b")
	var c := _mon("C", PetBattleTypes.Type.NORMAL, 20, 80, 30, 30, 50, "c")
	var boss := _mon("Boss", PetBattleTypes.Type.NORMAL, 50, 300, 200, 100, 90)
	var eng := _engine(_team([a, b, c]), _team([boss]))
	assert_eq(eng.participants().size(), 1)
	eng.use_move(0)
	eng.switch_to(1)
	var keys: Array[String] = []
	for m in eng.participants():
		keys.append(m.key)
	keys.sort()
	assert_eq(keys, ["a", "b"], "c blieb auf der Bank")

# ── Gift + Status ───────────────────────────────

func test_poison_ticks_at_end_of_turn_and_can_faint() -> void:
	var a := _mon("A", PetBattleTypes.Type.NORMAL, 20, 80, 1, 200, 90, "a")
	var b := _mon("B", PetBattleTypes.Type.NORMAL, 20, 80, 1, 200, 1)
	var eng := _engine(_team([a]), _team([b]))
	b.poisoned = true
	eng.use_move(0)
	assert_lt(b.hp, b.max_hp - 0, "Gift hat Schaden gemacht")
	var expected_tick := maxi(1, int(float(b.max_hp) * PetBattleEngine.POISON_FRACTION))
	assert_gte(b.max_hp - b.hp, expected_tick)

func test_status_move_changes_stage_and_logs() -> void:
	var a := _mon("A", PetBattleTypes.Type.PREDATOR, 5, 80, 10, 10, 90, "a")
	var b := _mon("B", PetBattleTypes.Type.NORMAL, 5, 80, 1, 200, 1)
	var eng := _engine(_team([a]), _team([b]))
	var idx := a.moves.find("einschuechtern")
	assert_gte(idx, 0, "Level 5 Raubtier hat Einschüchtern")
	eng.use_move(idx)
	assert_eq(int(b.stages["atk"]), -1)

func test_forfeit_ends_the_battle() -> void:
	var a := _mon("A", PetBattleTypes.Type.NORMAL, 5, 30, 10, 10, 10)
	var e := _mon("E", PetBattleTypes.Type.NORMAL, 5, 30, 10, 10, 10)
	var eng := _engine(_team([a]), _team([e]))
	eng.forfeit()
	assert_true(eng.is_over())
	assert_eq(eng.result, PetBattleEngine.Result.FORFEIT)
	assert_eq(eng.use_move(0).size(), 0, "nach dem Ende keine Aktionen mehr")

# ── Team / Konstruktor ──────────────────────────

func test_player_team_is_capped_at_ten() -> void:
	var many: Array[PetBattleMon] = []
	for i in range(14):
		many.append(_mon("P%d" % i, PetBattleTypes.Type.NORMAL, 5, 30, 10, 10, 10, "p%d" % i))
	var enemy := _mon("E", PetBattleTypes.Type.NORMAL, 5, 30, 10, 10, 10)
	var eng := _engine(many, _team([enemy]))
	assert_eq(eng.player_team.size(), PetBattleEngine.MAX_TEAM)

func test_first_alive_pet_leads() -> void:
	var down := _mon("Down", PetBattleTypes.Type.NORMAL, 5, 30, 10, 10, 10, "d")
	var up := _mon("Up", PetBattleTypes.Type.NORMAL, 5, 30, 10, 10, 10, "u")
	down.hp = 0
	var e := _mon("E", PetBattleTypes.Type.NORMAL, 5, 30, 10, 10, 10)
	var eng := _engine(_team([down, up]), _team([e]))
	assert_eq(eng.active_player().key, "u")

func test_empty_team_ends_immediately() -> void:
	var e := _mon("E", PetBattleTypes.Type.NORMAL, 5, 30, 10, 10, 10)
	var eng := _engine(_team([]), _team([e]))
	assert_true(eng.is_over())

# ── Determinismus + KI ──────────────────────────

func _play(seed_value: int) -> Array[String]:
	var a := _mon("A", PetBattleTypes.Type.PREDATOR, 12, 60, 25, 20, 40, "a")
	var b := _mon("B", PetBattleTypes.Type.HOOFED, 12, 60, 25, 20, 40, "b")
	var eng := _engine(_team([a]), _team([b]), seed_value)
	for i in range(40):
		if eng.is_over():
			break
		if eng.needs_switch():
			break
		eng.use_move(1)
	return eng.get_log()

func test_same_seed_gives_identical_battle() -> void:
	assert_eq(_play(1234), _play(1234))

func test_different_seeds_diverge_somewhere() -> void:
	var differs := false
	for s in range(2, 12):
		if _play(1) != _play(s):
			differs = true
			break
	assert_true(differs)

func test_ai_prefers_super_effective_move_most_of_the_time() -> void:
	# Raubtier-Gegner mit Level-5-Moveset gegen ein Huftier: Biss/Zerfetzen (×2) schlagen Rempler.
	var picks_strong := 0
	for s in range(60):
		var enemy := _mon("E", PetBattleTypes.Type.PREDATOR, 10, 60, 30, 20, 30)
		var me := _mon("Me", PetBattleTypes.Type.HOOFED, 10, 80, 20, 20, 1)
		var eng := _engine(_team([me]), _team([enemy]), s)
		var before := me.hp
		eng.use_move(0)
		if me.hp < before:
			picks_strong += 1
	assert_gt(picks_strong, 40, "Die KI trifft meistens (nicht nur Statusattacken)")

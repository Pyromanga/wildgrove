# res://tests/unit/test_pet_battle_basics.gd
extends GutTest

## Typen-Ring, Attacken-Freischaltung und Kampfwerte der Pet-Kämpfe (reine Logik, ohne Nodes).

# ── Typen ───────────────────────────────────────

func test_every_type_has_two_strengths_and_two_weaknesses() -> void:
	for a in PetBattleTypes.RING:
		var strong := 0
		var weak := 0
		for d in PetBattleTypes.RING:
			var eff := PetBattleTypes.effectiveness(a, d)
			if eff > 1.0:
				strong += 1
			elif eff < 1.0:
				weak += 1
		assert_eq(strong, 2, "%s: zwei Stärken" % PetBattleTypes.label_for(a))
		assert_eq(weak, 2, "%s: zwei Schwächen" % PetBattleTypes.label_for(a))

func test_effectiveness_is_antisymmetric() -> void:
	# Ist A gegen B stark, dann ist B gegen A schwach (und umgekehrt).
	for a in PetBattleTypes.RING:
		for d in PetBattleTypes.RING:
			var ad := PetBattleTypes.effectiveness(a, d)
			var da := PetBattleTypes.effectiveness(d, a)
			if ad > 1.0:
				assert_lt(da, 1.0)
			if ad < 1.0:
				assert_gt(da, 1.0)

func test_same_type_and_normal_are_neutral() -> void:
	for t in PetBattleTypes.RING:
		assert_eq(PetBattleTypes.effectiveness(t, t), 1.0)
		assert_eq(PetBattleTypes.effectiveness(PetBattleTypes.Type.NORMAL, t), 1.0)
		assert_eq(PetBattleTypes.effectiveness(t, PetBattleTypes.Type.NORMAL), 1.0)

func test_known_matchups() -> void:
	assert_eq(PetBattleTypes.effectiveness(PetBattleTypes.Type.PREDATOR, PetBattleTypes.Type.HOOFED), 2.0)
	assert_eq(PetBattleTypes.effectiveness(PetBattleTypes.Type.AQUA, PetBattleTypes.Type.PREDATOR), 2.0)
	assert_eq(PetBattleTypes.effectiveness(PetBattleTypes.Type.VENOM, PetBattleTypes.Type.PREDATOR), 2.0)
	assert_eq(PetBattleTypes.effectiveness(PetBattleTypes.Type.HOOFED, PetBattleTypes.Type.PREDATOR), 0.5)

func test_type_follows_body_plan_for_non_quadrupeds() -> void:
	assert_eq(PetBattleTypes.type_for("beetle", AnimalVisualProfile.BodyPlan.INSECT), PetBattleTypes.Type.INSECT)
	assert_eq(PetBattleTypes.type_for("viper", AnimalVisualProfile.BodyPlan.SNAKE), PetBattleTypes.Type.VENOM)
	assert_eq(PetBattleTypes.type_for("tarantula", AnimalVisualProfile.BodyPlan.SPIDER), PetBattleTypes.Type.VENOM)
	assert_eq(PetBattleTypes.type_for("trout", AnimalVisualProfile.BodyPlan.FISH), PetBattleTypes.Type.AQUA)

func test_quadruped_species_table_and_fallback() -> void:
	var quad := AnimalVisualProfile.BodyPlan.QUADRUPED
	assert_eq(PetBattleTypes.type_for("wolf", quad), PetBattleTypes.Type.PREDATOR)
	assert_eq(PetBattleTypes.type_for("Wolf", quad), PetBattleTypes.Type.PREDATOR, "Groß-/Kleinschreibung egal (Klassennamen)")
	assert_eq(PetBattleTypes.type_for("mouse", quad), PetBattleTypes.Type.RODENT)
	assert_eq(PetBattleTypes.type_for("moose", quad), PetBattleTypes.Type.HOOFED)
	assert_eq(PetBattleTypes.type_for("otter", quad), PetBattleTypes.Type.AQUA)
	assert_eq(PetBattleTypes.type_for("unbekannt", quad), PetBattleTypes.Type.HOOFED, "künftige Arten → Huftier")
	assert_eq(PetBattleTypes.type_for("", quad), PetBattleTypes.Type.HOOFED, "Alt-Saves ohne species_id")

func test_all_quadruped_db_species_are_classified_deliberately() -> void:
	# Jede Vierbeiner-Art der Datenbank steht bewusst in der Typ-Tabelle (kein stiller Fallback).
	for id: String in AnimalSpeciesDB.SPECIES:
		var def: Dictionary = AnimalSpeciesDB.SPECIES[id]
		if int(def["body_plan"]) == AnimalVisualProfile.BodyPlan.QUADRUPED:
			assert_true(PetBattleTypes.SPECIES_TYPES.has(id), "%s fehlt in PetBattleTypes.SPECIES_TYPES" % id)

# ── Attacken ────────────────────────────────────

func test_moves_unlock_with_level() -> void:
	var t := PetBattleTypes.Type.PREDATOR
	assert_eq(PetBattleMoves.moves_for(t, 1).size(), 2)
	assert_eq(PetBattleMoves.moves_for(t, PetBattleMoves.LEVEL_UTILITY).size(), 3)
	assert_eq(PetBattleMoves.moves_for(t, PetBattleMoves.LEVEL_FINISHER).size(), 4)
	assert_eq(PetBattleMoves.moves_for(t, 1)[0], "rempler")

func test_every_type_moveset_references_existing_moves() -> void:
	for t in PetBattleTypes.RING:
		var moves := PetBattleMoves.moves_for(t, 100)
		assert_eq(moves.size(), 4, "%s hat vier Attacken" % PetBattleTypes.label_for(t))
		for id in moves:
			assert_false(PetBattleMoves.get_move(id).is_empty(), "Attacke '%s' fehlt in MOVES" % id)

func test_basic_move_matches_own_type_for_stab() -> void:
	for t in PetBattleTypes.RING:
		var basic := PetBattleMoves.get_move(PetBattleMoves.moves_for(t, 1)[1])
		assert_eq(int(basic["type"]), t)

func test_status_moves_have_stat_and_target() -> void:
	for id in PetBattleMoves.MOVES:
		var move: Dictionary = PetBattleMoves.MOVES[id]
		if not PetBattleMoves.is_attack(move):
			assert_true(move.has("stat") and move.has("target") and move.has("stages"), id)

# ── Kampfwerte ──────────────────────────────────

func test_bigger_animals_are_sturdier() -> void:
	var ant := PetBattleStats.size_score(Vector3(0.06, 0.05, 0.08))
	var wolf := PetBattleStats.size_score(Vector3(0.5, 0.6, 0.65))
	var bear := PetBattleStats.size_score(Vector3(0.95, 1.05, 0.95))
	assert_lt(ant, wolf)
	assert_lt(wolf, bear)
	assert_between(ant, 0.0, 1.0)
	assert_between(bear, 0.0, 1.0)

func test_stats_grow_with_level() -> void:
	var low := PetBattleStats.compute(Vector3(0.5, 0.6, 0.65), 5.0, PetBattleTypes.Type.PREDATOR, 1)
	var high := PetBattleStats.compute(Vector3(0.5, 0.6, 0.65), 5.0, PetBattleTypes.Type.PREDATOR, 50)
	for k in ["max_hp", "atk", "def", "spd"]:
		assert_gt(int(high[k]), int(low[k]), k)

func test_level_is_clamped() -> void:
	var a := PetBattleStats.compute(Vector3(0.5, 0.6, 0.65), 5.0, PetBattleTypes.Type.HOOFED, 100)
	var b := PetBattleStats.compute(Vector3(0.5, 0.6, 0.65), 5.0, PetBattleTypes.Type.HOOFED, 999)
	assert_eq(a, b)
	assert_gt(int(PetBattleStats.compute(Vector3.ONE, 3.0, PetBattleTypes.Type.HOOFED, -5)["max_hp"]), 0)

func test_type_bonus_shapes_the_stats() -> void:
	var size := Vector3(0.5, 0.5, 0.5)
	var predator := PetBattleStats.base_stats(size, 5.0, PetBattleTypes.Type.PREDATOR)
	var hoofed := PetBattleStats.base_stats(size, 5.0, PetBattleTypes.Type.HOOFED)
	assert_gt(float(predator["atk"]), float(hoofed["atk"]))
	assert_gt(float(hoofed["def"]), float(predator["def"]))
	assert_gt(float(hoofed["hp"]), float(predator["hp"]))

func test_faster_animals_have_more_speed() -> void:
	var slow := PetBattleStats.base_stats(Vector3(0.4, 0.4, 0.4), 2.0, PetBattleTypes.Type.PREDATOR)
	var fast := PetBattleStats.base_stats(Vector3(0.4, 0.4, 0.4), 8.0, PetBattleTypes.Type.PREDATOR)
	assert_gt(float(fast["spd"]), float(slow["spd"]))
	assert_lte(float(fast["spd"]), PetBattleStats.BASE_SPD_MAX)

func test_stage_multiplier_matches_pokemon_curve() -> void:
	assert_eq(PetBattleMon.stage_multiplier(0), 1.0)
	assert_eq(PetBattleMon.stage_multiplier(2), 2.0)
	assert_almost_eq(PetBattleMon.stage_multiplier(-2), 0.5, 0.0001)
	assert_eq(PetBattleMon.stage_multiplier(99), PetBattleMon.stage_multiplier(6), "geklemmt")

func test_change_stage_clamps_and_reports_actual_change() -> void:
	var m := PetBattleMon.create("X", PetBattleTypes.Type.NORMAL, 5, {"max_hp": 20, "atk": 10, "def": 10, "spd": 10})
	assert_eq(m.change_stage("atk", 2), 2)
	assert_eq(m.change_stage("atk", 10), 4, "nur bis +6")
	assert_eq(m.change_stage("atk", 1), 0, "Anschlag")
	assert_eq(m.effective("atk"), 10.0 * PetBattleMon.stage_multiplier(6))

func test_take_damage_never_goes_below_zero() -> void:
	var m := PetBattleMon.create("X", PetBattleTypes.Type.NORMAL, 1, {"max_hp": 10, "atk": 5, "def": 5, "spd": 5})
	assert_eq(m.take_damage(4), 4)
	assert_eq(m.take_damage(100), 6)
	assert_true(m.is_fainted())
	assert_eq(m.hp, 0)

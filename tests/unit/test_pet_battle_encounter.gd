# res://tests/unit/test_pet_battle_encounter.gd
extends GutTest

## Gegner-Teams, Belohnungen, Art-Profile und Kampfteam-Auswahl der Pet-Kämpfe.

func _pet(species: String, level_xp: int = 0, in_team: bool = false, peer: int = 1) -> PetComponent:
	var pet := PetComponent.new()
	add_child_autofree(pet)
	pet.on_spawn({
		"species_id": species, "name": "Zahmes " + species, "owner_peer_id": peer,
		"body_size": Vector3(0.5, 0.6, 0.65), "speed": 4.0, "xp": level_xp, "battle_team": in_team,
	})
	return pet

# ── Art-Profile ─────────────────────────────────

func test_every_species_has_a_profile_with_appearance_and_size() -> void:
	for id in PetBattleSpecies.all_ids():
		var p := PetBattleSpecies.profile(id)
		assert_false(p.is_empty(), "%s hat kein Profil" % id)
		if p.is_empty():
			continue
		assert_false(String(p["display_name"]).is_empty(), id)
		var size: Vector3 = p["body_size"]
		assert_gt(size.x * size.y * size.z, 0.0, "%s: Größe" % id)
		assert_true((p["appearance"] as Dictionary).has("color"), "%s: Farbe" % id)

func test_all_ids_cover_curated_and_database_without_duplicates() -> void:
	var ids := PetBattleSpecies.all_ids()
	assert_eq(ids.size(), PetBattleSpecies.CURATED_IDS.size() + AnimalSpeciesDB.SPECIES.size())
	var seen := {}
	for id in ids:
		assert_false(seen.has(id), id)
		seen[id] = true

func test_unknown_species_has_empty_profile() -> void:
	assert_true(PetBattleSpecies.profile("einhorn").is_empty())
	assert_false(PetBattleSpecies.exists("einhorn"))
	assert_true(PetBattleSpecies.exists("Deer"), "Klassennamen-Schreibweise")

func test_curated_species_use_german_names_and_class_name_for_catching() -> void:
	var deer := PetBattleSpecies.profile("deer")
	assert_eq(deer["display_name"], "Reh")
	assert_eq(deer["catch_name"], "Deer", "wie AnimalCatcher: Klassenname → PetAbilities.default_for_species()")
	assert_eq(PetBattleSpecies.profile("wolf")["catch_name"], "wolf")

# ── Gegner-Teams ────────────────────────────────

func test_enemy_team_is_deterministic_per_seed() -> void:
	assert_eq(PetBattleEncounter.generate_enemy_team(42, 5), PetBattleEncounter.generate_enemy_team(42, 5))

func test_enemy_team_varies_between_seeds() -> void:
	var seen := {}
	for s in range(40):
		seen[str(PetBattleEncounter.generate_enemy_team(s, 5))] = true
	assert_gt(seen.size(), 10)

func test_enemy_team_size_and_levels_are_in_range() -> void:
	for s in range(60):
		var team := PetBattleEncounter.generate_enemy_team(s, 10)
		assert_between(team.size(), PetBattleEncounter.MIN_TEAM, PetBattleEncounter.MAX_TEAM)
		for e in team:
			assert_between(int(e["level"]), 10 + PetBattleEncounter.LEVEL_SPREAD_LOW, 10 + PetBattleEncounter.LEVEL_SPREAD_HIGH)
			assert_true(PetBattleSpecies.exists(String(e["species_id"])))

func test_low_average_level_never_drops_below_one() -> void:
	for s in range(40):
		for e in PetBattleEncounter.generate_enemy_team(s, 1):
			assert_gte(int(e["level"]), 1)
	for s in range(40):
		for e in PetBattleEncounter.generate_enemy_team(s, 100):
			assert_lte(int(e["level"]), PetLeveling.MAX_LEVEL)

func test_type_bias_makes_matching_species_more_likely() -> void:
	var biased := 0
	var unbiased := 0
	for s in range(120):
		for e in PetBattleEncounter.generate_enemy_team(s, 5, PetBattleTypes.Type.AQUA):
			if PetBattleEncounter._type_of(String(e["species_id"])) == PetBattleTypes.Type.AQUA:
				biased += 1
		for e in PetBattleEncounter.generate_enemy_team(s, 5, -1):
			if PetBattleEncounter._type_of(String(e["species_id"])) == PetBattleTypes.Type.AQUA:
				unbiased += 1
	assert_gt(biased, unbiased * 2, "Wasserträger bringen deutlich öfter Wassertiere mit")

func test_enemy_mons_are_built_with_level_and_appearance() -> void:
	var team: Array[Dictionary] = [{"species_id": "wolf", "level": 7}, {"species_id": "trout", "level": 3}]
	var mons := PetBattleEncounter.mons_for_enemy_team(team)
	assert_eq(mons.size(), 2)
	assert_eq(mons[0].level, 7)
	assert_eq(mons[0].type_id, PetBattleTypes.Type.PREDATOR)
	assert_eq(mons[1].type_id, PetBattleTypes.Type.AQUA)
	assert_true(mons[0].appearance.has("color"))
	assert_ne(mons[0].key, mons[1].key)

func test_unknown_species_in_team_is_skipped() -> void:
	var team: Array[Dictionary] = [{"species_id": "einhorn", "level": 3}, {"species_id": "wolf", "level": 3}]
	assert_eq(PetBattleEncounter.mons_for_enemy_team(team).size(), 1)

func test_seed_changes_per_round_and_villager() -> void:
	assert_eq(PetBattleEncounter.seed_for("a", 0), PetBattleEncounter.seed_for("a", 0))
	assert_ne(PetBattleEncounter.seed_for("a", 0), PetBattleEncounter.seed_for("a", 1))
	assert_ne(PetBattleEncounter.seed_for("a", 0), PetBattleEncounter.seed_for("b", 0))

# ── Belohnungen ─────────────────────────────────

func test_winner_xp_scales_with_enemy_levels_and_loser_gets_a_quarter() -> void:
	var levels: Array[int] = [4, 6]
	var win := PetBattleEncounter.xp_for_participant(levels, true)
	assert_eq(win, 10 * PetBattleEncounter.XP_PER_ENEMY_LEVEL)
	assert_eq(PetBattleEncounter.xp_for_participant(levels, false), int(float(win) / float(PetBattleEncounter.XP_LOSS_DIVISOR)))
	assert_gte(PetBattleEncounter.xp_for_participant([1] as Array[int], false), 1)

func test_gold_for_win() -> void:
	var levels: Array[int] = [5]
	assert_eq(PetBattleEncounter.gold_for_win(levels), 5 * PetBattleEncounter.GOLD_PER_ENEMY_LEVEL)

func test_reward_is_the_highest_level_enemy() -> void:
	var team: Array[Dictionary] = [{"species_id": "wolf", "level": 3}, {"species_id": "bear", "level": 9}, {"species_id": "trout", "level": 5}]
	assert_eq(PetBattleEncounter.pick_reward(team)["species_id"], "bear")
	var empty: Array[Dictionary] = []
	assert_true(PetBattleEncounter.pick_reward(empty).is_empty())

func test_reward_pet_config_has_everything_a_pet_needs() -> void:
	var cfg := PetBattleEncounter.reward_pet_config({"species_id": "wolf", "level": 6}, 3, "player-x")
	for key in ["name", "color", "body_size", "speed", "species_id", "owner_peer_id", "owner_player_id", "abilities", "xp",
			"ear_style", "tail_style", "snout_style", "headgear_style", "body_plan", "accent_style"]:
		assert_true(cfg.has(key), "Config-Feld '%s' fehlt" % key)
	assert_eq(cfg["owner_peer_id"], 3)
	assert_eq(cfg["owner_player_id"], "player-x")
	assert_eq(cfg["species_id"], "wolf")
	assert_eq(cfg["name"], "Zahmes Wolf")
	assert_eq(cfg["abilities"], PetAbilities.default_for_species("wolf"))
	assert_eq(int(cfg["xp"]), PetLeveling.xp_required_for_level(6))

func test_reward_pet_starts_at_the_enemys_level() -> void:
	var cfg := PetBattleEncounter.reward_pet_config({"species_id": "wolf", "level": 6}, 1, "")
	var pet := PetComponent.new()
	add_child_autofree(pet)
	pet.on_spawn(cfg)
	assert_eq(pet.get_level(), 6)
	assert_eq(pet.get_species_id(), "wolf")

func test_curated_reward_keeps_class_name_as_species() -> void:
	var cfg := PetBattleEncounter.reward_pet_config({"species_id": "deer", "level": 2}, 1, "")
	assert_eq(cfg["species_id"], "Deer")
	assert_eq(cfg["name"], "Zahmes Reh")

func test_reward_for_unknown_species_is_empty() -> void:
	assert_true(PetBattleEncounter.reward_pet_config({"species_id": "einhorn", "level": 2}, 1, "").is_empty())

# ── Kampfteam-Auswahl ───────────────────────────

func test_team_of_returns_only_flagged_pets_up_to_ten() -> void:
	var pets: Array = []
	for i in range(13):
		pets.append(_pet("wolf", 0, true))
	pets.append(_pet("fox", 0, false))
	assert_eq(PetBattleTeam.team_of(pets).size(), PetBattleEngine.MAX_TEAM)
	assert_false(PetBattleTeam.can_add(pets))

func test_can_add_while_below_limit() -> void:
	var pets: Array = [_pet("wolf", 0, true), _pet("fox", 0, false)]
	assert_true(PetBattleTeam.can_add(pets))
	assert_eq(PetBattleTeam.team_of(pets).size(), 1)

func test_set_battle_team_toggles_flag_for_own_pet() -> void:
	var pet := _pet("wolf")
	assert_false(pet.is_in_battle_team())
	pet.set_battle_team(true)
	assert_true(pet.is_in_battle_team())
	pet.set_battle_team(false)
	assert_false(pet.is_in_battle_team())

func test_battle_team_survives_save_and_restore() -> void:
	var pet := _pet("wolf", 0, true)
	var state := pet.get_save_state()
	assert_true(bool(state["battle_team"]))
	var restored := PetComponent.new()
	add_child_autofree(restored)
	restored.on_spawn(state)
	assert_true(restored.is_in_battle_team())

func test_old_save_without_battle_team_is_not_in_team() -> void:
	var pet := PetComponent.new()
	add_child_autofree(pet)
	pet.on_spawn({"species_id": "wolf", "owner_peer_id": 1})
	assert_false(pet.is_in_battle_team())

func test_mons_for_use_pet_level_type_and_source_id() -> void:
	var pet := _pet("wolf", PetLeveling.xp_required_for_level(8))
	var team: Array[PetComponent] = [pet]
	var mons := PetBattleTeam.mons_for(team)
	assert_eq(mons.size(), 1)
	assert_eq(mons[0].level, 8)
	assert_eq(mons[0].type_id, PetBattleTypes.Type.PREDATOR)
	assert_eq(mons[0].source_pet_id, pet.get_instance_id())
	assert_eq(PetBattleTeam.average_level(mons), 8)

func test_average_level_of_empty_team_is_one() -> void:
	var none: Array[PetBattleMon] = []
	assert_eq(PetBattleTeam.average_level(none), 1)

func test_whole_flow_player_beats_weak_enemy_with_fixed_seed() -> void:
	# Ende-zu-Ende ohne UI: Pet-Team → Engine → Gegner aus Seed. Ein Level-30-Pet schlägt ein Level-3-Team.
	var pet := _pet("bear", PetLeveling.xp_required_for_level(30), true)
	var team: Array[PetComponent] = [pet]
	var player := PetBattleTeam.mons_for(team)
	var enemy_entries: Array[Dictionary] = [{"species_id": "mouse", "level": 3}, {"species_id": "rat", "level": 3}]
	var enemy := PetBattleEncounter.mons_for_enemy_team(enemy_entries)
	var eng := PetBattleEngine.new(player, enemy, 99)
	for i in range(80):
		if eng.is_over():
			break
		if eng.needs_switch():
			break
		eng.use_move(eng.active_player().moves.size() - 1)
	assert_eq(eng.result, PetBattleEngine.Result.PLAYER_WON)

# res://tests/unit/test_pet_leveling.gd
extends GutTest

## Unit-Tests für PetLeveling — reine, statische XP-Kurve (RefCounted, keine
## Engine-Dependencies), daher ohne Scene-Tree-Setup testbar.

func test_level_1_requires_zero_xp() -> void:
	assert_eq(PetLeveling.xp_required_for_level(1), 0)

func test_xp_required_grows_with_each_level() -> void:
	var a := PetLeveling.xp_required_for_level(2)
	var b := PetLeveling.xp_required_for_level(3)
	var c := PetLeveling.xp_required_for_level(4)
	assert_true(a < b and b < c, "Jedes Level muss mehr Gesamt-XP brauchen als das vorherige")

func test_resolve_zero_xp_is_level_one() -> void:
	var r := PetLeveling.resolve(0)
	assert_eq(r["level"], 1)
	assert_eq(r["xp_into_level"], 0)

func test_resolve_exact_threshold_reaches_next_level() -> void:
	var needed := PetLeveling.xp_required_for_level(2)
	var r := PetLeveling.resolve(needed)
	assert_eq(r["level"], 2, "Exakt die benötigte XP-Summe muss das Level bereits erreichen")

func test_resolve_one_xp_below_threshold_stays_on_previous_level() -> void:
	var needed := PetLeveling.xp_required_for_level(2)
	var r := PetLeveling.resolve(needed - 1)
	assert_eq(r["level"], 1)

func test_resolve_xp_into_level_is_progress_since_last_levelup() -> void:
	var needed_lvl2 := PetLeveling.xp_required_for_level(2)
	var r := PetLeveling.resolve(needed_lvl2 + 5)
	assert_eq(r["level"], 2)
	assert_eq(r["xp_into_level"], 5)

func test_resolve_never_exceeds_max_level() -> void:
	var r := PetLeveling.resolve(999999999)
	assert_eq(r["level"], PetLeveling.MAX_LEVEL)

func test_resolve_at_max_level_has_no_next_level() -> void:
	var r := PetLeveling.resolve(999999999)
	assert_eq(r["xp_for_next"], -1)

func test_xp_required_caps_at_max_level() -> void:
	# Level über dem Cap darf nicht noch mehr XP verlangen als der Cap selbst.
	assert_eq(
		PetLeveling.xp_required_for_level(PetLeveling.MAX_LEVEL + 50),
		PetLeveling.xp_required_for_level(PetLeveling.MAX_LEVEL)
	)

func test_xp_reward_for_harvest_abilities() -> void:
	assert_eq(PetLeveling.xp_reward_for(PetAbilities.GATHERING), PetLeveling.XP_HARVEST)
	assert_eq(PetLeveling.xp_reward_for(PetAbilities.MINING), PetLeveling.XP_HARVEST)
	assert_eq(PetLeveling.xp_reward_for(PetAbilities.WOODCUTTING), PetLeveling.XP_HARVEST)

func test_xp_reward_for_combat_and_digging() -> void:
	assert_eq(PetLeveling.xp_reward_for(PetAbilities.COMBAT), PetLeveling.XP_COMBAT)
	assert_eq(PetLeveling.xp_reward_for(PetAbilities.DIGGING), PetLeveling.XP_DIG)

func test_xp_reward_for_unknown_ability_is_zero() -> void:
	assert_eq(PetLeveling.xp_reward_for("not_a_real_ability"), 0)

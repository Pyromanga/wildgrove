# res://tests/unit/test_pet_abilities.gd
extends GutTest

## Unit-Tests für PetAbilities — reine statische Logik (RefCounted, keine
## Engine-Dependencies), daher ohne Scene-Tree-Setup testbar.

# ─────────────────────────────────────────────
# default_for_species()
# ─────────────────────────────────────────────

func test_known_species_returns_its_defaults() -> void:
	assert_eq(PetAbilities.default_for_species("Boar"), [PetAbilities.MINING, PetAbilities.DIGGING])
	assert_eq(PetAbilities.default_for_species("Fox"), [PetAbilities.COMBAT])

func test_unknown_species_falls_back_to_gathering() -> void:
	assert_eq(PetAbilities.default_for_species("Dragon"), [PetAbilities.GATHERING])
	assert_eq(PetAbilities.default_for_species(""), [PetAbilities.GATHERING])

func test_default_for_species_returns_independent_copy() -> void:
	# Mutation des Rückgabewerts darf NICHT die globale Konstante verändern —
	# sonst würde jedes künftig gefangene Boar die Mutation eines früheren
	# Aufrufers erben.
	var result := PetAbilities.default_for_species("Boar")
	result.append("something_else")
	var result_again := PetAbilities.default_for_species("Boar")
	assert_eq(result_again, [PetAbilities.MINING, PetAbilities.DIGGING])
	assert_eq(result_again.size(), 2)

# ─────────────────────────────────────────────
# harvest_type_ids_for() / is_harvest_ability()
# ─────────────────────────────────────────────

func test_harvest_type_ids_for_known_abilities() -> void:
	assert_eq(PetAbilities.harvest_type_ids_for(PetAbilities.GATHERING), PetAbilities.GATHERING_TYPES)
	assert_eq(PetAbilities.harvest_type_ids_for(PetAbilities.WOODCUTTING), PetAbilities.WOODCUTTING_TYPES)
	assert_eq(PetAbilities.harvest_type_ids_for(PetAbilities.MINING), PetAbilities.MINING_TYPES)

func test_harvest_type_ids_for_non_harvest_abilities_is_empty() -> void:
	assert_eq(PetAbilities.harvest_type_ids_for(PetAbilities.COMBAT), [])
	assert_eq(PetAbilities.harvest_type_ids_for(PetAbilities.DIGGING), [])
	assert_eq(PetAbilities.harvest_type_ids_for("unknown"), [])

func test_is_harvest_ability() -> void:
	assert_true(PetAbilities.is_harvest_ability(PetAbilities.GATHERING))
	assert_true(PetAbilities.is_harvest_ability(PetAbilities.WOODCUTTING))
	assert_true(PetAbilities.is_harvest_ability(PetAbilities.MINING))
	assert_false(PetAbilities.is_harvest_ability(PetAbilities.COMBAT))
	assert_false(PetAbilities.is_harvest_ability(PetAbilities.DIGGING))

# ─────────────────────────────────────────────
# sanitize()
# ─────────────────────────────────────────────

func test_sanitize_keeps_known_ids() -> void:
	var result := PetAbilities.sanitize([PetAbilities.GATHERING, PetAbilities.COMBAT])
	assert_eq(result, [PetAbilities.GATHERING, PetAbilities.COMBAT])

func test_sanitize_drops_unknown_ids() -> void:
	var result := PetAbilities.sanitize([PetAbilities.GATHERING, "typo_ability", "fishing"])
	assert_eq(result, [PetAbilities.GATHERING])

func test_sanitize_drops_duplicates() -> void:
	var result := PetAbilities.sanitize([PetAbilities.GATHERING, PetAbilities.GATHERING])
	assert_eq(result, [PetAbilities.GATHERING])

func test_sanitize_non_array_returns_empty() -> void:
	assert_eq(PetAbilities.sanitize(null), [])
	assert_eq(PetAbilities.sanitize("gathering"), [])
	assert_eq(PetAbilities.sanitize(42), [])

func test_sanitize_empty_array_returns_empty() -> void:
	assert_eq(PetAbilities.sanitize([]), [])

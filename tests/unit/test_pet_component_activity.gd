# res://tests/unit/test_pet_component_activity.gd
extends GutTest

## Unit-Tests für PetComponent.get_current_activity()/get_appearance() und
## PetAbilityComponent.get_activity_state() — Lese-API fürs Pet-Menü (Status-Zeile
## + Filter "was tut das Pet gerade"). Kein SceneTree nötig: die Methoden lesen nur
## Kind-Knoten bzw. Felder, _ready()/on_spawn() sind nicht beteiligt.

var _pet: PetComponent

func before_each() -> void:
	_pet = autofree(PetComponent.new())

func _add_ability(ability_id: String, state: int) -> PetAbilityComponent:
	var comp := PetAbilityComponent.new()
	comp.ability_id = ability_id
	comp._state = state
	_pet.add_child(comp)
	return comp

func test_pet_without_ability_components_is_idle() -> void:
	var act := _pet.get_current_activity()
	assert_eq(act["ability"], "")
	assert_false(act["acting"])

func test_all_abilities_idle_means_idle() -> void:
	_add_ability(PetAbilities.GATHERING, PetAbilityComponent.State.IDLE)
	_add_ability(PetAbilities.MINING, PetAbilityComponent.State.IDLE)
	assert_eq(_pet.get_current_activity()["ability"], "")

func test_seeking_ability_reported_as_not_acting() -> void:
	_add_ability(PetAbilities.WOODCUTTING, PetAbilityComponent.State.SEEKING)
	var act := _pet.get_current_activity()
	assert_eq(act["ability"], PetAbilities.WOODCUTTING)
	assert_false(act["acting"])

func test_acting_ability_reported_as_acting() -> void:
	_add_ability(PetAbilities.MINING, PetAbilityComponent.State.ACTING)
	var act := _pet.get_current_activity()
	assert_eq(act["ability"], PetAbilities.MINING)
	assert_true(act["acting"])

func test_acting_ability_wins_over_seeking_one() -> void:
	_add_ability(PetAbilities.GATHERING, PetAbilityComponent.State.SEEKING)
	_add_ability(PetAbilities.MINING, PetAbilityComponent.State.ACTING)
	assert_eq(_pet.get_current_activity()["ability"], PetAbilities.MINING)

func test_digging_uses_its_own_state_variable() -> void:
	var comp := _add_ability(PetAbilities.DIGGING, PetAbilityComponent.State.IDLE)
	comp._dig_state = PetAbilityComponent.State.ACTING
	assert_eq(comp.get_activity_state(), PetAbilityComponent.State.ACTING)
	assert_eq(_pet.get_current_activity()["ability"], PetAbilities.DIGGING)

func test_non_ability_children_are_ignored() -> void:
	_pet.add_child(Node.new())
	assert_eq(_pet.get_current_activity()["ability"], "")

func test_appearance_contains_cosmetic_fields_with_defaults() -> void:
	var a := _pet.get_appearance()
	assert_true(a["color"] is Color)
	assert_eq(a["ear_style"], AnimalVisualProfile.EarStyle.ROUND)
	assert_eq(a["snout_style"], AnimalVisualProfile.SnoutStyle.SHORT)
	assert_eq(a["headgear_style"], AnimalVisualProfile.HeadgearStyle.NONE)

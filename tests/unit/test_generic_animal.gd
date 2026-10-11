# res://tests/unit/test_generic_animal.gd
extends GutTest

## Unit-Tests für GenericAnimal.gd — siehe dortigen Klassenkommentar für den Mechanismus
## (species_id aus dem ersten Wort des Node-Namens, wie ihn EntityOrchestrator.spawn_entity()
## deterministisch VOR add_child()/_ready() vergibt).

func test_species_id_derived_from_orchestrator_style_name() -> void:
	var animal := GenericAnimal.new()
	animal.name = "wolf_100_0_200"  # Format wie EntityOrchestrator.spawn_entity()
	add_child_autofree(animal)
	assert_eq(animal.get_species_id(), "wolf")

func test_stats_are_applied_from_species_db() -> void:
	var animal := GenericAnimal.new()
	animal.name = "wolf_0_0_0"
	add_child_autofree(animal)
	var def: Dictionary = AnimalSpeciesDB.get_definition("wolf")
	assert_eq(animal._color, def["color"])
	assert_eq(animal._body_size, def["body_size"])
	assert_eq(animal._speed, def["speed"])
	assert_eq(animal._body_plan, def["body_plan"])

func test_explicit_species_id_overrides_name_derived_one() -> void:
	var animal := GenericAnimal.new()
	animal.set_species_id("trout")
	animal.name = "wolf_0_0_0"  # würde ohne set_species_id() "wolf" ergeben
	add_child_autofree(animal)
	assert_eq(animal.get_species_id(), "trout")
	assert_eq(animal._body_plan, AnimalVisualProfile.BodyPlan.FISH)

func test_unknown_species_id_falls_back_to_animalbase_defaults_without_crash() -> void:
	var animal := GenericAnimal.new()
	animal.name = "voellig_unbekannt_0_0_0"
	add_child_autofree(animal)
	# Kein Crash, und body_plan bleibt der AnimalBase-Default (QUADRUPED).
	assert_eq(animal._body_plan, AnimalVisualProfile.BodyPlan.QUADRUPED)

func test_inspect_text_comes_from_species_db() -> void:
	var animal := GenericAnimal.new()
	animal.set_species_id("wolf")
	add_child_autofree(animal)
	assert_eq(animal.get_inspect_text(), AnimalSpeciesDB.get_definition("wolf")["inspect_text"])

func test_aquatic_flag_is_applied() -> void:
	var animal := GenericAnimal.new()
	animal.set_species_id("trout")
	add_child_autofree(animal)
	assert_true(animal._aquatic)

func test_species_id_with_underscore_is_resolved_from_entity_type_meta() -> void:
	# Regression ("Vogelspinne sah aus wie ein Hund"): "wolf_spider" wurde über den Node-Namen
	# zu "wolf" (ein Wolf) zerlegt. EntityOrchestrator setzt das Meta VOR add_child().
	var animal := GenericAnimal.new()
	animal.set_meta("entity_type", "wolf_spider")
	animal.name = "wolf_spider_1_2_3"
	add_child_autofree(animal)
	assert_eq(animal.get_species_id(), "wolf_spider")
	assert_eq(animal._body_plan, AnimalVisualProfile.BodyPlan.SPIDER)

func test_every_db_species_resolves_to_itself_via_meta() -> void:
	for id: String in AnimalSpeciesDB.SPECIES:
		var animal := GenericAnimal.new()
		animal.set_meta("entity_type", id)
		animal.name = "%s_0_0_0" % id
		add_child_autofree(animal)
		assert_eq(animal.get_species_id(), id)

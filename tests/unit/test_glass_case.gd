# res://tests/unit/test_glass_case.gd
extends GutTest

## Unit-Tests für GlassCase (Schaukasten + Schild) und den captive-Modus von AnimalBase.

const INNER := Vector3(2.0, 1.6, 3.0)

func _case(label: String = "Wolf", water: bool = false) -> GlassCase:
	var c := GlassCase.new()
	add_child_autofree(c)
	c.on_spawn({"inner": INNER, "label": label, "water": water, "foundation": 1.0}, null)
	return c

func test_case_has_four_glass_panes_with_collision() -> void:
	var c := _case()
	for n in ["GlassFront", "GlassBack", "GlassLeft", "GlassRight"]:
		var pane := c.find_child(n, true, false) as MeshInstance3D
		assert_not_null(pane, n)
		assert_true(pane.material_override is StandardMaterial3D)
		assert_eq((pane.material_override as StandardMaterial3D).transparency, BaseMaterial3D.TRANSPARENCY_ALPHA, "%s durchsichtig" % n)
	var body := c.find_child("CaseBody", true, false) as StaticBody3D
	assert_not_null(body)
	var shapes := 0
	for child in body.get_children():
		if child is CollisionShape3D:
			shapes += 1
	assert_gte(shapes, 4 + 1 + 4 + 1, "Scheiben + Sockel + Pfosten + Deckel haben Kollision")

func test_glass_encloses_the_inner_volume() -> void:
	var c := _case()
	var front := c.find_child("GlassFront", true, false) as MeshInstance3D
	var back := c.find_child("GlassBack", true, false) as MeshInstance3D
	var right := c.find_child("GlassRight", true, false) as MeshInstance3D
	assert_almost_eq(front.position.z, INNER.z * 0.5, 0.0001)
	assert_almost_eq(back.position.z, -INNER.z * 0.5, 0.0001)
	assert_almost_eq(right.position.x, INNER.x * 0.5, 0.0001)
	assert_almost_eq((front.mesh as BoxMesh).size.y, INNER.y, 0.0001)

func test_sign_shows_animal_name_in_front_of_the_case() -> void:
	var c := _case("Wolfsspinne")
	var text := c.find_child("SignText", true, false) as Label3D
	assert_not_null(text)
	assert_eq(text.text, "Wolfsspinne")
	var sign_node := c.find_child("Sign", true, false) as Node3D
	assert_gt(sign_node.position.z, INNER.z * 0.5, "Schild steht vor der Glasfront (+Z)")
	assert_eq(c.get_label(), "Wolfsspinne")

func test_sign_board_grows_with_text_length() -> void:
	assert_gt(GlassCase.sign_width("Rotschulterfalke"), GlassCase.sign_width("Fuchs"))
	assert_lte(GlassCase.sign_width("x".repeat(200)), 2.8)
	assert_gte(GlassCase.sign_width(""), 1.0)

func test_water_only_in_aquatic_cases() -> void:
	assert_null(_case("Wolf", false).find_child("Water", true, false))
	var tank := _case("Forelle", true).find_child("Water", true, false) as MeshInstance3D
	assert_not_null(tank)
	assert_lt((tank.mesh as BoxMesh).size.y, INNER.y, "Wasser steht unter dem Deckel")

func test_respawn_with_other_config_rebuilds_geometry() -> void:
	var c := _case("Wolf")
	c.on_spawn({"inner": Vector3(1.6, 1.3, 1.6), "label": "Fuchs", "water": false}, null)
	await get_tree().process_frame  # queue_free der alten Kinder abwarten
	assert_eq(c.get_label(), "Fuchs")
	assert_eq(c.get_inner_size(), Vector3(1.6, 1.3, 1.6))
	assert_eq(c.find_children("SignText", "Label3D", true, false).size(), 1)

# ─────────────────────────────────────────────
# captive-Modus
# ─────────────────────────────────────────────

func test_captive_animal_has_no_catch_interaction() -> void:
	var animal := GenericAnimal.new()
	animal.set_species_id("wolf")
	add_child_autofree(animal)
	assert_not_null(animal._catch_interactable, "wilde Tiere sind fangbar")
	animal.on_spawn({"captive": true}, null)
	assert_true(animal.is_captive())
	assert_null(animal._catch_interactable)

func test_captive_animal_does_not_move() -> void:
	var animal := GenericAnimal.new()
	animal.set_species_id("wolf")
	add_child_autofree(animal)
	animal.position = Vector3(3.0, 1.0, 4.0)
	animal.on_spawn({"captive": true}, null)
	for i in range(5):
		animal._physics_process(0.1)
	assert_eq(animal.position, Vector3(3.0, 1.0, 4.0))
	assert_eq(animal.velocity, Vector3.ZERO)

func test_non_captive_default() -> void:
	var animal := GenericAnimal.new()
	animal.set_species_id("wolf")
	add_child_autofree(animal)
	animal.on_spawn({}, null)
	assert_false(animal.is_captive())

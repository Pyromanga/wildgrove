# res://tests/unit/test_character_sex.gd
extends GutTest

## Tests für Geschlecht (Frau/Mann): Datenmodell, Körperform im Builder, NPC-Presets.

func _build(look: Dictionary) -> Dictionary:
	var parts := CharacterPartBuilder.build(CharacterLook.sanitize(look))
	autofree(parts["root"])
	return parts

func test_sex_is_an_editor_field_with_two_options_and_male_default() -> void:
	assert_eq(CharacterLook.option_ids("sex"), ["male", "female"])
	assert_eq(CharacterLook.DEFAULTS["sex"], "male")
	var keys: Array = []
	for f in CharacterLook.editor_fields():
		keys.append((f as Dictionary)["key"])
	assert_true(keys.has("sex"), "Der Editor muss das Geschlecht anbieten.")

func test_invalid_sex_falls_back_to_male() -> void:
	assert_eq(CharacterLook.sanitize({"sex": "robot"})["sex"], "male")
	assert_eq(CharacterLook.sex_of({"sex": 5}), "male")

func test_female_has_narrower_shoulders_and_wider_hips_than_male() -> void:
	assert_lt(CharacterLook.sex_param("female", "shoulder_w"), CharacterLook.sex_param("male", "shoulder_w"))
	assert_gt(CharacterLook.sex_param("female", "hip_w"), CharacterLook.sex_param("male", "hip_w"))
	assert_gt(CharacterLook.sex_param("female", "bust"), 0.0)
	assert_eq(CharacterLook.sex_param("male", "bust"), 0.0)

func test_female_is_slightly_smaller_at_same_height_setting() -> void:
	var m := CharacterLook.body_scale({"sex": "male", "height": "medium"})
	var f := CharacterLook.body_scale({"sex": "female", "height": "medium"})
	assert_eq(m, 1.0)
	assert_lt(f, m)
	assert_gt(CharacterLook.body_scale({"sex": "female", "height": "tall"}), f, "Größenstufe wirkt weiter.")

func test_shoulder_x_follows_sex() -> void:
	var m := CharacterPartBuilder.shoulder_x({"sex": "male"})
	var f := CharacterPartBuilder.shoulder_x({"sex": "female"})
	assert_lt(f, m, "Frauen: schmalere Schultern (und damit Handposition).")

func test_body_silhouette_differs_between_male_and_female() -> void:
	var male := _build({"sex": "male"})
	var female := _build({"sex": "female"})
	var m_torso := (male["torso"] as MeshInstance3D).scale.x
	var f_torso := (female["torso"] as MeshInstance3D).scale.x
	assert_lt(f_torso, m_torso, "Frauen-Rumpf ist schmaler.")
	var m_pelvis := ((male["root"] as Node3D).get_node("Pelvis") as MeshInstance3D).mesh as CapsuleMesh
	var f_pelvis := ((female["root"] as Node3D).get_node("Pelvis") as MeshInstance3D).mesh as CapsuleMesh
	assert_gt(f_pelvis.height, m_pelvis.height, "Frauen-Becken ist breiter.")
	var m_leg_x := absf((male["leg_r"] as Node3D).position.x)
	var f_leg_x := absf((female["leg_r"] as Node3D).position.x)
	assert_gt(f_leg_x, m_leg_x, "Beine sitzen bei Frauen weiter auseinander (breitere Hüfte).")

func test_only_female_has_a_bust() -> void:
	assert_null((_build({"sex": "male"})["root"] as Node3D).get_node_or_null("BustR"))
	assert_not_null((_build({"sex": "female"})["root"] as Node3D).get_node_or_null("BustR"))
	assert_not_null((_build({"sex": "female"})["root"] as Node3D).get_node_or_null("BustL"))

func test_random_looks_include_both_sexes_and_women_have_no_beard() -> void:
	var seen_male := false
	var seen_female := false
	for i in 120:
		var look := CharacterLook.from_seed("npc-%d" % i)
		if look["sex"] == "female":
			seen_female = true
			assert_eq(look["beard"], "none", "Zufällige Frauen tragen keinen Bart.")
		else:
			seen_male = true
	assert_true(seen_male and seen_female, "Zufalls-NPCs müssen beide Geschlechter erzeugen.")

func test_from_seed_is_deterministic_including_sex() -> void:
	assert_eq(CharacterLook.from_seed("Fremder Wanderer"), CharacterLook.from_seed("Fremder Wanderer"))

func test_story_npc_presets_have_the_right_sex() -> void:
	for female_name in ["Bergarbeiterin Mira", "Wegweiser Mira", "Kampfmeisterin Wei", "Wächterin Talia", "Kräuterkundige Senna", "Marktschreierin Odile"]:
		assert_eq(NPCLook.resolve(female_name)["look"]["sex"], "female", "%s ist eine Frau." % female_name)
	for male_name in ["Waldläufer Erik", "Dorfältester Rasmus", "Ahnengeist Babatunde", "Bankier Aurelius", "Händler Toma", "Förster Holgar"]:
		assert_eq(NPCLook.resolve(male_name)["look"]["sex"], "male", "%s ist ein Mann." % male_name)

func test_npc_scale_uses_sex_factor() -> void:
	var spec := NPCLook.resolve("Wächterin Talia")
	assert_eq(spec["scale"], CharacterLook.body_scale(spec["look"]))

func test_every_sex_builds_with_every_build_and_height() -> void:
	for sex in CharacterLook.option_ids("sex"):
		for build in CharacterLook.option_ids("build"):
			for height in CharacterLook.option_ids("height"):
				var parts := _build({"sex": sex, "build": build, "height": height})
				assert_not_null(parts["head"])

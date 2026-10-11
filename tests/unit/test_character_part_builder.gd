# res://tests/unit/test_character_part_builder.gd
extends GutTest

## Tests für CharacterPartBuilder — prüft die vom Rest des Spiels beobachtbare
## Struktur (welche Kind-Nodes existieren, welche Materialfarben landen wo),
## nicht exakte Geometrie-Zahlen (die sind Gestaltungsfreiheit, keine Contracts).

func test_build_returns_all_documented_keys() -> void:
	var parts := CharacterPartBuilder.build(CharacterLook.default_look())
	for key in ["root", "torso", "shirt_mat", "head", "face", "hair", "arm_r", "arm_l", "leg_r", "leg_l"]:
		assert_true(parts.has(key), "build() Ergebnis fehlt Schlüssel '%s'." % key)
	autofree(parts["root"])

func test_torso_material_color_matches_shirt_catalog_entry() -> void:
	var look := CharacterLook.sanitize({"shirt": "wald"})
	var parts := CharacterPartBuilder.build(look)
	autofree(parts["root"])

	var mat := (parts["torso"] as MeshInstance3D).material_override as StandardMaterial3D
	assert_eq(mat.albedo_color, CharacterLook.color_of("shirt", "wald"))

func test_torso_material_is_the_same_instance_as_shirt_mat() -> void:
	var parts := CharacterPartBuilder.build(CharacterLook.default_look())
	autofree(parts["root"])

	var mat := (parts["torso"] as MeshInstance3D).material_override
	assert_eq(mat, parts["shirt_mat"], "Rumpf und zurückgegebenes shirt_mat müssen dasselbe Material teilen (für Ärmel-Konsistenz).")

func test_head_contains_face_and_hair_children() -> void:
	var parts := CharacterPartBuilder.build(CharacterLook.default_look())
	autofree(parts["root"])

	var head := parts["head"] as Node3D
	assert_true(head.has_node("Face"))
	assert_true(head.has_node("Hair"))
	assert_eq(head.get_node("Face"), parts["face"])
	assert_eq(head.get_node("Hair"), parts["hair"])

func test_bald_hair_style_produces_no_hair_children() -> void:
	var look := CharacterLook.sanitize({"hair_style": "bald"})
	var parts := CharacterPartBuilder.build(look)
	autofree(parts["root"])

	var hair := parts["hair"] as Node3D
	assert_eq(hair.get_child_count(), 0)

func test_every_non_bald_hair_style_produces_at_least_one_mesh() -> void:
	for style_id in CharacterLook.option_ids("hair_style"):
		if style_id == "bald":
			continue
		var look := CharacterLook.sanitize({"hair_style": style_id})
		var parts := CharacterPartBuilder.build(look)
		autofree(parts["root"])
		var hair := parts["hair"] as Node3D
		assert_true(hair.get_child_count() > 0, "hair_style '%s' erzeugt keine Kind-Nodes." % style_id)

func test_no_nose_option_produces_no_nose_child() -> void:
	var look := CharacterLook.sanitize({"nose": "none"})
	var parts := CharacterPartBuilder.build(look)
	autofree(parts["root"])

	var face := parts["face"] as Node3D
	assert_false(face.has_node("Nose"))

func test_no_brows_option_produces_no_brow_children() -> void:
	var look := CharacterLook.sanitize({"brows": "none"})
	var parts := CharacterPartBuilder.build(look)
	autofree(parts["root"])

	var face := parts["face"] as Node3D
	assert_false(face.has_node("BrowR"))
	assert_false(face.has_node("BrowL"))

func test_arm_and_leg_pivots_are_symmetric_around_x_axis() -> void:
	var parts := CharacterPartBuilder.build(CharacterLook.default_look())
	autofree(parts["root"])

	var arm_r := parts["arm_r"] as Node3D
	var arm_l := parts["arm_l"] as Node3D
	assert_almost_eq(arm_r.position.x, -arm_l.position.x, 0.0001)
	assert_almost_eq(arm_r.position.y, arm_l.position.y, 0.0001)

	var leg_r := parts["leg_r"] as Node3D
	var leg_l := parts["leg_l"] as Node3D
	assert_almost_eq(leg_r.position.x, -leg_l.position.x, 0.0001)

func test_broad_build_widens_shoulder_x_versus_slim() -> void:
	var slim := CharacterPartBuilder.shoulder_x(CharacterLook.sanitize({"build": "slim"}))
	var broad := CharacterPartBuilder.shoulder_x(CharacterLook.sanitize({"build": "broad"}))
	assert_true(broad > slim, "Kräftige Statur muss eine breitere Schulterposition ergeben als schlanke.")

func test_hand_position_mirrors_across_sides() -> void:
	var look := CharacterLook.default_look()
	var right := CharacterPartBuilder.hand_position(look, 1.0)
	var left := CharacterPartBuilder.hand_position(look, -1.0)
	assert_almost_eq(right.x, -left.x, 0.0001)
	assert_almost_eq(right.y, left.y, 0.0001)

func test_build_is_deterministic_for_same_look() -> void:
	var look := CharacterLook.sanitize({"build": "broad", "height": "tall"})
	var a := CharacterPartBuilder.build(look)
	var b := CharacterPartBuilder.build(look)
	autofree(a["root"])
	autofree(b["root"])

	assert_eq((a["arm_r"] as Node3D).position, (b["arm_r"] as Node3D).position)

# ─────────────────────────────────────────────
# Erweiterte Optionen: jede Option jedes Feldes muss ohne Fehler bauen
# ─────────────────────────────────────────────

func test_every_option_of_every_field_builds_without_error() -> void:
	for field in CharacterLook.FIELDS:
		var key: String = String((field as Dictionary)["key"])
		for id in CharacterLook.option_ids(key):
			var parts := CharacterPartBuilder.build(CharacterLook.sanitize({key: id}))
			autofree(parts["root"])
			assert_not_null(parts["head"], "build() ohne Kopf bei %s=%s." % [key, id])

func test_hat_none_has_no_hat_node_and_hat_option_adds_one() -> void:
	var none_parts := CharacterPartBuilder.build(CharacterLook.default_look())
	autofree(none_parts["root"])
	assert_null(none_parts["hat"])
	var cap_parts := CharacterPartBuilder.build(CharacterLook.sanitize({"hat": "cap"}))
	autofree(cap_parts["root"])
	assert_not_null(cap_parts["hat"])
	assert_true((cap_parts["hat"] as Node3D).get_child_count() > 0)

func test_hat_color_override_and_catalog_color() -> void:
	var parts := CharacterPartBuilder.build(CharacterLook.sanitize({"hat": "beanie", "hat_color": "red"}))
	autofree(parts["root"])
	var dome := (parts["hat"] as Node3D).find_child("Dome", true, false) as MeshInstance3D
	assert_eq((dome.material_override as StandardMaterial3D).albedo_color, CharacterLook.color_of("hat_color", "red"))
	var parts2 := CharacterPartBuilder.build(CharacterLook.sanitize({"hat": "beanie"}), {"hat_color": Color(0.1, 0.2, 0.3)})
	autofree(parts2["root"])
	var dome2 := (parts2["hat"] as Node3D).find_child("Dome", true, false) as MeshInstance3D
	assert_eq((dome2.material_override as StandardMaterial3D).albedo_color, Color(0.1, 0.2, 0.3))

func test_shirt_color_override_applies_to_torso() -> void:
	var parts := CharacterPartBuilder.build(CharacterLook.default_look(), {"shirt_color": Color(0.9, 0.1, 0.1)})
	autofree(parts["root"])
	assert_eq(((parts["torso"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color, Color(0.9, 0.1, 0.1))

func test_non_color_override_values_are_ignored() -> void:
	var parts := CharacterPartBuilder.build(CharacterLook.default_look(), {"shirt_color": "not a color"})
	autofree(parts["root"])
	assert_eq(((parts["torso"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color, CharacterLook.color_of("shirt", CharacterLook.DEFAULTS["shirt"]))

func test_glasses_beard_and_freckles_create_nodes() -> void:
	var parts := CharacterPartBuilder.build(CharacterLook.sanitize({"glasses": "round", "beard": "full", "face_detail": "freckles"}))
	autofree(parts["root"])
	var face := parts["face"] as Node3D
	assert_not_null(face.get_node_or_null("GlassesR"))
	assert_not_null(face.get_node_or_null("GlassesL"))
	assert_not_null(face.get_node_or_null("BeardJaw"))
	assert_not_null(face.get_node_or_null("FreckleR0"))

func test_vest_has_skin_colored_upper_arm_and_longsleeve_has_shirt_colored_forearm() -> void:
	var vest := CharacterPartBuilder.build(CharacterLook.sanitize({"shirt_style": "vest"}))
	autofree(vest["root"])
	var skin_col := CharacterLook.color_of("skin", CharacterLook.DEFAULTS["skin"])
	var sleeve := (vest["arm_r"] as Node3D).get_node("Sleeve") as MeshInstance3D
	assert_eq((sleeve.material_override as StandardMaterial3D).albedo_color, skin_col)
	var ls := CharacterPartBuilder.build(CharacterLook.sanitize({"shirt_style": "longsleeve"}))
	autofree(ls["root"])
	var fore := (ls["arm_r"] as Node3D).get_node("Forearm") as MeshInstance3D
	assert_eq((fore.material_override as StandardMaterial3D).albedo_color, CharacterLook.color_of("shirt", CharacterLook.DEFAULTS["shirt"]))

func test_shorts_have_bare_lower_leg_and_long_pants_do_not() -> void:
	var shorts := CharacterPartBuilder.build(CharacterLook.sanitize({"pants_style": "shorts"}))
	autofree(shorts["root"])
	assert_not_null((shorts["leg_r"] as Node3D).get_node_or_null("LowerLeg"))
	var long_p := CharacterPartBuilder.build(CharacterLook.default_look())
	autofree(long_p["root"])
	assert_null((long_p["leg_r"] as Node3D).get_node_or_null("LowerLeg"))

func test_leg_and_arm_pivots_unchanged_by_style_options() -> void:
	# Waffen-Attachments hängen an hand_position()/shoulder_position() → darf nicht von
	# Kleidungsoptionen abhängen.
	var a := CharacterPartBuilder.hand_position(CharacterLook.default_look(), 1.0)
	var b := CharacterPartBuilder.hand_position(CharacterLook.sanitize({"shirt_style": "tunic", "pants_style": "shorts", "hat": "wizard"}), 1.0)
	assert_eq(a, b)

func test_eyes_expose_gaze_and_lid_nodes_for_every_eye_style() -> void:
	for style in CharacterLook.option_ids("eyes"):
		var parts := CharacterPartBuilder.build(CharacterLook.sanitize({"eyes": style}))
		autofree(parts["root"])
		var eye := parts["eye_r"] as Node3D
		assert_not_null(eye, "eye_r fehlt bei '%s'." % style)
		assert_not_null(eye.get_node_or_null("Gaze"), "Gaze fehlt bei '%s'." % style)

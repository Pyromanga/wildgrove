# res://tests/unit/test_worn_gear_visuals.gd
extends GutTest

## Tests für die Optik von Nacktheit/Unterwäsche, Zubehör und Rüstung (CharacterPartBuilder +
## WornGearBuilder). Was getragen wird, kommt ausschließlich aus dem Look.

func _build(look: Dictionary) -> Dictionary:
	var parts := CharacterPartBuilder.build(CharacterLook.sanitize(look))
	autofree(parts["root"])
	return parts

func _albedo(node: Node) -> Color:
	return ((node as MeshInstance3D).material_override as StandardMaterial3D).albedo_color

# ── Nackt / Unterwäsche ─────────────────────────────────────────────────────

func test_without_shirt_torso_and_arms_show_skin() -> void:
	var look := {"shirt": "none", "skin": "dark"}
	var parts := _build(look)
	var skin := CharacterLook.color_of("skin", "dark")
	assert_eq(_albedo(parts["torso"]), skin)
	assert_eq(_albedo((parts["arm_r"] as Node3D).get_node("Sleeve")), skin)
	assert_eq(_albedo((parts["arm_r"] as Node3D).get_node("Forearm")), skin)
	assert_null((parts["root"] as Node3D).get_node_or_null("Collar"), "Ohne Oberteil gibt es keinen Kragen.")

func test_without_shirt_tunic_has_no_skirt() -> void:
	var parts := _build({"shirt": "none", "shirt_style": "tunic"})
	assert_null((parts["root"] as Node3D).get_node_or_null("TunicSkirt"))

func test_without_pants_pelvis_is_underwear_and_legs_are_skin() -> void:
	var parts := _build({"pants": "none", "skin": "light"})
	assert_eq(_albedo((parts["root"] as Node3D).get_node("Pelvis")), CharacterPartBuilder.UNDERWEAR_COLOR)
	assert_eq(_albedo((parts["leg_r"] as Node3D).get_node("Leg")), CharacterLook.color_of("skin", "light"))

func test_without_shoes_feet_are_bare() -> void:
	var parts := _build({"shoes": "none", "skin": "light"})
	var leg := parts["leg_r"] as Node3D
	assert_null(leg.get_node_or_null("Shoe"))
	assert_null(leg.get_node_or_null("Sole"))
	assert_eq(_albedo(leg.get_node("Foot")), CharacterLook.color_of("skin", "light"))

func test_underwear_top_only_for_female_without_shirt() -> void:
	assert_not_null((_build({"sex": "female", "shirt": "none"})["root"] as Node3D).get_node_or_null("UnderTop"))
	assert_null((_build({"sex": "male", "shirt": "none"})["root"] as Node3D).get_node_or_null("UnderTop"))
	assert_null((_build({"sex": "female"})["root"] as Node3D).get_node_or_null("UnderTop"), "Mit Oberteil kein Brustband.")

func test_completely_naked_character_builds() -> void:
	for sex in ["male", "female"]:
		var parts := _build({"sex": sex, "shirt": "none", "pants": "none", "shoes": "none"})
		assert_not_null(parts["head"])

func test_random_looks_are_never_naked() -> void:
	for i in 100:
		var look := CharacterLook.from_seed("zufall-%d" % i)
		assert_ne(look["shirt"], "none")
		assert_ne(look["pants"], "none")
		assert_ne(look["shoes"], "none")

# ── Zubehör ─────────────────────────────────────────────────────────────────

func test_accessories_appear_only_when_worn() -> void:
	var plain := (_build({})["root"] as Node3D)
	for n in ["Scarf", "Cape", "Backpack", "Pouch", "PauldronR"]:
		assert_null(plain.find_child(n, true, false), "'%s' darf ohne Item nicht erscheinen." % n)
	var dressed := (_build({"scarf": "red", "back": "cape_green", "pouch": "brown", "shoulders": "steel"})["root"] as Node3D)
	for n in ["Scarf", "Cape", "Pouch", "PauldronR", "PauldronL"]:
		assert_not_null(dressed.find_child(n, true, false), "'%s' fehlt." % n)
	assert_not_null((_build({"back": "backpack"})["root"] as Node3D).find_child("Backpack", true, false))

func test_cape_color_comes_from_the_back_option() -> void:
	var root := _build({"back": "cape_violet"})["root"] as Node3D
	var panel := root.find_child("Panel", true, false)
	assert_eq(_albedo(panel), CharacterLook.color_of("back", "cape_violet"))

func test_hardhat_and_tophat_are_hat_options() -> void:
	var hard := _build({"hat": "hardhat"})
	assert_not_null(hard["hat"])
	assert_not_null((hard["hat"] as Node3D).find_child("Lamp", true, false))
	var top := _build({"hat": "tophat"})
	assert_not_null((top["hat"] as Node3D).find_child("Crown", true, false))

# ── Rüstung ─────────────────────────────────────────────────────────────────

func test_helmet_covers_hair_and_hat() -> void:
	var parts := _build({"armor_helmet": "iron_helmet", "hat": "cap"})
	assert_not_null((parts["head"] as Node3D).get_node_or_null("ArmorHelmet"))
	assert_false((parts["hair"] as Node3D).visible, "Unter dem Helm sind Haare unsichtbar.")
	assert_false((parts["hat"] as Node3D).visible, "Unter dem Helm ist der Hut unsichtbar.")

func test_no_helmet_keeps_hair_visible() -> void:
	var parts := _build({})
	assert_true((parts["hair"] as Node3D).visible)
	assert_null((parts["head"] as Node3D).get_node_or_null("ArmorHelmet"))

func test_chest_legs_and_boots_armor_are_drawn() -> void:
	var parts := _build({"armor_chest": "steel_chestplate", "armor_legs": "iron_greaves", "armor_boots": "copper_boots"})
	var root := parts["root"] as Node3D
	assert_not_null(root.get_node_or_null("ArmorChest"))
	assert_not_null(root.get_node_or_null("ArmorFaulds"))
	for leg_key in ["leg_r", "leg_l"]:
		assert_not_null((parts[leg_key] as Node3D).get_node_or_null("ArmorLeg"))
		assert_not_null((parts[leg_key] as Node3D).get_node_or_null("ArmorBoot"))

func test_armor_tier_changes_material() -> void:
	var copper := WornGearBuilder.armor_mat("copper")
	var steel := WornGearBuilder.armor_mat("steel")
	assert_ne(copper.albedo_color, steel.albedo_color)
	assert_gt(steel.metallic, 0.0)

func test_chest_plate_is_deeper_for_female_bust() -> void:
	var m := (_build({"sex": "male", "armor_chest": "iron_chestplate"})["root"] as Node3D).get_node("ArmorChest/Plate") as MeshInstance3D
	var f := (_build({"sex": "female", "armor_chest": "iron_chestplate"})["root"] as Node3D).get_node("ArmorChest/Plate") as MeshInstance3D
	assert_gt(f.scale.z, m.scale.z, "Der weibliche Panzer muss die Brust überdecken.")

func test_full_armor_set_builds_for_every_tier_and_sex() -> void:
	for sex in ["male", "female"]:
		for tier in ["copper", "iron", "steel"]:
			var parts := _build({
				"sex": sex,
				"armor_helmet": "%s_helmet" % tier, "armor_chest": "%s_chestplate" % tier,
				"armor_legs": "%s_greaves" % tier, "armor_boots": "%s_boots" % tier,
			})
			assert_not_null(parts["head"])

# ── Look-Filter ─────────────────────────────────────────────────────────────

func test_sanitize_body_keeps_worn_state_from_base() -> void:
	var base := CharacterLook.sanitize({"shirt": "wald", "armor_chest": "iron_chestplate", "skin": "light"})
	var out := CharacterLook.sanitize_body({"skin": "dark", "shirt": "red", "armor_chest": "none", "hat": "wizard"}, base)
	assert_eq(out["skin"], "dark", "Körper-Felder darf der Spieler ändern.")
	assert_eq(out["shirt"], "wald", "Kleidung nicht.")
	assert_eq(out["armor_chest"], "iron_chestplate", "Rüstungs-Spiegel nicht.")
	assert_eq(out["hat"], "none", "Auch kein Hut per Look-Update.")

func test_editor_fields_exclude_all_worn_fields() -> void:
	for f in CharacterLook.editor_fields():
		assert_false(bool((f as Dictionary).get("worn", false)))
	assert_eq(CharacterLook.editor_fields().size() + CharacterLook.worn_keys().size(), CharacterLook.FIELDS.size())

# res://tests/unit/test_npc_look.gd
extends GutTest

## Tests für NPCLook (Presets/Zufallslook) und den neuen NPCVisualBuilder.

func test_every_preset_resolves_to_a_fully_valid_look() -> void:
	for entry in NPCLook.PRESETS:
		var name_word: String = String(((entry as Dictionary)["words"] as Array)[0])
		var spec := NPCLook.resolve(name_word)
		assert_eq(spec["look"], CharacterLook.sanitize(spec["look"]), "Preset '%s' liefert keinen gültigen Look." % name_word)

func test_preset_fields_are_valid_catalog_ids() -> void:
	# sanitize() würde ungültige IDs STILL durch Defaults ersetzen → Tippfehler im Preset
	# fielen sonst nie auf. Hier direkt gegen den Katalog prüfen.
	for entry in NPCLook.PRESETS:
		var look: Dictionary = (entry as Dictionary)["look"]
		for key in look.keys():
			assert_true(String(look[key]) in CharacterLook.option_ids(String(key)), "Preset %s: '%s' ist keine gültige ID für '%s'." % [(entry as Dictionary)["words"], look[key], key])

func test_find_preset_matches_whole_words_only() -> void:
	assert_false(NPCLook.find_preset("Waldläufer Erik").is_empty())
	assert_true(NPCLook.find_preset("Erikson").is_empty(), "Teilwort darf nicht matchen.")

func test_two_miras_get_different_looks() -> void:
	var a := NPCLook.resolve("Bergarbeiterin Mira")
	var b := NPCLook.resolve("Wegweiser Mira")
	assert_ne(a["look"], b["look"])

func test_unknown_name_gets_deterministic_random_look() -> void:
	var a := NPCLook.resolve("Fremder Wanderer")
	var b := NPCLook.resolve("Fremder Wanderer")
	var c := NPCLook.resolve("Anderer Wanderer")
	assert_eq(a["look"], b["look"])
	assert_ne(a["look"], c["look"])

func test_explicit_look_overrides_single_fields() -> void:
	var spec := NPCLook.resolve("Waldläufer Erik", NPCLook.DEFAULT_BODY_COLOR, {"hair_style": "bald", "bogus": "x"})
	assert_eq(spec["look"]["hair_style"], "bald")
	assert_false((spec["look"] as Dictionary).has("bogus"))

func test_non_default_body_color_becomes_shirt_override() -> void:
	var spec := NPCLook.resolve("Händler Toma", Color(0.1, 0.5, 0.2))
	assert_eq(spec["overrides"]["shirt_color"], Color(0.1, 0.5, 0.2))
	var plain := NPCLook.resolve("Händler Toma")
	assert_false((plain["overrides"] as Dictionary).has("shirt_color"))

func test_builder_keeps_signature_and_returns_hidden_dialog_label() -> void:
	var parent: Node3D = add_child_autofree(Node3D.new())
	var lbl := NPCVisualBuilder.build(parent, "Dorfbewohner")
	assert_not_null(lbl)
	assert_false(lbl.visible)
	assert_eq(lbl.text, "")

func test_builder_creates_body_head_and_gaze() -> void:
	var parent: Node3D = add_child_autofree(Node3D.new())
	NPCVisualBuilder.build(parent, "Waldläufer Erik", Color(0.2, 0.4, 0.2))
	var visual := parent.get_node_or_null("Visual")
	assert_not_null(visual)
	assert_not_null(visual.get_node_or_null("Parts/Head/Face/EyeR"))
	assert_not_null(visual.get_node_or_null("Parts/LegR"))
	var gaze := visual.get_node_or_null("Gaze") as CharacterGaze
	assert_not_null(gaze)
	assert_true(gaze.is_bound())
	assert_eq(gaze.owner_exclude, parent)

func test_builder_name_label_sits_above_tall_figure() -> void:
	var parent: Node3D = add_child_autofree(Node3D.new())
	NPCVisualBuilder.build(parent, "Wächterin Talia")
	var labels := parent.get_children().filter(func(c: Node) -> bool: return c is Label3D)
	assert_eq(labels.size(), 2)
	assert_true((labels[0] as Label3D).position.y >= 2.3)

# ─────────────────────────────────────────────
# NPCProps (Requisiten / Zubehör / Geister-Look)
# ─────────────────────────────────────────────

func test_preset_props_and_extras_are_known_ids() -> void:
	for entry in NPCLook.PRESETS:
		var e := entry as Dictionary
		if e.has("prop"):
			assert_true(String(e["prop"]) in NPCProps.PROP_IDS, "Unbekanntes prop in %s." % [e["words"]])
		for x in (e.get("extras", []) as Array):
			assert_true(String(x) in NPCProps.EXTRA_IDS, "Unbekanntes extra '%s' in %s." % [x, e["words"]])

func test_every_prop_and_extra_builds_without_error() -> void:
	for prop_id in NPCProps.PROP_IDS:
		var parts := CharacterPartBuilder.build(CharacterLook.default_look())
		autofree(parts["root"])
		NPCProps.apply(parts, CharacterLook.default_look(), {"prop": prop_id, "extras": NPCProps.EXTRA_IDS, "cape": Color(0.4, 0.2, 0.2)})
		var arm_name := "arm_l" if prop_id in NPCProps.LEFT_HAND_PROPS else "arm_r"
		assert_not_null((parts[arm_name] as Node3D).get_node_or_null("Prop_" + String(prop_id)), "Requisit '%s' fehlt." % prop_id)

func test_axe_is_held_in_right_hand_and_arm_is_raised_forward() -> void:
	var parent: Node3D = add_child_autofree(Node3D.new())
	NPCVisualBuilder.build(parent, "Waldläufer Erik")
	var arm := parent.get_node("Visual/Parts/ArmR") as Node3D
	assert_not_null(arm.get_node_or_null("Prop_axe"))
	assert_true(arm.rotation.x < 0.0, "Arm soll nach vorn angehoben sein.")

func test_quest_npcs_have_signature_gear() -> void:
	var expect := {
		"Bergarbeiterin Mira": "Prop_pickaxe",
		"Wächterin Talia": "Prop_spear",
		"Kräuterkundige Senna": "Prop_basket",
		"Bankier Aurelius": "Prop_ledger",
		"Förster Holgar": "Prop_sapling",
	}
	for npc_name in expect.keys():
		var parent: Node3D = add_child_autofree(Node3D.new())
		NPCVisualBuilder.build(parent, String(npc_name))
		assert_not_null(parent.find_child(String(expect[npc_name]), true, false), "%s trägt nicht %s." % [npc_name, expect[npc_name]])

func test_miner_wears_hardhat_guard_wears_helm_banker_wears_tophat() -> void:
	var cases := {"Bergarbeiterin Mira": "Lamp", "Wächterin Talia": "NoseGuard", "Bankier Aurelius": "Crown"}
	for npc_name in cases.keys():
		var parent: Node3D = add_child_autofree(Node3D.new())
		NPCVisualBuilder.build(parent, String(npc_name))
		assert_not_null(parent.find_child(String(cases[npc_name]), true, false), "%s: Kopfbedeckung fehlt." % npc_name)

func test_ghost_is_translucent_and_hovers() -> void:
	var parent: Node3D = add_child_autofree(Node3D.new())
	NPCVisualBuilder.build(parent, "Ahnengeist Babatunde")
	var visual := parent.get_node("Visual") as Node3D
	assert_true(visual.position.y > 0.05, "Geist soll schweben.")
	var torso := visual.get_node("Parts/Torso") as MeshInstance3D
	var mat := torso.material_override as StandardMaterial3D
	assert_eq(mat.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_true(mat.albedo_color.a < 1.0)

func test_non_ghost_stays_opaque_and_grounded() -> void:
	var parent: Node3D = add_child_autofree(Node3D.new())
	NPCVisualBuilder.build(parent, "Waldläufer Erik")
	var visual := parent.get_node("Visual") as Node3D
	assert_almost_eq(visual.position.y, 0.0, 0.0001)
	var mat := (visual.get_node("Parts/Torso") as MeshInstance3D).material_override as StandardMaterial3D
	assert_eq(mat.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED)

func test_elder_wears_cape_and_merchant_wears_backpack() -> void:
	var elder: Node3D = add_child_autofree(Node3D.new())
	NPCVisualBuilder.build(elder, "Dorfältester Rasmus")
	assert_not_null(elder.find_child("Cape", true, false))
	var merchant: Node3D = add_child_autofree(Node3D.new())
	NPCVisualBuilder.build(merchant, "Händler Toma")
	assert_not_null(merchant.find_child("Backpack", true, false))

func test_npc_without_preset_has_no_props() -> void:
	var spec := NPCLook.resolve("Fremder Wanderer")
	assert_eq(spec["prop"], "")
	assert_true((spec["extras"] as Array).is_empty())
	assert_null(spec["cape"])

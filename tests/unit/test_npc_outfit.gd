# res://tests/unit/test_npc_outfit.gd
extends GutTest

## Tests für echte Kleidung bei NPCs: NPCVisualBuilder.wear()/take_off()/get_outfit().

func _npc(display_name: String) -> Node3D:
	var parent: Node3D = add_child_autofree(Node3D.new())
	NPCVisualBuilder.build(parent, display_name)
	return parent

func test_npc_outfit_lists_clothing_as_real_item_ids() -> void:
	var npc := _npc("Dorfältester Rasmus")
	var outfit := NPCVisualBuilder.get_outfit(npc)
	assert_eq(outfit["back"], "cl_back_cape_green")
	assert_true(outfit.has("shirt") and outfit.has("pants") and outfit.has("shoes"))
	for slot in outfit.keys():
		assert_true(WearableCatalog.is_wearable_id(String(outfit[slot])) or WearableCatalog.armor_slot_of_id(String(outfit[slot])) != "",
			"'%s' im Slot '%s' ist kein echtes Item." % [outfit[slot], slot])

func test_guard_talia_wears_real_helmet_and_pauldrons() -> void:
	var outfit := NPCVisualBuilder.get_outfit(_npc("Wächterin Talia"))
	assert_eq(outfit["helmet"], "steel_helmet")
	assert_eq(outfit["shoulders"], "cl_shoulders_steel")

func test_take_off_removes_the_visible_piece() -> void:
	var npc := _npc("Dorfältester Rasmus")
	assert_not_null(npc.find_child("Cape", true, false))
	assert_true(NPCVisualBuilder.take_off(npc, "back"))
	assert_null(npc.find_child("Cape", true, false), "Umhang muss weg sein.")
	assert_false(NPCVisualBuilder.get_outfit(npc).has("back"))

func test_wear_puts_the_piece_on() -> void:
	var npc := _npc("Waldläufer Erik")
	assert_null(npc.find_child("Cape", true, false))
	assert_true(NPCVisualBuilder.wear(npc, "cl_back_cape_red"))
	assert_not_null(npc.find_child("Cape", true, false))
	assert_eq(NPCVisualBuilder.get_outfit(npc)["back"], "cl_back_cape_red")

func test_wear_replaces_what_is_in_the_same_slot() -> void:
	var npc := _npc("Waldläufer Erik")
	NPCVisualBuilder.wear(npc, "cl_shirt_red_vest")
	NPCVisualBuilder.wear(npc, "cl_shirt_teal_tunic")
	assert_eq(NPCVisualBuilder.get_outfit(npc)["shirt"], "cl_shirt_teal_tunic")

func test_npc_without_shirt_shows_bare_skin() -> void:
	var npc := _npc("Dorfältester Rasmus")
	NPCVisualBuilder.take_off(npc, "shirt")
	var torso := npc.find_child("Torso", true, false) as MeshInstance3D
	var skin := CharacterLook.color_of("skin", String(NPCLook.resolve("Dorfältester Rasmus")["look"]["skin"]))
	assert_eq((torso.material_override as StandardMaterial3D).albedo_color, skin)

func test_npc_can_wear_armor_by_id() -> void:
	var npc := _npc("Waldläufer Erik")
	assert_true(NPCVisualBuilder.wear(npc, "iron_chestplate"))
	assert_not_null(npc.find_child("ArmorChest", true, false))
	assert_eq(NPCVisualBuilder.get_outfit(npc)["chest"], "iron_chestplate")
	assert_true(NPCVisualBuilder.take_off(npc, "chest"))
	assert_null(npc.find_child("ArmorChest", true, false))

func test_visual_node_keeps_its_name_after_rebuild() -> void:
	var npc := _npc("Waldläufer Erik")
	NPCVisualBuilder.wear(npc, "cl_hat_cap_blue")
	NPCVisualBuilder.take_off(npc, "hat")
	var count := 0
	for c in npc.get_children():
		if c.name == "Visual":
			count += 1
	assert_eq(count, 1, "Genau ein Knoten 'Visual' (alter wurde vorher entfernt).")
	assert_not_null(npc.get_node_or_null("Visual"))

func test_invalid_requests_return_false() -> void:
	var npc := _npc("Waldläufer Erik")
	assert_false(NPCVisualBuilder.wear(npc, "not_an_item"))
	assert_false(NPCVisualBuilder.take_off(npc, "back"), "Leerer Slot.")
	assert_false(NPCVisualBuilder.take_off(npc, "not_a_slot"))
	var plain: Node3D = add_child_autofree(Node3D.new())
	assert_false(NPCVisualBuilder.wear(plain, "cl_hat_cap_blue"), "Kein per build() erzeugter NPC.")
	assert_true(NPCVisualBuilder.get_outfit(plain).is_empty())

func test_ghost_keeps_cape_semi_transparent() -> void:
	var npc := _npc("Ahnengeist Babatunde")
	var panel := npc.find_child("Panel", true, false) as MeshInstance3D
	assert_not_null(panel, "Der Geist trägt seinen Umhang.")
	assert_lt(((panel.material_override) as StandardMaterial3D).albedo_color.a, 1.0)

# res://tests/unit/test_nest_content.gd
extends GutTest

## Konsistenz-Tests für die Nest-Objekte + ihre NPCs (docs/nests.md).
##
## Warum: Wie bei den Hain-Skills hängt ein Nest nur über Strings zusammen (Objekt-Typ <->
## KNOWN_PROP_TYPES <-> register_all() <-> Biom <-> Respawn <-> LootTable <-> Item <-> Skill),
## und jeder Nest-NPC zusätzlich über Quest-IDs/Ziel-Items/Spawn. Fehlt ein Glied, bricht nichts
## laut — das Objekt spawnt nie, die XP verpuffen oder die Quest ist unlösbar. Diese Tests machen
## die stillen Lücken laut. Der Bienenstock (wild_beehive) ist bereits in
## test_hain_skill_content.gd abgedeckt; hier nur sein NPC (Zeidlerin Gerlinde).
##
## Kein SceneTree für die Objekt-Tests nötig (nur instanziiert, kein add_child).

const BIOME_IDS: Array[String] = [
	"forest", "dense_forest", "meadow", "desert", "winter", "swamp", "mountain", "dead_forest"
]

## type_id -> { script, skill, loot_item }
const NEST_OBJECTS: Dictionary = {
	"ant_hill":      {"script": "res://scripts/world/objects/AntHill.gd",      "skill": "entomology", "loot_item": "formic_acid"},
	"termite_mound": {"script": "res://scripts/world/objects/TermiteMound.gd", "skill": "entomology", "loot_item": "termite_clay"},
	"mole_hill":     {"script": "res://scripts/world/objects/MoleHill.gd",     "skill": "digging",    "loot_item": "molehill_soil"},
	"wasp_nest":     {"script": "res://scripts/world/objects/WaspNest.gd",     "skill": "entomology", "loot_item": "wasp_paper"},
	"hornet_nest":   {"script": "res://scripts/world/objects/HornetNest.gd",   "skill": "entomology", "loot_item": "hornet_paper"},
}

## entity_type -> { class, npc_id, quest1, quest2 }
const NEST_NPCS: Dictionary = {
	"myrmex_npc":        {"npc_id": "myrmex_ant",       "quest1": "quest_myrmex_acid",     "quest2": "quest_myrmex_scholar"},
	"rudo_builder_npc":  {"npc_id": "rudo_builder",     "quest1": "quest_rudo_clay",       "quest2": "quest_rudo_wall"},
	"surveyor_npc":      {"npc_id": "lucius_surveyor",  "quest1": "quest_lucius_boundary", "quest2": "quest_lucius_survey"},
	"zeidler_npc":       {"npc_id": "gerlinde_zeidler", "quest1": "quest_gerlinde_combs",  "quest2": "quest_gerlinde_master"},
	"papermaker_npc":    {"npc_id": "lian_paper",       "quest1": "quest_lian_wasp_paper", "quest2": "quest_lian_fibre"},
	"hornet_oracle_npc": {"npc_id": "sigrun_oracle",    "quest1": "quest_sigrun_myth",     "quest2": "quest_sigrun_scholar"},
}

var _bus: MockEventBus

func before_each() -> void:
	_bus = MockEventBus.new()

# ─────────────────────────────────────────────
# Helfer
# ─────────────────────────────────────────────

func _manifest_skill_ids() -> Array[String]:
	var ids: Array[String] = []
	for path: String in DataManifest.SKILLS:
		var def := load(path) as SkillDefinition
		if def != null:
			ids.append(def.id)
	return ids

func _manifest_item_ids() -> Array[String]:
	var ids: Array[String] = []
	for path: String in DataManifest.ITEMS:
		var item := load(path) as ItemDefinition
		if item != null:
			ids.append(item.id)
	return ids

func _manifest_quest(quest_id: String) -> QuestDefinition:
	for path: String in DataManifest.QUESTS:
		var q := load(path) as QuestDefinition
		if q != null and q.id == quest_id:
			return q
	return null

# ─────────────────────────────────────────────
# Objekte: XP-Quelle <-> Skill <-> Loot <-> Item
# ─────────────────────────────────────────────

func test_nest_objects_xp_type_is_a_registered_skill() -> void:
	var skill_ids := _manifest_skill_ids()
	for type_id: String in NEST_OBJECTS:
		var entity: HarvestableEntity = autofree(load(NEST_OBJECTS[type_id]["script"]).new())
		assert_eq(entity._get_entity_type_id(), type_id, "type_id von %s" % type_id)
		var d: InteractableData = entity._build_interactable_data()
		assert_eq(d.xp_type, NEST_OBJECTS[type_id]["skill"], "%s: xp_type" % type_id)
		assert_true(d.xp_type in skill_ids, "%s: xp_type '%s' ist kein registrierter Skill" % [type_id, d.xp_type])
		assert_gt(d.xp_amount, 0, "%s: xp_amount muss > 0 sein" % type_id)
		assert_false(d.label.is_empty(), "%s: label fehlt" % type_id)
		assert_true(d.id.begins_with("harvest_"), "%s: Interaktions-id folgt 'harvest_<objekttyp>'" % type_id)
		assert_true(d.inspect_text.contains("Wusstest du?"), "%s: inspect_text trägt den Fakt" % type_id)

func test_nest_objects_loot_items_are_registered() -> void:
	var item_ids := _manifest_item_ids()
	for type_id: String in NEST_OBJECTS:
		var entity: HarvestableEntity = autofree(load(NEST_OBJECTS[type_id]["script"]).new())
		var d: InteractableData = entity._build_interactable_data()
		assert_not_null(d.loot_table, "%s: loot_table fehlt" % type_id)
		if d.loot_table == null:
			continue
		assert_gt(d.loot_table.entries.size(), 0, "%s: loot_table ohne Einträge" % type_id)
		var found_expected := false
		for entry: LootEntry in d.loot_table.entries:
			assert_true(entry.item_id in item_ids, "%s: Loot-Item '%s' fehlt in DataManifest.ITEMS" % [type_id, entry.item_id])
			if entry.item_id == NEST_OBJECTS[type_id]["loot_item"]:
				found_expected = true
		assert_true(found_expected, "%s: Loot muss '%s' enthalten (Quest-Zielitem)" % [type_id, NEST_OBJECTS[type_id]["loot_item"]])

func test_nest_loot_tables_are_in_manifest() -> void:
	for type_id: String in NEST_OBJECTS:
		var entity: HarvestableEntity = autofree(load(NEST_OBJECTS[type_id]["script"]).new())
		var d: InteractableData = entity._build_interactable_data()
		assert_true(d.loot_table.resource_path in DataManifest.LOOT_TABLES,
			"%s: %s fehlt in DataManifest.LOOT_TABLES" % [type_id, d.loot_table.resource_path])

func test_occupied_nest_objects_only_offer_the_abandoned_nest() -> void:
	## Schutz-Haltung (docs/nests.md): Wespen-/Hornissennester werden nur VERLASSEN geborgen.
	for type_id in ["wasp_nest", "hornet_nest"]:
		var entity: HarvestableEntity = autofree(load(NEST_OBJECTS[type_id]["script"]).new())
		var d: InteractableData = entity._build_interactable_data()
		assert_true(d.label.contains("Verlassenes"), "%s: label muss das verlassene Nest benennen" % type_id)

func test_entomology_skill_has_fact_and_xp_curve() -> void:
	var def := load("res://data/skills/entomology.tres") as SkillDefinition
	assert_not_null(def, "entomology.tres muss laden")
	if def == null:
		return
	assert_eq(def.get_xp_required(1), 100, "Level 1->2 kostet 100 XP")
	var prev := 0
	for level in range(1, 31):
		var need := def.get_xp_required(level)
		assert_gt(need, 0, "Lv %d: XP-Bedarf > 0" % level)
		assert_true(need >= prev, "Lv %d: XP-Kurve darf nicht fallen" % level)
		prev = need

# ─────────────────────────────────────────────
# Welt-Verdrahtung: KNOWN_PROP_TYPES / register_all / Biome / Respawn
# ─────────────────────────────────────────────

func test_nest_types_are_known_prop_types() -> void:
	for type_id: String in NEST_OBJECTS:
		assert_true(type_id in WorldEntityRegistry.KNOWN_PROP_TYPES,
			"%s muss in WorldEntityRegistry.KNOWN_PROP_TYPES stehen, sonst wird er still gefiltert" % type_id)

func test_nest_types_spawn_in_at_least_one_biome() -> void:
	for type_id: String in NEST_OBJECTS:
		var found := false
		for biome_id in BIOME_IDS:
			var b: BiomeDefinition = BiomeRegistry.get_biome(biome_id)
			if b.prop_chances.has(type_id):
				found = true
				assert_between(float(b.prop_chances[type_id]), 0.0001, 1.0,
					"%s in %s: Chance muss in (0, 1] liegen" % [type_id, biome_id])
		assert_true(found, "%s kommt in keinem Biom vor — würde nie spawnen" % type_id)

func test_nest_biome_mapping_matches_real_world_logic() -> void:
	# Termitenhügel nur im trocken-warmen Biom, nie im Schnee.
	assert_true(BiomeRegistry.get_biome("desert").prop_chances.has("termite_mound"), "Termitenhügel in der Wüste")
	assert_false(BiomeRegistry.get_biome("winter").prop_chances.has("termite_mound"), "kein Termitenhügel im Schnee")
	# Waldameisen: Wald, nie Wüste.
	for biome_id in ["forest", "dense_forest"]:
		assert_true(BiomeRegistry.get_biome(biome_id).prop_chances.has("ant_hill"), "Waldameisen gehören in den Wald (%s)" % biome_id)
	assert_false(BiomeRegistry.get_biome("desert").prop_chances.has("ant_hill"), "keine Waldameisen in der Wüste")
	# Maulwurf: weicher Boden (Wiese/Wald), nicht in der Wüste.
	assert_true(BiomeRegistry.get_biome("meadow").prop_chances.has("mole_hill"), "Maulwurf auf der Wiese")
	assert_false(BiomeRegistry.get_biome("desert").prop_chances.has("mole_hill"), "kein Maulwurf im Sand")
	# Hornissen brauchen Baumhöhlen.
	assert_true(BiomeRegistry.get_biome("forest").prop_chances.has("hornet_nest"), "Hornissen im Wald")
	assert_false(BiomeRegistry.get_biome("desert").prop_chances.has("hornet_nest"), "keine Hornissen in der Wüste")

func test_nest_types_have_respawn_config() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/world/core/WorldService.gd")
	assert_false(src.is_empty(), "WorldService.gd muss lesbar sein")
	for type_id: String in NEST_OBJECTS:
		assert_true(src.contains('register_config("%s"' % type_id),
			"%s: fehlende respawn.register_config() in WorldService.configure()" % type_id)

# ─────────────────────────────────────────────
# NPCs: Registrierung, Spawn, Quests, Dialogbaum
# ─────────────────────────────────────────────

func test_nest_npcs_are_registered_and_spawned() -> void:
	var reg := FileAccess.get_file_as_string("res://scripts/world/core/WorldEntityRegistry.gd")
	var spawner := FileAccess.get_file_as_string("res://scripts/world/core/WorldSpawner.gd")
	for type_id: String in NEST_NPCS:
		assert_true(reg.contains('register_definition("%s"' % type_id), "%s: nicht in WorldEntityRegistry registriert" % type_id)
		assert_true(spawner.contains('spawn_entity("%s"' % type_id), "%s: wird in WorldSpawner nie gespawnt" % type_id)

func test_nest_npc_quests_exist_and_chain() -> void:
	var item_ids := _manifest_item_ids()
	var skill_ids := _manifest_skill_ids()
	for type_id: String in NEST_NPCS:
		var q1 := _manifest_quest(NEST_NPCS[type_id]["quest1"])
		var q2 := _manifest_quest(NEST_NPCS[type_id]["quest2"])
		assert_not_null(q1, "%s: quest1 fehlt in DataManifest.QUESTS" % type_id)
		assert_not_null(q2, "%s: quest2 fehlt in DataManifest.QUESTS" % type_id)
		if q1 == null or q2 == null:
			continue
		assert_true(NEST_NPCS[type_id]["quest1"] in q2.prerequisites, "%s: quest2 muss quest1 voraussetzen" % type_id)
		for q: QuestDefinition in [q1, q2]:
			assert_gt(q.objectives.size(), 0, "%s: Quest ohne Objectives" % q.id)
			for obj: QuestObjective in q.objectives:
				if obj.type == QuestObjective.Type.COLLECT:
					assert_true(obj.target_id in item_ids, "%s: COLLECT-Ziel '%s' ist kein registriertes Item" % [q.id, obj.target_id])
				elif obj.type == QuestObjective.Type.SKILL:
					assert_true(obj.target_id in skill_ids, "%s: SKILL-Ziel '%s' ist kein registrierter Skill" % [q.id, obj.target_id])
			for skill_id: String in q.reward.xp_rewards:
				assert_true(skill_id in skill_ids, "%s: Belohnungs-Skill '%s' unbekannt" % [q.id, skill_id])

func test_nest_quest_collect_targets_are_obtainable_from_nests() -> void:
	## Jede Nest-Quest der Stufe 1 muss mit dem Loot ihres Nests lösbar sein.
	var obtainable := {"formic_acid": true, "termite_clay": true, "molehill_soil": true,
		"wasp_paper": true, "hornet_paper": true, "honeycomb": true}
	for type_id: String in NEST_NPCS:
		var q1 := _manifest_quest(NEST_NPCS[type_id]["quest1"])
		if q1 == null:
			continue
		for obj: QuestObjective in q1.objectives:
			assert_true(obtainable.has(obj.target_id), "%s: Stufe-1-Ziel '%s' ist kein Nest-Loot" % [q1.id, obj.target_id])

func _spawn(npc: QuestNPC) -> QuestNPC:
	add_child_autofree(npc)
	var ctx := EntityContext.for_test()
	ctx._bus = _bus
	npc.on_spawn({}, ctx)
	return npc

func _assert_uses_tree(npc: QuestNPC, expected_npc_id: String) -> void:
	assert_eq(npc.npc_id, expected_npc_id)
	assert_not_null(npc._dialogue_tree, "%s muss _build_dialogue_tree() überschreiben" % expected_npc_id)

func test_myrmex_npc_uses_dialogue_tree() -> void:
	_assert_uses_tree(_spawn(MyrmexNPC.new()), "myrmex_ant")

func test_rudo_builder_npc_uses_dialogue_tree() -> void:
	_assert_uses_tree(_spawn(RudoBuilderNPC.new()), "rudo_builder")

func test_surveyor_npc_uses_dialogue_tree() -> void:
	_assert_uses_tree(_spawn(SurveyorNPC.new()), "lucius_surveyor")

func test_zeidler_npc_uses_dialogue_tree() -> void:
	_assert_uses_tree(_spawn(ZeidlerNPC.new()), "gerlinde_zeidler")

func test_papermaker_npc_uses_dialogue_tree() -> void:
	_assert_uses_tree(_spawn(PapermakerNPC.new()), "lian_paper")

func test_hornet_oracle_npc_uses_dialogue_tree() -> void:
	_assert_uses_tree(_spawn(HornetOracleNPC.new()), "sigrun_oracle")

func test_nest_npc_ids_match_test_table() -> void:
	var classes := {"myrmex_npc": MyrmexNPC, "rudo_builder_npc": RudoBuilderNPC, "surveyor_npc": SurveyorNPC,
		"zeidler_npc": ZeidlerNPC, "papermaker_npc": PapermakerNPC, "hornet_oracle_npc": HornetOracleNPC}
	for type_id: String in NEST_NPCS:
		var npc: QuestNPC = autofree(classes[type_id].new())
		assert_eq(npc.npc_id, NEST_NPCS[type_id]["npc_id"], "%s: npc_id" % type_id)
		assert_eq(npc.quest_id, "", "%s: kein Slot-System mehr" % type_id)

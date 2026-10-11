# res://tests/unit/test_hain_skill_content.gd
extends GutTest

## Konsistenz-Tests für Skill-Content (siehe docs/skill-writing-guide.md).
##
## Warum: Ein Skill besteht aus mehreren Teilen, die nur über Strings zusammenhängen
## (Skill-.tres <-> DataManifest.SKILLS <-> xp_type im Weltobjekt <-> LootTable <-> Item <->
## KNOWN_PROP_TYPES <-> register_all() <-> BiomeRegistry <-> Respawn-Config). Fehlt ein Glied,
## bricht nichts laut — die XP verpuffen still (so war "digging" jahrelang unsichtbar: .tres
## vorhanden, aber nicht im Manifest -> "Unbekannter Skill"). Diese Tests machen die stillen
## Lücken laut.
##
## Abgedeckt:
##   - JEDE data/skills/*.tres ist in DataManifest.SKILLS registriert (Regression: digging)
##   - Alle Manifest-Skills laden, haben eindeutige ids, Beschreibung mit "Wusstest du?"
##   - Die 5 Hain-Objekte: xp_type == registrierter Skill, LootTable -> registriertes Item,
##     Typ in KNOWN_PROP_TYPES + register_all() + mind. einem Biom + Respawn-Config
##   - XP-Kurve der Hain-Skills: > 0 und monoton nicht fallend
##
## Kein SceneTree nötig; die Objekte werden nur instanziiert (kein add_child), _ready() läuft nicht.

const SKILLS_DIR := "res://data/skills"

## type_id -> { script, skill }
const HAIN_OBJECTS: Dictionary = {
	"fulgurite":     {"script": "res://scripts/world/objects/Fulgurite.gd",    "skill": "stormlore"},
	"wild_beehive":  {"script": "res://scripts/world/objects/WildBeehive.gd",  "skill": "beekeeping"},
	"meteorite":     {"script": "res://scripts/world/objects/Meteorite.gd",    "skill": "stargazing"},
	"sulfur_crust":  {"script": "res://scripts/world/objects/SulfurCrust.gd",  "skill": "alchemy"},
	"charcoal_kiln": {"script": "res://scripts/world/objects/CharcoalKiln.gd", "skill": "charcoal_burning"},
}

const BIOME_IDS: Array[String] = [
	"forest", "dense_forest", "meadow", "desert", "winter", "swamp", "mountain", "dead_forest"
]

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

# ─────────────────────────────────────────────
# Skill-Registrierung (Regression: "digging" fehlte im Manifest)
# ─────────────────────────────────────────────

func test_every_skill_tres_file_is_registered_in_manifest() -> void:
	var files := DirAccess.get_files_at(SKILLS_DIR)
	assert_gt(files.size(), 0, "data/skills/ muss .tres-Dateien enthalten")
	for f: String in files:
		if not f.ends_with(".tres"):
			continue
		var res_path := "%s/%s" % [SKILLS_DIR, f]
		assert_true(res_path in DataManifest.SKILLS,
			"%s existiert, fehlt aber in DataManifest.SKILLS — XP würden als 'Unbekannter Skill' verworfen" % res_path)

func test_every_manifest_skill_loads_with_unique_id() -> void:
	var seen: Dictionary = {}
	for path: String in DataManifest.SKILLS:
		var def := load(path) as SkillDefinition
		assert_not_null(def, "%s muss als SkillDefinition ladbar sein" % path)
		if def == null:
			continue
		assert_false(def.id.is_empty(), "%s: id darf nicht leer sein" % path)
		assert_false(seen.has(def.id), "Skill-id '%s' ist doppelt vergeben" % def.id)
		seen[def.id] = true
		assert_eq(path.get_file().get_basename(), def.id,
			"Dateiname muss der id entsprechen (%s)" % path)

func test_skill_descriptions_follow_two_layer_rule() -> void:
	## Zwei-Ebenen-Regel (docs/skill-writing-guide.md, Abschnitt 2): Magie-Satz + "Wusstest du?"-Fakt.
	for path: String in DataManifest.SKILLS:
		var def := load(path) as SkillDefinition
		if def == null:
			continue
		assert_true(def.description.contains("Wusstest du?"),
			"Skill '%s': description braucht den Fakt-Teil 'Wusstest du?'" % def.id)
		assert_false(def.display_name.is_empty(), "Skill '%s': display_name fehlt" % def.id)

# ─────────────────────────────────────────────
# Hain-Objekte: XP-Quelle <-> Skill <-> Loot <-> Item
# ─────────────────────────────────────────────

func test_hain_objects_xp_type_is_a_registered_skill() -> void:
	var skill_ids := _manifest_skill_ids()
	for type_id: String in HAIN_OBJECTS:
		var entity: HarvestableEntity = autofree(load(HAIN_OBJECTS[type_id]["script"]).new())
		assert_eq(entity._get_entity_type_id(), type_id, "type_id von %s" % type_id)
		var d: InteractableData = entity._build_interactable_data()
		assert_eq(d.xp_type, HAIN_OBJECTS[type_id]["skill"], "%s: xp_type" % type_id)
		assert_true(d.xp_type in skill_ids,
			"%s: xp_type '%s' ist kein in DataManifest.SKILLS registrierter Skill" % [type_id, d.xp_type])
		assert_gt(d.xp_amount, 0, "%s: xp_amount muss > 0 sein" % type_id)
		assert_false(d.label.is_empty(), "%s: label fehlt" % type_id)
		assert_true(d.id.begins_with("harvest_"), "%s: Interaktions-id folgt '<verb>_<objekttyp>'" % type_id)
		assert_true(d.inspect_text.contains("Wusstest du?"), "%s: inspect_text trägt den Fakt" % type_id)

func test_hain_objects_loot_items_are_registered() -> void:
	var item_ids := _manifest_item_ids()
	for type_id: String in HAIN_OBJECTS:
		var entity: HarvestableEntity = autofree(load(HAIN_OBJECTS[type_id]["script"]).new())
		var d: InteractableData = entity._build_interactable_data()
		assert_not_null(d.loot_table, "%s: loot_table fehlt" % type_id)
		if d.loot_table == null:
			continue
		assert_gt(d.loot_table.entries.size(), 0, "%s: loot_table ohne Einträge" % type_id)
		for entry: LootEntry in d.loot_table.entries:
			assert_true(entry.item_id in item_ids,
				"%s: Loot-Item '%s' fehlt in DataManifest.ITEMS" % [type_id, entry.item_id])
			assert_true(entry.quantity_min >= 1 and entry.quantity_max >= entry.quantity_min,
				"%s: quantity_min/max unplausibel" % type_id)

# ─────────────────────────────────────────────
# Welt-Verdrahtung: KNOWN_PROP_TYPES / register_all / Biome / Respawn
# ─────────────────────────────────────────────

func test_hain_types_are_known_prop_types() -> void:
	for type_id: String in HAIN_OBJECTS:
		assert_true(type_id in WorldEntityRegistry.KNOWN_PROP_TYPES,
			"%s muss in WorldEntityRegistry.KNOWN_PROP_TYPES stehen, sonst wird er still gefiltert" % type_id)

func test_known_prop_types_are_all_registered_in_register_all() -> void:
	## KNOWN_PROP_TYPES und register_all() müssen synchron bleiben (kein automatischer Abgleich,
	## siehe WorldEntityRegistry-Klassenkommentar) — hier als statischer Quelltext-Check.
	var src := FileAccess.get_file_as_string("res://scripts/world/core/WorldEntityRegistry.gd")
	assert_false(src.is_empty(), "WorldEntityRegistry.gd muss lesbar sein")
	for type_id: String in WorldEntityRegistry.KNOWN_PROP_TYPES:
		assert_true(src.contains('register_definition("%s"' % type_id),
			"%s steht in KNOWN_PROP_TYPES, aber register_all() registriert ihn nicht" % type_id)

func test_hain_types_spawn_in_at_least_one_biome() -> void:
	for type_id: String in HAIN_OBJECTS:
		var found := false
		for biome_id in BIOME_IDS:
			var b: BiomeDefinition = BiomeRegistry.get_biome(biome_id)
			if b.prop_chances.has(type_id):
				found = true
				assert_between(float(b.prop_chances[type_id]), 0.0001, 1.0,
					"%s in %s: Chance muss in (0, 1] liegen" % [type_id, biome_id])
		assert_true(found, "%s kommt in keinem Biom vor — würde nie spawnen" % type_id)

func test_hain_biome_mapping_matches_real_world_logic() -> void:
	## Bewusste Fach-Zuordnung (Bildungsanspruch): Blitzglas nur im Sand, Meiler nur im Wald.
	assert_true(BiomeRegistry.get_biome("desert").prop_chances.has("fulgurite"), "Fulgurit entsteht in Sand")
	for biome_id in ["forest", "dense_forest"]:
		assert_true(BiomeRegistry.get_biome(biome_id).prop_chances.has("charcoal_kiln"),
			"Kohlenmeiler gehört in den Wald (%s)" % biome_id)
	assert_false(BiomeRegistry.get_biome("desert").prop_chances.has("charcoal_kiln"), "kein Meiler in der Wüste")
	assert_false(BiomeRegistry.get_biome("winter").prop_chances.has("fulgurite"), "kein Blitzglas im Schnee")

func test_hain_types_have_respawn_config() -> void:
	## Ohne register_config() wäre jede Interaktion einmalig (RespawnService bricht sonst ab).
	var src := FileAccess.get_file_as_string("res://scripts/world/core/WorldService.gd")
	assert_false(src.is_empty(), "WorldService.gd muss lesbar sein")
	for type_id: String in HAIN_OBJECTS:
		assert_true(src.contains('register_config("%s"' % type_id),
			"%s: fehlende respawn.register_config() in WorldService.configure()" % type_id)

# ─────────────────────────────────────────────
# XP-Kurve der Hain-Skills
# ─────────────────────────────────────────────

func test_hain_skill_xp_curve_is_positive_and_monotonic() -> void:
	for type_id: String in HAIN_OBJECTS:
		var def := load("res://data/skills/%s.tres" % HAIN_OBJECTS[type_id]["skill"]) as SkillDefinition
		assert_not_null(def, "%s: Skill-Resource" % type_id)
		if def == null:
			continue
		assert_eq(def.get_xp_required(1), 100, "%s: Level 1->2 kostet 100 XP" % def.id)
		var prev := 0
		for level in range(1, 31):
			var need := def.get_xp_required(level)
			assert_gt(need, 0, "%s Lv %d: XP-Bedarf muss > 0 sein" % [def.id, level])
			assert_true(need >= prev, "%s Lv %d: XP-Kurve darf nicht fallen" % [def.id, level])
			prev = need

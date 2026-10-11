# res://tests/unit/test_animal_species_db.gd
extends GutTest

## Unit-Tests für AnimalSpeciesDB (reine Daten, AUTO-GENERIERT — siehe dortigen
## Kopfkommentar). Prüft die Invarianten, auf die sich GenericAnimal.gd und
## ChunkEntitySpawner verlassen, OHNE jeden der 39+ Einträge einzeln aufzuzählen (das wäre
## exakt die Art manueller Pflege, die AnimalSpeciesDB vermeiden soll).

## Dieselben zehn IDs wie ChunkEntitySpawner.CURATED_LAND_ANIMAL_TYPES/CURATED_FISH_TYPES —
## AnimalSpeciesDB darf keine davon doppelt vergeben (siehe WorldEntityRegistry-Kommentar).
const CURATED_IDS: Array[String] = ["deer", "rabbit", "boar", "fox", "squirrel", "sheep", "bee", "spider", "snake", "bear", "fish"]

const REQUIRED_KEYS: Array[String] = [
	"display_name", "inspect_text", "color", "body_size", "speed", "flee_radius",
	"idle_time", "wander_range", "ear_style", "tail_style", "snout_style",
	"headgear_style", "tail_scale", "body_plan", "wing_style", "back_style",
	"body_shape", "leg_style", "pattern_style", "pattern_color", "accent_style", "aquatic",
]

func test_species_db_is_not_empty() -> void:
	assert_gt(AnimalSpeciesDB.SPECIES.size(), 0)

func test_species_ids_are_lowercase_identifiers() -> void:
	# Ein "_" in der ID ist erlaubt ("wolf_spider", "grass_snake"): GenericAnimal liest die ID aus
	# dem Meta "entity_type" (vom EntityOrchestrator gesetzt), nicht mehr aus dem Node-Namen — siehe
	# test_generic_animal.gd. Erlaubt sind nur a-z, 0-9 und "_" (die ID steckt in Node-Namen,
	# Quest-Signalen "caught_<id>" und Pet-Saves).
	var rx := RegEx.new()
	rx.compile("^[a-z][a-z0-9_]*$")
	for id: String in AnimalSpeciesDB.SPECIES:
		assert_not_null(rx.search(id), "species_id '%s' ist kein gültiger Bezeichner" % id)

func test_no_species_id_collides_with_curated_animals() -> void:
	for id: String in AnimalSpeciesDB.SPECIES:
		assert_false(id in CURATED_IDS, "species_id '%s' kollidiert mit einer handgeschriebenen Tierart" % id)

func test_every_entry_has_all_required_keys() -> void:
	for id: String in AnimalSpeciesDB.SPECIES:
		var def: Dictionary = AnimalSpeciesDB.SPECIES[id]
		for key in REQUIRED_KEYS:
			assert_true(def.has(key), "'%s' fehlt Feld '%s'" % [id, key])

func test_every_entry_has_sane_value_types_and_ranges() -> void:
	for id: String in AnimalSpeciesDB.SPECIES:
		var def: Dictionary = AnimalSpeciesDB.SPECIES[id]
		assert_true(def["color"] is Color, id)
		assert_true(def["body_size"] is Vector3, id)
		assert_gt(float(def["speed"]), 0.0, id)
		assert_gt(float(def["flee_radius"]), 0.0, id)
		var bs: Vector3 = def["body_size"]
		assert_gt(bs.x, 0.0, id)
		assert_gt(bs.y, 0.0, id)
		assert_gt(bs.z, 0.0, id)
		assert_true(def["aquatic"] is bool, id)
		assert_true(def["pattern_color"] is Color, id)

func test_patterned_entries_use_quadruped_body_plan() -> void:
	# pattern_style wirkt nur auf QUADRUPED (siehe AnimalVisualBuilder._build_body_material()-
	# Kommentar) — ein Eintrag mit Muster auf einem anderen Bauplan wäre kein Crash, aber
	# totes Daten-Feld ohne jede sichtbare Wirkung.
	for id: String in AnimalSpeciesDB.SPECIES:
		var def: Dictionary = AnimalSpeciesDB.SPECIES[id]
		if int(def["pattern_style"]) != AnimalVisualProfile.PatternStyle.NONE:
			assert_eq(int(def["body_plan"]), AnimalVisualProfile.BodyPlan.QUADRUPED, "%s hat ein Muster, aber keinen QUADRUPED-Bauplan" % id)

func test_aquatic_entries_use_fish_body_plan() -> void:
	for id: String in AnimalSpeciesDB.SPECIES:
		var def: Dictionary = AnimalSpeciesDB.SPECIES[id]
		if def["aquatic"]:
			assert_eq(int(def["body_plan"]), AnimalVisualProfile.BodyPlan.FISH, "%s ist aquatic, aber kein FISH-Bauplan" % id)

func test_land_and_aquatic_species_ids_partition_all_species() -> void:
	var land: Array[String] = AnimalSpeciesDB.land_species_ids()
	var aquatic: Array[String] = AnimalSpeciesDB.aquatic_species_ids()
	assert_eq(land.size() + aquatic.size(), AnimalSpeciesDB.SPECIES.size())
	for id in land:
		assert_false(id in aquatic, id)

func test_has_and_get_definition() -> void:
	var any_id: String = AnimalSpeciesDB.SPECIES.keys()[0]
	assert_true(AnimalSpeciesDB.has(any_id))
	assert_false(AnimalSpeciesDB.get_definition(any_id).is_empty())
	assert_false(AnimalSpeciesDB.has("definitiv_keine_echte_art"))
	assert_true(AnimalSpeciesDB.get_definition("definitiv_keine_echte_art").is_empty())

func test_every_headgear_style_in_use_is_drawn_by_the_builder() -> void:
	# Regression ("die Tiere sehen alle gleich aus"): HORNS/BROAD_ANTLERS standen in der DB,
	# wurden vom Builder aber nie gezeichnet — Tiere mit solchem Eintrag hatten gar keinen
	# Kopfschmuck. Jede Art mit headgear_style != NONE muss jetzt wirklich Geometrie erzeugen.
	for id: String in AnimalSpeciesDB.SPECIES:
		var def: Dictionary = AnimalSpeciesDB.SPECIES[id]
		if int(def["headgear_style"]) == AnimalVisualProfile.HeadgearStyle.NONE:
			continue
		var with_gear := AnimalVisualProfile.new(def["color"], def["body_size"])
		with_gear.headgear_style = int(def["headgear_style"])
		var without_gear := AnimalVisualProfile.new(def["color"], def["body_size"])
		var root_with := AnimalVisualBuilder.build(with_gear)
		var root_without := AnimalVisualBuilder.build(without_gear)
		add_child_autofree(root_with)
		add_child_autofree(root_without)
		var head_with: Node = root_with.find_child("Head", true, false)
		var head_without: Node = root_without.find_child("Head", true, false)
		assert_gt(head_with.get_child_count(), head_without.get_child_count(), "%s: headgear_style wird nicht gezeichnet" % id)

func test_accent_style_only_set_on_plans_that_use_it() -> void:
	# accent_style bedeutet je Bauplan etwas anderes (siehe AnimalVisualProfile.AccentStyle) —
	# ein Wert, der für den eigenen Bauplan nichts bewirkt, wäre totes Datenfeld.
	const ACCENTS_BY_PLAN := {
		AnimalVisualProfile.BodyPlan.SNAKE: [AnimalVisualProfile.AccentStyle.TRIANGLE_HEAD, AnimalVisualProfile.AccentStyle.HOOD, AnimalVisualProfile.AccentStyle.RATTLE],
		AnimalVisualProfile.BodyPlan.FISH: [AnimalVisualProfile.AccentStyle.BARBELS, AnimalVisualProfile.AccentStyle.LONG_JAW, AnimalVisualProfile.AccentStyle.RIBBON],
		AnimalVisualProfile.BodyPlan.SPIDER: [AnimalVisualProfile.AccentStyle.BIG_EYES, AnimalVisualProfile.AccentStyle.ABDOMEN_MARK, AnimalVisualProfile.AccentStyle.STOUT],
		AnimalVisualProfile.BodyPlan.INSECT: [AnimalVisualProfile.AccentStyle.SPOTS, AnimalVisualProfile.AccentStyle.STRIPES],
	}
	for id: String in AnimalSpeciesDB.SPECIES:
		var def: Dictionary = AnimalSpeciesDB.SPECIES[id]
		var accent: int = int(def["accent_style"])
		if accent == AnimalVisualProfile.AccentStyle.NONE:
			continue
		var allowed: Array = ACCENTS_BY_PLAN.get(int(def["body_plan"]), [])
		assert_true(accent in allowed, "%s: accent_style %d passt nicht zum Bauplan" % [id, accent])

func test_species_of_same_plan_are_visually_distinguishable() -> void:
	# Kern des Wunschs: innerhalb eines Bauplans darf nicht fast alles identisch sein. Die
	# Form-Signatur (alles außer Farbe/Größe/Tempo) muss für die großen Gruppen mehrere
	# verschiedene Werte haben.
	for plan in [AnimalVisualProfile.BodyPlan.SNAKE, AnimalVisualProfile.BodyPlan.FISH, AnimalVisualProfile.BodyPlan.SPIDER]:
		var signatures := {}
		var members := 0
		for id: String in AnimalSpeciesDB.SPECIES:
			var def: Dictionary = AnimalSpeciesDB.SPECIES[id]
			if int(def["body_plan"]) != plan:
				continue
			members += 1
			signatures[int(def["accent_style"])] = true
		assert_gt(signatures.size(), 2, "Bauplan %d: zu wenige verschiedene Formen bei %d Arten" % [plan, members])

## tests/unit/test_chunk_entity_spawner_biome.gd
## Round 75 — Tests für ChunkEntitySpawner._roll_weighted_type(): die reine
## Auswahllogik hinter dem biom-gewichteten Prop-/Gegner-Spawning. Deckt NICHT
## ab: spawn_for_chunk()/_spawn_props()/_spawn_enemy() selbst (brauchen eine
## echte TerrainField-Instanz + spawn_entity-Callback-Verkabelung — siehe
## TODO-offene-probleme.md "Tests gegen die echte Godot/GUT-Runtime").

extends GutTest

var _spawner: ChunkEntitySpawner

func before_each() -> void:
	_spawner = ChunkEntitySpawner.new(64.0, 12345, func(_type: String, _pos: Vector3) -> void: pass)

func test_unregistered_type_is_never_selected() -> void:
	# "cactus" hat chance=1.0 (würde immer treffen), ist aber in `known` nicht
	# gelistet (kein registrierter Entity-Typ, siehe WorldEntityRegistry) —
	# muss trotzdem leer zurückkommen, nie fälschlich spawnen.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var result: String = _spawner._roll_weighted_type({"cactus": 1.0}, [], rng)
	assert_eq(result, "", "Nicht registrierter Typ darf nie ausgewählt werden, egal wie hoch die Chance")

func test_known_type_with_chance_one_always_selected() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var result: String = _spawner._roll_weighted_type({"oak_tree": 1.0}, ["oak_tree"], rng)
	assert_eq(result, "oak_tree")

func test_known_type_with_chance_zero_never_selected() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var result: String = _spawner._roll_weighted_type({"oak_tree": 0.0}, ["oak_tree"], rng)
	assert_eq(result, "")

func test_unregistered_entry_does_not_block_a_later_registered_one() -> void:
	# "cactus" (unregistriert, würde immer treffen) UND "oak_tree" (registriert,
	# chance=1.0) in derselben Tabelle — oak_tree muss trotzdem gefunden werden,
	# der gefilterte Eintrag darf die Suche nicht abbrechen.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var result: String = _spawner._roll_weighted_type(
		{"cactus": 1.0, "oak_tree": 1.0}, ["oak_tree"], rng
	)
	assert_eq(result, "oak_tree")

func test_empty_chances_returns_empty_string() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var result: String = _spawner._roll_weighted_type({}, ["oak_tree"], rng)
	assert_eq(result, "")

func test_desert_biome_definition_has_skeleton_in_enemy_chances() -> void:
	# Regressionsschutz für die eigentliche Anfrage (Round 75: "vermehrt
	# Skelette [...] im Wüsten-Biom") — stellt sicher, dass die Daten-Seite
	# (BiomeRegistry) tatsächlich mit dem gesetzt ist, was ChunkEntitySpawner
	# konsumiert.
	var desert: BiomeDefinition = BiomeRegistry.get_biome("desert")
	assert_true(desert.enemy_chances.has("skeleton"),
		"Wüsten-Biom muss 'skeleton' in enemy_chances haben")
	assert_true("skeleton" in WorldEntityRegistry.KNOWN_ENEMY_TYPES,
		"'skeleton' muss tatsächlich als spawnbarer Typ registriert sein, sonst würde es gefiltert")

func test_desert_biome_cactus_is_now_spawnable() -> void:
	# Round 76: vorher ("test_desert_biome_cactus_is_correctly_unspawnable_for_now")
	# dokumentierte dieser Test bewusst den unvollständigen Zustand (kein
	# Cactus-Entity-Typ). Jetzt umgedreht, seit Cactus.gd existiert und
	# registriert ist (WorldEntityRegistry.register_all() + KNOWN_PROP_TYPES).
	assert_true("cactus" in WorldEntityRegistry.KNOWN_PROP_TYPES,
		"Cactus-Entity-Typ existiert jetzt (Cactus.gd) — muss in KNOWN_PROP_TYPES stehen")
	var desert: BiomeDefinition = BiomeRegistry.get_biome("desert")
	assert_true(desert.prop_chances.has("cactus"),
		"desert.prop_chances muss weiterhin 'cactus' enthalten (seit Round 74, unverändert)")

func test_mountain_biome_rock_boulder_is_now_spawnable() -> void:
	# Round 78: rock_boulder stand schon vorher in mehreren prop_chances
	# (forest/meadow/desert/winter), aber ohne registrierten Entity-Typ —
	# wurde überall gefiltert. Jetzt registriert (RockBoulder.gd), spawnt
	# also in ALLEN Biomen, die es listen — hier stellvertretend am neuen
	# "mountain"-Biom geprüft (dort am höchsten gewichtet).
	assert_true("rock_boulder" in WorldEntityRegistry.KNOWN_PROP_TYPES,
		"RockBoulder-Entity-Typ existiert jetzt (RockBoulder.gd) — muss in KNOWN_PROP_TYPES stehen")
	var mountain: BiomeDefinition = BiomeRegistry.get_biome("mountain")
	assert_true(mountain.prop_chances.has("rock_boulder"),
		"mountain.prop_chances muss 'rock_boulder' enthalten")

func test_forest_biome_mushroom_cluster_is_now_spawnable() -> void:
	# Round 79: mushroom_cluster stand schon vorher in mehreren prop_chances
	# (forest/dense_forest/swamp), aber ohne registrierten Entity-Typ.
	assert_true("mushroom_cluster" in WorldEntityRegistry.KNOWN_PROP_TYPES,
		"MushroomCluster-Entity-Typ existiert jetzt (MushroomCluster.gd) — muss in KNOWN_PROP_TYPES stehen")
	var forest: BiomeDefinition = BiomeRegistry.get_biome("forest")
	assert_true(forest.prop_chances.has("mushroom_cluster"),
		"forest.prop_chances muss 'mushroom_cluster' enthalten")

func test_dead_forest_biome_fallen_tree_is_now_spawnable() -> void:
	# Round 79: fallen_tree stand schon vorher in mehreren prop_chances
	# (forest/dense_forest/winter/swamp), aber ohne registrierten Entity-Typ.
	assert_true("fallen_tree" in WorldEntityRegistry.KNOWN_PROP_TYPES,
		"FallenTree-Entity-Typ existiert jetzt (FallenTree.gd) — muss in KNOWN_PROP_TYPES stehen")
	var dead_forest: BiomeDefinition = BiomeRegistry.get_biome("dead_forest")
	assert_true(dead_forest.prop_chances.has("fallen_tree"),
		"dead_forest.prop_chances muss 'fallen_tree' enthalten")

func test_fern_is_now_spawnable() -> void:
	# Fern-Rollout: "fern" war der letzte Prefab-ohne-Entity-Typ (stand schon
	# in forest/dense_forest/swamp), aber ohne registrierten Entity-Typ.
	assert_true("fern" in WorldEntityRegistry.KNOWN_PROP_TYPES,
		"Fern-Entity-Typ existiert jetzt (Fern.gd) — muss in KNOWN_PROP_TYPES stehen")

func test_fern_spawns_in_every_biome_except_winter_and_desert() -> void:
	# Anfrage: fern soll in jedem Biom außer Eis (winter) und Wüste (desert) spawnen.
	for biome_id in ["forest", "dense_forest", "meadow", "swamp", "mountain", "dead_forest"]:
		var b: BiomeDefinition = BiomeRegistry.get_biome(biome_id)
		assert_true(b.prop_chances.has("fern"),
			"%s.prop_chances muss 'fern' enthalten" % biome_id)
		assert_gt(b.prop_chances["fern"], 0.0)
	for biome_id in ["winter", "desert"]:
		var b: BiomeDefinition = BiomeRegistry.get_biome(biome_id)
		assert_false(b.prop_chances.has("fern"),
			"%s.prop_chances darf 'fern' NICHT enthalten (Anfrage: Ausnahme Eis/Wüste)" % biome_id)

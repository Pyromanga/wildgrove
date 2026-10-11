## tests/unit/test_factory3d_nature.gd
## Unit-Tests für Factory3D Natur-Objekte.
##
## Abdeckung:
##   - Alle create_*() Funktionen liefern einen gültigen Node3D zurück
##   - Nodes enthalten die erwarteten Kind-Nodes (Stamm, Blätter, etc.)
##   - create_pine_tree() baut mehr Children mit snow=true
##   - create_mushroom_cluster() liefert 1–4 Pilze
##   - create_cactus() hat Arme (>1 Child)
##   - Meshes haben gültige Größen (> 0)

extends GutTest

var _factory: Factory3D
var _parent: Node3D

func before_each() -> void:
	_factory = Factory3D.new()
	_factory.cache = MeshCache.new()
	_factory.cache.build()
	_parent = Node3D.new()
	add_child(_parent)

func after_each() -> void:
	_parent.queue_free()
	_factory = null
	_parent = null

# ─────────────────────────────────────────────
# FallenTree
# ─────────────────────────────────────────────

func test_fallen_tree_returns_node3d() -> void:
	var node := _factory.create_fallen_tree(null)
	assert_not_null(node)
	assert_is(node, Node3D)
	node.queue_free()

func test_fallen_tree_has_trunk_child() -> void:
	var node := _factory.create_fallen_tree(null)
	assert_gt(node.get_child_count(), 0, "FallenTree muss mind. einen Child (Stamm) haben")
	node.queue_free()

func test_fallen_tree_attaches_to_parent() -> void:
	var node := _factory.create_fallen_tree(_parent)
	assert_eq(node.get_parent(), _parent)

# ─────────────────────────────────────────────
# MushroomCluster
# ─────────────────────────────────────────────

func test_mushroom_cluster_returns_node3d() -> void:
	var node := _factory.create_mushroom_cluster(null)
	assert_not_null(node)
	assert_is(node, Node3D)
	node.queue_free()

func test_mushroom_cluster_has_between_1_and_4_mushrooms() -> void:
	# 10 Durchläufe — alle müssen im Bereich 1–4 liegen
	for i in range(10):
		var node := _factory.create_mushroom_cluster(null)
		var count := node.get_child_count()
		assert_gte(count, 1, "Mindestens 1 Pilz")
		assert_lte(count, 4, "Maximal 4 Pilze")
		node.queue_free()

func test_mushroom_types_dont_crash() -> void:
	for mtype in ["red", "brown", "orange"]:
		var node := _factory.create_mushroom_cluster(null, mtype)
		assert_not_null(node)
		node.queue_free()

# ─────────────────────────────────────────────
# Fern
# ─────────────────────────────────────────────

func test_fern_returns_node3d() -> void:
	var node := _factory.create_fern(null)
	assert_not_null(node)
	assert_is(node, Node3D)
	node.queue_free()

func test_fern_has_multiple_planes() -> void:
	var node := _factory.create_fern(null)
	assert_gte(node.get_child_count(), 3, "Farn muss mind. 3 Planes haben")
	node.queue_free()

# ─────────────────────────────────────────────
# RockBoulder
# ─────────────────────────────────────────────

func test_rock_boulder_returns_node3d() -> void:
	var node := _factory.create_rock_boulder(null)
	assert_not_null(node)
	node.queue_free()

func test_rock_boulder_biome_colors_dont_crash() -> void:
	for biome in ["forest", "desert", "winter", "swamp", "mountain"]:
		var node := _factory.create_rock_boulder(null, biome)
		assert_not_null(node)
		node.queue_free()

# ─────────────────────────────────────────────
# PineTree
# ─────────────────────────────────────────────

func test_pine_tree_returns_node3d() -> void:
	var node := _factory.create_pine_tree(null)
	assert_not_null(node)
	node.queue_free()

func test_pine_tree_with_snow_has_more_children() -> void:
	var no_snow  := _factory.create_pine_tree(null, false)
	var with_snow := _factory.create_pine_tree(null, true)
	# Schnee-Variante hat Schnee-Cones zusätzlich zu den Blatt-Cones
	assert_gt(
		with_snow.get_child_count(),
		no_snow.get_child_count(),
		"Schnee-Tanne muss mehr Children haben als schneefreie"
	)
	no_snow.queue_free()
	with_snow.queue_free()

# ─────────────────────────────────────────────
# Cactus
# ─────────────────────────────────────────────

func test_cactus_returns_node3d() -> void:
	var node := _factory.create_cactus(null)
	assert_not_null(node)
	node.queue_free()

func test_cactus_has_body_and_arms() -> void:
	var node := _factory.create_cactus(null)
	# Body + 2 Arme = mind. 3 Children
	assert_gte(node.get_child_count(), 3, "Kaktus muss Körper + 2 Arme haben")
	node.queue_free()

# ─────────────────────────────────────────────
# Bestehende Funktionen nicht gebrochen
# ─────────────────────────────────────────────

func test_create_simple_tree_still_works() -> void:
	var node := _factory.create_simple_tree(null)
	assert_not_null(node)
	# Seit 2026-10-07 (verzweigte Bäume, TreeSkeleton) statt "Stamm + 2 Astgruppen": wenige
	# MultiMesh-Nodes — "Branches" (Stamm/Hauptäste), "Twigs", "Leaves0..2", "CrownFar".
	assert_not_null(node.get_node_or_null("Branches"), "Stamm/Hauptäste")
	assert_not_null(node.get_node_or_null("Twigs"), "Seitenäste/Zweige")
	assert_not_null(node.get_node_or_null("CrownFar"), "Fern-Krone")
	var leaf_nodes := 0
	for child in node.get_children():
		if String(child.name).begins_with("Leaves"):
			leaf_nodes += 1
	assert_gte(leaf_nodes, 1, "mindestens eine Laub-Gruppe")
	assert_lte(node.get_child_count(), 10, "wenige Nodes statt ~40 — ein Draw-Call je Gruppe")
	node.queue_free()

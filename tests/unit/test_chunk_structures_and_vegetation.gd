## tests/unit/test_chunk_structures_and_vegetation.gd
## Zufällige Gebäude (ChunkStructurePlanner/-Builder), Gras/Büsche (ChunkVegetationBuilder),
## gewichtetes Prop-Sampling und Biom-Dichte. NICHT in einer Godot-Runtime ausgeführt (kein
## Binary in der Entwicklungsumgebung) — beim ersten GUT-Lauf bitte beobachten.

extends GutTest

class FlatField extends TerrainField:
	func get_height_at(_x: float, _z: float) -> float:
		return 5.0

class SlopedField extends TerrainField:
	func get_height_at(x: float, _z: float) -> float:
		return 5.0 + x * 0.5

var _field: FlatField

func before_each() -> void:
	_field = FlatField.new()

## Erster Chunk fern vom Spawn, in dem ein Plan entsteht (Chance 16 % → Suche über viele Chunks).
func _find_planned_chunk(field: TerrainField) -> Dictionary:
	for i in range(400):
		var coord := Vector2i(10 + i % 20, 10 + i / 20)
		var center := Vector2(coord.x * 64.0, coord.y * 64.0)
		var plan := ChunkStructurePlanner.plan(coord, center, field, 4242, 64.0)
		if not plan.is_empty():
			plan["_coord"] = coord
			plan["_center"] = center
			return plan
	return {}

# ── Planner ─────────────────────────────────────────────

func test_planner_is_deterministic() -> void:
	var p1 := _find_planned_chunk(_field)
	assert_false(p1.is_empty(), "Auf ebenem Gelände muss irgendwo ein Gebäude geplant werden.")
	var p2 := ChunkStructurePlanner.plan(p1["_coord"], p1["_center"], _field, 4242, 64.0)
	assert_eq(p2["type"], p1["type"])
	assert_eq(p2["x"], p1["x"])
	assert_eq(p2["z"], p1["z"])
	assert_eq(p2["yaw_steps"], p1["yaw_steps"])

func test_planned_site_stays_inside_chunk_margin() -> void:
	var p := _find_planned_chunk(_field)
	var c: Vector2 = p["_center"]
	var reach: float = 32.0 - ChunkStructurePlanner.EDGE_MARGIN
	assert_lte(absf(float(p["x"]) - c.x) + float(p["radius"]), reach + 0.001)
	assert_lte(absf(float(p["z"]) - c.y) + float(p["radius"]), reach + 0.001)

func test_no_structure_near_spawn() -> void:
	for cx in range(-2, 3):
		for cz in range(-2, 3):
			var coord := Vector2i(cx, cz)
			var plan := ChunkStructurePlanner.plan(coord, Vector2(cx * 64.0, cz * 64.0), _field, 4242, 64.0)
			assert_true(plan.is_empty(), "Chunk %s liegt im Spawn-Sperrring" % str(coord))

func test_steep_terrain_rejects_site() -> void:
	var steep := SlopedField.new()
	var r := ChunkStructurePlanner.evaluate_site(steep, 640.0, 640.0, 0, Vector2(3.5, 4.0))
	assert_true(r.is_empty(), "7 m Fläche bei 0.5 Steigung überschreitet MAX_HEIGHT_SPREAD")

func test_flat_terrain_accepts_site_with_base_at_highest_point() -> void:
	var r := ChunkStructurePlanner.evaluate_site(_field, 640.0, 640.0, 1, Vector2(3.5, 4.0))
	assert_false(r.is_empty())
	assert_almost_eq(float(r["base_y"]), 5.0, 0.001)
	assert_almost_eq(float(r["spread"]), 0.0, 0.001)

func test_all_structure_types_have_footprint_and_biomes_only_name_known_types() -> void:
	for biome_id in ["forest", "dense_forest", "meadow", "desert", "winter", "swamp", "mountain", "dead_forest"]:
		var b: BiomeDefinition = BiomeRegistry.get_biome(biome_id)
		for t: String in b.structure_types:
			assert_true(ChunkStructurePlanner.TYPES.has(t), "%s: unbekannter structure_type '%s'" % [biome_id, t])

func test_local_to_world_rotates_by_yaw_steps() -> void:
	var plan := {"x": 100.0, "z": 50.0, "yaw_steps": 1}
	var w := ChunkStructurePlanner.local_to_world(plan, 0.0, 2.0)
	# Rotation um +90° (Y) bildet lokal +Z auf +X ab.
	assert_almost_eq(w.x, 102.0, 0.001)
	assert_almost_eq(w.y, 50.0, 0.001)

# ── Builder ─────────────────────────────────────────────

func test_builder_creates_body_with_collision_for_every_type() -> void:
	for type_id in ChunkStructurePlanner.TYPES.keys():
		var spec: Dictionary = ChunkStructurePlanner.TYPES[type_id]
		var plan := {
			"type": type_id, "x": 10.0, "z": 20.0, "base_y": 5.0, "spread": 0.2,
			"yaw_steps": 2, "half_x": spec["half"].x, "half_z": spec["half"].y,
			"radius": spec["radius"], "seed": 99,
		}
		var root := ChunkStructureBuilder.build(plan, Vector2(0.0, 0.0))
		autofree(root)
		var body: Node = root.get_node_or_null("Body")
		assert_not_null(body, "%s: Body fehlt" % type_id)
		var shapes := 0
		for child in body.get_children():
			if child is CollisionShape3D:
				shapes += 1
		assert_gt(shapes, 0, "%s: keine Kollision" % type_id)
		assert_almost_eq(root.position.y, 5.0, 0.001)

func test_npc_slots_lie_inside_the_slab() -> void:
	for type_id in ChunkStructureBuilder.NPC_SLOTS.keys():
		var half: Vector2 = ChunkStructurePlanner.TYPES[type_id]["half"]
		for slot: Vector2 in ChunkStructureBuilder.npc_slots(type_id):
			assert_lt(absf(slot.x), half.x, "%s: Slot x außerhalb der Platte" % type_id)
			assert_lt(absf(slot.y), half.y, "%s: Slot z außerhalb der Platte" % type_id)

func test_structure_npc_types_are_registered() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/world/core/WorldEntityRegistry.gd")
	for type_id in ChunkStructureBuilder.NPC_TYPE_BY_STRUCTURE.values():
		assert_true(src.contains('register_definition("%s"' % type_id), "%s nicht registriert" % type_id)

# ── Spawner-Integration ─────────────────────────────────

func test_spawner_builds_structure_and_npcs_only_with_chunk_node() -> void:
	var cb := func(_type_id: String, pos: Vector3) -> Node3D:
		var n := Node3D.new()
		n.position = pos
		autofree(n)
		return n
	var spawner := ChunkEntitySpawner.new(64.0, 4242, cb)
	var p := _find_planned_chunk(_field)
	var coord: Vector2i = p["_coord"]
	var center: Vector2 = p["_center"]

	spawner.spawn_for_chunk(coord, center, _field)  # ohne chunk_node
	assert_eq(_building_zones(spawner, coord).size(), 0, "Ohne chunk_node keine Gebäude-Zone")
	spawner.despawn_for_chunk(coord, func(_n: Node3D) -> void: pass)

	var chunk_node := Node3D.new()
	autofree(chunk_node)
	spawner.spawn_for_chunk(coord, center, _field, chunk_node)
	assert_eq(_building_zones(spawner, coord).size(), 1)
	assert_not_null(chunk_node.get_child(0), "Gebäude-Geometrie muss am Chunk-Node hängen")
	var zone: Vector3 = _building_zones(spawner, coord)[0]
	spawner.despawn_for_chunk(coord, func(_n: Node3D) -> void: pass)
	assert_eq(spawner.get_clear_zones(coord).size(), 0, "Despawn räumt die Zone auf (auch die Zoo-Zonen)")
	assert_gt(zone.z, 0.0)

# ── Gewichtetes Sampling + Dichte ───────────────────────

func test_weighted_roll_honours_absolute_probabilities() -> void:
	var spawner := ChunkEntitySpawner.new(64.0, 1, func(_t: String, _p: Vector3) -> void: pass)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var hits := {"oak_tree": 0, "fern": 0, "": 0}
	var n := 20000
	for i in range(n):
		hits[spawner._roll_weighted_type({"oak_tree": 0.3, "fern": 0.1}, ["oak_tree", "fern"], rng)] += 1
	# Vorher dämpfte "erster Treffer gewinnt" fern auf ~0.07 — jetzt exakt ~0.10.
	assert_almost_eq(float(hits["fern"]) / n, 0.10, 0.015)
	assert_almost_eq(float(hits["oak_tree"]) / n, 0.30, 0.02)

func test_weighted_roll_normalises_when_sum_exceeds_one() -> void:
	var spawner := ChunkEntitySpawner.new(64.0, 1, func(_t: String, _p: Vector3) -> void: pass)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in range(200):
		assert_ne(spawner._roll_weighted_type({"oak_tree": 1.0, "fern": 1.0}, ["oak_tree", "fern"], rng), "")

func test_forests_are_denser_than_before() -> void:
	# Vorher: Ø 7 Versuche × 0.28 ≈ 2 Eichen pro Chunk. Wunsch 2026-10-08 "Wälder richtig dicht an dicht":
	# Wald ≥ 18, dichter Wald ≥ 30 Bäume pro 64-m-Chunk (Kronen überlappen).
	var minimum := {"forest": 18.0, "dense_forest": 30.0}
	for biome_id in minimum.keys():
		var b: BiomeDefinition = BiomeRegistry.get_biome(biome_id)
		var mean_attempts: float = float(b.prop_attempts_min + b.prop_attempts_max) * 0.5
		var tree_chance := 0.0
		for t in ["oak_tree", "maple_tree", "pine_tree", "willow_tree"]:
			tree_chance += float(b.prop_chances.get(t, 0.0))
		assert_gt(mean_attempts * tree_chance, float(minimum[biome_id]), "%s: zu wenige Bäume pro Chunk" % biome_id)

func test_swamp_has_living_trees_and_all_land_biomes_have_vegetation() -> void:
	assert_true(BiomeRegistry.get_biome("swamp").prop_chances.has("willow_tree"))
	for biome_id in ["forest", "dense_forest", "meadow", "swamp", "mountain", "dead_forest", "desert"]:
		var b: BiomeDefinition = BiomeRegistry.get_biome(biome_id)
		assert_gt(b.grass_per_chunk, 0, "%s: kein Gras" % biome_id)
		assert_gt(b.bush_per_chunk, 0, "%s: keine Büsche" % biome_id)

# ── Vegetation ──────────────────────────────────────────

func _flat_grid(res: int, value: float) -> PackedFloat32Array:
	var g := PackedFloat32Array()
	g.resize((res + 1) * (res + 1))
	g.fill(value)
	return g

func test_vegetation_sample_is_bilinear_and_reports_slope() -> void:
	var res := 4
	var grid := _flat_grid(res, 3.0)
	var flat := ChunkVegetationBuilder._sample(grid, res, 64.0, 5.0, -7.0)
	assert_almost_eq(flat.x, 3.0, 0.0001)
	assert_almost_eq(flat.y, 0.0, 0.0001)
	# Rampe: Höhe = x-Index → 1 Einheit pro 16 m Gitterabstand
	for z in range(res + 1):
		for x in range(res + 1):
			grid[z * (res + 1) + x] = float(x)
	var ramp := ChunkVegetationBuilder._sample(grid, res, 64.0, 0.0, 0.0)
	assert_almost_eq(ramp.x, 2.0, 0.0001)
	assert_almost_eq(ramp.y, rad_to_deg(atan(1.0 / 16.0)), 0.001)

func test_vegetation_builds_multimeshes_and_clear_removes_them() -> void:
	var res := 32
	var chunk := Node3D.new()
	autofree(chunk)
	var veg := ChunkVegetationBuilder.new(_field, 4242)
	# Meadow-ähnlich: Wasserraster weit unter dem Gelände.
	var coord := Vector2i(10, 10)
	# Biom-Abfrage am Chunk-Zentrum ist Noise — Chunk suchen, in dem Gras entsteht.
	var built := false
	for i in range(40):
		var c := Vector2i(10 + i, 10)
		veg.build(c, chunk, Vector2(c.x * 64.0, c.y * 64.0), _flat_grid(res, 5.0), _flat_grid(res, 0.0), res, 64.0)
		if chunk.get_node_or_null(ChunkVegetationBuilder.NODE_GRASS) != null:
			built = true
			var mmi := chunk.get_node(ChunkVegetationBuilder.NODE_GRASS) as MultiMeshInstance3D
			assert_gt(mmi.multimesh.instance_count, 0)
			assert_gt(mmi.visibility_range_end, 0.0)
			break
	assert_true(built, "Auf ebenem, trockenem Gelände muss irgendwo Gras entstehen.")
	veg.clear(chunk)
	assert_null(chunk.get_node_or_null(ChunkVegetationBuilder.NODE_GRASS))
	assert_null(chunk.get_node_or_null(ChunkVegetationBuilder.NODE_BUSHES))

func test_vegetation_respects_exclusion_zone_and_water() -> void:
	var res := 32
	var chunk := Node3D.new()
	autofree(chunk)
	var veg := ChunkVegetationBuilder.new(_field, 4242)
	# Alles unter Wasser → nichts wächst.
	for i in range(10):
		var c := Vector2i(10 + i, 10)
		veg.build(c, chunk, Vector2(c.x * 64.0, c.y * 64.0), _flat_grid(res, 1.0), _flat_grid(res, 2.0), res, 64.0)
		assert_null(chunk.get_node_or_null(ChunkVegetationBuilder.NODE_GRASS), "Unter Wasser darf kein Gras wachsen")
	# Riesige Sperrzone über den ganzen Chunk → nichts wächst.
	for i in range(10):
		var c := Vector2i(10 + i, 10)
		var center := Vector2(c.x * 64.0, c.y * 64.0)
		veg.build(c, chunk, center, _flat_grid(res, 5.0), _flat_grid(res, 0.0), res, 64.0, [Vector3(center.x, center.y, 200.0)])
		assert_null(chunk.get_node_or_null(ChunkVegetationBuilder.NODE_GRASS), "Sperrzone muss Gras verhindern")

# ── Blumen, Sense, Mähen ────────────────────────────────

func _grass_transforms(chunk: Node3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var node := chunk.get_node_or_null(ChunkVegetationBuilder.NODE_GRASS) as MultiMeshInstance3D
	if node == null:
		return out
	for i in range(node.multimesh.instance_count):
		out.append(node.multimesh.get_instance_transform(i).origin)
	return out

## Erster Chunk (ab (10,10)), in dem Gras UND Blumen entstehen. Liefert {} wenn keiner gefunden.
func _find_meadow_chunk(veg: ChunkVegetationBuilder, chunk: Node3D, res: int) -> Dictionary:
	for i in range(120):
		var c := Vector2i(10 + i % 12, 10 + i / 12)
		var center := Vector2(c.x * 64.0, c.y * 64.0)
		veg.build(c, chunk, center, _flat_grid(res, 5.0), _flat_grid(res, 0.0), res, 64.0)
		if chunk.get_node_or_null(ChunkVegetationBuilder.NODE_FLOWERS) != null \
				and chunk.get_node_or_null(ChunkVegetationBuilder.NODE_GRASS) != null:
			return {"coord": c, "center": center}
	return {}

func test_flowers_are_built_as_multimesh_with_colors() -> void:
	var res := 32
	var chunk := Node3D.new()
	autofree(chunk)
	var veg := ChunkVegetationBuilder.new(_field, 4242)
	var found := _find_meadow_chunk(veg, chunk, res)
	assert_false(found.is_empty(), "Irgendwo muss es Blumen geben (Wiese/Wald).")
	var mmi := chunk.get_node(ChunkVegetationBuilder.NODE_FLOWERS) as MultiMeshInstance3D
	assert_gt(mmi.multimesh.instance_count, 0)
	assert_true(mmi.multimesh.use_custom_data)
	veg.clear(chunk)
	assert_null(chunk.get_node_or_null(ChunkVegetationBuilder.NODE_FLOWERS))

func test_fresh_cut_removes_and_counts_grass_without_moving_the_rest() -> void:
	var res := 32
	var chunk := Node3D.new()
	autofree(chunk)
	var veg := ChunkVegetationBuilder.new(_field, 4242)
	var found := _find_meadow_chunk(veg, chunk, res)
	assert_false(found.is_empty())
	var coord: Vector2i = found["coord"]
	var center: Vector2 = found["center"]
	var before := _grass_transforms(chunk)
	var cut := Vector3(center.x, center.y, 10.0)
	var stats := veg.build(coord, chunk, center, _flat_grid(res, 5.0), _flat_grid(res, 0.0), res, 64.0, [], [], cut)
	var after := _grass_transforms(chunk)
	assert_gt(int(stats["grass"]), 0, "Im Mähkreis lag Gras.")
	assert_eq(before.size() - after.size(), int(stats["grass"]), "Gezählt == tatsächlich entfernt.")
	# Determinismus: jedes verbliebene Büschel steht exakt dort, wo es vorher stand.
	for p: Vector3 in after:
		assert_true(before.has(p), "Rest der Wiese darf sich nicht verschieben.")
	for p: Vector3 in after:
		assert_gte(Vector2(p.x, p.z).distance_to(Vector2.ZERO), 10.0 - 0.001, "Nichts mehr im gemähten Kreis.")

func test_existing_cut_zone_hides_grass_and_flowers_but_does_not_count() -> void:
	var res := 32
	var chunk := Node3D.new()
	autofree(chunk)
	var veg := ChunkVegetationBuilder.new(_field, 4242)
	var found := _find_meadow_chunk(veg, chunk, res)
	var coord: Vector2i = found["coord"]
	var center: Vector2 = found["center"]
	var stats := veg.build(coord, chunk, center, _flat_grid(res, 5.0), _flat_grid(res, 0.0), res, 64.0, [], [Vector3(center.x, center.y, 200.0)])
	assert_null(chunk.get_node_or_null(ChunkVegetationBuilder.NODE_GRASS))
	assert_null(chunk.get_node_or_null(ChunkVegetationBuilder.NODE_FLOWERS))
	assert_eq(int(stats["grass"]) + int(stats["flowers"]), 0, "Bereits gemähtes zählt nicht erneut.")

func test_chunk_manager_ignores_expired_cut_zones() -> void:
	var mgr := ChunkManager.new()
	autofree(mgr)
	var now := float(Time.get_ticks_msec()) / 1000.0
	mgr._cut_zones[Vector2i(1, 1)] = [Vector4(1.0, 2.0, 3.0, now + 100.0), Vector4(9.0, 9.0, 1.0, now - 5.0)]
	var circles := mgr._active_cut_circles(Vector2i(1, 1))
	assert_eq(circles.size(), 1)
	assert_eq(circles[0], Vector3(1.0, 2.0, 3.0))

func test_scythe_tool_definition_and_items() -> void:
	var scythe := load("res://data/items/tools/Scythe.tres") as ToolDefinition
	assert_not_null(scythe)
	assert_eq(scythe.id, GroundToolController.SCYTHE_ID)
	assert_eq(scythe.tool_type, ToolDefinition.ToolType.SCYTHE)
	assert_eq(scythe.speed_stat_id, GroundToolController.MOW_SPEED_STAT)
	assert_eq((load("res://data/items/Hay.tres") as ItemDefinition).id, WorldService.ITEM_HAY)
	assert_eq((load("res://data/items/Wildflower.tres") as ItemDefinition).id, WorldService.ITEM_WILDFLOWER)
	var manifest := FileAccess.get_file_as_string("res://scripts/persistence/DataManifest.gd")
	for path in ["tools/Scythe.tres", "Hay.tres", "Wildflower.tres"]:
		assert_true(manifest.contains(path), "%s fehlt im DataManifest" % path)
	assert_true(FileAccess.get_file_as_string("res://scripts/economy/shop/ShopService.gd").contains('"tool_scythe"'))

func test_mow_action_shape_and_event() -> void:
	var bus := MockEventBus.new()
	watch_signals(bus.world())
	var a := GroundToolController.build_mow_action(Vector3(4, 0, 5), "p1", 3, bus)
	assert_eq(a.id, "mow_ground")
	assert_eq(a.speed_stat_id, GroundToolController.MOW_SPEED_STAT)
	assert_eq(a.peer_id, 3)
	assert_signal_not_emitted(bus.world(), "grass_cut_requested")
	a.on_complete.call(3)
	assert_signal_emitted_with_parameters(bus.world(), "grass_cut_requested", ["p1", Vector3(4, 0, 5)])


## Freihaltezonen eines Chunks OHNE die des Tier-Zoos (ZooLayout, Spawn-Nähe) — der Test prüft die
## Gebäude-Zonen; je nach Lage des gefundenen Chunks können zusätzlich Zoo-Kreise darin liegen.
func _building_zones(spawner: ChunkEntitySpawner, coord: Vector2i) -> Array:
	var zoo: Array[Vector3] = ZooLayout.clear_zone_circles()
	var out: Array = []
	for z: Vector3 in spawner.get_clear_zones(coord):
		if not zoo.has(z):
			out.append(z)
	return out

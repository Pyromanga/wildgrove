## tests/unit/test_settlements.gd
## Dörfer, Straßen, Bauteile: PartBatch, StructureParts/BuildingRecipes, SettlementSites,
## RoadPaths, VillageLayout, SettlementRegistry, ChunkSettlementBuilder.
## NICHT in einer Godot-Runtime ausgeführt (kein Binary in der Entwicklungsumgebung) — beim
## ersten GUT-Lauf bitte beobachten.

extends GutTest

## Ebene, trockene Wiese: jeder Kandidat ist ein gültiger Dorfplatz → Tests sind unabhängig vom Noise.
class FlatMeadow extends TerrainField:
	func get_base_height_at(_x: float, _z: float) -> float:
		return 5.0
	func get_height_at(_x: float, _z: float) -> float:
		return 5.0
	func get_water_level_at(_x: float, _z: float) -> float:
		return 0.0
	func get_biome_id_at(_x: float, _z: float) -> String:
		return "meadow"

var _field: FlatMeadow

func before_each() -> void:
	_field = FlatMeadow.new(null, 777)

## Erstes echtes (nicht festes) Dorf im Bereich um den Ursprung.
func _find_site(field: TerrainField) -> Dictionary:
	var reg: SettlementRegistry = field.get_settlements()
	for cz in range(-4, 5):
		for cx in range(-4, 5):
			var s: Dictionary = reg.get_site(Vector2i(cx, cz))
			if not s.is_empty() and not bool(s["fixed"]):
				return s
	return {}

# ── Mathe ───────────────────────────────────────────────

func test_mix_is_deterministic_and_spreads() -> void:
	assert_eq(SettlementMath.mix(1, 2, 3, 4), SettlementMath.mix(1, 2, 3, 4))
	assert_ne(SettlementMath.mix(1, 2, 3, 4), SettlementMath.mix(1, 2, 4, 3))
	assert_gte(SettlementMath.mix(-5, 9, 2, 1), 0)

func test_facing_yaw_points_local_front_to_target() -> void:
	var yaw: float = BuildingRecipes.facing_yaw(Vector2.ZERO, Vector2(3.0, 4.0))
	var front: Vector2 = SettlementMath.front_dir(yaw)
	assert_almost_eq(front.x, 0.6, 0.001)
	assert_almost_eq(front.y, 0.8, 0.001)
	# local_to_world: lokale +Z-Strecke läuft entlang der Front.
	var p: Vector2 = SettlementMath.local_to_world(Vector2(10.0, 10.0), yaw, Vector2(0.0, 5.0))
	assert_almost_eq(p.x, 13.0, 0.001)
	assert_almost_eq(p.y, 14.0, 0.001)

func test_obb_overlap_detects_rotation() -> void:
	var h := Vector2(4.0, 2.0)
	assert_true(SettlementMath.obb_overlap(Vector2.ZERO, h, 0.0, Vector2(6.0, 0.0), h, 0.0))
	assert_false(SettlementMath.obb_overlap(Vector2.ZERO, h, 0.0, Vector2(9.0, 0.0), h, 0.0))
	# Um 90° gedreht ist das Rechteck in X nur noch 2 breit → kein Kontakt bei 6.
	assert_false(SettlementMath.obb_overlap(Vector2.ZERO, h, 0.0, Vector2(6.5, 0.0), h, PI * 0.5))

# ── PartBatch / Rezepte ─────────────────────────────────

func test_part_batch_box_counts() -> void:
	var b := PartBatch.new()
	b.add_box(Vector3.ONE, Vector3.ZERO, Color.WHITE)
	assert_eq(b.triangle_count(), 12)
	assert_eq(b.shape_count(), 1)
	b.add_box(Vector3.ONE, Vector3(3, 0, 0), Color.WHITE, 0.0, false)
	assert_eq(b.shape_count(), 1, "collide=false darf keine Kollisionsform erzeugen.")

func test_part_batch_build_makes_single_mesh_and_body() -> void:
	var b := PartBatch.new()
	b.add_box(Vector3.ONE, Vector3.ZERO, Color.WHITE)
	b.add_gable_roof(1.0, 1.0, 0.5, Vector3(0, 0.5, 0), Color.RED)
	var node: Node3D = b.build("T")
	add_child_autofree(node)
	assert_not_null(node.get_node_or_null("Mesh"))
	assert_not_null(node.get_node_or_null("Body"))
	assert_eq(node.get_node("Body").get_child_count(), 2)

func test_every_catalog_type_builds_geometry() -> void:
	for type_id: String in BuildingRecipes.CATALOG:
		var batch := PartBatch.new()
		BuildingRecipes.build(type_id, batch, 1, 1.5)
		assert_gt(batch.triangle_count(), 20, "%s erzeugt keine Geometrie." % type_id)
		var half: Vector2 = BuildingRecipes.half_extents(type_id)
		assert_gt(half.x, 0.0)
		assert_gt(half.y, 0.0)
		for slot_entry: Variant in BuildingRecipes.npc_slots(type_id):
			var entry: Array = slot_entry
			var slot: Vector2 = entry[1]
			assert_lte(absf(slot.x), half.x, "%s: NPC-Slot außerhalb des Grundstücks." % type_id)
			assert_lte(absf(slot.y), half.y, "%s: NPC-Slot außerhalb des Grundstücks." % type_id)
			var allowed: Array = ["settler_npc", "farmer_npc", "water_carrier_npc"] + ProfessionCatalog.npc_types()
			assert_true(allowed.has(String(entry[0])), "%s: unerlaubter NPC-Typ." % type_id)

func test_wall_run_with_door_leaves_gap() -> void:
	var with_door := PartBatch.new()
	StructureParts.wall_run(with_door, Vector2(0, 0), Vector2(6, 0), 2.5, Color.WHITE, [{"t0": 2.5, "t1": 3.7, "kind": "door", "top": 2.1}])
	var solid := PartBatch.new()
	StructureParts.wall_run(solid, Vector2(0, 0), Vector2(6, 0), 2.5, Color.WHITE)
	# Türwand: linkes + rechtes Stück + Sturz = 3 Kollisionsboxen; massiv = 1.
	assert_eq(solid.shape_count(), 1)
	assert_eq(with_door.shape_count(), 3)

# ── Standorte / Straßen ─────────────────────────────────

func test_sites_are_deterministic() -> void:
	var other := FlatMeadow.new(null, 777)
	for cz in range(-3, 4):
		for cx in range(-3, 4):
			var a: Dictionary = _field.get_settlements().get_site(Vector2i(cx, cz))
			var b: Dictionary = other.get_settlements().get_site(Vector2i(cx, cz))
			assert_eq(a.is_empty(), b.is_empty())
			if not a.is_empty():
				assert_eq(a["center"], b["center"])
				assert_eq(a["name"], b["name"])
				assert_eq(a["tier"], b["tier"])

func test_spawn_cell_holds_fixed_start_village() -> void:
	var cell: Vector2i = SettlementSites.cell_of(SettlementSites.SPAWN_CENTER.x, SettlementSites.SPAWN_CENTER.y)
	var s: Dictionary = _field.get_settlements().get_site(cell)
	assert_false(s.is_empty())
	assert_true(bool(s["fixed"]))
	assert_eq(s["name"], SettlementSites.SPAWN_NAME)

func test_generated_sites_keep_distance_to_spawn_and_stay_in_cell() -> void:
	var reg: SettlementRegistry = _field.get_settlements()
	var found: int = 0
	for cz in range(-4, 5):
		for cx in range(-4, 5):
			var s: Dictionary = reg.get_site(Vector2i(cx, cz))
			if s.is_empty() or bool(s["fixed"]):
				continue
			found += 1
			var c: Vector2 = s["center"]
			assert_gte(c.distance_to(SettlementSites.SPAWN_CENTER), SettlementSites.SPAWN_EXCLUSION)
			assert_eq(SettlementSites.cell_of(c.x, c.y), Vector2i(cx, cz))
	assert_gt(found, 3, "Auf ebener Wiese müssen mehrere Dörfer entstehen.")

func test_villages_get_name_and_known_tier() -> void:
	var s: Dictionary = _find_site(_field)
	assert_false(s.is_empty())
	assert_gt(String(s["name"]).length(), 4)
	assert_true([SettlementSites.TIER_HAMLET, SettlementSites.TIER_VILLAGE, SettlementSites.TIER_TOWN].has(String(s["tier"])))

func test_villages_are_connected_by_roads() -> void:
	var reg: SettlementRegistry = _field.get_settlements()
	var s: Dictionary = _find_site(_field)
	reg.ensure_cell(s["cell"])
	assert_gt(reg.get_edges_of(s["id"]).size(), 0, "Ein Dorf mit Nachbarn braucht mindestens eine Fernstraße.")
	for e: Dictionary in reg.get_edges_of(s["id"]):
		var pts: PackedVector2Array = e["points"]
		assert_gte(pts.size(), 2)

func test_road_path_has_both_endpoints() -> void:
	var a := Vector2(0.0, 0.0)
	var b := Vector2(300.0, 40.0)
	var pts: PackedVector2Array = RoadPaths.build_path(_field, a, b, 12345)
	assert_eq(pts[0], a)
	assert_eq(pts[pts.size() - 1], b)
	assert_eq(pts, RoadPaths.build_path(_field, a, b, 12345), "Pfad muss deterministisch sein.")

func test_edge_key_is_direction_independent() -> void:
	assert_eq(RoadPaths.edge_key("s_1_2", "s_3_4"), RoadPaths.edge_key("s_3_4", "s_1_2"))

# ── Layout ──────────────────────────────────────────────

func test_layout_starts_with_center_piece_and_has_buildings() -> void:
	var reg: SettlementRegistry = _field.get_settlements()
	var s: Dictionary = _find_site(_field)
	reg.ensure_cell(s["cell"])
	var layout: Dictionary = reg.get_layout(s["id"])
	var list: Array = layout["buildings"]
	assert_gte(list.size(), 4, "Auch ein Weiler braucht mehrere Gebäude.")
	var first: String = (list[0] as Dictionary)["type"]
	assert_true(first == BuildingRecipes.T_MARKET or first == BuildingRecipes.T_WELL)
	assert_gt((layout["streets"] as Array).size(), 1)

func test_layout_buildings_do_not_overlap_and_stay_near_village() -> void:
	var reg: SettlementRegistry = _field.get_settlements()
	var s: Dictionary = _find_site(_field)
	reg.ensure_cell(s["cell"])
	var list: Array = reg.get_layout(s["id"])["buildings"]
	var center: Vector2 = s["center"]
	for i in range(list.size()):
		var a: Dictionary = list[i]
		var ah: Vector2 = BuildingRecipes.half_extents(a["type"])
		assert_lte(Vector2(float(a["x"]), float(a["z"])).distance_to(center), float(s["radius"]) * 1.5 + 20.0)
		for j in range(i + 1, list.size()):
			var b: Dictionary = list[j]
			var bh: Vector2 = BuildingRecipes.half_extents(b["type"])
			assert_false(SettlementMath.obb_overlap(
				Vector2(float(a["x"]), float(a["z"])), ah, float(a["yaw"]),
				Vector2(float(b["x"]), float(b["z"])), bh, float(b["yaw"])),
				"%s und %s überlappen." % [a["type"], b["type"]])

func test_house_fronts_face_a_street() -> void:
	var reg: SettlementRegistry = _field.get_settlements()
	var s: Dictionary = _find_site(_field)
	reg.ensure_cell(s["cell"])
	var layout: Dictionary = reg.get_layout(s["id"])
	var streets: Array = layout["streets"]
	for b: Dictionary in layout["buildings"]:
		if not [BuildingRecipes.T_HOUSE_SMALL, BuildingRecipes.T_HOUSE_LONG].has(String(b["type"])):
			continue
		var half: Vector2 = BuildingRecipes.half_extents(b["type"])
		var front: Vector2 = SettlementMath.local_to_world(Vector2(float(b["x"]), float(b["z"])), float(b["yaw"]), Vector2(0.0, half.y + 1.0))
		var best: float = INF
		for st: Dictionary in streets:
			best = minf(best, SettlementMath.dist_to_segment(front, st["a"] as Vector2, st["b"] as Vector2))
		assert_lt(best, 6.0, "Hausfront liegt nicht an einer Straße (Abstand %.1f m)." % best)

func test_layout_is_independent_of_query_order() -> void:
	var s: Dictionary = _find_site(_field)
	var other := FlatMeadow.new(null, 777)
	var reg_b: SettlementRegistry = other.get_settlements()
	# Zuerst ganz andere Zellen anfragen, dann erst das Dorf.
	var cell: Vector2i = s["cell"]
	reg_b.ensure_cell(cell + Vector2i(2, 2))
	reg_b.ensure_cell(cell + Vector2i(-1, 1))
	reg_b.ensure_cell(cell)
	_field.get_settlements().ensure_cell(cell)
	var la: Array = _field.get_settlements().get_layout(s["id"])["buildings"]
	var lb: Array = reg_b.get_layout(s["id"])["buildings"]
	assert_eq(la.size(), lb.size())
	for i in range(la.size()):
		assert_eq((la[i] as Dictionary)["type"], (lb[i] as Dictionary)["type"])
		assert_eq((la[i] as Dictionary)["x"], (lb[i] as Dictionary)["x"])
		assert_eq((la[i] as Dictionary)["yaw"], (lb[i] as Dictionary)["yaw"])

# ── Registry-Abfragen ───────────────────────────────────

func test_road_tint_only_on_roads() -> void:
	var reg: SettlementRegistry = _field.get_settlements()
	var s: Dictionary = _find_site(_field)
	reg.ensure_cell(s["cell"])
	var edge: Dictionary = reg.get_edges_of(s["id"])[0]
	var pts: PackedVector2Array = edge["points"]
	var mid: Vector2 = pts[pts.size() / 2]
	var base := Color(0.2, 0.6, 0.2)
	assert_ne(reg.road_tint(mid.x, mid.y, base), base, "Auf der Straße muss die Farbe abweichen.")
	assert_true(reg.on_road(mid.x, mid.y))
	var far := Vector2(mid.x + 15.0, mid.y + 15.0)
	if not reg.on_road(far.x, far.y, 3.0):
		assert_eq(reg.road_tint(far.x, far.y, base), base)

func test_buildings_block_vegetation() -> void:
	var reg: SettlementRegistry = _field.get_settlements()
	var s: Dictionary = _find_site(_field)
	reg.ensure_cell(s["cell"])
	var list: Array = reg.get_layout(s["id"])["buildings"]
	var b: Dictionary = list[list.size() - 1]
	assert_true(reg.blocks_vegetation(float(b["x"]), float(b["z"]), 0.5))

func test_buildings_in_rect_unique_ownership() -> void:
	var reg: SettlementRegistry = _field.get_settlements()
	var s: Dictionary = _find_site(_field)
	reg.ensure_cell(s["cell"])
	var c: Vector2 = s["center"]
	var seen: Dictionary = {}
	# 64-m-Chunks im Dorf: jedes Gebäude darf in genau einem Chunk auftauchen.
	var c0: Vector2i = Vector2i(floori((c.x - 100.0) / 64.0), floori((c.y - 100.0) / 64.0))
	for cz in range(c0.y, c0.y + 4 + 3):
		for cx in range(c0.x, c0.x + 4 + 3):
			var rect := Rect2(Vector2(float(cx) * 64.0, float(cz) * 64.0), Vector2(64.0, 64.0))
			for b: Dictionary in reg.buildings_in_rect(rect):
				assert_false(seen.has(b["id"]), "Gebäude doppelt vergeben.")
				seen[b["id"]] = true
	assert_gt(seen.size(), 0)

func test_chunk_settlement_builder_creates_nodes() -> void:
	var reg: SettlementRegistry = _field.get_settlements()
	var s: Dictionary = _find_site(_field)
	reg.ensure_cell(s["cell"])
	var list: Array = (reg.get_layout(s["id"])["buildings"] as Array).slice(0, 3)
	var root: Node3D = ChunkSettlementBuilder.build(list, s["center"])
	add_child_autofree(root)
	assert_eq(root.get_child_count(), 3)

func test_structure_planner_avoids_villages() -> void:
	var reg: SettlementRegistry = _field.get_settlements()
	var s: Dictionary = _find_site(_field)
	reg.ensure_cell(s["cell"])
	var c: Vector2 = s["center"]
	var r: float = float(s["radius"])
	for cz in range(floori((c.y - r) / 64.0), floori((c.y + r) / 64.0) + 1):
		for cx in range(floori((c.x - r) / 64.0), floori((c.x + r) / 64.0) + 1):
			var center := Vector2(float(cx) * 64.0, float(cz) * 64.0)
			var plan: Dictionary = ChunkStructurePlanner.plan(Vector2i(cx, cz), center, _field, 4242, 64.0)
			if plan.is_empty():
				continue
			assert_gt(Vector2(float(plan["x"]), float(plan["z"])).distance_to(c), r, "Zufallsgebäude steht im Dorf.")

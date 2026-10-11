## tests/unit/test_village_kinds.gd
## Dorf-Arten (VillageKind/VillageKinds) und das Baumdorf (CanopyVillageKind/CanopyLayout/CanopyTree),
## dazu die neuen PartBatch-Bausteine (Gruppen, Kegelstumpf, Brett).

extends GutTest

## Ebener Wald: Standort-/Layout-Tests unabhängig vom Noise.
class FlatForest extends TerrainField:
	func get_base_height_at(_x: float, _z: float) -> float:
		return 5.0
	func get_height_at(_x: float, _z: float) -> float:
		return 5.0
	func get_water_level_at(_x: float, _z: float) -> float:
		return 0.0
	func get_biome_id_at(_x: float, _z: float) -> String:
		return "forest"

## Wiese: Baumdörfer dürfen hier NICHT entstehen (Rückfall auf Bodendorf).
class FlatMeadow extends TerrainField:
	func get_base_height_at(_x: float, _z: float) -> float:
		return 5.0
	func get_height_at(_x: float, _z: float) -> float:
		return 5.0
	func get_water_level_at(_x: float, _z: float) -> float:
		return 0.0
	func get_biome_id_at(_x: float, _z: float) -> String:
		return "meadow"

## Sanfter Hang: Bäume stehen verschieden hoch (Brücken müssen den Höhenunterschied ausgleichen).
class SlopedForest extends TerrainField:
	func get_base_height_at(x: float, _z: float) -> float:
		return 5.0 + x * 0.02
	func get_height_at(x: float, z: float) -> float:
		return get_base_height_at(x, z)
	func get_water_level_at(_x: float, _z: float) -> float:
		return 0.0
	func get_biome_id_at(_x: float, _z: float) -> String:
		return "forest"

var ALLOWED_NPCS: Array = ["settler_npc", "farmer_npc", "water_carrier_npc"] + ProfessionCatalog.npc_types()

func _canopy_sites(field: TerrainField) -> Array:
	var reg: SettlementRegistry = field.get_settlements()
	var out: Array = []
	for cz in range(-5, 6):
		for cx in range(-5, 6):
			var s: Dictionary = reg.get_site(Vector2i(cx, cz))
			if not s.is_empty() and String(s["kind"]) == VillageKinds.KIND_CANOPY:
				out.append(s)
	return out

func _site_of_tier(field: TerrainField, tier: String) -> Dictionary:
	for s: Dictionary in _canopy_sites(field):
		if String(s["tier"]) == tier:
			return s
	return {}

func _layout_of(field: TerrainField, site: Dictionary) -> Dictionary:
	var reg: SettlementRegistry = field.get_settlements()
	reg.ensure_cell(site["cell"])
	return reg.get_layout(site["id"])

# ── Register ────────────────────────────────────────────

func test_registry_knows_all_kinds_and_falls_back_to_ground() -> void:
	assert_true(VillageKinds.all_ids().has(VillageKinds.KIND_GROUND))
	assert_true(VillageKinds.all_ids().has(VillageKinds.KIND_CANOPY))
	assert_eq(VillageKinds.get_kind("gibt_es_nicht").id(), VillageKinds.KIND_GROUND)
	assert_eq(VillageKinds.kind_of_site({}).id(), VillageKinds.KIND_GROUND, "Alte Standorte ohne `kind` sind Bodendörfer.")
	for kind_id: String in VillageKinds.all_ids():
		assert_eq(VillageKinds.get_kind(kind_id).id(), kind_id)

func test_roll_ranges_try_special_kinds_first_and_always_end_with_ground() -> void:
	var low: Array[String] = VillageKinds.ids_for_roll(0.0)
	assert_eq(low[0], VillageKinds.KIND_CANOPY)
	assert_eq(low[low.size() - 1], VillageKinds.KIND_GROUND)
	var high: Array[String] = VillageKinds.ids_for_roll(0.999)
	assert_eq(high, [VillageKinds.KIND_GROUND] as Array[String])

func test_special_kind_chances_do_not_exceed_one() -> void:
	var sum: float = 0.0
	for kind_id: String in VillageKinds.SPECIAL_ORDER:
		sum += VillageKinds.get_kind(kind_id).chance()
	assert_lte(sum, 1.0)

func test_every_kind_catalog_type_builds_and_is_resolvable() -> void:
	for kind_id: String in VillageKinds.all_ids():
		var catalog: Dictionary = VillageKinds.get_kind(kind_id).catalog()
		assert_gt(catalog.size(), 0, "%s hat keinen Katalog." % kind_id)
		for type_id: String in catalog:
			assert_true(BuildingRecipes.has_type(type_id), "%s: Typ %s nicht auflösbar." % [kind_id, type_id])
			var batch := PartBatch.new()
			BuildingRecipes.build(type_id, batch, 3, 1.5)
			assert_gt(batch.triangle_count(), 20, "%s erzeugt keine Geometrie." % type_id)
			var half: Vector2 = BuildingRecipes.half_extents(type_id)
			for slot_entry: Variant in BuildingRecipes.npc_slots(type_id):
				var entry: Array = slot_entry
				var slot: Vector2 = entry[1]
				assert_lte(absf(slot.x), half.x, "%s: NPC-Slot außerhalb." % type_id)
				assert_lte(absf(slot.y), half.y, "%s: NPC-Slot außerhalb." % type_id)
				assert_true(ALLOWED_NPCS.has(String(entry[0])), "%s: unerlaubter NPC-Typ." % type_id)

func test_catalog_types_are_unique_across_kinds() -> void:
	var seen: Dictionary = {}
	for kind_id: String in VillageKinds.all_ids():
		for type_id: String in VillageKinds.get_kind(kind_id).catalog():
			assert_false(seen.has(type_id), "Typ %s kommt in zwei Dorf-Arten vor." % type_id)
			seen[type_id] = kind_id

func test_canopy_footprint_matches_tree_geometry() -> void:
	for type_id: String in CanopyVillageKind.CATALOG:
		var half: Vector2 = BuildingRecipes.half_extents(type_id)
		assert_eq(half.x, CanopyTree.FOOTPRINT_HALF)
		assert_gt(half.x, CanopyTree.RAMP_R + CanopyTree.RAMP_W * 0.5, "Rampe ragt aus dem Grundstück.")

# ── PartBatch-Bausteine ─────────────────────────────────

func test_part_batch_group_moves_geometry_and_collision() -> void:
	var b := PartBatch.new()
	b.push_group(Vector3(0.0, 10.0, 0.0), 0.0)
	b.add_box(Vector3.ONE, Vector3(2.0, 0.0, 0.0), Color.WHITE)
	b.pop_group()
	b.add_box(Vector3.ONE, Vector3(2.0, 0.0, 0.0), Color.WHITE)
	var node: Node3D = b.build("G")
	add_child_autofree(node)
	var body: Node = node.get_node("Body")
	assert_almost_eq((body.get_child(0) as CollisionShape3D).transform.origin.y, 10.0, 0.001)
	assert_almost_eq((body.get_child(1) as CollisionShape3D).transform.origin.y, 0.0, 0.001, "Nach pop_group wieder am Ursprung.")
	var aabb: AABB = (node.get_node("Mesh") as MeshInstance3D).get_aabb()
	assert_almost_eq(aabb.position.y, -0.5, 0.01)
	assert_almost_eq(aabb.end.y, 10.5, 0.01)

func test_part_batch_group_rotation_matches_building_yaw_convention() -> void:
	# Lokal +Z einer um yaw gedrehten Gruppe zeigt nach (sin yaw, cos yaw) — wie SettlementMath.front_dir.
	var yaw: float = 0.7
	var b := PartBatch.new()
	b.push_group(Vector3.ZERO, yaw)
	b.add_box(Vector3.ONE, Vector3(0.0, 0.0, 5.0), Color.WHITE)
	b.pop_group()
	var node: Node3D = b.build("R")
	add_child_autofree(node)
	var pos: Vector3 = (node.get_node("Body").get_child(0) as CollisionShape3D).transform.origin
	var front: Vector2 = SettlementMath.front_dir(yaw) * 5.0
	assert_almost_eq(pos.x, front.x, 0.001)
	assert_almost_eq(pos.z, front.y, 0.001)

func test_part_batch_nested_groups_compose() -> void:
	var b := PartBatch.new()
	b.push_group(Vector3(0.0, 5.0, 0.0), 0.0)
	b.push_group(Vector3(0.0, 3.0, 0.0), 0.0)
	b.add_box(Vector3.ONE, Vector3.ZERO, Color.WHITE)
	b.pop_group()
	b.add_box(Vector3.ONE, Vector3.ZERO, Color.WHITE)
	b.pop_group()
	var node: Node3D = b.build("N")
	add_child_autofree(node)
	var body: Node = node.get_node("Body")
	assert_almost_eq((body.get_child(0) as CollisionShape3D).transform.origin.y, 8.0, 0.001)
	assert_almost_eq((body.get_child(1) as CollisionShape3D).transform.origin.y, 5.0, 0.001)

func test_part_batch_frustum_and_plank() -> void:
	var b := PartBatch.new()
	b.add_frustum(2.0, 1.0, 4.0, Vector3.ZERO, Color.WHITE, true, 10)
	assert_eq(b.triangle_count(), 40, "10 Segmente: 20 Mantel- + 20 Deckeldreiecke.")
	assert_eq(b.shape_count(), 1)
	b.add_plank(Vector3.ZERO, Vector3(4.0, 1.0, 0.0), 1.0, 0.2, Color.WHITE, true)
	assert_eq(b.triangle_count(), 52)
	assert_eq(b.shape_count(), 2)
	b.add_plank(Vector3.ZERO, Vector3(4.0, 1.0, 0.0), 1.0, 0.2, Color.WHITE, false)
	assert_eq(b.shape_count(), 2, "collide=false darf keine Form erzeugen.")

# ── Standortwahl ────────────────────────────────────────

func test_meadow_never_gets_canopy_villages() -> void:
	var field := FlatMeadow.new(null, 777)
	var reg: SettlementRegistry = field.get_settlements()
	var found: int = 0
	for cz in range(-5, 6):
		for cx in range(-5, 6):
			var s: Dictionary = reg.get_site(Vector2i(cx, cz))
			if s.is_empty():
				continue
			found += 1
			assert_eq(String(s["kind"]), VillageKinds.KIND_GROUND)
	assert_gt(found, 5)

func test_forest_gets_a_mix_of_canopy_and_ground_villages() -> void:
	var field := FlatForest.new(null, 4242)
	var reg: SettlementRegistry = field.get_settlements()
	var canopy: int = 0
	var ground: int = 0
	for cz in range(-6, 7):
		for cx in range(-6, 7):
			var s: Dictionary = reg.get_site(Vector2i(cx, cz))
			if s.is_empty() or bool(s["fixed"]):
				continue
			if String(s["kind"]) == VillageKinds.KIND_CANOPY:
				canopy += 1
			else:
				ground += 1
	assert_gt(canopy, 3, "Im Wald müssen Baumdörfer entstehen.")
	assert_gt(ground, 3, "Nicht jedes Dorf im Wald darf ein Baumdorf sein.")

func test_canopy_site_has_own_names_and_labels() -> void:
	var field := FlatForest.new(null, 4242)
	var sites: Array = _canopy_sites(field)
	assert_gt(sites.size(), 0)
	for s: Dictionary in sites:
		var ends_ok: bool = false
		for suffix: String in CanopyVillageKind.SUFFIXES:
			if String(s["name"]).ends_with(suffix):
				ends_ok = true
		assert_true(ends_ok, "Name %s hat keine Baumdorf-Endung." % s["name"])
		assert_true(["Baumweiler", "Baumdorf", "Baumstadt"].has(VillageKinds.tier_label(s)))
		assert_eq(float(s["radius"]), CanopyVillageKind.TIER_RADIUS[s["tier"]])

func test_site_choice_is_deterministic_including_kind() -> void:
	var a := FlatForest.new(null, 99)
	var b := FlatForest.new(null, 99)
	for cz in range(-4, 5):
		for cx in range(-4, 5):
			var sa: Dictionary = a.get_settlements().get_site(Vector2i(cx, cz))
			var sb: Dictionary = b.get_settlements().get_site(Vector2i(cx, cz))
			assert_eq(sa.is_empty(), sb.is_empty())
			if not sa.is_empty():
				assert_eq(sa["kind"], sb["kind"])
				assert_eq(sa["center"], sb["center"])
				assert_eq(sa["name"], sb["name"])

# ── Baumdorf-Layout ─────────────────────────────────────

func test_tree_count_grows_with_tier() -> void:
	var field := FlatForest.new(null, 4242)
	var hamlet: Dictionary = _site_of_tier(field, "hamlet")
	var village: Dictionary = _site_of_tier(field, "village")
	var town: Dictionary = _site_of_tier(field, "town")
	assert_false(hamlet.is_empty())
	assert_false(village.is_empty())
	assert_false(town.is_empty())
	var n_h: int = (_layout_of(field, hamlet)["buildings"] as Array).size()
	var n_v: int = (_layout_of(field, village)["buildings"] as Array).size()
	var n_t: int = (_layout_of(field, town)["buildings"] as Array).size()
	assert_eq(n_h, 1, "Der Baumweiler beginnt klein: ein Riesenbaum.")
	assert_eq(n_v, 3)
	assert_eq(n_t, 5)

func test_hamlet_starts_small_two_levels_four_huts_no_bridges() -> void:
	var field := FlatForest.new(null, 4242)
	var tree: Dictionary = (_layout_of(field, _site_of_tier(field, "hamlet"))["buildings"] as Array)[0]
	var params: Dictionary = tree["params"]
	assert_eq(String(tree["type"]), CanopyVillageKind.T_ELDER)
	assert_eq(int(params["level_count"]), 2)
	assert_false(bool(params["hall"]))
	assert_eq((params["links"] as Array).size(), 0)
	var huts: int = 0
	for n: int in params["huts"]:
		huts += n
	assert_eq(huts, 4)

func test_trees_do_not_overlap_and_keep_distance() -> void:
	var field := FlatForest.new(null, 4242)
	for tier: String in ["village", "town"]:
		var list: Array = _layout_of(field, _site_of_tier(field, tier))["buildings"]
		for i in range(list.size()):
			for j in range(i + 1, list.size()):
				var a: Dictionary = list[i]
				var b: Dictionary = list[j]
				var d: float = Vector2(float(a["x"]), float(a["z"])).distance_to(Vector2(float(b["x"]), float(b["z"])))
				assert_gte(d, CanopyLayout.MIN_TREE_DIST, "Bäume zu dicht (%.1f m)." % d)

func test_first_tree_is_elder_in_village_center() -> void:
	var field := FlatForest.new(null, 4242)
	var site: Dictionary = _site_of_tier(field, "village")
	var list: Array = _layout_of(field, site)["buildings"]
	var elder: Dictionary = list[0]
	assert_eq(String(elder["type"]), CanopyVillageKind.T_ELDER)
	assert_lt(Vector2(float(elder["x"]), float(elder["z"])).distance_to(site["center"] as Vector2), 6.0)
	assert_true(bool((elder["params"] as Dictionary)["hall"]))
	for i in range(1, list.size()):
		assert_eq(String((list[i] as Dictionary)["type"]), CanopyVillageKind.T_GROVE)

func test_village_trees_are_all_connected_by_bridges() -> void:
	var field := FlatForest.new(null, 4242)
	var list: Array = _layout_of(field, _site_of_tier(field, "village"))["buildings"]
	var by_id: Dictionary = {}
	for t: Dictionary in list:
		by_id[t["id"]] = t
	var link_total: int = 0
	var reached: Dictionary = {list[0]["id"]: true}
	var changed: bool = true
	while changed:
		changed = false
		for t: Dictionary in list:
			if not reached.has(t["id"]):
				continue
			for l: Dictionary in (t["params"] as Dictionary)["links"]:
				if not reached.has(l["peer"]):
					reached[l["peer"]] = true
					changed = true
	for t: Dictionary in list:
		link_total += ((t["params"] as Dictionary)["links"] as Array).size()
	assert_eq(reached.size(), list.size(), "Alle Bäume müssen über Brücken erreichbar sein.")
	assert_eq(link_total, 2 * (list.size() - 1), "Spannbaum: n−1 Brücken, je zwei Hälften.")

func test_bridge_halves_meet_in_the_middle_on_a_slope() -> void:
	var field := SlopedForest.new(null, 4242)
	var found_bridge: bool = false
	for s: Dictionary in _canopy_sites(field):
		var list: Array = _layout_of(field, s)["buildings"]
		var by_id: Dictionary = {}
		for t: Dictionary in list:
			by_id[t["id"]] = t
		for a: Dictionary in list:
			for l: Dictionary in (a["params"] as Dictionary)["links"]:
				found_bridge = true
				var b: Dictionary = by_id[l["peer"]]
				var back: Dictionary = {}
				for l2: Dictionary in (b["params"] as Dictionary)["links"]:
					if l2["peer"] == a["id"]:
						back = l2
				assert_false(back.is_empty(), "Brücke ohne Gegenstück.")
				var pa: Vector3 = CanopyTree.bridge_points(l, CanopyTree.LEVELS[CanopyTree.BRIDGE_LEVEL]).slice(-1)[0]
				var pb: Vector3 = CanopyTree.bridge_points(back, CanopyTree.LEVELS[CanopyTree.BRIDGE_LEVEL]).slice(-1)[0]
				assert_almost_eq(float(a["x"]) + pa.x, float(b["x"]) + pb.x, 0.001)
				assert_almost_eq(float(a["z"]) + pa.z, float(b["z"]) + pb.z, 0.001)
				assert_almost_eq(float(a["y"]) + pa.y, float(b["y"]) + pb.y, 0.001, "Brückenhälften treffen sich nicht in der Höhe.")
	assert_true(found_bridge)

func test_bridge_slope_is_walkable() -> void:
	var field := SlopedForest.new(null, 4242)
	for s: Dictionary in _canopy_sites(field):
		for a: Dictionary in _layout_of(field, s)["buildings"]:
			for l: Dictionary in (a["params"] as Dictionary)["links"]:
				var pts: PackedVector3Array = CanopyTree.bridge_points(l, CanopyTree.LEVELS[CanopyTree.BRIDGE_LEVEL])
				assert_gt(pts.size(), 2)
				for i in range(pts.size() - 1):
					var run: float = Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z).length()
					var rise: float = absf(pts[i + 1].y - pts[i].y)
					assert_lt(rise / run, 0.45, "Brücke zu steil.")

func test_ramp_phase_keeps_bridges_clear() -> void:
	var field := SlopedForest.new(null, 4242)
	var checked: int = 0
	for s: Dictionary in _canopy_sites(field):
		for t: Dictionary in _layout_of(field, s)["buildings"]:
			var params: Dictionary = t["params"]
			if (params["links"] as Array).is_empty():
				continue
			var angles: Array = []
			for l: Dictionary in params["links"]:
				angles.append(atan2(float(l["mz"]), float(l["mx"])))
			var score: float = CanopyTree.phase_score(float(params["phase"]), CanopyTree.level_heights(int(params["level_count"])), angles, -float(t["spread"]))
			assert_gte(score, 0.95, "Rampe kollidiert mit Brücke/Zufahrt (Score %.2f)." % score)
			checked += 1
	assert_gt(checked, 0)

func test_hut_angles_respect_separation_and_blocked_directions() -> void:
	var blocked: Array = [0.3, 2.0]
	var angles: Array[float] = CanopyTree.hut_angles(3, blocked, 4)
	assert_eq(angles.size(), 3)
	for i in range(angles.size()):
		for bl: float in blocked:
			assert_gte(CanopyTree.ang_diff(angles[i], bl), CanopyTree.HUT_BLOCK_MARGIN)
		for j in range(i + 1, angles.size()):
			assert_gte(CanopyTree.ang_diff(angles[i], angles[j]), CanopyTree.HUT_MIN_SEP)

func test_ramp_geometry_is_walkable() -> void:
	var slope_deg: float = rad_to_deg(atan(CanopyTree.RAMP_SLOPE))
	assert_lt(slope_deg, 20.0)
	# Rampe verläuft außerhalb des Decks; der Steg verbindet beide (flach, auf Deckhöhe).
	var inner_edge: float = CanopyTree.RAMP_R - CanopyTree.RAMP_W * 0.5
	assert_gt(inner_edge, CanopyTree.PLATFORM_R)
	assert_gt(CanopyTree.LEAD_IN_R0, inner_edge, "Steg muss die Rampe berühren.")
	assert_lt(CanopyTree.LEAD_IN_R1, CanopyTree.PLATFORM_R, "Steg muss auf dem Deck enden.")
	# Rampenhöhe am Steg = Deckhöhe (bei jedem Startwinkel/Starthöhe).
	for ly: float in CanopyTree.LEVELS:
		var phi: float = CanopyTree.landing_angle(ly, 1.3, -1.7)
		assert_almost_eq(CanopyTree.ramp_y(phi, 1.3, -1.7), ly, 0.0001)

func test_streets_stop_at_the_elder_plaza() -> void:
	var field := FlatForest.new(null, 4242)
	var site: Dictionary = _site_of_tier(field, "village")
	var center: Vector2 = site["center"]
	var layout: Dictionary = _layout_of(field, site)
	for st: Dictionary in layout["streets"]:
		assert_gte((st["a"] as Vector2).distance_to(center), CanopyLayout.HUB_CLEAR - 0.1)
		assert_gte((st["b"] as Vector2).distance_to(center), CanopyLayout.HUB_CLEAR - 0.1)

func test_foot_paths_connect_each_tree() -> void:
	var field := FlatForest.new(null, 4242)
	var layout: Dictionary = _layout_of(field, _site_of_tier(field, "village"))
	assert_gte((layout["paths"] as Array).size(), 2)

func test_canopy_layout_is_independent_of_query_order() -> void:
	var a := FlatForest.new(null, 4242)
	var s: Dictionary = _site_of_tier(a, "village")
	var b := FlatForest.new(null, 4242)
	var cell: Vector2i = s["cell"]
	b.get_settlements().ensure_cell(cell + Vector2i(1, 1))
	b.get_settlements().ensure_cell(cell + Vector2i(-1, 0))
	b.get_settlements().ensure_cell(cell)
	a.get_settlements().ensure_cell(cell)
	var la: Array = a.get_settlements().get_layout(s["id"])["buildings"]
	var lb: Array = b.get_settlements().get_layout(s["id"])["buildings"]
	assert_eq(la.size(), lb.size())
	for i in range(la.size()):
		assert_eq((la[i] as Dictionary)["x"], (lb[i] as Dictionary)["x"])
		assert_eq(((la[i] as Dictionary)["params"] as Dictionary)["phase"], ((lb[i] as Dictionary)["params"] as Dictionary)["phase"])
		assert_eq(((la[i] as Dictionary)["params"] as Dictionary)["links"], ((lb[i] as Dictionary)["params"] as Dictionary)["links"])

# ── Gebäude, Chunk, Vegetation ──────────────────────────

func test_planned_trees_build_with_collision_and_sane_triangle_count() -> void:
	var field := FlatForest.new(null, 4242)
	var site: Dictionary = _site_of_tier(field, "town")
	assert_false(site.is_empty())
	var list: Array = _layout_of(field, site)["buildings"]
	for t: Dictionary in list:
		var batch := PartBatch.new()
		BuildingRecipes.build(String(t["type"]), batch, int(t["variant"]), float(t["spread"]) + ChunkSettlementBuilder.SLAB_RESERVE, t)
		assert_gt(batch.triangle_count(), 1500, "Baum zu karg.")
		assert_lt(batch.triangle_count(), 25000, "Baum zu teuer für Mobilgeräte.")
		assert_lt(batch.shape_count(), 450, "Zu viele Kollisionsformen je Baum.")
		assert_gt(batch.shape_count(), 60)

func test_chunk_builder_builds_canopy_trees_as_single_nodes() -> void:
	var field := FlatForest.new(null, 4242)
	var site: Dictionary = _site_of_tier(field, "village")
	var list: Array = _layout_of(field, site)["buildings"]
	var root: Node3D = ChunkSettlementBuilder.build(list, site["center"])
	add_child_autofree(root)
	assert_eq(root.get_child_count(), list.size())
	for n: Node in root.get_children():
		assert_not_null(n.get_node_or_null("Mesh"))
		assert_not_null(n.get_node_or_null("Body"))

func test_trees_block_vegetation_and_keep_lot_in_active_zone_radius() -> void:
	var field := FlatForest.new(null, 4242)
	var reg: SettlementRegistry = field.get_settlements()
	var list: Array = _layout_of(field, _site_of_tier(field, "village"))["buildings"]
	for t: Dictionary in list:
		assert_true(reg.blocks_vegetation(float(t["x"]), float(t["z"]), 0.5))
		assert_lte(BuildingRecipes.radius(String(t["type"])), ChunkSettlementBuilder.MAX_FOOTPRINT_RADIUS)

func test_ground_villages_still_work_beside_canopy_ones() -> void:
	var field := FlatForest.new(null, 4242)
	var reg: SettlementRegistry = field.get_settlements()
	var checked: int = 0
	for cz in range(-6, 7):
		for cx in range(-6, 7):
			var s: Dictionary = reg.get_site(Vector2i(cx, cz))
			if s.is_empty() or bool(s["fixed"]) or String(s["kind"]) != VillageKinds.KIND_GROUND:
				continue
			reg.ensure_cell(Vector2i(cx, cz))
			assert_gte((reg.get_layout(s["id"])["buildings"] as Array).size(), 4)
			checked += 1
	assert_gt(checked, 0)

# ── Echte Physik: kann man den Baum hochlaufen? ─────────

## Läuft `body` geradeaus (xz) auf `target` zu, bis er < 0.6 m davor ist (max. `max_frames` Physik-Frames).
func _walk_to(body: CharacterBody3D, target: Vector2, max_frames: int = 240) -> bool:
	for _i in range(max_frames):
		var here := Vector2(body.global_position.x, body.global_position.z)
		var to_t: Vector2 = target - here
		if to_t.length() < 0.6:
			return true
		var dir: Vector2 = to_t.normalized()
		body.velocity.x = dir.x * 4.0
		body.velocity.z = dir.y * 4.0
		body.velocity.y -= 12.0 / 60.0
		body.move_and_slide()
		await get_tree().physics_frame
	return false

func test_player_can_walk_up_the_ramp_and_onto_the_platform() -> void:
	var batch := PartBatch.new()
	var info: Dictionary = {"spread": 0.0, "params": {"level_count": 2, "huts": [2, 2], "phase": 0.0, "links": [], "hall": false}}
	BuildingRecipes.build(CanopyVillageKind.T_ELDER, batch, 5, 1.4, info)
	var tree: Node3D = batch.build("Tree")
	add_child_autofree(tree)
	var ground := StaticBody3D.new()
	var gcol := CollisionShape3D.new()
	var gshape := BoxShape3D.new()
	gshape.size = Vector3(80.0, 1.0, 80.0)
	gcol.shape = gshape
	ground.add_child(gcol)
	ground.position = Vector3(0.0, -0.5, 0.0)
	add_child_autofree(ground)
	var body := CharacterBody3D.new()
	var bcol := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	bcol.shape = cap
	body.add_child(bcol)
	add_child_autofree(body)
	var phase: float = 0.0
	var y0: float = 0.0
	var start: Vector3 = CanopyTree.ramp_point(phase - 0.3, phase, y0)
	body.global_position = Vector3(start.x, 1.0, start.z)
	await get_tree().physics_frame
	var level: float = CanopyTree.LEVELS[0]
	var phi: float = CanopyTree.landing_angle(level, phase, y0)
	var theta: float = phase
	var steps: int = ceili((phi - phase) / CanopyTree.RAMP_STEP)
	for i in range(steps + 1):
		theta = minf(phase + float(i) * CanopyTree.RAMP_STEP, phi)
		var p: Vector3 = CanopyTree.ramp_point(theta, phase, y0)
		var ok: bool = await _walk_to(body, Vector2(p.x, p.z))
		assert_true(ok, "Hängt an Rampenstück %d fest (Höhe %.2f, Soll %.2f)." % [i, body.global_position.y, p.y])
		if not ok:
			return
	# Zufahrt: von der Rampe radial nach innen auf die Plattform.
	var inner := Vector2(cos(phi), sin(phi)) * 7.8
	var reached: bool = await _walk_to(body, inner)
	var dbg: String = ""
	if not reached:
		for ci in range(body.get_slide_collision_count()):
			var kc: KinematicCollision3D = body.get_slide_collision(ci)
			dbg += " | n=%s pos=%s" % [kc.get_normal(), kc.get_position()]
		var pc: Vector3 = CanopyTree.ramp_point(phi, phase, y0)
		dbg += " | ramp_pt=%s floor=%s ang=%.3f" % [pc, body.is_on_floor(), atan2(body.global_position.z, body.global_position.x)]
	assert_true(reached, "Kommt nicht von der Rampe auf die Plattform (Pos %s, Ziel %s, phi %.3f)%s" % [body.global_position, inner, phi, dbg])
	assert_gt(body.global_position.y, level - 0.4, "Nicht auf Plattformhöhe (%.2f)." % body.global_position.y)
	assert_lt(body.global_position.y, level + 1.4)

func test_player_can_cross_a_bridge_between_two_trees_on_a_slope() -> void:
	var field := SlopedForest.new(null, 4242)
	var a: Dictionary = {}
	var link: Dictionary = {}
	var list: Array = []
	var site: Dictionary = {}
	for s: Dictionary in _canopy_sites(field):
		var candidate: Array = _layout_of(field, s)["buildings"]
		for t: Dictionary in candidate:
			var links: Array = (t["params"] as Dictionary)["links"]
			if not links.is_empty() and absf(float((links[0] as Dictionary)["dh"])) > 0.5:
				a = t
				link = links[0]
				list = candidate
				site = s
				break
		if not a.is_empty():
			break
	assert_false(a.is_empty(), "Kein Baum mit Brücke auf geneigtem Gelände gefunden.")
	if a.is_empty():
		return
	var b: Dictionary = {}
	for t2: Dictionary in list:
		if t2["id"] == link["peer"]:
			b = t2
	var origin: Vector2 = site["center"]
	var root: Node3D = ChunkSettlementBuilder.build(list, origin)
	add_child_autofree(root)
	var body := CharacterBody3D.new()
	var bcol := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	bcol.shape = cap
	body.add_child(bcol)
	add_child_autofree(body)
	var deck_a: float = float(a["y"]) + ChunkSettlementBuilder.SLAB_TOP + CanopyTree.LEVELS[CanopyTree.BRIDGE_LEVEL]
	var deck_b: float = float(b["y"]) + ChunkSettlementBuilder.SLAB_TOP + CanopyTree.LEVELS[CanopyTree.BRIDGE_LEVEL]
	var pos_a := Vector2(float(a["x"]) - origin.x, float(a["z"]) - origin.y)
	var pos_b := Vector2(float(b["x"]) - origin.x, float(b["z"]) - origin.y)
	var dir: Vector2 = (pos_b - pos_a).normalized()
	var start: Vector2 = pos_a + dir * 7.8
	body.global_position = Vector3(start.x, deck_a + 1.0, start.y)
	for _i in range(3):
		await get_tree().physics_frame
	var pts: PackedVector3Array = CanopyTree.bridge_points(link, CanopyTree.LEVELS[CanopyTree.BRIDGE_LEVEL])
	for i in range(pts.size()):
		var w := Vector2(pos_a.x + pts[i].x, pos_a.y + pts[i].z)
		var ok: bool = await _walk_to(body, w)
		assert_true(ok, "Bleibt auf der Brücke bei Punkt %d hängen (Pos %s)." % [i, body.global_position])
		if not ok:
			return
	var target: Vector2 = pos_b - dir * 7.8
	var reached: bool = await _walk_to(body, target, 480)
	assert_true(reached, "Kommt nicht auf die Plattform des Nachbarbaums (Pos %s, Ziel %s)." % [body.global_position, target])
	assert_almost_eq(body.global_position.y - 0.9, deck_b, 0.35, "Nicht auf Deckhöhe des Nachbarbaums.")

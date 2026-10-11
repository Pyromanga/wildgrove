## tests/unit/test_tree_skeleton.gd
## Verzweigte Bäume in echten Proportionen (TreeSkeleton + MeshCache._assemble_tree), Wunsch
## 2026-10-07: "Bäume sind winzig im Vergleich zum Spieler, kaum Verästelungen, jeder Baum nur 7 Blätter".
## Ohne Godot-Binary geschrieben — beim ersten GUT-Lauf beobachten.

extends GutTest

const PLAYER_HEIGHT: float = 1.8

var _cache: MeshCache

func before_all() -> void:
	_cache = MeshCache.new()
	_cache.build()

## Höchster Punkt der Szene aus den AABBs aller MultiMeshes (Koordinaten lokal zur Wurzel).
func _scene_height(key: String) -> float:
	var root: Node3D = _cache.instantiate_scene(key)
	autofree(root)
	var top := 0.0
	for child in root.get_children():
		if child is MultiMeshInstance3D:
			top = maxf(top, (child as MultiMeshInstance3D).multimesh.get_aabb().end.y)
	return top

func _card_count(key: String) -> int:
	var root: Node3D = _cache.instantiate_scene(key)
	autofree(root)
	var n := 0
	for child in root.get_children():
		if String(child.name).begins_with("Leaves"):
			n += (child as MultiMeshInstance3D).multimesh.instance_count
	return n

func _small_cfg() -> Dictionary:
	return {
		"trunk_height": 4.0, "trunk_radius": 0.4, "trunk_segments": 4, "trunk_bend": 0.1, "leaf_min_level": 2,
		"levels": [
			{"count": 6, "t_min": 0.5, "t_max": 0.95, "ang_min": 40.0, "ang_max": 65.0, "len_min": 0.9, "len_max": 1.2,
			 "rad_frac": 0.5, "segments": 3, "droop": 0.04, "bend": 0.15, "up_bias": 0.1},
			{"count": 4, "t_min": 0.3, "t_max": 0.95, "ang_min": 30.0, "ang_max": 60.0, "len_min": 0.45, "len_max": 0.65,
			 "rad_frac": 0.55, "segments": 2, "droop": 0.05, "bend": 0.2, "up_bias": 0.1},
			{"count": 2, "t_min": 0.4, "t_max": 0.9, "ang_min": 25.0, "ang_max": 55.0, "len_min": 0.45, "len_max": 0.6,
			 "rad_frac": 0.6, "segments": 2, "droop": 0.04, "bend": 0.2, "up_bias": 0.1},
		],
	}

# ── Skelett ─────────────────────────────────────────────

func test_skeleton_is_deterministic() -> void:
	var a := TreeSkeleton.deciduous(_small_cfg(), 1.0, 3, 1.0, 77)
	var b := TreeSkeleton.deciduous(_small_cfg(), 1.0, 3, 1.0, 77)
	assert_eq(a["segments"].size(), b["segments"].size())
	assert_eq(a["tips"].size(), b["tips"].size())
	assert_eq(a["segments"][5]["b"], b["segments"][5]["b"])
	var c := TreeSkeleton.deciduous(_small_cfg(), 1.0, 3, 1.0, 78)
	assert_ne(a["segments"][5]["b"], c["segments"][5]["b"], "anderer Seed → andere Form")

func test_deeper_levels_add_branches_and_tips() -> void:
	var l1 := TreeSkeleton.deciduous(_small_cfg(), 1.0, 1, 1.0, 5)
	var l2 := TreeSkeleton.deciduous(_small_cfg(), 1.0, 2, 1.0, 5)
	var l3 := TreeSkeleton.deciduous(_small_cfg(), 1.0, 3, 1.0, 5)
	assert_gt(l2["segments"].size(), l1["segments"].size())
	assert_gt(l3["segments"].size(), l2["segments"].size())
	assert_gt(l3["tips"].size(), l1["tips"].size())
	# 6 Hauptäste × 4 Seitenäste × 2 Zweige — deutlich mehr als die früheren 2 Äste.
	assert_gte(l3["tips"].size(), 40)

func test_every_branch_starts_where_its_parent_is() -> void:
	# Kein Ast darf "in der Luft" hängen: jeder Start liegt (fast) auf einem anderen Abschnitt.
	var sk := TreeSkeleton.deciduous(_small_cfg(), 1.0, 3, 1.0, 9)
	var segs: Array = sk["segments"]
	for i in range(segs.size()):
		if int(segs[i]["level"]) == 0:
			continue
		var start: Vector3 = segs[i]["a"]
		var best := INF
		for j in range(segs.size()):
			if j == i:
				continue
			var a: Vector3 = segs[j]["a"]
			var b: Vector3 = segs[j]["b"]
			var closest := Geometry3D.get_closest_point_to_segment(start, a, b)
			best = minf(best, start.distance_to(closest))
		assert_lt(best, 0.05, "Ast %d hängt frei in der Luft" % i)

func test_radii_taper_along_trunk() -> void:
	var sk := TreeSkeleton.deciduous(_small_cfg(), 1.0, 0, 1.0, 1)
	var radii: Array[float] = []
	for seg: Dictionary in sk["segments"]:
		radii.append(float(seg["r"]))
	for i in range(1, radii.size()):
		assert_lt(radii[i], radii[i - 1])

func test_scale_scales_height() -> void:
	var full := TreeSkeleton.deciduous(_small_cfg(), 1.0, 3, 1.0, 3)
	var small := TreeSkeleton.deciduous(_small_cfg(), 0.25, 3, 1.0, 3)
	assert_almost_eq(float(small["height"]), float(full["height"]) * 0.25, 0.01)

func test_conifer_has_whorls_shrinking_upwards() -> void:
	var cfg := {
		"trunk_height": 13.0, "trunk_radius": 0.3, "trunk_segments": 5, "trunk_bend": 0.05, "leaf_min_level": 1,
		"whorl_t_min": 0.16, "whorl_t_max": 0.97, "per_whorl": 5, "len_base": 3.4, "len_top": 0.5,
		"levels": [
			{"count": 1, "t_min": 0.0, "t_max": 1.0, "ang_min": 74.0, "ang_max": 104.0, "len_min": 1.0, "len_max": 1.0,
			 "rad_frac": 0.3, "segments": 2, "droop": 0.1, "bend": 0.08, "up_bias": 0.0},
			{"count": 2, "t_min": 0.35, "t_max": 0.95, "ang_min": 50.0, "ang_max": 70.0, "len_min": 0.3, "len_max": 0.45,
			 "rad_frac": 0.5, "segments": 2, "droop": 0.05, "bend": 0.1, "up_bias": 0.0},
		],
	}
	var sk := TreeSkeleton.conifer(cfg, 1.0, 11, 2, 4)
	var branch_reach_low := 0.0
	var branch_reach_high := 0.0
	for seg: Dictionary in sk["segments"]:
		if int(seg["level"]) != 1:
			continue
		var b: Vector3 = seg["b"]
		var reach := Vector2(b.x, b.z).length()
		if b.y < 4.0:
			branch_reach_low = maxf(branch_reach_low, reach)
		elif b.y > 10.0:
			branch_reach_high = maxf(branch_reach_high, reach)
	assert_gt(branch_reach_low, branch_reach_high * 2.0, "unten breiter als oben (Tannenform)")
	assert_gte(sk["tips"].size(), 100)

func test_min_y_keeps_hanging_branches_off_the_ground() -> void:
	var cfg := _small_cfg()
	cfg["min_y"] = 1.4
	# Extrem hängende Zweige — ohne min_y würden sie unter 0 enden.
	cfg["levels"][1]["droop"] = 0.9
	cfg["levels"][2]["droop"] = 0.9
	var sk := TreeSkeleton.deciduous(cfg, 1.0, 3, 1.0, 12)
	for seg: Dictionary in sk["segments"]:
		if int(seg["level"]) >= 1:
			assert_gte((seg["b"] as Vector3).y, 1.4 - 0.001, "Ast endet unter min_y")
	var no_floor := TreeSkeleton.deciduous(_small_cfg(), 1.0, 3, 1.0, 12)
	assert_eq(no_floor["floor"], -1000.0, "ohne min_y keine Grenze")

# ── Karten / Blobs ──────────────────────────────────────

func test_cards_surround_the_tip_and_face_outwards() -> void:
	var pos := Vector3(2, 5, 1)
	var cards := TreeSkeleton.cards_for_tip(pos, 8, 1.0, 1.5, 3)
	assert_eq(cards.size(), 8)
	for c in cards:
		assert_lte(c.origin.distance_to(pos), 1.0 + 0.001, "Karte außerhalb des Büschelradius")
		assert_almost_eq(c.basis.z.length(), 1.0, 0.01, "Normale ist normiert (nur x/y tragen die Größe)")

func test_crown_blobs_merge_nearby_tips() -> void:
	var tips: Array = []
	for i in range(10):
		tips.append({"pos": Vector3(float(i) * 0.1, 5.0, 0.0), "level": 3})
	var blobs := TreeSkeleton.crown_blobs(tips, 2.0, 1.7)
	assert_lte(blobs.size(), 2)
	assert_gt(float(blobs[0]["r"]), 0.0)

# ── Fertige Bäume ───────────────────────────────────────

func test_mature_trees_are_much_taller_than_the_player() -> void:
	for key in ["tree_oak", "tree_maple", "tree_willow", "tree_pine", "tree_pine_snow"]:
		var h := _scene_height(key)
		assert_gt(h, PLAYER_HEIGHT * 3.5, "%s: nur %.1f m hoch" % [key, h])
		assert_lt(h, 20.0, "%s: unplausibel hoch (%.1f m)" % [key, h])
	assert_gt(_scene_height("tree_pine"), _scene_height("tree_oak"), "Tanne höher als Eiche")

func test_growth_stages_get_taller() -> void:
	for species in ["oak", "maple", "willow", "pine"]:
		var s := _scene_height("tree_%s_sapling" % species)
		var y := _scene_height("tree_%s_young" % species)
		var m := _scene_height("tree_%s" % species)
		assert_lt(s, y, "%s: Sapling < Jungbaum" % species)
		assert_lt(y, m, "%s: Jungbaum < ausgewachsen" % species)
		assert_lt(s, PLAYER_HEIGHT * 2.5, "%s: Sapling soll ≈ Spielergröße haben" % species)

func test_trees_have_hundreds_of_leaf_cards_not_seven() -> void:
	assert_gt(_card_count("tree_oak"), 150)
	assert_gt(_card_count("tree_maple"), 100)
	assert_gt(_card_count("tree_willow"), 60)
	assert_gt(_card_count("tree_pine"), 150)
	assert_gt(_card_count("tree_oak"), _card_count("tree_oak_young"))
	assert_gt(_card_count("tree_oak_young"), _card_count("tree_oak_sapling") / 2)

func test_trees_stay_light_in_nodes() -> void:
	for key in ["tree_oak", "tree_willow", "tree_maple", "tree_pine", "tree_pine_snow"]:
		var root: Node3D = _cache.instantiate_scene(key)
		autofree(root)
		assert_lte(root.get_child_count(), 10, "%s: zu viele Nodes — MultiMesh nutzen" % key)

func test_snow_pine_has_extra_snow_node() -> void:
	var root: Node3D = _cache.instantiate_scene("tree_pine_snow")
	autofree(root)
	assert_not_null(root.get_node_or_null("Snow"))
	var plain: Node3D = _cache.instantiate_scene("tree_pine")
	autofree(plain)
	assert_null(plain.get_node_or_null("Snow"))

func test_near_lod_extends_to_tree_scale() -> void:
	assert_gte(MeshCache.LOD_NEAR_DISTANCE, 40.0, "Laub muss bei großen Bäumen weit sichtbar bleiben")
	var root: Node3D = _cache.instantiate_scene("tree_oak")
	autofree(root)
	var leaves := root.get_node("Leaves0") as MultiMeshInstance3D
	var far := root.get_node("CrownFar") as MultiMeshInstance3D
	assert_eq(leaves.visibility_range_end, MeshCache.LOD_NEAR_DISTANCE)
	assert_eq(far.visibility_range_begin, MeshCache.LOD_NEAR_DISTANCE)

func test_foliage_texture_is_dense_not_a_single_leaf() -> void:
	var tex := ProceduralTextureFactory.foliage_card(128, 3, ProceduralTextureFactory.LeafShape.LOBED, 14, 0.55)
	var img := tex.get_image()
	var opaque := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a > 0.5:
				opaque += 1
	var coverage := float(opaque) / float(img.get_width() * img.get_height())
	assert_gt(coverage, 0.25, "Büschel-Karte soll gut gefüllt sein")
	assert_lt(coverage, 0.95, "…aber Lücken zum Durchsehen haben")

func test_needle_spray_texture_has_pixels() -> void:
	var img := ProceduralTextureFactory.foliage_card(128, 60, ProceduralTextureFactory.LeafShape.NEEDLE, 12).get_image()
	var opaque := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a > 0.5:
				opaque += 1
	assert_gt(opaque, 300)

# ── Spawner: Platzbedarf ────────────────────────────────

func test_trees_need_more_room_than_small_props() -> void:
	assert_gt(ChunkEntitySpawner.PROP_RADIUS_TREE, ChunkEntitySpawner.PROP_RADIUS_SMALL)
	for t in ["oak_tree", "maple_tree", "willow_tree", "pine_tree"]:
		assert_true(t in ChunkEntitySpawner.TREE_PROP_TYPES)

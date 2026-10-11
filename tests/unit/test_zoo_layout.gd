# res://tests/unit/test_zoo_layout.gd
extends GutTest

## Unit-Tests für ZooLayout (reine Arithmetik, keine Nodes) und ZooMeasure (Tiermodell-Maße).

func test_inner_size_fits_animal_with_margin() -> void:
	var box := AABB(Vector3(-1.0, 0.0, -2.0), Vector3(2.0, 1.5, 4.0))
	var inner := ZooLayout.inner_size(box, false)
	assert_almost_eq(inner.x, 2.0 + ZooLayout.SIDE_MARGIN * 2.0, 0.0001)
	assert_almost_eq(inner.z, 4.0 + ZooLayout.SIDE_MARGIN * 2.0, 0.0001)
	assert_almost_eq(inner.y, 1.5 + ZooLayout.HEAD_MARGIN, 0.0001)

func test_inner_size_never_below_minimum() -> void:
	var tiny := AABB(Vector3.ZERO, Vector3(0.05, 0.04, 0.05))
	var inner := ZooLayout.inner_size(tiny, false)
	assert_eq(inner, ZooLayout.MIN_INNER)

func test_aquatic_gets_tall_tank() -> void:
	var fish := AABB(Vector3(-0.1, 0.0, -0.2), Vector3(0.2, 0.5, 0.4))
	var tank := ZooLayout.inner_size(fish, true)
	assert_almost_eq(tank.y, maxf(0.5 * ZooLayout.AQUATIC_HEIGHT_FACTOR, ZooLayout.AQUATIC_MIN_INNER.y), 0.0001)
	assert_gte(tank.x, ZooLayout.AQUATIC_MIN_INNER.x)

func test_footprint_adds_frame_and_plinth() -> void:
	var fp := ZooLayout.footprint(Vector3(2.0, 1.0, 3.0))
	var extra: float = (ZooLayout.FRAME + ZooLayout.PLINTH) * 2.0
	assert_almost_eq(fp.x, 2.0 + extra, 0.0001)
	assert_almost_eq(fp.y, 3.0 + extra, 0.0001)

func test_pack_wraps_rows_and_never_overlaps() -> void:
	var fps: Array[Vector2] = []
	for i in range(40):
		fps.append(Vector2(2.0 + float(i % 5) * 0.7, 2.0 + float(i % 3) * 0.9))
	var packed := ZooLayout.pack(fps)
	var centers: Array = packed["centers"]
	assert_eq(centers.size(), fps.size())
	for i in range(centers.size()):
		var a := Rect2((centers[i] as Vector2) - fps[i] * 0.5, fps[i])
		assert_gte(a.position.x, -0.0001, "Kasten %d links im Zoo" % i)
		assert_lte(a.end.x, ZooLayout.ROW_MAX_WIDTH + 0.0001, "Kasten %d innerhalb der Zeilenbreite" % i)
		for j in range(i + 1, centers.size()):
			var b := Rect2((centers[j] as Vector2) - fps[j] * 0.5, fps[j])
			assert_false(a.intersects(b), "Kasten %d und %d überlappen" % [i, j])

func test_pack_leaves_aisle_between_rows() -> void:
	var fps: Array[Vector2] = [Vector2(40.0, 3.0), Vector2(40.0, 3.0)]  # zweiter passt nicht mehr in Zeile 1
	var packed := ZooLayout.pack(fps)
	var c: Array = packed["centers"]
	var gap: float = ((c[1] as Vector2).y - 1.5) - ((c[0] as Vector2).y + 1.5)
	assert_almost_eq(gap, ZooLayout.AISLE, 0.0001)

func test_clear_zone_circles_cover_whole_zoo_rect() -> void:
	var circles := ZooLayout.clear_zone_circles()
	var r := ZooLayout.ZOO_RECT
	var step := 1.0
	var x := r.position.x
	while x <= r.end.x:
		var z := r.position.y
		while z <= r.end.y:
			var covered := false
			for c: Vector3 in circles:
				if (x - c.x) * (x - c.x) + (z - c.y) * (z - c.y) < c.z * c.z:
					covered = true
					break
			assert_true(covered, "(%.0f, %.0f) nicht von einer Freihaltezone überdeckt" % [x, z])
			z += 4.0
		x += 4.0 * step

func test_zones_for_chunk_only_returns_touching_circles() -> void:
	var far := ZooLayout.zones_for_chunk(Vector2(5000.0, 5000.0), 64.0)
	assert_eq(far.size(), 0)
	var near := ZooLayout.zones_for_chunk(Vector2(0.0, 64.0), 64.0)
	assert_gt(near.size(), 0)

func test_spawn_origin_not_inside_zoo_rect() -> void:
	# Der Spieler spawnt bei (0,0) und soll nicht im Zoo landen.
	assert_false(ZooLayout.ZOO_RECT.has_point(Vector2.ZERO))

# ─────────────────────────────────────────────
# ZooMeasure
# ─────────────────────────────────────────────

func test_all_type_ids_cover_curated_and_db_without_duplicates() -> void:
	var ids := ZooMeasure.all_type_ids()
	assert_eq(ids.size(), ZooMeasure.CURATED_IDS.size() + AnimalSpeciesDB.SPECIES.size())
	var seen := {}
	for id in ids:
		assert_false(seen.has(id), "doppelte Tier-ID %s" % id)
		seen[id] = true

func test_every_animal_is_measurable_with_positive_box_and_name() -> void:
	for id in ZooMeasure.all_type_ids():
		var info := ZooMeasure.measure(id)
		assert_false(info.is_empty(), "%s nicht messbar" % id)
		if info.is_empty():
			continue
		var box: AABB = info["aabb"]
		assert_gt(box.size.x, 0.0, "%s: Breite" % id)
		assert_gt(box.size.y, 0.0, "%s: Höhe" % id)
		assert_gt(box.size.z, 0.0, "%s: Länge" % id)
		assert_false(String(info["display_name"]).is_empty(), "%s: Schildtext" % id)

func test_every_case_is_big_enough_for_its_animal() -> void:
	for id in ZooMeasure.all_type_ids():
		var info := ZooMeasure.measure(id)
		if info.is_empty():
			continue
		var box: AABB = info["aabb"]
		var inner := ZooLayout.inner_size(box, bool(info["aquatic"]))
		assert_gte(inner.x, box.size.x + ZooLayout.SIDE_MARGIN * 2.0 - 0.0001, "%s: Kasten zu schmal" % id)
		assert_gte(inner.z, box.size.z + ZooLayout.SIDE_MARGIN * 2.0 - 0.0001, "%s: Kasten zu kurz" % id)
		assert_gt(inner.y, box.size.y, "%s: Kasten zu niedrig" % id)

func test_wolf_spider_is_measured_as_spider_not_wolf() -> void:
	var info := ZooMeasure.measure("wolf_spider")
	assert_eq(int(info["body_plan"]), AnimalVisualProfile.BodyPlan.SPIDER)

func test_snake_model_faces_plus_z() -> void:
	# Schlange: vorne = +Z wie bei allen Bauplänen (Kopf "Head" hat positives z im Parent-Raum).
	var profile := AnimalVisualProfile.new(Color(0.3, 0.5, 0.2), Vector3(0.14, 0.1, 1.1))
	profile.body_plan = AnimalVisualProfile.BodyPlan.SNAKE
	var root := AnimalVisualBuilder.build(profile)
	add_child_autofree(root)
	var head: Node3D = root.find_child("Head", true, false)
	assert_gt((root.transform * head.position).z, 0.0)

# res://tests/unit/test_world_map_baker.gd
extends GutTest

## Tests für WorldMapBaker (Kachel-Geometrie, Zeitscheiben-Backen, Farben) mit Stub-Gelände.

## Gelände-Stub: Höhe/Wasser/Biom frei einstellbar, ohne den echten Layerstapel zu benutzen.
class StubField extends TerrainField:
	var height: float = 10.0
	var water: float = 0.0
	var grass: Color = Color(0.2, 0.6, 0.2)
	var calls: int = 0

	func get_height_at(_x: float, _z: float) -> float:
		calls += 1
		return height

	func get_water_level_at(_x: float, _z: float) -> float:
		return water

	func get_biome_at(_x: float, _z: float) -> BiomeDefinition:
		var b := BiomeDefinition.new()
		b.terrain_color_grass = grass
		return b

func _field() -> StubField:
	return StubField.new()

func _baker(field: TerrainField, cell: float = 8.0, px: int = 8) -> WorldMapBaker:
	var b := WorldMapBaker.new(cell, px)
	b.setup(field)
	return b

func _drain(b: WorldMapBaker) -> void:
	var guard := 0
	while b.pending_count() > 0 and guard < 100000:
		b.step(5.0)
		guard += 1

# ── Geometrie ─────────────────────────────────────────────────────

func test_tile_size_is_cell_times_pixels() -> void:
	var b := WorldMapBaker.new(8.0, 64)
	assert_almost_eq(b.tile_m, 512.0, 0.0001)

func test_world_to_tile_handles_negative_coordinates() -> void:
	var b := WorldMapBaker.new(8.0, 8)   # 64 m Kacheln
	assert_eq(b.world_to_tile(Vector2(0.0, 0.0)), Vector2i(0, 0))
	assert_eq(b.world_to_tile(Vector2(63.9, 63.9)), Vector2i(0, 0))
	assert_eq(b.world_to_tile(Vector2(64.0, 0.0)), Vector2i(1, 0))
	assert_eq(b.world_to_tile(Vector2(-0.1, -0.1)), Vector2i(-1, -1))

func test_tile_rect_matches_coordinate() -> void:
	var b := WorldMapBaker.new(8.0, 8)
	assert_eq(b.tile_rect(Vector2i(-1, 2)), Rect2(Vector2(-64.0, 128.0), Vector2(64.0, 64.0)))

func test_tiles_in_radius_contains_center_tile_and_is_sorted_nearest_first() -> void:
	var b := WorldMapBaker.new(8.0, 8)
	var center := Vector2(10.0, 10.0)
	var tiles := b.tiles_in_radius(center, 100.0)
	assert_true(tiles.has(Vector2i(0, 0)))
	assert_eq(tiles[0], Vector2i(0, 0))
	var prev := -1.0
	for c in tiles:
		var d := b.tile_rect(c).get_center().distance_squared_to(center)
		assert_true(d >= prev, "Kacheln müssen nach Abstand sortiert sein.")
		prev = d

func test_tiles_in_radius_skips_corner_tiles_outside_circle() -> void:
	var b := WorldMapBaker.new(8.0, 8)   # 64 m
	var tiles := b.tiles_in_radius(Vector2(32.0, 32.0), 40.0)
	assert_false(tiles.has(Vector2i(2, 2)), "Diagonale Eckkachel liegt außerhalb des Kreises.")

# ── Backen ────────────────────────────────────────────────────────

func test_baker_without_field_is_inert() -> void:
	var b := WorldMapBaker.new(8.0, 8)
	assert_false(b.is_ready())
	b.request_area(Vector2.ZERO, 500.0)
	assert_eq(b.step(5.0), 0)
	assert_eq(b.pending_count(), 0)
	assert_null(b.bake_tile_now(Vector2i.ZERO))

func test_request_and_step_bakes_all_tiles_in_radius() -> void:
	var b := _baker(_field())
	b.request_area(Vector2(32.0, 32.0), 80.0)
	var expected := b.tiles_in_radius(Vector2(32.0, 32.0), 80.0).size()
	assert_true(expected > 1)
	_drain(b)
	assert_eq(b.tile_count(), expected)
	assert_eq(b.pending_count(), 0)
	assert_not_null(b.get_tile_texture(Vector2i(0, 0)))

func test_step_makes_progress_even_with_zero_budget() -> void:
	var b := _baker(_field())
	b.request_area(Vector2(32.0, 32.0), 10.0)
	var guard := 0
	while b.pending_count() > 0 and guard < 10000:
		b.step(0.0)
		guard += 1
	assert_true(guard < 10000, "Mit Budget 0 muss trotzdem je Aufruf eine Reihe fertig werden.")
	assert_true(b.has_tile(Vector2i(0, 0)))

func test_already_baked_tiles_are_not_requested_again() -> void:
	var f := _field()
	var b := _baker(f)
	b.request_area(Vector2(32.0, 32.0), 20.0)
	_drain(b)
	var calls_before := f.calls
	b.request_area(Vector2(32.0, 32.0), 20.0)
	assert_eq(b.pending_count(), 0)
	_drain(b)
	assert_eq(f.calls, calls_before, "Cache: kein erneutes Sampeln.")

func test_new_request_drops_tiles_that_are_no_longer_wanted() -> void:
	var b := _baker(_field())
	b.request_area(Vector2(32.0, 32.0), 200.0)
	var many := b.pending_count()
	b.request_area(Vector2(32.0, 32.0), 10.0)
	assert_true(b.pending_count() < many)

func test_clear_empties_cache_and_queue() -> void:
	var b := _baker(_field())
	b.request_area(Vector2(32.0, 32.0), 100.0)
	_drain(b)
	assert_true(b.tile_count() > 0)
	b.request_area(Vector2(5000.0, 5000.0), 100.0)
	b.clear()
	assert_eq(b.tile_count(), 0)
	assert_eq(b.pending_count(), 0)

func test_baked_image_has_tile_size_and_opaque_pixels() -> void:
	var b := _baker(_field(), 8.0, 8)
	var img := b.bake_tile_now(Vector2i(0, 0))
	assert_eq(img.get_width(), 8)
	assert_eq(img.get_height(), 8)
	for y in 8:
		for x in 8:
			assert_almost_eq(img.get_pixel(x, y).a, 1.0, 0.0001)

func test_land_is_greenish_and_ocean_is_blue() -> void:
	var land := _field()
	land.height = 8.0
	var img_land := _baker(land).bake_tile_now(Vector2i(0, 0))
	var c := img_land.get_pixel(4, 4)
	assert_true(c.g > c.b and c.g > 0.2, "Flachland soll grünlich sein (Biom-Gras).")

	var sea := _field()
	sea.height = -10.0
	var img_sea := _baker(sea).bake_tile_now(Vector2i(0, 0))
	var w := img_sea.get_pixel(4, 4)
	assert_true(w.b > w.r and w.b > w.g, "Wasser soll blau sein.")

func test_deeper_water_is_darker_than_shallow_water() -> void:
	var b := _baker(_field())
	var shallow := b.color_for(-0.5, 0.0, Color.GREEN, Vector3.UP, 0.0, 0.0)
	var deep := b.color_for(-8.0, 0.0, Color.GREEN, Vector3.UP, 0.0, 0.0)
	assert_true(deep.get_luminance() < shallow.get_luminance())

func test_sun_facing_slope_is_brighter_than_shade_slope() -> void:
	var b := _baker(_field())
	var grass := Color(0.2, 0.6, 0.2)
	var lit := b.color_for(10.0, 0.0, grass, Vector3(-0.3, 1.0, -0.3).normalized(), 0.0, 0.0)
	var flat := b.color_for(10.0, 0.0, grass, Vector3.UP, 0.0, 0.0)
	var dark := b.color_for(10.0, 0.0, grass, Vector3(0.3, 1.0, 0.3).normalized(), 0.0, 0.0)
	assert_true(lit.get_luminance() > flat.get_luminance())
	assert_true(dark.get_luminance() < flat.get_luminance())

func test_snow_on_high_peaks() -> void:
	var f := _field()
	var b := _baker(f)
	var peak := b.color_for(f.get_config().max_height * 0.95, 0.0, Color(0.2, 0.6, 0.2), Vector3.UP, 0.0, 0.0)
	assert_true(peak.r > 0.7 and peak.g > 0.7 and peak.b > 0.7, "Hochgebirge soll weiß (Schnee) sein.")

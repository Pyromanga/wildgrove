# res://tests/unit/test_terrain_field.gd
extends GutTest

## Tests für den Terrain-Stack: TerrainSeed, TerrainConfig, Layer und TerrainField.
## Schwerpunkt: die ARCHITEKTUR-GARANTIEN, auf die sich der Rest des Spiels verlässt —
## Determinismus, Seed-Stabilität über Engine-Versionen, Weltkoordinaten, Spawn-Plateau,
## Wasser als Eigenschaft der Höhe.

## Höhenfeld mit fester/beliebiger Funktion — für Wasser-/Steigungs-Tests.
class FuncField extends TerrainField:
	var fn: Callable
	func get_height_at(x: float, z: float) -> float:
		return float(fn.call(x, z))

const SEEDS: Array[int] = [1337, 42, 987654321]

# ── TerrainSeed ─────────────────────────────────

func test_seed_golden_values_never_change() -> void:
	# FESTE Werte: ändert sich einer, sieht JEDE bestehende Welt anders aus. Diese Tests sind
	# der Grund, warum FNV-1a statt String.hash() benutzt wird (nicht versionsstabil).
	assert_eq(TerrainSeed.derive(1337, "terrain.continent"), 343236760)
	assert_eq(TerrainSeed.derive(1337, "terrain.detail"), 2030383245)
	assert_eq(TerrainSeed.derive(0, ""), 1441645609)
	assert_eq(TerrainSeed.derive(42, "climate.temp"), 38122628)
	assert_eq(TerrainSeed.derive(-5, "x"), 2144768907)

func test_seed_is_non_negative_31_bit() -> void:
	for s in [0, 1, -1, 123456789, -987654321, 9223372036854775807]:
		var d := TerrainSeed.derive(s, "terrain.continent")
		assert_true(d >= 0 and d <= 0x7FFFFFFF, "Seed %d → %d außerhalb 31 Bit" % [s, d])

func test_seed_different_salts_and_seeds_differ() -> void:
	assert_ne(TerrainSeed.derive(1, "a"), TerrainSeed.derive(1, "b"))
	assert_ne(TerrainSeed.derive(1, "a"), TerrainSeed.derive(2, "a"))

func test_seed_is_deterministic() -> void:
	assert_eq(TerrainSeed.derive(77, "terrain.river"), TerrainSeed.derive(77, "terrain.river"))

# ── TerrainConfig ───────────────────────────────

func test_config_resolution_follows_edit_lattice() -> void:
	# Chunk-Vertices MÜSSEN auf den Punkten der Edit-Schicht liegen — sonst passt Umgraben nicht.
	var cfg := TerrainConfig.new()
	assert_eq(cfg.get_vertex_spacing(), TerrainEditLayer.SPACING)
	assert_eq(cfg.get_resolution(), 32)

func test_config_defaults_are_sane() -> void:
	var cfg := TerrainConfig.new()
	assert_gt(cfg.spawn_blend_radius, cfg.spawn_flat_radius)
	assert_gt(cfg.basin_end, cfg.basin_start)
	assert_gt(cfg.hill_end, cfg.hill_start)
	assert_gt(cfg.spawn_height, cfg.water_level + 1.0, "Spawn muss klar über dem Wasser liegen.")

# ── TerrainField: Determinismus ─────────────────

func test_same_seed_gives_same_world() -> void:
	var a := TerrainField.new(null, 4711)
	var b := TerrainField.new(null, 4711)
	for i in 50:
		var x := float(i * 137 - 3000)
		var z := float(i * 211 - 4000)
		assert_eq(a.get_height_at(x, z), b.get_height_at(x, z))
		assert_eq(a.get_biome_id_at(x, z), b.get_biome_id_at(x, z))

func test_different_seeds_give_different_worlds() -> void:
	var a := TerrainField.new(null, 1)
	var b := TerrainField.new(null, 2)
	var differs := false
	for i in 50:
		if not is_equal_approx(a.get_height_at(i * 97.0 + 200.0, i * 53.0 + 200.0), b.get_height_at(i * 97.0 + 200.0, i * 53.0 + 200.0)):
			differs = true
			break
	assert_true(differs, "Der world_seed muss im Terrain ankommen (war früher wirkungslos!).")

func test_seed_zero_falls_back_to_default() -> void:
	assert_eq(TerrainField.new(null, 0).get_seed(), TerrainConfig.DEFAULT_SEED)
	assert_eq(TerrainField.new(null, 55).get_seed(), 55)

func test_heights_are_finite_and_in_plausible_range() -> void:
	for s in SEEDS:
		var f := TerrainField.new(null, s)
		for iz in 30:
			for ix in 30:
				var h := f.get_height_at(float(ix) * 173.0 - 2500.0, float(iz) * 191.0 - 2800.0)
				assert_false(is_nan(h) or is_inf(h))
				assert_true(h > -8.0 and h < 110.0, "Höhe %.2f außerhalb des plausiblen Bereichs (seed %d)" % [h, s])

# ── Spawn-Plateau ───────────────────────────────

func test_spawn_area_is_flat_and_dry_for_every_seed() -> void:
	# DAS ist die Garantie für Dorf/NPCs/Ackerbeete: egal welcher Seed, um den Ursprung ist es
	# eben und trocken. (Vorher hing es vom Zufall ab, ob dort See, Hang oder Fluss war.)
	var cfg := TerrainConfig.new()
	for s in [1, 2, 3, 99, 1337, 123456, 987654321, 55555]:
		var f := TerrainField.new(cfg, s)
		for i in 24:
			var ang := float(i) * TAU / 24.0
			for r in [0.0, 10.0, 25.0, cfg.spawn_flat_radius - 1.0]:
				var x: float = cos(ang) * r
				var z: float = sin(ang) * r
				assert_almost_eq(f.get_height_at(x, z), cfg.spawn_height, 0.001, "seed %d @ r=%.0f" % [s, r])
				assert_false(f.is_water_at(x, z))

func test_spawn_plateau_blends_smoothly() -> void:
	var cfg := TerrainConfig.new()
	var f := TerrainField.new(cfg, 1337)
	var prev := f.get_height_at(cfg.spawn_flat_radius, 0.0)
	var r := cfg.spawn_flat_radius
	while r < cfg.spawn_blend_radius:
		r += 1.0
		var h := f.get_height_at(r, 0.0)
		assert_lt(absf(h - prev), 2.5, "Sprung im Übergangsbereich bei r=%.0f" % r)
		prev = h

func test_terrain_far_from_spawn_is_untouched_by_plateau() -> void:
	var cfg := TerrainConfig.new()
	var layer := TerrainSpawnPlateauLayer.new(cfg)
	assert_eq(layer.apply(cfg.spawn_blend_radius + 5.0, 0.0, 7.3), 7.3)
	assert_eq(layer.apply(0.0, 0.0, 7.3), cfg.spawn_height)

# ── Layer ───────────────────────────────────────

func test_river_only_lowers_never_raises() -> void:
	var layer := TerrainRiverLayer.new(TerrainConfig.new(), 1337)
	for i in 400:
		var x := float(i % 20) * 41.0 - 400.0
		var z := float(i / 20) * 37.0 - 400.0
		assert_true(layer.apply(x, z, 2.0) <= 2.0 + 0.0001)

func test_river_exists_and_is_sparse() -> void:
	var layer := TerrainRiverLayer.new(TerrainConfig.new(), 1337)
	var carved := 0
	var total := 0
	for iz in 160:
		for ix in 160:
			total += 1
			if layer.apply(float(ix) * 25.0, float(iz) * 25.0, 2.0) < 1.99:
				carved += 1
	var frac := float(carved) / float(total)
	assert_gt(frac, 0.003, "Es muss Flüsse geben.")
	assert_lt(frac, 0.25, "Flüsse dürfen nicht die halbe Welt fluten.")

func test_river_does_not_cut_into_hills() -> void:
	var cfg := TerrainConfig.new()
	var layer := TerrainRiverLayer.new(cfg, 1337)
	var h_high: float = cfg.river_max_height + cfg.river_fade_range + 1.0
	for i in 400:
		var x := float(i % 20) * 41.0 - 400.0
		var z := float(i / 20) * 37.0 - 400.0
		assert_eq(layer.apply(x, z, h_high), h_high, "Hügel bleiben unberührt (Fluss läuft aus).")

## Sucht auf einem Raster (außerhalb der Spawn-Zone) alle Punkte, an denen der Fluss bei konstanter
## Geländehöhe `h` Wasser führt (Wasserspiegel nicht NAN). Ohne Basis-Layer ist die Flussmitte-
## Höhe gleich `h` — dadurch sind Wasserspiegel und Bett exakt vorhersagbar.
func _river_water_points(layer: TerrainRiverLayer, h: float) -> Array[Vector2]:
	var found: Array[Vector2] = []
	for iz in 200:
		for ix in 200:
			var x := float(ix) * 20.0 + 150.0
			var z := float(iz) * 20.0 + 150.0
			if not is_nan(layer.get_water_target_at(x, z, h)):
				found.append(Vector2(x, z))
	return found

func test_river_bed_reaches_depth_below_water_surface() -> void:
	# Bett = Wasserspiegel − river_depth, Wasserspiegel = Uferhöhe − river_bank_drop.
	var cfg := TerrainConfig.new()
	var layer := TerrainRiverLayer.new(cfg, 1337)
	var h: float = 2.4
	var lowest := 100.0
	for iz in 200:
		for ix in 200:
			lowest = minf(lowest, layer.apply(float(ix) * 20.0 + 150.0, float(iz) * 20.0 + 150.0, h))
	var expected: float = (h - cfg.river_bank_drop) - cfg.river_depth
	assert_almost_eq(lowest, expected, 0.05, "Volle Flussbett-Tiefe muss erreicht werden.")

func test_river_water_surface_lies_below_the_banks() -> void:
	# DER Kern des Umbaus ("Flüsse sind Gräben mit Wasser, nicht Wasser auf dem Boden"): der
	# Wasserspiegel liegt überall um river_bank_drop UNTER der Uferhöhe.
	var cfg := TerrainConfig.new()
	var layer := TerrainRiverLayer.new(cfg, 1337)
	var h: float = 3.0
	var points := _river_water_points(layer, h)
	assert_gt(points.size(), 10, "Es muss Flusswasser im Suchraster geben.")
	for p in points:
		assert_almost_eq(layer.get_water_target_at(p.x, p.y, h), h - cfg.river_bank_drop, 0.0001)

func test_river_follows_local_terrain_instead_of_one_global_level() -> void:
	# Ein Fluss durch höheres Gelände muss auch höher liegen als einer im Tiefland.
	var cfg := TerrainConfig.new()
	var layer := TerrainRiverLayer.new(cfg, 1337)
	var lowland := 100.0
	var upland := 100.0
	for iz in 200:
		for ix in 200:
			var x := float(ix) * 20.0 + 150.0
			var z := float(iz) * 20.0 + 150.0
			lowland = minf(lowland, layer.apply(x, z, 3.5))
			upland = minf(upland, layer.apply(x, z, 5.5))
	assert_almost_eq(upland - lowland, 2.0, 0.1)

func test_river_water_target_is_nan_away_from_rivers() -> void:
	var layer := TerrainRiverLayer.new(TerrainConfig.new(), 1337)
	# Eine Stelle suchen, die der Vorfilter sicher ausschließt, und dort NAN erwarten.
	for i in 400:
		var x := float(i) * 53.0 + 500.0
		if not layer.is_candidate(x, 777.0):
			assert_true(is_nan(layer.get_water_target_at(x, 777.0, 2.0)))
			assert_eq(layer.apply(x, 777.0, 2.0), 2.0)
			return
	fail_test("Keine flussfreie Stelle gefunden — Testdaten prüfen.")

func test_no_river_near_spawn() -> void:
	# Dorf/NPCs/Beete: bis spawn_blend_radius kein Fluss (und kein Flusswasser) — für jeden Seed.
	var cfg := TerrainConfig.new()
	for s in [1, 42, 1337, 987654321]:
		var layer := TerrainRiverLayer.new(cfg, s)
		for i in 360:
			var ang := float(i) * TAU / 360.0
			for r in [10.0, 40.0, cfg.spawn_blend_radius - 1.0]:
				var x: float = cos(ang) * r
				var z: float = sin(ang) * r
				assert_eq(layer.apply(x, z, 2.5), 2.5)
				assert_true(is_nan(layer.get_water_target_at(x, z, 2.5)))

func test_river_channel_is_a_trench_with_banks_above_the_water() -> void:
	# Gesamtfeld (mit echter Basis): an Flusswasser-Punkten liegt rundherum (Ring 24 m) irgendwo
	# Gelände klar über dem Wasserspiegel — Wasser ist eingefasst statt "auf dem Boden".
	var cfg := TerrainConfig.new()
	var f := TerrainField.new(cfg, 1337)
	var checked := 0
	for iz in 120:
		for ix in 120:
			var x := float(ix) * 25.0 - 1500.0
			var z := float(iz) * 25.0 - 1500.0
			var water: float = f.get_water_level_at(x, z)
			if water < cfg.water_level + 0.3 or not f.is_water_at(x, z):
				continue
			if not is_nan(f.get_lake_layer().get_water_target_at(x, z)):
				continue  # Bergsee, kein Fluss (eigener Test)
			var highest := -1000.0
			for k in 16:
				var a := float(k) * TAU / 16.0
				highest = maxf(highest, f.get_height_at(x + cos(a) * 24.0, z + sin(a) * 24.0))
			assert_gt(highest, water + 0.2,
				"Fluss bei (%.0f, %.0f): kein Ufer über dem Wasser (Spiegel %.2f, höchstes Ufer %.2f)" % [x, z, water, highest])
			checked += 1
			if checked >= 40:
				return
	assert_gt(checked, 0, "Es muss Flusswasser über dem Meeresspiegel geben.")

# ── Gebirge ─────────────────────────────────────

func test_mountains_exist_and_are_much_higher_than_hills() -> void:
	for s in SEEDS:
		var f := TerrainField.new(null, s)
		var highest := -100.0
		for iz in 60:
			for ix in 60:
				highest = maxf(highest, f.get_height_at(float(ix) * 100.0 - 3000.0, float(iz) * 100.0 - 3000.0))
		assert_gt(highest, 45.0, "seed %d: keine echten Berge (höchster Punkt %.1f m)" % [s, highest])

func test_no_mountains_near_spawn() -> void:
	var cfg := TerrainConfig.new()
	for s in SEEDS:
		var f := TerrainField.new(cfg, s)
		for i in 72:
			var ang := float(i) * TAU / 72.0
			for r in [20.0, 90.0, cfg.mountain_spawn_clear - 1.0]:
				assert_eq(f.get_mountain_weight_at(cos(ang) * r, sin(ang) * r), 0.0)

func test_mountains_are_steep_but_not_vertical() -> void:
	# Berge dürfen steil sein (Felswände), aber keine senkrechten Sprünge auf 1 m Distanz.
	for s in SEEDS:
		var f := TerrainField.new(null, s)
		for i in 600:
			var x := float(i % 30) * 211.0 - 3000.0
			var z := float(i / 30) * 173.0 - 1700.0
			if f.get_mountain_weight_at(x, z) < 0.05:
				continue
			assert_lt(absf(f.get_height_at(x + 1.0, z) - f.get_height_at(x, z)), 9.0)
			assert_lt(absf(f.get_height_at(x, z + 1.0) - f.get_height_at(x, z)), 9.0)

func test_no_mountains_in_basins() -> void:
	# Seen/Meer sind Becken: dort wird nie ein Gebirge aufgesetzt (Küste bleibt flach bis hügelig).
	var f := TerrainField.new(null, 1337)
	var checked := 0
	for iz in 80:
		for ix in 80:
			var x := float(ix) * 60.0 - 2400.0
			var z := float(iz) * 60.0 - 2400.0
			if f.get_base_height_at(x, z) < -1.0:
				assert_lt(f.get_mountain_weight_at(x, z), 0.3, "Gebirge mitten im Becken bei (%.0f, %.0f)" % [x, z])
				checked += 1
	assert_gt(checked, 0)

# ── Erosionsfilter (2026-10-05) ─────────────────

func test_erosion_does_nothing_in_lowland() -> void:
	var cfg := TerrainConfig.new()
	var base := TerrainBaseLayer.new(cfg, 1337)
	var layer := TerrainErosionLayer.new(cfg, 1337, base)
	for i in 200:
		var x := float(i) * 37.0 - 3000.0
		assert_eq(layer.apply(x, 123.0, cfg.erosion_start_alt - 0.01), cfg.erosion_start_alt - 0.01,
			"Unter erosion_start_alt darf der Filter die Höhe nicht anfassen (Flüsse, Strände).")

func test_erosion_can_be_disabled() -> void:
	var cfg := TerrainConfig.new()
	cfg.erosion_enabled = false
	var layer := TerrainErosionLayer.new(cfg, 1337, TerrainBaseLayer.new(cfg, 1337))
	assert_eq(layer.apply(500.0, 500.0, 40.0), 40.0)

func test_erosion_is_deterministic_and_seed_dependent() -> void:
	var cfg := TerrainConfig.new()
	var a := TerrainErosionLayer.new(cfg, 1337, TerrainBaseLayer.new(cfg, 1337))
	var b := TerrainErosionLayer.new(cfg, 1337, TerrainBaseLayer.new(cfg, 1337))
	var c := TerrainErosionLayer.new(cfg, 4242, TerrainBaseLayer.new(cfg, 4242))
	var differs := false
	for i in 40:
		var x := float(i) * 53.0 + 400.0
		var z := float(i) * 29.0 - 900.0
		assert_eq(a.erosion_offset(x, z, 40.0), b.erosion_offset(x, z, 40.0))
		if not is_equal_approx(a.erosion_offset(x, z, 40.0), c.erosion_offset(x, z, 40.0)):
			differs = true
	assert_true(differs, "Der Seed muss die Rinnen verschieben.")

func test_erosion_offset_is_bounded_by_total_amplitude() -> void:
	# |Offset| <= Summe der Oktav-Amplituden (jede Oktave: faded in [-1, 1] * amp).
	var cfg := TerrainConfig.new()
	var layer := TerrainErosionLayer.new(cfg, 1337, TerrainBaseLayer.new(cfg, 1337))
	var limit: float = 0.0
	var amp: float = cfg.erosion_strength
	for _o in range(cfg.erosion_octaves):
		limit += amp
		amp *= cfg.erosion_gain
	for i in 300:
		var x := float(i % 20) * 97.0 - 900.0
		var z := float(i / 20) * 83.0 - 600.0
		assert_lt(absf(layer.erosion_offset(x, z, 45.0)), limit + 0.001)

func test_erosion_is_continuous_no_new_cliffs() -> void:
	# Kern-Garantie (in der Simulation Ursache von 14-m-Sprüngen, siehe erosion_gradient_step):
	# der Filter darf auf 1 m Distanz nicht mehr als wenige Meter Höhe hinzufügen.
	var cfg := TerrainConfig.new()
	var layer := TerrainErosionLayer.new(cfg, 1337, TerrainBaseLayer.new(cfg, 1337))
	var worst: float = 0.0
	for i in 600:
		var x := float(i % 30) * 211.0 - 3000.0
		var z := float(i / 30) * 173.0 - 1700.0
		var d: float = absf(layer.erosion_offset(x + 1.0, z, 45.0) - layer.erosion_offset(x, z, 45.0))
		worst = maxf(worst, d)
	assert_lt(worst, 6.0, "Erosionsversatz springt um %.2f m auf 1 m." % worst)

func test_erosion_actually_shapes_mountains() -> void:
	# Mit Filter muss das Gebirge messbar anders aussehen als ohne (sonst wäre er wirkungslos).
	var with_erosion := TerrainField.new(null, 1337)
	var cfg := TerrainConfig.new()
	cfg.erosion_enabled = false
	var without := TerrainField.new(cfg, 1337)
	var changed := 0
	var checked := 0
	for iz in 60:
		for ix in 60:
			var x := float(ix) * 100.0 - 3000.0
			var z := float(iz) * 100.0 - 3000.0
			if with_erosion.get_mountain_weight_at(x, z) > 0.5:
				checked += 1
				if absf(with_erosion.get_base_height_at(x, z) - without.get_base_height_at(x, z)) > 0.5:
					changed += 1
	assert_gt(checked, 0)
	assert_gt(float(changed) / float(checked), 0.3, "Erosion verändert im Gebirge zu wenig.")

func test_erosion_leaves_spawn_plateau_flat() -> void:
	var cfg := TerrainConfig.new()
	for s in SEEDS:
		var f := TerrainField.new(cfg, s)
		for i in 24:
			var ang := float(i) * TAU / 24.0
			var x: float = cos(ang) * (cfg.spawn_flat_radius - 1.0)
			var z: float = sin(ang) * (cfg.spawn_flat_radius - 1.0)
			assert_almost_eq(f.get_height_at(x, z), cfg.spawn_height, 0.001)

# ── Meer, Strand, Seen, Wasserfälle (2026-10-05) ─

func test_beach_remap_is_monotone_sign_preserving_and_identity_far_away() -> void:
	var prev: float = TerrainBaseLayer.beach_remap(-20.0, 0.35, 5.0)
	var h: float = -19.9
	while h <= 20.0:
		var v: float = TerrainBaseLayer.beach_remap(h, 0.35, 5.0)
		assert_gte(v, prev - 0.0001, "Strand-Stauchung muss monoton sein (h=%.1f)" % h)
		assert_eq(signf(v), signf(h), "Vorzeichen (Küstenlinie) darf sich nicht ändern.")
		prev = v
		h += 0.1
	assert_almost_eq(TerrainBaseLayer.beach_remap(12.0, 0.35, 5.0), 12.0, 0.0001)
	assert_almost_eq(TerrainBaseLayer.beach_remap(-12.0, 0.35, 5.0), -12.0, 0.0001)
	assert_lt(TerrainBaseLayer.beach_remap(1.0, 0.35, 5.0), 0.5, "Am Wasser ist der Hang flach (Strand).")

func test_seas_have_real_depth() -> void:
	# Mindestens ein großes Becken muss deutlich tiefer als die alten ~3 m sein.
	for s in SEEDS:
		var f := TerrainField.new(null, s)
		var deepest: float = 100.0
		for iz in 80:
			for ix in 80:
				deepest = minf(deepest, f.get_base_height_at(float(ix) * 60.0 - 2400.0, float(iz) * 60.0 - 2400.0))
		assert_lt(deepest, -8.0, "seed %d: tiefster Punkt %.1f m — Meer zu flach" % [s, deepest])

func test_fall_surface_is_a_staircase() -> void:
	var h: float = 5.5
	var e: float = 0.06
	# Gewicht 0 → unverändert
	assert_almost_eq(TerrainRiverLayer.fall_surface(13.37, h, e, 0.0), 13.37, 0.0001)
	var prev: float = TerrainRiverLayer.fall_surface(0.0, h, e, 1.0)
	var plateau_samples: int = 0
	var max_jump: float = 0.0
	var s: float = 0.01
	while s < 40.0:
		var v: float = TerrainRiverLayer.fall_surface(s, h, e, 1.0)
		assert_gte(v, prev - 0.0001, "Treppe muss monoton steigen (s=%.2f)" % s)
		# Wasser liegt nie (nennenswert) über dem Ausgangsspiegel.
		assert_lt(v, s + 0.1 * h, "Wasser über Ausgangsspiegel bei s=%.2f" % s)
		if is_equal_approx(v, prev):
			plateau_samples += 1
		max_jump = maxf(max_jump, v - prev)
		prev = v
		s += 0.01
	assert_gt(plateau_samples, 3000, "Es muss lange ruhige Becken (Plateaus) geben.")
	assert_gt(max_jump, 0.05, "Es muss Stufen geben.")

func test_fall_surface_steps_are_exactly_one_fall_height() -> void:
	var h: float = 5.5
	var low: float = TerrainRiverLayer.fall_surface(2.0 * h + 0.01, h, 0.06, 1.0)
	var high: float = TerrainRiverLayer.fall_surface(3.0 * h - 0.0001, h, 0.06, 1.0)
	assert_almost_eq(high - low, h, 0.02, "Zwischen zwei Becken liegt genau eine Stufenhöhe.")

func test_strata_height_is_monotone_and_close_to_identity_on_average() -> void:
	var prev: float = TerrainErosionLayer.strata_height(0.0, 7.0, 0.3)
	var total_dev: float = 0.0
	var n: int = 0
	var h: float = 0.05
	while h < 70.0:
		var v: float = TerrainErosionLayer.strata_height(h, 7.0, 0.3)
		assert_gte(v, prev - 0.0001)
		assert_lt(v, h + 0.7 + 0.001)
		total_dev += absf(v - h)
		n += 1
		prev = v
		h += 0.05
	assert_lt(total_dev / float(n), 3.5, "Treppe darf das Gelände im Mittel nicht verschieben.")

func test_lakes_exist_and_are_consistent() -> void:
	var cfg := TerrainConfig.new()
	var found: int = 0
	for s in SEEDS:
		var f := TerrainField.new(cfg, s)
		var lakes: TerrainLakeLayer = f.get_lake_layer()
		for ci in range(-6, 6):
			for cj in range(-6, 6):
				var rec: Dictionary = lakes.get_lake_record(Vector2i(ci, cj))
				if rec.is_empty():
					continue
				found += 1
				var c: Vector2 = rec["center"]
				var level: float = rec["level"]
				assert_gt(c.length(), cfg.lake_spawn_clear, "Kein See in Spawn-Nähe.")
				assert_gte(level, cfg.lake_min_alt)
				assert_lte(level, cfg.lake_max_alt)
				assert_almost_eq(lakes.get_water_target_at(c.x, c.y), level, 0.0001)
				assert_almost_eq(f.get_water_level_at(c.x, c.y), level, 0.0001, "Seespiegel kommt aus dem Feld.")
				assert_lt(f.get_height_at(c.x, c.y), level - 1.0, "Seemitte liegt klar unter dem Spiegel.")
				assert_true(f.is_water_at(c.x, c.y))
	assert_gt(found, 0, "In 4 Seeds x 144 Zellen muss es Bergseen geben.")

func test_lake_shore_is_banked_above_the_water() -> void:
	var cfg := TerrainConfig.new()
	var f := TerrainField.new(cfg, 1337)
	var lakes: TerrainLakeLayer = f.get_lake_layer()
	var checked: int = 0
	for ci in range(-6, 6):
		for cj in range(-6, 6):
			var rec: Dictionary = lakes.get_lake_record(Vector2i(ci, cj))
			if rec.is_empty():
				continue
			var c: Vector2 = rec["center"]
			var radius: float = rec["radius"]
			var level: float = rec["level"]
			# Direkt außerhalb der Böschung (Radius × 1.28 + Ufer + Auslauf) ist KEIN Seewasser mehr.
			var far: float = radius * (1.0 + cfg.lake_shape_amplitude) + cfg.lake_bank_width + cfg.lake_outer_blend + 2.0
			assert_true(is_nan(lakes.get_water_target_at(c.x + far, c.y)), "Seespiegel endet hinter der Böschung.")
			# Auf dem Uferring: nirgends Seewasser UNTER dem Spiegel jenseits der Uferlinie.
			for k in 24:
				var a := float(k) * TAU / 24.0
				var d: float = (radius * (1.0 + cfg.lake_shape_amplitude) + cfg.lake_bank_width)
				var px: float = c.x + cos(a) * d
				var pz: float = c.y + sin(a) * d
				assert_gte(f.get_height_at(px, pz), level + cfg.lake_bank_min - 0.05,
					"Ufer bei (%.0f, %.0f) liegt unter dem Seespiegel — Wasser würde auslaufen." % [px, pz])
			checked += 1
	assert_gt(checked, 0)

func test_lakes_are_deterministic() -> void:
	var a := TerrainField.new(null, 777)
	var b := TerrainField.new(null, 777)
	for ci in range(-4, 4):
		for cj in range(-4, 4):
			assert_eq(a.get_lake_layer().get_lake_record(Vector2i(ci, cj)), b.get_lake_layer().get_lake_record(Vector2i(ci, cj)))

func test_lakes_can_be_disabled() -> void:
	var cfg := TerrainConfig.new()
	cfg.lake_enabled = false
	var f := TerrainField.new(cfg, 1337)
	for ci in range(-3, 3):
		for cj in range(-3, 3):
			assert_true(f.get_lake_layer().get_lake_record(Vector2i(ci, cj)).is_empty())

# ── Statistik der Gesamtwelt (großzügige Grenzen, gegen grobe Fehlabstimmung) ──

func test_world_has_water_hills_and_mostly_land_for_multiple_seeds() -> void:
	for s in SEEDS:
		var f := TerrainField.new(null, s)
		var water := 0
		var hills := 0
		var total := 0
		for iz in 60:
			for ix in 60:
				total += 1
				var h := f.get_height_at(float(ix) * 160.0 - 4800.0, float(iz) * 160.0 - 4800.0)
				if h < 0.0:
					water += 1
				if h > 5.0:
					hills += 1
		var water_frac := float(water) / float(total)
		var hill_frac := float(hills) / float(total)
		assert_gt(water_frac, 0.02, "seed %d: kaum Wasser (%.1f%%)" % [s, water_frac * 100.0])
		assert_lt(water_frac, 0.40, "seed %d: zu viel Wasser (%.1f%%)" % [s, water_frac * 100.0])
		assert_gt(hill_frac, 0.03, "seed %d: kaum Hügel (%.1f%%)" % [s, hill_frac * 100.0])
		assert_lt(hill_frac, 0.65, "seed %d: zu viel Hügel (%.1f%%)" % [s, hill_frac * 100.0])

func test_terrain_has_no_cliffs() -> void:
	# Kein (fast) senkrechter Höhensprung auf 1 m Distanz — auch nicht an Flussufern und im
	# Übergang zum Spawn-Plateau. (Der alte Fluss/See hatte pro Chunk harte Kanten.)
	for s in SEEDS:
		var f := TerrainField.new(null, s)
		for i in 400:
			var x := float(i % 20) * 233.0 - 2300.0
			var z := float(i / 20) * 197.0 - 2000.0
			if f.get_mountain_weight_at(x, z) > 0.05:
				continue  # Gebirge: eigener Test (test_mountains_are_steep_but_not_vertical)
			assert_lt(absf(f.get_height_at(x + 1.0, z) - f.get_height_at(x, z)), 6.5)  # Wasserfälle: 5.5 m Stufen
			assert_lt(absf(f.get_height_at(x, z + 1.0) - f.get_height_at(x, z)), 6.5)

# ── Edit-Schicht ────────────────────────────────

func test_edit_layer_changes_height_but_not_base() -> void:
	var f := TerrainField.new(null, 1337)
	var layer := TerrainEditLayer.new()
	layer.set_delta(Vector2i(50, 50), -1.5)   # Weltposition (100, 100)
	var before := f.get_height_at(100.0, 100.0)
	f.set_edit_layer(layer)
	assert_almost_eq(f.get_height_at(100.0, 100.0), before - 1.5, 0.0001)
	assert_almost_eq(f.get_base_height_at(100.0, 100.0), before, 0.0001)

func test_field_without_edit_layer_equals_base() -> void:
	var f := TerrainField.new(null, 1337)
	assert_eq(f.get_height_at(321.0, -123.0), f.get_base_height_at(321.0, -123.0))

func test_edit_layer_can_be_replaced_and_removed() -> void:
	var f := TerrainField.new(null, 1337)
	var layer := TerrainEditLayer.new()
	layer.set_delta(Vector2i(50, 50), 2.0)
	f.set_edit_layer(layer)
	assert_same(f.get_edit_layer(), layer)
	f.set_edit_layer(null)
	assert_eq(f.get_height_at(100.0, 100.0), f.get_base_height_at(100.0, 100.0))

# ── Bodenmaterial (2026-09-26, "überall nur Erde" / "Sand bleibt Sand") ──

func test_material_without_layers_follows_biome_surface_material() -> void:
	var f := TerrainField.new(null, 1337)
	# Irgendeine Position im "meadow"-Klimabereich (Default-Fallback von
	# get_biome_for()) — surface_material dort ist "dirt" (Default).
	var biome := f.get_biome_at(1000000.0, 1000000.0)
	assert_eq(f.get_material_at(1000000.0, 1000000.0), biome.surface_material)

func test_material_override_wins_over_natural_material() -> void:
	var f := TerrainField.new(null, 1337)
	var materials := TerrainMaterialLayer.new()
	materials.set_override(Vector2i(50, 50), "sand")  # Weltposition (100, 100)
	f.set_material_layer(materials)
	assert_eq(f.get_material_at(100.0, 100.0), "sand")

func test_material_falls_back_to_gravel_below_subsoil_depth() -> void:
	var f := TerrainField.new(null, 1337)
	var edits := TerrainEditLayer.new()
	edits.set_delta(Vector2i(50, 50), TerrainField.SUBSOIL_DEPTH - 0.5)  # tiefer als die Schwelle
	f.set_edit_layer(edits)
	assert_eq(f.get_material_at(100.0, 100.0), "gravel")

func test_material_override_wins_even_below_subsoil_depth() -> void:
	# Bewusst abgelegtes Material (z.B. einen tiefen Schacht mit Sand verfüllt)
	# gewinnt IMMER gegen die Tiefen-Heuristik.
	var f := TerrainField.new(null, 1337)
	var edits := TerrainEditLayer.new()
	edits.set_delta(Vector2i(50, 50), TerrainField.SUBSOIL_DEPTH - 5.0)
	f.set_edit_layer(edits)
	var materials := TerrainMaterialLayer.new()
	materials.set_override(Vector2i(50, 50), "sand")
	f.set_material_layer(materials)
	assert_eq(f.get_material_at(100.0, 100.0), "sand")

func test_material_layer_can_be_replaced_and_removed() -> void:
	var f := TerrainField.new(null, 1337)
	var materials := TerrainMaterialLayer.new()
	materials.set_override(Vector2i(50, 50), "gravel")
	f.set_material_layer(materials)
	assert_same(f.get_material_layer(), materials)
	f.set_material_layer(null)
	assert_ne(f.get_material_at(100.0, 100.0), "")  # fällt sauber auf natürliches Material zurück, crasht nicht

# ── Wasser ──────────────────────────────────────

func _field_with(fn: Callable) -> FuncField:
	var f := FuncField.new()
	f.fn = fn
	return f

func test_water_is_where_terrain_is_below_water_level() -> void:
	var low := _field_with(func(_x: float, _z: float) -> float: return -1.0)
	var high := _field_with(func(_x: float, _z: float) -> float: return 3.0)
	assert_true(low.is_water_at(0, 0))
	assert_false(high.is_water_at(0, 0))

func test_water_depth() -> void:
	var f := _field_with(func(_x: float, _z: float) -> float: return -1.5)
	assert_almost_eq(f.get_water_depth_at(0, 0), 1.5, 0.0001)
	var dry := _field_with(func(_x: float, _z: float) -> float: return 2.0)
	assert_eq(dry.get_water_depth_at(0, 0), 0.0)

func test_water_level_comes_from_config() -> void:
	var cfg := TerrainConfig.new()
	cfg.water_level = 3.0
	var f := TerrainField.new(cfg, 1)
	assert_eq(f.get_water_level(), 3.0)

func test_water_level_at_matches_global_level_away_from_rivers() -> void:
	# Weitab von jedem Fluss (river_search_band-Vorfilter) muss der lokale Spiegel exakt dem
	# globalen entsprechen — das "beim Buddeln irgendwann auf Wasser stoßen" bleibt gleich.
	var f := TerrainField.new(null, 1337)
	assert_eq(f.get_water_level_at(999999.0, 999999.0), f.get_water_level())

func test_water_level_at_follows_river_terrain_not_one_flat_plane() -> void:
	# BUGFIX (2026-09-20, "Wasser/Flüsse & Seen sind alle auf einer Ebene"): innerhalb eines
	# echten Flusslaufs muss der Spiegel dem umgebenden (uneingeschnittenen) Gelände folgen —
	# nicht überall exakt derselbe globale Wert sein.
	var f := TerrainField.new(null, 1337)
	var differs := false
	for iz in 300:
		for ix in 300:
			var x := float(ix) * 15.0 - 2250.0
			var z := float(iz) * 15.0 - 2250.0
			if not is_equal_approx(f.get_water_level_at(x, z), f.get_water_level()):
				differs = true
				break
		if differs:
			break
	assert_true(differs, "Es muss Flussstellen geben, an denen der Spiegel vom globalen abweicht.")

func test_digging_away_from_rivers_still_floods_at_the_global_level() -> void:
	# Der Kern-Punkt aus dem BUGFIX-Kommentar: das gegrabene Loch abseits von Flüssen wird
	# NICHT sein eigener kleiner See auf der ursprünglichen Geländehöhe — es flutet weiterhin
	# beim globalen Spiegel, wie vorher.
	var f := TerrainField.new(null, 1337)
	var layer := TerrainEditLayer.new()
	f.set_edit_layer(layer)
	# Eine Stelle weit weg von jedem Fluss suchen, dort ein tiefes Loch graben.
	var x := 999999.0
	var z := 999999.0
	var natural_h: float = f.get_base_height_at(x, z)
	layer.set_delta(TerrainEditLayer.world_to_lattice(Vector2(x, z)), f.get_water_level() - 1.0 - natural_h)
	assert_true(f.is_water_at(x, z), "Tief genug gegraben → muss geflutet sein.")
	assert_almost_eq(f.get_water_level_at(x, z), f.get_water_level(), 0.0001,
		"Spiegel darf sich nicht auf die (ungegrabene) natürliche Höhe dieser Stelle verschieben.")

# ── Steigung ────────────────────────────────────

func test_slope_flat_and_tilted() -> void:
	var flat := _field_with(func(_x: float, _z: float) -> float: return 4.0)
	assert_almost_eq(flat.get_slope_at(10, 10), 0.0, 0.001)
	var ramp := _field_with(func(x: float, _z: float) -> float: return x)   # 1 m Anstieg pro m → 45°
	assert_almost_eq(ramp.get_slope_at(10, 10), 45.0, 0.01)

# ── Klima / Biome ───────────────────────────────

func test_climate_is_bounded_and_resolves_to_a_biome() -> void:
	var f := TerrainField.new(null, 1337)
	for i in 100:
		var c := f.get_climate_at(float(i) * 311.0 - 15000.0, float(i) * 173.0 - 9000.0)
		assert_true(c.x >= -1.0 and c.x <= 1.0 and c.y >= -1.0 and c.y <= 1.0)
		assert_not_null(f.get_biome_at(float(i) * 311.0, float(i) * 173.0))
		assert_false(f.get_biome_id_at(float(i) * 311.0, float(i) * 173.0).is_empty())

func test_climate_differs_between_seeds() -> void:
	var a := TerrainField.new(null, 1)
	var b := TerrainField.new(null, 2)
	var differs := false
	for i in 30:
		if a.get_climate_at(i * 500.0, i * 300.0) != b.get_climate_at(i * 500.0, i * 300.0):
			differs = true
			break
	assert_true(differs)

func test_all_biomes_occur_somewhere_in_the_world() -> void:
	# Regressionsschutz für "ich habe noch nie eine Wüste / Eislandschaft gesehen":
	# in einer 20-km-Weltscheibe müssen Wüste UND Winter vorkommen.
	var f := TerrainField.new(null, 1337)
	var seen: Dictionary = {}
	for iz in 80:
		for ix in 80:
			seen[f.get_biome_id_at(float(ix) * 250.0 - 10000.0, float(iz) * 250.0 - 10000.0)] = true
	assert_true(seen.has("desert"), "Keine Wüste in 20 km × 20 km")
	assert_true(seen.has("winter"), "Kein Eis in 20 km × 20 km")

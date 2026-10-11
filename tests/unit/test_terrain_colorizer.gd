# res://tests/unit/test_terrain_colorizer.gd
extends GutTest

## Unit-Tests für TerrainColorizer.height_to_color() (stateless, reine Funktion).
##
## Test-Setup: max_height=98.0, sea_level=20.0 -> min_h=-2.0 (Konstante im
## Code) -> ratio = (h+2)/100, sl_ratio = 22/100 = 0.22. Damit ergeben sich
## sehr saubere Grenzwerte für jedes der sieben Bänder.
##
## Strategie GEGEN Lerp-Rundungsrisiko: für jede Bandgrenze wird exakt der
## Wert gewählt, bei dem der jeweilige lerp()-Faktor t=0 ist — an der Stelle
## liefert lerp() immer exakt die Startfarbe zurück, ganz ohne
## Fließkomma-Unschärfe. Nur EIN Test prüft einen echten Interior-Punkt
## (t=0.5), dessen erwarteter Wert vorher in Python nachgerechnet wurde
## (siehe Kommentar dort).
##
## Abgedeckt: alle sieben Farbbänder (inkl. beider Clamping-Enden), ein
## Lerp-Interior-Punkt, Konsistenz bei wiederholtem Aufruf (stateless).

const MAX_HEIGHT := 98.0
const SEA_LEVEL := 20.0
const GRASS := Color(0.3, 0.6, 0.25)  # beliebige Biom-Grasfarbe, ungleich dem Fallback-COL_GRASS

var _colorizer: TerrainColorizer


func before_each() -> void:
	_colorizer = TerrainColorizer.new()


func after_each() -> void:
	_colorizer = null


func _color(h: float) -> Color:
	return _colorizer.height_to_color(h, GRASS, MAX_HEIGHT, SEA_LEVEL)


# ─────────────────────────────────────────────
# Sieben Bänder, jeweils an einer t=0-Grenze (exakt, kein Lerp-Risiko)
# ─────────────────────────────────────────────

func test_deep_water_interior() -> void:
	assert_eq(_color(3.0), TerrainColorizer.COL_DEEP_WATER)  # ratio=0.05 < 0.11

func test_shallow_at_band_start() -> void:
	assert_eq(_color(9.0), TerrainColorizer.COL_SHALLOW)  # ratio=0.11, t=0 im shallow->sand-Lerp

func test_sand_at_band_start() -> void:
	assert_eq(_color(20.0), TerrainColorizer.COL_SAND)  # ratio=0.22=sl_ratio, t=0 im sand->grass-Lerp

func test_grass_at_band_start() -> void:
	assert_eq(_color(24.0), GRASS)  # ratio=0.26=sl_ratio+0.04, direkt grass_color (kein Lerp mehr)

func test_grass_interior() -> void:
	assert_eq(_color(38.0), GRASS)  # ratio=0.40, mitten im reinen Grass-Band

func test_hill_at_band_start() -> void:
	assert_eq(_color(53.0), GRASS)  # ratio=0.55, t=0 im grass->hill-Lerp -> exakt grass_color

func test_rock_at_band_start() -> void:
	assert_eq(_color(70.0), TerrainColorizer.COL_HILL)  # ratio=0.72, t=0 im hill->rock-Lerp

func test_snow_lerp_at_band_start() -> void:
	assert_eq(_color(86.0), TerrainColorizer.COL_ROCK)  # ratio=0.88, t=0 im rock->snow-Lerp

func test_full_snow_at_max_height() -> void:
	assert_eq(_color(98.0), TerrainColorizer.COL_SNOW)  # ratio=1.0, t=1 im rock->snow-Lerp


# ─────────────────────────────────────────────
# Clamping an beiden Enden
# ─────────────────────────────────────────────

func test_height_far_above_max_clamps_to_snow() -> void:
	assert_eq(_color(10000.0), TerrainColorizer.COL_SNOW)

func test_height_far_below_min_clamps_to_deep_water() -> void:
	assert_eq(_color(-10000.0), TerrainColorizer.COL_DEEP_WATER)


# ─────────────────────────────────────────────
# Ein echter Lerp-Interior-Punkt (Wert vorab in Python nachgerechnet)
# ─────────────────────────────────────────────

func test_shallow_to_sand_lerp_interior_point() -> void:
	# ratio=0.165 -> t=(0.165-0.11)/0.11=0.5 im shallow->sand-Band.
	var c := _color(14.5)
	assert_almost_eq(c.r, 0.47, 0.0005)
	assert_almost_eq(c.g, 0.595, 0.0005)
	assert_almost_eq(c.b, 0.6, 0.0005)


# ─────────────────────────────────────────────
# Stateless — wiederholter Aufruf liefert dasselbe Ergebnis
# ─────────────────────────────────────────────

func test_repeated_calls_are_consistent() -> void:
	var first := _color(38.0)
	var second := _color(38.0)
	assert_eq(first, second)


# ─────────────────────────────────────────────
# terrain_color() — Wasserspiegel, Steigung, Gebirgszonen (2026-10-04)
# ─────────────────────────────────────────────

func _tc(h: float, water: float = 0.0, slope_cos: float = 1.0, jitter: float = 0.0) -> Color:
	return _colorizer.terrain_color(h, GRASS, 100.0, water, slope_cos, jitter)

func test_terrain_color_flat_meadow_is_pure_biome_grass() -> void:
	assert_eq(_tc(10.0), GRASS)

func test_terrain_color_underwater_is_sand_shallow_and_silt_deep() -> void:
	assert_eq(_tc(-0.0001, 0.0), TerrainColorizer.COL_SAND.lerp(TerrainColorizer.COL_SILT, 0.0001 / TerrainColorizer.BED_FULL_DEPTH))
	assert_eq(_tc(-10.0, 0.0), TerrainColorizer.COL_SILT)

func test_terrain_color_river_bed_above_sea_level_is_still_water_bed() -> void:
	# Flussbett bei h=1.0 mit lokalem Wasserspiegel 3.0 → Gewässerboden, NICHT Wiese.
	assert_eq(_tc(1.0, 3.0), TerrainColorizer.COL_SAND.lerp(TerrainColorizer.COL_SILT, 2.0 / TerrainColorizer.BED_FULL_DEPTH))

func test_terrain_color_shore_strip_is_sand_not_grass() -> void:
	var c := _tc(0.1, 0.0)
	assert_ne(c, GRASS)
	assert_gt(c.r, GRASS.r, "Ufer ist heller/sandiger als Gras.")

func test_terrain_color_steep_slope_is_rock_at_any_height() -> void:
	var steep := _tc(10.0, 0.0, 0.5)  # ~60°
	assert_ne(steep, GRASS)
	assert_almost_eq(steep.r, TerrainColorizer.COL_ROCK.r, 0.1)

func test_terrain_color_snow_on_high_flat_ground_but_not_on_cliffs() -> void:
	assert_eq(_tc(95.0), TerrainColorizer.COL_SNOW)
	var cliff := _tc(95.0, 0.0, 0.4)
	assert_ne(cliff, TerrainColorizer.COL_SNOW, "Schnee haftet nicht an Steilwänden.")

func test_terrain_color_zones_progress_grass_rock_snow() -> void:
	var low := _tc(10.0)
	var mid := _tc(40.0)
	var high := _tc(90.0)
	assert_eq(low, GRASS)
	assert_gt(high.r + high.g + high.b, mid.r + mid.g + mid.b, "Oben heller (Schnee) als mittig (Fels).")

func test_terrain_color_jitter_shifts_snow_line() -> void:
	# Bei Höhe an der Schneegrenze entscheidet jitter, ob schon Schnee liegt.
	var h: float = 100.0 * (TerrainColorizer.SNOW_START + TerrainColorizer.SNOW_END) * 0.5
	var snowier := _tc(h, 0.0, 1.0, 1.0)
	var barer := _tc(h, 0.0, 1.0, -1.0)
	assert_gt(snowier.r + snowier.g + snowier.b, barer.r + barer.g + barer.b)

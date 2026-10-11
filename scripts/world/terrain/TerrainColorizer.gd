class_name TerrainColorizer
extends RefCounted

## TerrainColorizer — Höhe + Biome → Vertex-Farbe.
##
## Kapselt die gesamte Farbgebungs-Logik (aufgerufen vom TerrainMeshBuilder).
## Stateless: jede Methode braucht nur die übergebenen Werte.

const COL_DEEP_WATER := Color(0.08, 0.25, 0.55)
const COL_SHALLOW    := Color(0.18, 0.48, 0.70)
const COL_SAND       := Color(0.76, 0.71, 0.50)
const COL_GRASS      := Color(0.24, 0.54, 0.20)  # Fallback, falls kein Biom auflösbar (siehe height_to_color())
const COL_HILL       := Color(0.36, 0.30, 0.20)
const COL_ROCK       := Color(0.50, 0.46, 0.42)
const COL_GRAVEL      := Color(0.55, 0.52, 0.47)  # Kies-Unterboden, siehe TerrainField.SUBSOIL_DEPTH
const COL_SNOW        := Color(0.93, 0.94, 0.96)

## h in [-2, max_height], grass_color = BiomeDefinition.terrain_color_grass des
## Bioms an dieser Weltposition (Round 74 — vorher: synthetischer 0..1
## "biome"-Float ohne echte Biom-Zuordnung, siehe TerrainChunkBuilder._biome_color()).
## sea_level in Welteinheiten.
func height_to_color(h: float, grass_color: Color, max_height: float, sea_level: float) -> Color:
	var min_h: float    = -2.0
	var ratio: float    = clampf((h - min_h) / (max_height - min_h), 0.0, 1.0)
	var sl_ratio: float = (sea_level - min_h) / (max_height - min_h)

	if ratio < sl_ratio * 0.5:
		return COL_DEEP_WATER
	elif ratio < sl_ratio:
		return COL_SHALLOW.lerp(COL_SAND, (ratio - sl_ratio * 0.5) / (sl_ratio * 0.5))
	elif ratio < sl_ratio + 0.04:
		return COL_SAND.lerp(grass_color, (ratio - sl_ratio) / 0.04)
	elif ratio < 0.55:
		return grass_color
	elif ratio < 0.72:
		return grass_color.lerp(COL_HILL, (ratio - 0.55) / 0.17)
	elif ratio < 0.88:
		return COL_HILL.lerp(COL_ROCK, (ratio - 0.72) / 0.16)
	else:
		return COL_ROCK.lerp(COL_SNOW, (ratio - 0.88) / 0.12)

# ─────────────────────────────────────────────
# Gelände-Färbung mit Wasser, Steigung und Gebirgszonen (2026-10-04, "realistischeres Terrain")
# ─────────────────────────────────────────────
#
# height_to_color() kennt nur die Höhe über einem EINZIGEN Meeresspiegel. Mit Flusstälern und
# Gebirgen reicht das nicht mehr: ein Flussbett liegt über dem Meeresspiegel (wäre "Wiese"), und
# ein Hang ist an jeder Höhe Fels, sobald er steil genug ist. Diese Funktion bekommt deshalb den
# LOKALEN Wasserspiegel und die Steigung (Normale.y). Zonen von unten nach oben:
#
#   Gewässerboden   Sand → dunkler Schlick (je tiefer, desto dunkler)
#   Ufer            Sand-/Kiesstreifen bis ~1 m über Wasser
#   Vorland         Grasfarbe des Bioms
#   Hügel/Waldgrenze ab ~20-32 % max_height Übergang ins Braun-Graue
#   Fels            ab ~30-46 % max_height Fels; steile Hänge sind IMMER felsig
#   Schnee          ab ~58-70 % max_height, haftet nicht an steilen Wänden
#
# `jitter` (~[-1,1], aus glatter Weltkoordinaten-Funktion) verschiebt die Grenzen um bis zu ±4 %
# max_height, damit Wald-/Schneegrenze nicht wie mit dem Lineal gezogen aussehen.

const COL_SILT       := Color(0.30, 0.31, 0.27)  # Flussbett/Seegrund in der Tiefe
const COL_ROCK_DARK  := Color(0.36, 0.34, 0.33)  # schattige/steile Felspartien
const COL_BANK       := Color(0.50, 0.45, 0.33)  # feuchtes Ufer (Sand-Erde-Mischung)

const BED_FULL_DEPTH: float = 6.0       # ab dieser Wassertiefe ist der Grund voll "Schlick"
const SHORE_HEIGHT: float = 0.9         # Uferstreifen: Höhe über Wasser, bis zu der Sand/Kies liegt
const HILL_START: float = 0.20
const HILL_END: float = 0.32
const ROCK_START: float = 0.30
const ROCK_END: float = 0.46
const SNOW_START: float = 0.58
const SNOW_END: float = 0.70
const JITTER_SPAN: float = 0.04

## slope_cos = Normale.y (1 = eben, 0.7 ≈ 45°). water_level = LOKALER Wasserspiegel an dieser Stelle.
func terrain_color(
	h: float, grass_color: Color, max_height: float, water_level: float,
	slope_cos: float = 1.0, jitter: float = 0.0
) -> Color:
	var depth: float = water_level - h
	if depth > 0.0:
		var bed_t: float = clampf(depth / BED_FULL_DEPTH, 0.0, 1.0)
		return COL_SAND.lerp(COL_SILT, bed_t)

	var above: float = -depth   # Höhe über Wasser
	var a: float = h / maxf(max_height, 0.001) + jitter * JITTER_SPAN
	var col: Color = grass_color

	var hill_w: float = smoothstep(HILL_START, HILL_END, a)
	if hill_w > 0.0:
		col = col.lerp(COL_HILL, hill_w)

	var rock_w: float = smoothstep(ROCK_START, ROCK_END, a)
	# Steile Hänge sind Fels, egal wie hoch: ab ~28° beginnt es, ab ~50° ist es voller Fels.
	rock_w = maxf(rock_w, 1.0 - smoothstep(0.64, 0.88, slope_cos))
	if rock_w > 0.0:
		var rock: Color = COL_ROCK.lerp(COL_ROCK_DARK, clampf(jitter * 0.5 + 0.5, 0.0, 1.0) * 0.6)
		col = col.lerp(rock, rock_w)

	var snow_w: float = smoothstep(SNOW_START, SNOW_END, a)
	# Schnee haftet nicht an Steilwänden (ab ~55° kaum noch).
	snow_w *= smoothstep(0.50, 0.78, slope_cos)
	if snow_w > 0.0:
		col = col.lerp(COL_SNOW, snow_w)

	# Ufer zuletzt: unabhängig von Zone ein Streifen aus Sand/Kies/feuchter Erde direkt am Wasser.
	# Aber NICHT an Steilwänden (Wasserfall, Schlucht, Felsküste): dort bleibt es Fels, nur nasser.
	var flat_w: float = smoothstep(0.55, 0.85, slope_cos)
	var shore_w: float = (1.0 - smoothstep(SHORE_HEIGHT * 0.35, SHORE_HEIGHT, above)) * flat_w
	var wet_rock: float = (1.0 - flat_w) * (1.0 - smoothstep(1.0, 4.0, above))
	if wet_rock > 0.0:
		col = col.lerp(COL_ROCK_DARK * 0.8, wet_rock)
	if shore_w > 0.0:
		var shore: Color = COL_SAND.lerp(COL_BANK, clampf(jitter * 0.5 + 0.5, 0.0, 1.0))
		col = col.lerp(shore, shore_w)
	return col

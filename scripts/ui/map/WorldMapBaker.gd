class_name WorldMapBaker
extends RefCounted

## WorldMapBaker — backt die Weltkarte (Draufsicht) aus dem TerrainField in Kachel-Texturen.
##
## WARUM NICHT EINFACH DIE GELADENEN CHUNKS ABFILMEN?
##   Das Gelände wird nur in einem Fenster um den Spieler gestreamt (ChunkManager.LOAD_RADIUS,
##   ~576 m). Eine Karte soll weiter reichen. TerrainField ist aber "die eine Wahrheit" und
##   kann Höhe/Wasser/Biom an JEDEM Weltpunkt liefern, auch ohne geladenen Chunk — daraus
##   entsteht die Karte, mit denselben Farben wie das echte Gelände (TerrainColorizer).
##
## ZEITSCHEIBEN
##   Höhe/Wasser pro Punkt laufen durch den GDScript-Layerstapel (Erosion, Flüsse, Seen) — das
##   kostet. Deshalb arbeitet der Baker in Reihen und über step(budget_msec) verteilt auf Frames,
##   nächste Kacheln zuerst. Ein Frame überschreitet das Budget höchstens um eine Reihe.
##
## DARSTELLUNG
##   Pro Punkt: Wasser (Flachwasser → Tiefwasser) oder Gelände-Farbe laut TerrainColorizer
##   (Biom-Gras, Hügel, Fels, Schnee, Ufer), dazu Reliefschattierung ("Hillshade") aus der Steigung.
##   Die Kachel hat 1 Zelle Rand zusätzlich im Sample-Gitter (nur für die Steigung), das Bild
##   selbst ist tile_px × tile_px.
##
## ZWEI AUFLÖSUNGEN
##   Der Aufrufer (WorldMapView) hält zwei Baker: fein (nah, wenig Fläche) und grob (weit).
##   Der Baker selbst kennt nur `cell_m` und `tile_px`.

const LOG_CAT := "WorldMapBaker"

## Tiefe, ab der Wasser voll "tief" gefärbt ist (m).
const WATER_FULL_DEPTH: float = 6.0
## Lichtrichtung der Reliefschattierung (von Nordwest/oben, in Weltkoordinaten x,y,z).
const LIGHT_DIR := Vector3(-0.5, 0.75, -0.45)
## Stärke der Schattierung (0 = flach).
const SHADE_STRENGTH: float = 1.7
const SHADE_MIN: float = 0.62
const SHADE_MAX: float = 1.32

var cell_m: float
var tile_px: int
var tile_m: float

var _field: TerrainField = null
var _colorizer: TerrainColorizer = TerrainColorizer.new()
var _max_height: float = 95.0
var _light: Vector3 = LIGHT_DIR.normalized()

var _tiles: Dictionary = {}         # { Vector2i: ImageTexture }
var _queue: Array[Vector2i] = []    # wartende Kacheln (vorn = wichtigste)
var _job: Dictionary = {}           # laufende Kachel (siehe _begin_job)

func _init(cell_meters: float = 8.0, tile_pixels: int = 64) -> void:
	cell_m = maxf(0.5, cell_meters)
	tile_px = maxi(4, tile_pixels)
	tile_m = cell_m * float(tile_px)

## `field` darf null sein (Tests, Welt noch nicht bereit) — dann bleibt der Baker leer.
func setup(field: TerrainField) -> void:
	_field = field
	if _field != null and _field.get_config() != null:
		_max_height = maxf(1.0, _field.get_config().max_height)
	clear()

func is_ready() -> bool:
	return _field != null

## Alles verwerfen (z. B. nach großen Terrain-Änderungen).
func clear() -> void:
	_tiles.clear()
	_queue.clear()
	_job = {}

# ─────────────────────────────────────────────
# Kachel-Geometrie
# ─────────────────────────────────────────────

func world_to_tile(world_xz: Vector2) -> Vector2i:
	return Vector2i(floori(world_xz.x / tile_m), floori(world_xz.y / tile_m))

## Weltrechteck (x, z) der Kachel.
func tile_rect(coord: Vector2i) -> Rect2:
	return Rect2(Vector2(coord) * tile_m, Vector2(tile_m, tile_m))

func tile_count() -> int:
	return _tiles.size()

func pending_count() -> int:
	return _queue.size() + (1 if not _job.is_empty() else 0)

func has_tile(coord: Vector2i) -> bool:
	return _tiles.has(coord)

func get_tile_texture(coord: Vector2i) -> ImageTexture:
	return _tiles.get(coord, null) as ImageTexture

## Alle Kachelkoordinaten, die den Kreis (center, radius) berühren, sortiert nach Abstand der
## Kachelmitte zum Zentrum (nächste zuerst).
func tiles_in_radius(center: Vector2, radius: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var lo := world_to_tile(center - Vector2(radius, radius))
	var hi := world_to_tile(center + Vector2(radius, radius))
	for ty in range(lo.y, hi.y + 1):
		for tx in range(lo.x, hi.x + 1):
			var c := Vector2i(tx, ty)
			var r := tile_rect(c)
			# Nächster Punkt des Rechtecks zum Zentrum — berührt der Kreis die Kachel?
			var nearest := Vector2(clampf(center.x, r.position.x, r.end.x), clampf(center.y, r.position.y, r.end.y))
			if nearest.distance_to(center) <= radius:
				out.append(c)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return tile_rect(a).get_center().distance_squared_to(center) < tile_rect(b).get_center().distance_squared_to(center))
	return out

# ─────────────────────────────────────────────
# Anfordern + Backen
# ─────────────────────────────────────────────

## Fordert alle noch fehlenden Kacheln im Kreis an. Die Warteschlange wird dabei NEU geordnet:
## nicht mehr benötigte (außerhalb des Kreises) wartende Kacheln fallen raus, die nächsten
## kommen zuerst. Bereits fertige Kacheln bleiben im Cache.
func request_area(center: Vector2, radius: float) -> void:
	if _field == null:
		return
	var wanted := tiles_in_radius(center, radius)
	_queue.clear()
	for c in wanted:
		if _tiles.has(c):
			continue
		if not _job.is_empty() and _job["coord"] == c:
			continue
		_queue.append(c)

## Arbeitet höchstens ~budget_msec Millisekunden ab. Rückgabe: Anzahl in diesem Aufruf FERTIG
## gewordener Kacheln. Mindestens eine Reihe wird immer bearbeitet (Fortschritt garantiert).
func step(budget_msec: float) -> int:
	if _field == null:
		return 0
	var finished := 0
	var t_start := Time.get_ticks_usec()
	var budget_usec := int(maxf(0.0, budget_msec) * 1000.0)
	while true:
		if _job.is_empty():
			if _queue.is_empty():
				break
			_job = _begin_job(_queue.pop_front())
		if _advance_job():
			var coord: Vector2i = _job["coord"]
			_tiles[coord] = ImageTexture.create_from_image(_job["image"] as Image)
			_job = {}
			finished += 1
		if Time.get_ticks_usec() - t_start >= budget_usec:
			break
	return finished

## Backt eine Kachel komplett und sofort (Tests, Vorschau). Rückgabe: Image.
func bake_tile_now(coord: Vector2i) -> Image:
	if _field == null:
		return null
	var job := _begin_job(coord)
	while not _advance_job_for(job):
		pass
	return job["image"] as Image

func _begin_job(coord: Vector2i) -> Dictionary:
	var n := tile_px + 2   # Sample-Gitter inkl. 1 Zelle Rand
	return {
		"coord": coord,
		"n": n,
		"stage": 0,           # 0 = Höhen sampeln, 1 = einfärben
		"row": 0,
		"heights": PackedFloat32Array(),
		"water": PackedFloat32Array(),
		"grass": PackedColorArray(),
		"image": Image.create(tile_px, tile_px, false, Image.FORMAT_RGBA8),
	}

## Ein Zeitschritt = eine Reihe. true = Kachel fertig.
func _advance_job() -> bool:
	return _advance_job_for(_job)

func _advance_job_for(job: Dictionary) -> bool:
	var n: int = job["n"]
	var coord: Vector2i = job["coord"]
	var origin := Vector2(coord) * tile_m   # Weltposition der oberen linken Bildecke
	if int(job["stage"]) == 0:
		var row: int = job["row"]
		var heights: PackedFloat32Array = job["heights"]
		var water: PackedFloat32Array = job["water"]
		var grass: PackedColorArray = job["grass"]
		var wz := origin.y + (float(row - 1) + 0.5) * cell_m
		for ix in n:
			var wx := origin.x + (float(ix - 1) + 0.5) * cell_m
			heights.append(_field.get_height_at(wx, wz))
			water.append(_field.get_water_level_at(wx, wz))
			var biome: BiomeDefinition = _field.get_biome_at(wx, wz)
			grass.append(biome.terrain_color_grass if is_instance_valid(biome) else TerrainColorizer.COL_GRASS)
		job["heights"] = heights
		job["water"] = water
		job["grass"] = grass
		job["row"] = row + 1
		if row + 1 >= n:
			job["stage"] = 1
			job["row"] = 0
		return false

	var py: int = job["row"]
	var img: Image = job["image"]
	var heights2: PackedFloat32Array = job["heights"]
	var water2: PackedFloat32Array = job["water"]
	var grass2: PackedColorArray = job["grass"]
	for px in tile_px:
		var wx2 := origin.x + (float(px) + 0.5) * cell_m
		var wz2 := origin.y + (float(py) + 0.5) * cell_m
		img.set_pixel(px, py, _shade_cell(heights2, water2, grass2, n, px + 1, py + 1, wx2, wz2))
	job["row"] = py + 1
	return py + 1 >= tile_px

## Farbe einer Zelle (ix, iy im Sample-Gitter inkl. Rand).
func _shade_cell(
	heights: PackedFloat32Array, water: PackedFloat32Array, grass: PackedColorArray,
	n: int, ix: int, iy: int, wx: float, wz: float
) -> Color:
	var i := iy * n + ix
	var h := heights[i]
	var wl := water[i]
	var gx := (heights[i + 1] - heights[i - 1]) / (2.0 * cell_m)
	var gz := (heights[i + n] - heights[i - n]) / (2.0 * cell_m)
	var normal := Vector3(-gx, 1.0, -gz).normalized()
	return color_for(h, wl, grass[i], normal, wx, wz)

## Reine Farbfunktion (testbar): Höhe, lokaler Wasserspiegel, Biom-Gras, Normale → Kartenfarbe.
func color_for(h: float, water_level: float, grass: Color, normal: Vector3, wx: float, wz: float) -> Color:
	var depth := water_level - h
	var col: Color
	if depth > 0.0:
		col = TerrainColorizer.COL_SHALLOW.lerp(TerrainColorizer.COL_DEEP_WATER, clampf(depth / WATER_FULL_DEPTH, 0.0, 1.0))
		# Wasser nur ganz leicht schattieren (Ufer-Relief soll nicht durchscheinen).
		return Color(col.r, col.g, col.b, 1.0)
	# Glatte Pseudo-Zufallsfunktion für unregelmäßige Wald-/Schneegrenzen (wie am echten Gelände).
	var jitter := sin(wx * 0.011 + 1.3) * cos(wz * 0.013 - 0.7)
	col = _colorizer.terrain_color(h, grass, _max_height, water_level, normal.y, jitter)
	var shade := clampf(1.0 + (normal.dot(_light) - _light.y) * SHADE_STRENGTH, SHADE_MIN, SHADE_MAX)
	return Color(clampf(col.r * shade, 0.0, 1.0), clampf(col.g * shade, 0.0, 1.0), clampf(col.b * shade, 0.0, 1.0), 1.0)

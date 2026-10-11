class_name TerrainLakeLayer
extends TerrainLayer

## TerrainLakeLayer — Bergseen und Hügelseen auf EIGENER Höhe.
##
## Meer und Tiefland-Seen sind Becken des TerrainBaseLayers und stehen auf dem globalen Spiegel
## (stehendes Wasser gleicht sich aus). Hügel und Berge haben aber auch Seen, die hoch über dem
## Meer liegen — das geht nur mit eigenem Wasserspiegel pro See. Dieser Layer setzt sie.
##
## ═══ PLATZIERUNG (rein prozedural, ohne Zustand) ═══
## Raster aus Zellen (lake_cell_size). Pro Zelle würfelt ein Integer-Hash, OB und WO ein See
## liegt (Mittelpunkt in [0.3, 0.7] der Zelle), wie groß er ist und wie tief. Reichweite
## (Radius × (1+Formamplitude) + Ufer) < 0.3 × Zelle → ein See reicht nie in die Nachbarzelle,
## es muss pro Punkt nur EINE Zelle geprüft werden.
## Der Seespiegel wird einmal pro Zelle bestimmt (Ergebnis zwischengespeichert, deterministisch):
##   Spiegel = lake_level_quantile der Randhöhen (16 Punkte auf dem Uferradius) − 0.3 m
## Die tiefsten Randpunkte liegen dadurch unter dem Spiegel; dort hebt die Böschung das Ufer zu einem
## niedrigen Damm an (bank_top = max(Gelände, Spiegel + bank_min)). Ist dieser Damm höher als
## lake_max_dam, gibt es keinen See. (Ein Spiegel am TIEFSTEN Randpunkt scheiterte in der Simulation
## fast überall: in 150 m Umkreis liegt fast immer irgendwo Meeresniveau oder ein Flusstal.)
## Ungeeignete Stellen (Spiegel außerhalb min/max_alt, Hügelkuppe, zu nah an Fluss/Spawn) bekommen keinen See.
##
## ═══ FORM ═══
## Ufer = Kreis mit verzerrtem Radius (Formnoise, ±lake_shape_amplitude). Innen Parabelbett (flach
## am Ufer, am tiefsten in der Mitte), außen wie beim Fluss eine Böschung bis zur Geländehöhe,
## mindestens lake_bank_min über dem Wasser (sonst Uferwall).
## Wasserspiegel-Ziel gilt bis zum Ende der Böschung; ob dort Wasser steht, entscheidet wie
## überall der Vergleich mit der Geländehöhe.

var _cfg: TerrainConfig
var _seed: int
## Callable(x, z) -> float: Geländehöhe der Layer VOR diesem (Basis, Erosion, Fluss).
var _height_below: Callable
var _river: TerrainRiverLayer
var _shape: FastNoiseLite
## Vector2i (Zelle) → Dictionary (leer = kein See). Rein aus dem Seed ableitbar.
var _cache: Dictionary = {}

func _init(cfg: TerrainConfig, world_seed: int, height_below: Callable, river: TerrainRiverLayer = null) -> void:
	_cfg = cfg
	_seed = TerrainSeed.derive(world_seed, "terrain.lake") & 0xFFFFF
	_height_below = height_below
	_river = river
	_shape = make_noise(TerrainSeed.derive(world_seed, "terrain.lake_shape"), 0.012, 2)

func apply(world_x: float, world_z: float, h: float) -> float:
	return _sample(world_x, world_z, h).x

## Seespiegel an (x, z), NAN wenn hier kein See(-ufer) ist. Unabhängig von der Geländehöhe.
func get_water_target_at(world_x: float, world_z: float) -> float:
	return _sample(world_x, world_z, 0.0).y

## Seeeintrag der Zelle (leeres Dictionary = kein See). Felder: center (Vector2), radius, level, depth.
func get_lake_record(cell: Vector2i) -> Dictionary:
	if _cache.has(cell):
		return _cache[cell]
	var rec: Dictionary = _build_record(cell)
	_cache[cell] = rec
	return rec

func _cell_of(world_x: float, world_z: float) -> Vector2i:
	return Vector2i(floori(world_x / _cfg.lake_cell_size), floori(world_z / _cfg.lake_cell_size))

## x, z: zwei Zufallswerte; Rückgabe 5 Werte [0,1) für Existenz, Lage x/z, Radius, Tiefe.
func _rolls(cell: Vector2i) -> PackedFloat32Array:
	var a: Vector2 = TerrainErosionLayer._hash2(cell.x, cell.y, _seed)
	var b: Vector2 = TerrainErosionLayer._hash2(cell.x + 7919, cell.y - 104729, _seed + 1)
	var c: Vector2 = TerrainErosionLayer._hash2(cell.x - 31337, cell.y + 271, _seed + 2)
	return PackedFloat32Array([a.x, a.y, b.x, b.y, c.x])

func _build_record(cell: Vector2i) -> Dictionary:
	if not _cfg.lake_enabled or not _height_below.is_valid():
		return {}
	var r: PackedFloat32Array = _rolls(cell)
	if r[0] > _cfg.lake_chance:
		return {}

	var cs: float = _cfg.lake_cell_size
	var center := Vector2((float(cell.x) + 0.3 + 0.4 * r[1]) * cs, (float(cell.y) + 0.3 + 0.4 * r[2]) * cs)
	var radius: float = lerpf(_cfg.lake_min_radius, _cfg.lake_max_radius, r[3])
	var depth: float = lerpf(_cfg.lake_depth_min, _cfg.lake_depth_max, r[4])

	if center.length() < _cfg.lake_spawn_clear + radius:
		return {}

	# Randhöhen auf dem Uferradius → Seespiegel (siehe Klassenkommentar).
	var h_center: float = _height_below.call(center.x, center.y)
	var rim: Array[float] = []
	var steps: int = 16
	for i in range(steps):
		var a: float = TAU * float(i) / float(steps)
		rim.append(_height_below.call(center.x + cos(a) * radius, center.y + sin(a) * radius))
	rim.sort()
	var level: float = rim[int(_cfg.lake_level_quantile * float(steps - 1))] - 0.3

	if level < _cfg.lake_min_alt or level > _cfg.lake_max_alt:
		return {}
	# Mittelpunkt darf nicht weit ÜBER dem Spiegel liegen (Kuppe) — sonst wäre es eine Riesen-Grube.
	if h_center - level > _cfg.lake_max_pit:
		return {}
	# Kein haushoher künstlicher Damm.
	if level - rim[0] > _cfg.lake_max_dam:
		return {}
	# Nicht auf einem Fluss.
	if _river != null:
		var clear: float = radius + _cfg.lake_river_clear
		if _river.distance_m(center.x, center.y) < clear:
			return {}
		for i in range(8):
			var a2: float = TAU * float(i) / 8.0
			if _river.distance_m(center.x + cos(a2) * radius, center.y + sin(a2) * radius) < _cfg.lake_river_clear:
				return {}
	return {"center": center, "radius": radius, "level": level, "depth": depth}

## Rückgabe: x = neue Höhe, y = Seespiegel (NAN = keiner), z = Einfluss 0 … 1.
func _sample(world_x: float, world_z: float, h: float) -> Vector3:
	var none := Vector3(h, NAN, 0.0)
	if not _cfg.lake_enabled:
		return none
	var rec: Dictionary = get_lake_record(_cell_of(world_x, world_z))
	if rec.is_empty():
		return none

	var center: Vector2 = rec["center"]
	var radius: float = rec["radius"]
	var dx: float = world_x - center.x
	var dz: float = world_z - center.y
	var dist: float = sqrt(dx * dx + dz * dz)
	var zone_end: float = _cfg.lake_bank_width + _cfg.lake_outer_blend
	# Schneller Ausstieg: außerhalb der größtmöglichen Reichweite.
	if dist > radius * (1.0 + _cfg.lake_shape_amplitude) + zone_end:
		return none

	var shape: float = 1.0 + _cfg.lake_shape_amplitude * _shape.get_noise_2d(world_x, world_z)
	var d_eff: float = dist / shape
	var sd: float = d_eff - radius          # <0 im See, >0 am Ufer (m)
	if sd >= zone_end:
		return none

	var level: float = rec["level"]
	var profile: float
	if sd < 0.0:
		var u: float = clampf(d_eff / radius, 0.0, 1.0)
		profile = level - float(rec["depth"]) * (1.0 - u * u)
	else:
		var t: float = clampf(sd / _cfg.lake_bank_width, 0.0, 1.0)
		var e: float = 1.0 - (1.0 - t) * (1.0 - t)
		var bank_top: float = maxf(h, level + _cfg.lake_bank_min)
		profile = lerpf(level, bank_top, e)

	var inside: float = 1.0 - smoothstep(_cfg.lake_bank_width, zone_end, maxf(sd, 0.0))
	var carved: float = lerpf(h, profile, inside)
	var water: float = level if sd < _cfg.lake_bank_width else NAN
	return Vector3(carved, water, inside)

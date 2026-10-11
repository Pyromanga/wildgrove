class_name TreeSkeleton
extends RefCounted

## TreeSkeleton — erzeugt das Astwerk eines Baums als reine Daten (keine Nodes, keine Meshes).
##
## Wunsch (2026-10-07): "Bäume sind winzig im Vergleich zum Spieler, kaum Verästelungen, jeder
## Baum hat gefühlt nur 7 Blätter". Vorher: 2 m Stamm, 2 Äste, ein Blattbüschel je Ast. Jetzt:
## echte Proportionen (Eiche ≈ 9–10 m bei 1,8 m Spielergröße) und rekursive Verzweigung über bis
## zu drei Ebenen (Hauptäste → Seitenäste → Zweige), an deren Enden Blattanker sitzen.
##
## Rein deterministisch: gleicher (cfg, scale, max_level, seed) → gleiches Ergebnis, auf jedem
## Peer (RandomNumberGenerator mit festem Seed, kein globaler Zufall). Dadurch ohne Godot-Szene
## testbar (tests/unit/test_tree_skeleton.gd). MeshCache setzt daraus MultiMeshes zusammen.
##
## Ergebnis: {
##   "segments": Array[{a: Vector3, b: Vector3, r: float, level: int}]   — Astabschnitte (Radius = Basisradius)
##   "tips":     Array[{pos: Vector3, level: int}]                        — Blattanker
##   "height":   float                                                    — höchster Punkt (m)
## }
## level 0 = Stamm, 1 = Hauptäste, 2 = Seitenäste, 3 = Zweige.
##
## cfg (Laubbaum): trunk_height, trunk_radius, trunk_segments, trunk_bend, leaf_min_level,
## min_y (optional, Meter bei scale 1: Äste/Zweige enden nie tiefer — hängende Weide!) und
## "levels": Array von Ebenen-Specs (Index 0 = Hauptäste, 1 = Seitenäste, 2 = Zweige) mit
##   count, t_min, t_max (Position entlang des Elternasts, 0..1), ang_min, ang_max (Grad zur
##   Elternrichtung; bei Hauptästen zur Senkrechten), len_min, len_max (Anteil an Stammhöhe bzw.
##   Elternastlänge), rad_frac (Radius relativ zum Elternradius an der Abzweigung), segments,
##   droop (Durchhang je Abschnitt), bend (Zufalls-Knick), up_bias (Zug nach oben beim Abzweigen).

## Verjüngung je Abschnitt = top_radius/bottom_radius des Meshes "branch_seg" (MeshCache).
const TAPER: float = 0.75
const GOLDEN_ANGLE: float = 2.399963

static func deciduous(cfg: Dictionary, scale: float, max_level: int, density: float, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out: Dictionary = {"segments": [], "tips": [], "height": 0.0, "floor": float(cfg.get("min_y", -1000.0)) * scale}

	var height: float = float(cfg["trunk_height"]) * scale
	var radius: float = float(cfg["trunk_radius"]) * scale
	var segs: int = int(cfg.get("trunk_segments", 4))
	var bend: float = float(cfg.get("trunk_bend", 0.1)) * scale
	var pts: Array[Vector3] = _trunk(out, rng, height, radius, segs, bend)

	out["tips"].append({"pos": pts[pts.size() - 1], "level": 1})   # Wipfel
	if max_level >= 1:
		var spec: Dictionary = cfg["levels"][0]
		var n: int = maxi(1, roundi(float(spec["count"]) * density))
		for i in range(n):
			var tn: float = (float(i) + 0.5) / float(n)               # 0 = unterster, 1 = oberster Ast
			var t: float = lerpf(float(spec["t_min"]), float(spec["t_max"]), tn)
			var origin: Vector3 = _sample(pts, t)
			var az: float = float(i) * GOLDEN_ANGLE + rng.randf_range(-0.3, 0.3)
			# Obere Äste steiler, untere ausladender (typische Kronenform).
			var ang: float = deg_to_rad(lerpf(float(spec["ang_max"]), float(spec["ang_min"]), tn) + rng.randf_range(-6.0, 6.0))
			var dir: Vector3 = _deflect(Vector3.UP, ang, az)
			var length: float = height * rng.randf_range(float(spec["len_min"]), float(spec["len_max"]))
			length *= lerpf(1.0, 0.7, tn)                              # oben kürzer → Kegel/Ei statt Zylinder
			var r_here: float = radius * pow(TAPER, t * float(segs))
			_grow(out, rng, origin, dir, length, r_here * float(spec["rad_frac"]), 1, cfg, max_level, density)
	out["height"] = _max_height(out)
	return out

## Nadelbaum: gerader Leittrieb mit regelmäßigen Astkränzen (Wirteln), nach oben kürzer.
## cfg zusätzlich: whorls, per_whorl, whorl_t_min, whorl_t_max, len_base, len_top (m, vor scale).
static func conifer(cfg: Dictionary, scale: float, whorls: int, max_level: int, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out: Dictionary = {"segments": [], "tips": [], "height": 0.0, "floor": float(cfg.get("min_y", -1000.0)) * scale}

	var height: float = float(cfg["trunk_height"]) * scale
	var radius: float = float(cfg["trunk_radius"]) * scale
	var segs: int = int(cfg.get("trunk_segments", 4))
	var pts: Array[Vector3] = _trunk(out, rng, height, radius, segs, float(cfg.get("trunk_bend", 0.05)) * scale)
	out["tips"].append({"pos": pts[pts.size() - 1], "level": 1})

	var per: int = int(cfg["per_whorl"])
	var spec: Dictionary = cfg["levels"][0]
	for w in range(whorls):
		var tn: float = (float(w) + 0.5) / float(maxi(whorls, 1))
		var t: float = lerpf(float(cfg["whorl_t_min"]), float(cfg["whorl_t_max"]), tn)
		var origin: Vector3 = _sample(pts, t)
		var length: float = lerpf(float(cfg["len_base"]), float(cfg["len_top"]), tn) * scale
		var r_here: float = radius * pow(TAPER, t * float(segs))
		for b in range(per):
			var az: float = TAU * float(b) / float(per) + float(w) * 0.55 + rng.randf_range(-0.2, 0.2)
			# Untere Äste hängen leicht, obere zeigen waagrecht bis leicht aufwärts.
			var ang: float = deg_to_rad(lerpf(float(spec["ang_max"]), float(spec["ang_min"]), tn) + rng.randf_range(-5.0, 5.0))
			_grow(out, rng, origin, _deflect(Vector3.UP, ang, az), length * rng.randf_range(0.85, 1.1),
				r_here * float(spec["rad_frac"]), 1, cfg, max_level, 1.0)
	out["height"] = _max_height(out)
	return out

## Blattkarten um einen Anker: Fibonacci-Kugel, Kartennormale zeigt nach außen (so liest sich
## ein Büschel als Blattmasse), zufälliges Rollen um die Normale.
## flat < 1 plättet die Kugel (Nadelbüschel), drop senkt Karten nach unten (Weide: Vorhang),
## stretch streckt die Karte (x = Breite, y = Länge), size = Kartenkante in Metern.
static func cards_for_tip(
	pos: Vector3, count: int, radius: float, size: float, salt: int,
	flat: float = 1.0, drop: float = 0.0, stretch: Vector2 = Vector2.ONE
) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for i in range(count):
		var y: float = 1.0 - 2.0 * (float(i) + 0.5) / float(maxi(count, 1))
		var rr: float = sqrt(maxf(0.0, 1.0 - y * y))
		var th: float = float(i) * GOLDEN_ANGLE + float(salt) * 1.7
		var h1: float = _hash(float(i) * 12.9898 + float(salt) * 78.233)
		var h2: float = _hash(float(i) * 39.346 + float(salt) * 11.135)
		var dir := Vector3(cos(th) * rr, y * flat, sin(th) * rr)
		var p: Vector3 = pos + dir * radius * (0.45 + 0.55 * h1)
		p.y -= drop * (0.25 + 0.75 * h2)
		var n: Vector3 = (dir + Vector3(h2 - 0.5, h1 - 0.5, h1 - h2) * 0.6).normalized()
		var xn: Vector3 = n.cross(Vector3.UP)
		if xn.length() < 0.1:
			xn = n.cross(Vector3.RIGHT)
		xn = xn.normalized()
		var yn: Vector3 = n.cross(xn).normalized()
		var roll: float = (h2 - 0.5) * TAU
		var xr: Vector3 = xn * cos(roll) + yn * sin(roll)
		var yr: Vector3 = n.cross(xr).normalized()
		var s: float = size * (0.8 + 0.45 * h1)
		out.append(Transform3D(Basis(xr * s * stretch.x, yr * s * stretch.y, n), p))
	return out

## Fasst Blattanker zu groben Kugeln zusammen (Fern-LOD): Mittelpunkt je Gitterzelle,
## Radius = Zellenhälfte × spread. Liefert Array[{pos, r}].
static func crown_blobs(tips: Array, cell: float, spread: float) -> Array:
	var buckets: Dictionary = {}
	for tip in tips:
		var p: Vector3 = tip["pos"]
		var key := Vector3i(floori(p.x / cell), floori(p.y / cell), floori(p.z / cell))
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(p)
	var out: Array = []
	for key in buckets.keys():
		var list: Array = buckets[key]
		var c := Vector3.ZERO
		for p: Vector3 in list:
			c += p
		c /= float(list.size())
		out.append({"pos": c, "r": cell * 0.5 * spread * (0.8 + 0.1 * minf(float(list.size()), 4.0))})
	return out

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

static func _trunk(out: Dictionary, rng: RandomNumberGenerator, height: float, radius: float, segs: int, bend: float) -> Array[Vector3]:
	var pts: Array[Vector3] = [Vector3.ZERO]
	var p := Vector3.ZERO
	for i in range(segs):
		var np: Vector3 = p + Vector3(rng.randf_range(-bend, bend), height / float(segs), rng.randf_range(-bend, bend))
		out["segments"].append({"a": p, "b": np, "r": radius * pow(TAPER, i), "level": 0})
		pts.append(np)
		p = np
	return pts

static func _grow(
	out: Dictionary, rng: RandomNumberGenerator, start: Vector3, dir: Vector3, length: float,
	radius: float, level: int, cfg: Dictionary, max_level: int, density: float
) -> void:
	var levels: Array = cfg["levels"]
	var spec: Dictionary = levels[level - 1]
	var segs: int = int(spec.get("segments", 3))
	var droop: float = float(spec.get("droop", 0.0))
	var bend: float = float(spec.get("bend", 0.15))
	var seg_len: float = length / float(segs)
	var pts: Array[Vector3] = [start]
	var cur: Vector3 = dir.normalized()
	var p: Vector3 = start
	for s in range(segs):
		cur = (cur + Vector3(rng.randf_range(-bend, bend), rng.randf_range(-bend, bend) - droop, rng.randf_range(-bend, bend))).normalized()
		var np: Vector3 = p + cur * seg_len
		np.y = maxf(np.y, float(out["floor"]))   # nie unter min_y (siehe cfg)
		out["segments"].append({"a": p, "b": np, "r": radius * pow(TAPER, s), "level": level})
		pts.append(np)
		p = np
	if level >= int(cfg.get("leaf_min_level", 2)) or level == max_level:
		out["tips"].append({"pos": p, "level": level})
	if level >= max_level or level >= levels.size():
		return
	var cs: Dictionary = levels[level]
	var n: int = maxi(1, roundi(float(cs["count"]) * density))
	for c in range(n):
		var tn: float = (float(c) + 0.5) / float(n)
		var t: float = lerpf(float(cs["t_min"]), float(cs["t_max"]), tn)
		var origin: Vector3 = _sample(pts, t)
		var pdir: Vector3 = _direction_at(pts, t)
		var az: float = float(c) * GOLDEN_ANGLE + rng.randf_range(-0.4, 0.4)
		var ang: float = deg_to_rad(rng.randf_range(float(cs["ang_min"]), float(cs["ang_max"])))
		var cdir: Vector3 = _deflect(pdir, ang, az)
		cdir = (cdir + Vector3.UP * float(cs.get("up_bias", 0.0))).normalized()
		var clen: float = length * rng.randf_range(float(cs["len_min"]), float(cs["len_max"]))
		var crad: float = radius * pow(TAPER, t * float(segs)) * float(cs["rad_frac"])
		_grow(out, rng, origin, cdir, clen, crad, level + 1, cfg, max_level, density)

## Punkt bei Anteil t (0..1) entlang des Polygonzugs (nach Länge, nicht nach Index).
static func _sample(pts: Array[Vector3], t: float) -> Vector3:
	var total: float = 0.0
	for i in range(pts.size() - 1):
		total += pts[i].distance_to(pts[i + 1])
	var target: float = clampf(t, 0.0, 1.0) * total
	var acc: float = 0.0
	for i in range(pts.size() - 1):
		var d: float = pts[i].distance_to(pts[i + 1])
		if acc + d >= target or i == pts.size() - 2:
			var f: float = 0.0 if d <= 0.0001 else clampf((target - acc) / d, 0.0, 1.0)
			return pts[i].lerp(pts[i + 1], f)
		acc += d
	return pts[pts.size() - 1]

static func _direction_at(pts: Array[Vector3], t: float) -> Vector3:
	var total: float = 0.0
	for i in range(pts.size() - 1):
		total += pts[i].distance_to(pts[i + 1])
	var target: float = clampf(t, 0.0, 1.0) * total
	var acc: float = 0.0
	for i in range(pts.size() - 1):
		var d: float = pts[i].distance_to(pts[i + 1])
		if acc + d >= target or i == pts.size() - 2:
			return (pts[i + 1] - pts[i]).normalized()
		acc += d
	return Vector3.UP

## Dreht `dir` um `angle` von sich weg, Richtung der Abweichung per `azimuth` um die Achse.
static func _deflect(dir: Vector3, angle: float, azimuth: float) -> Vector3:
	var yn: Vector3 = dir.normalized()
	var refv: Vector3 = Vector3.FORWARD if absf(yn.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var xn: Vector3 = refv.cross(yn).normalized()
	var zn: Vector3 = xn.cross(yn).normalized()
	return (yn * cos(angle) + (xn * cos(azimuth) + zn * sin(azimuth)) * sin(angle)).normalized()

static func _max_height(out: Dictionary) -> float:
	var h: float = 0.0
	for seg: Dictionary in out["segments"]:
		h = maxf(h, (seg["b"] as Vector3).y)
	return h

static func _hash(x: float) -> float:
	var s: float = sin(x) * 43758.5453
	return s - floor(s)

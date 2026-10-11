class_name CanopyLayout
extends RefCounted

## CanopyLayout — plant EIN Baumdorf: Riesenbäume, Hängebrücken, Fußwege, Zufahrtsstraßen.
##
## Idee: Der ALTBAUM steht in der Dorfmitte (dort endet die Fernstraße an einem Platz), die Dorfbäume im
## Ring darum. Bäume, die nah genug (≤ LINK_MAX) und auf ähnlicher Höhe (≤ LINK_MAX_DH) stehen, werden
## per Hängebrücke zu einem Baum-Netz verbunden (minimaler Spannbaum ab dem Altbaum). Jede Brücke wird von
## beiden Bäumen je zur Hälfte gebaut (CanopyTree.bridge_points) — dadurch bleibt ein Baum ein Gebäude
## und gehört genau einem Chunk. Am Boden führen Fußwege vom Rampenanfang jedes Baums zur Straße/zum Altbaum.
##
## Rein deterministisch aus (Standort, ankommende Straßen, Basis-Gelände). Ergebnis wie VillageLayout.plan.
## Baum-Datensatz = Gebäude-Dictionary + `params` (role, level_count, huts, hall, phase, links).

const HUB_CLEAR: float = 15.0       ## Fernstraßen enden am Platz um den Altbaum
const PATH_W: float = 2.0
const MIN_TREE_DIST: float = 30.0
const LINK_MAX: float = 50.0
const LINK_MAX_DH: float = 5.0
const LINK_CLEAR: float = 15.0      ## Brücken führen nicht dichter als so an einem dritten Baum vorbei
const ATTEMPTS: int = 10
const ELDER_OFFSETS: Array[Vector2] = [
	Vector2.ZERO, Vector2(4, 0), Vector2(-4, 0), Vector2(0, 4), Vector2(0, -4),
	Vector2(3, 3), Vector2(-3, 3), Vector2(3, -3), Vector2(-3, -3),
]
const TREES_BY_TIER: Dictionary = {
	VillageKind.TIER_HAMLET: 1, VillageKind.TIER_VILLAGE: 3, VillageKind.TIER_TOWN: 5,
}
## Ringradius der Dorfbäume als Anteil des Dorfradius.
const RING_FRACTION: Dictionary = {VillageKind.TIER_VILLAGE: 0.64, VillageKind.TIER_TOWN: 0.58}

static func plan(field: TerrainField, site: Dictionary, incoming: Array) -> Dictionary:
	var result: Dictionary = {"buildings": [], "streets": [], "paths": []}
	if bool(site.get("fixed", false)):
		return result
	var center: Vector2 = site["center"]
	var radius: float = site["radius"]
	var tier: String = site["tier"]
	var site_id: String = site["id"]
	var site_seed: int = site["seed"]
	var rng := RandomNumberGenerator.new()
	rng.seed = SettlementMath.mix(site_seed, 0, 0, 0xCA70)

	# ── Straßen: Fernstraßen enden am Platz um den Altbaum ──
	var streets: Array = []
	for path: PackedVector2Array in incoming:
		_append_trimmed(streets, path, center, radius * 1.15)

	# ── Bäume ──
	var trees: Array = []
	for off: Vector2 in ELDER_OFFSETS:
		var elder: Dictionary = VillageLayout.make_building(
			field, CanopyVillageKind.T_ELDER, center + off, 0.0, rng.randi(), site_id, site_seed, 0)
		if not elder.is_empty():
			trees.append(elder)
			break
	if trees.is_empty():
		return result
	var count: int = int(TREES_BY_TIER.get(tier, 1))
	var ring_r: float = radius * float(RING_FRACTION.get(tier, 0.6))
	var base_angle: float = rng.randf() * TAU
	for k in range(1, count):
		for attempt in range(ATTEMPTS):
			var ang: float = base_angle + TAU * float(k - 1) / float(count - 1) + (rng.randf() - 0.5) * 0.7
			var r: float = ring_r + (rng.randf() - 0.5) * 8.0
			var pos: Vector2 = center + Vector2(cos(ang), sin(ang)) * r
			var variant: int = rng.randi()
			if pos.distance_to(center) > radius * 0.95 or _too_close(pos, trees):
				continue
			if not VillageLayout.fits(CanopyVillageKind.T_GROVE, pos, 0.0, trees, streets, true):
				continue
			var tree: Dictionary = VillageLayout.make_building(
				field, CanopyVillageKind.T_GROVE, pos, 0.0, variant, site_id, site_seed, trees.size())
			if tree.is_empty():
				continue
			trees.append(tree)
			break

	# ── Größe der Bäume je Stufe (hier wächst das Dorf: Ebenen, Hütten, Halle) ──
	for i in range(trees.size()):
		var t: Dictionary = trees[i]
		var is_elder: bool = i == 0
		var level_count: int = 2
		if is_elder and tier == VillageKind.TIER_VILLAGE:
			level_count = 3
		elif is_elder and tier == VillageKind.TIER_TOWN:
			level_count = 4
		elif not is_elder and tier == VillageKind.TIER_TOWN and rng.randf() < 0.4:
			level_count = 3
		var hall: bool = is_elder and tier != VillageKind.TIER_HAMLET
		var huts: Array = []
		for li in range(level_count):
			if hall and li == level_count - 1:
				huts.append(0)
			elif is_elder:
				huts.append(2 if tier == VillageKind.TIER_HAMLET else 3)
			else:
				huts.append(2)
		t["params"] = {
			"role": "elder" if is_elder else "grove", "level_count": level_count, "huts": huts,
			"hall": hall, "phase": 0.0, "links": [],
		}

	# ── Hängebrücken: minimaler Spannbaum ab dem Altbaum ──
	var visited: Dictionary = {0: true}
	while visited.size() < trees.size():
		var best: Vector2i = Vector2i(-1, -1)
		var best_d: float = INF
		for i: int in visited:
			for j in range(trees.size()):
				if visited.has(j) or not _link_ok(trees, i, j):
					continue
				var d: float = _pos(trees[i]).distance_to(_pos(trees[j]))
				if d < best_d:
					best_d = d
					best = Vector2i(i, j)
		if best.x < 0:
			break
		visited[best.y] = true
		_add_link(trees[best.x], trees[best.y])
		_add_link(trees[best.y], trees[best.x])

	# ── Rampenstart je Baum (wählt Winkel, die Brücken/Zufahrten nicht stören) ──
	for t2: Dictionary in trees:
		var params: Dictionary = t2["params"]
		var link_angles: Array = []
		for l: Dictionary in params["links"]:
			link_angles.append(atan2(float(l["mz"]), float(l["mx"])))
		var level_ys: Array = CanopyTree.level_heights(int(params["level_count"]))
		params["phase"] = CanopyTree.pick_phase(level_ys, link_angles, -float(t2["spread"]), int(t2["variant"]))

	# ── Fußwege vom Rampenanfang zur Straße bzw. zum Altbaum ──
	var paths: Array = []
	var elder_start: Vector2 = _ramp_start(trees[0])
	for i in range(trees.size()):
		var start: Vector2 = _ramp_start(trees[i])
		var target: Vector2 = start
		var best_d2: float = INF
		if not streets.is_empty():
			target = VillageLayout.closest_street_point(start, streets)
			best_d2 = start.distance_to(target)
		if i > 0 and start.distance_to(elder_start) < best_d2:
			target = elder_start
			best_d2 = start.distance_to(elder_start)
		if best_d2 > 1.0 and best_d2 < 70.0:
			paths.append({"a": start, "b": target, "w": PATH_W})

	result["buildings"] = trees
	result["streets"] = streets
	result["paths"] = paths
	return result

# ─────────────────────────────────────────────
# Hilfen
# ─────────────────────────────────────────────

static func _pos(t: Dictionary) -> Vector2:
	return Vector2(float(t["x"]), float(t["z"]))

static func _ramp_start(t: Dictionary) -> Vector2:
	return _pos(t) + CanopyTree.ramp_start_offset(float((t["params"] as Dictionary)["phase"]))

static func _too_close(pos: Vector2, trees: Array) -> bool:
	for t: Dictionary in trees:
		if pos.distance_to(_pos(t)) < MIN_TREE_DIST:
			return true
	return false

## Darf zwischen Baum i und j eine Brücke hängen? (Reichweite, Höhenunterschied, kein dritter Baum im Weg)
static func _link_ok(trees: Array, i: int, j: int) -> bool:
	var a: Vector2 = _pos(trees[i])
	var b: Vector2 = _pos(trees[j])
	if a.distance_to(b) > LINK_MAX:
		return false
	if absf(float((trees[j] as Dictionary)["y"]) - float((trees[i] as Dictionary)["y"])) > LINK_MAX_DH:
		return false
	for k in range(trees.size()):
		if k == i or k == j:
			continue
		if SettlementMath.dist_to_segment(_pos(trees[k]), a, b) < LINK_CLEAR:
			return false
	return true

## Trägt in `from` die Brücke zu `to` ein (Mitte, Höhenunterschied, Partner-ID).
static func _add_link(from: Dictionary, to: Dictionary) -> void:
	var a: Vector2 = _pos(from)
	var b: Vector2 = _pos(to)
	var mid: Vector2 = (b - a) * 0.5
	((from["params"] as Dictionary)["links"] as Array).append({
		"mx": mid.x, "mz": mid.y, "dh": float(to["y"]) - float(from["y"]), "peer": to["id"],
	})

## Hängt die Fernstraße von HUB_CLEAR (Platzrand) bis max_dist (vom Zentrum) als Straßenstücke an `out`.
static func _append_trimmed(out: Array, path: PackedVector2Array, center: Vector2, max_dist: float) -> void:
	var pts: Array[Vector2] = []
	var started: bool = false
	for i in range(path.size()):
		var p: Vector2 = path[i]
		var d: float = p.distance_to(center)
		if not started:
			if d < HUB_CLEAR:
				continue
			if i > 0:
				var prev: Vector2 = path[i - 1]
				var dp: float = prev.distance_to(center)
				var t: float = clampf((HUB_CLEAR - dp) / maxf(d - dp, 0.0001), 0.0, 1.0)
				pts.append(prev.lerp(p, t))
			started = true
		pts.append(p)
		if d > max_dist:
			break
	for i in range(pts.size() - 1):
		out.append({"a": pts[i], "b": pts[i + 1], "w": VillageLayout.STREET_W})

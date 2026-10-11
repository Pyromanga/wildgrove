class_name SettlementRegistry
extends RefCounted

## SettlementRegistry — die EINE Anlaufstelle für alles, was Dörfer und Straßen betrifft.
##
## Hängt lazy an TerrainField (get_settlements()). Wer etwas wissen will (Terrain-Färbung,
## Chunk-Gebäude, Vegetation, Karte), fragt hier; die Registry plant bei Bedarf nach und
## cached. Alles ist deterministisch aus (world_seed, Basis-Gelände) → jeder Peer kommt zum
## selben Ergebnis, ohne dass etwas übertragen wird.
##
## Ebenen (jeweils nur bei Bedarf berechnet):
##   Standort (SettlementSites)  →  Straßenkanten (RoadPaths)  →  Dorf-Layout (je Dorf-Art: VillageKind.plan)
## Cache-Ebenen:  _sites (Zelle→Standort), _edges (Straßen), _layouts (Gebäude/Gassen/Wege).
##
## Alle Queries laufen auf dem Hauptthread (es gibt keinen Worker für Chunk-Bau) — daher
## keine Locks.

const SEG_CELL: float = 32.0
const BUILD_CELL: float = 64.0
const WAYSIDE_SPACING: float = 130.0
const WAYSIDE_CHANCE: float = 0.5

const COL_ROAD := Color(0.48, 0.38, 0.25)
const COL_STREET := Color(0.54, 0.47, 0.36)
const COL_PATH := Color(0.50, 0.42, 0.30)

var _field: TerrainField
var _seed: int
var _sites: Dictionary = {}          # Vector2i → Dictionary ({} = kein Dorf)
var _edge_cells: Dictionary = {}     # Zellen, für die Standorte+Kanten berechnet sind
var _layout_cells: Dictionary = {}   # Zellen, für die zusätzlich das Layout steht
var _edges: Dictionary = {}          # Kantenschlüssel → {key, a_id, b_id, points}
var _site_edges: Dictionary = {}     # Standort-ID → Array[Dictionary]
var _site_by_id: Dictionary = {}     # Standort-ID → Standort
var _layouts: Dictionary = {}        # Standort-ID → Layout
var _segs: Dictionary = {}           # Vector2i(SEG_CELL) → Array[{a,b,w,col}]
var _builds: Dictionary = {}         # Vector2i(BUILD_CELL) → Array[Dictionary]

func _init(field: TerrainField) -> void:
	_field = field
	_seed = field.get_seed()

# ─────────────────────────────────────────────
# Standorte
# ─────────────────────────────────────────────

func get_site(cell: Vector2i) -> Dictionary:
	if _sites.has(cell):
		return _sites[cell]
	var site: Dictionary = SettlementSites.find_site(_field, _seed, cell)
	_sites[cell] = site
	if not site.is_empty():
		_site_by_id[site["id"]] = site
	return site

## Bereits berechnete Standorte, deren Zentrum in `rect` liegt (kein Nachplanen — für die Karte).
func known_sites_in_rect(rect: Rect2) -> Array:
	var out: Array = []
	for cell: Vector2i in _sites:
		var site: Dictionary = _sites[cell]
		if not site.is_empty() and rect.has_point(site["center"] as Vector2):
			out.append(site)
	return out

## Dorf, in dessen Radius (+pad) der Punkt liegt, sonst {}.
func village_at(x: float, z: float, pad: float = 0.0) -> Dictionary:
	var site: Dictionary = get_site(SettlementSites.cell_of(x, z))
	if site.is_empty():
		return {}
	if Vector2(x, z).distance_to(site["center"] as Vector2) <= float(site["radius"]) + pad:
		return site
	return {}

# ─────────────────────────────────────────────
# Vorbereiten (Straßennetz + Layout)
# ─────────────────────────────────────────────

## Standorte der 5×5-Umgebung und alle Kanten, die durch Zelle `c` laufen können.
func ensure_edges(c: Vector2i) -> void:
	if _edge_cells.has(c):
		return
	_edge_cells[c] = true
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var site: Dictionary = get_site(c + Vector2i(dx, dz))
			if site.is_empty():
				continue
			for partner: Dictionary in RoadPaths.pick_partners(site, _neighbor_sites(site)):
				_ensure_edge(site, partner)

## Wie ensure_edges, plus das Dorf-Layout (Gebäude, Gassen, Wege) des Dorfs dieser Zelle.
func ensure_cell(c: Vector2i) -> void:
	if _layout_cells.has(c):
		return
	ensure_edges(c)
	_layout_cells[c] = true
	var site: Dictionary = get_site(c)
	if not site.is_empty():
		_ensure_layout(site)

## Für die Karte: bereitet höchstens `max_new` noch unfertige Zellen im Rechteck vor (Straßen,
## keine Layouts). Gibt die Anzahl neu vorbereiteter Zellen zurück.
func prepare_edges_in_rect(rect: Rect2, max_new: int) -> int:
	var done: int = 0
	var c0: Vector2i = SettlementSites.cell_of(rect.position.x, rect.position.y)
	var c1: Vector2i = SettlementSites.cell_of(rect.end.x, rect.end.y)
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var c := Vector2i(cx, cz)
			if _edge_cells.has(c):
				continue
			ensure_edges(c)
			done += 1
			if done >= max_new:
				return done
	return done

func _neighbor_sites(site: Dictionary) -> Array:
	var cell: Vector2i = site["cell"]
	var out: Array = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			var other: Dictionary = get_site(cell + Vector2i(dx, dz))
			if not other.is_empty():
				out.append(other)
	return out

func _ensure_edge(a: Dictionary, b: Dictionary) -> void:
	var a_id: String = a["id"]
	var b_id: String = b["id"]
	var key: String = RoadPaths.edge_key(a_id, b_id)
	if _edges.has(key):
		return
	var low: Dictionary = a if a_id < b_id else b
	var high: Dictionary = b if a_id < b_id else a
	var low_cell: Vector2i = low["cell"]
	var high_cell: Vector2i = high["cell"]
	var key_hash: int = SettlementMath.mix(low_cell.x, low_cell.y, high_cell.x, high_cell.y ^ _seed)
	var points: PackedVector2Array = RoadPaths.build_path(_field, low["center"] as Vector2, high["center"] as Vector2, key_hash)
	var edge: Dictionary = {"key": key, "a_id": low["id"], "b_id": high["id"], "points": points}
	_edges[key] = edge
	for id: String in [a_id, b_id]:
		if not _site_edges.has(id):
			_site_edges[id] = []
		(_site_edges[id] as Array).append(edge)
	for i in range(points.size() - 1):
		_add_segment(points[i], points[i + 1], RoadPaths.WIDTH, COL_ROAD)
	_add_waysides(edge, low, high, key_hash)

## Fernstraße VOM Zentrum des Dorfs nach außen orientiert.
func _oriented_from(site: Dictionary, edge: Dictionary) -> PackedVector2Array:
	var pts: PackedVector2Array = edge["points"]
	if String(edge["a_id"]) == String(site["id"]):
		return pts
	var rev := PackedVector2Array()
	for i in range(pts.size() - 1, -1, -1):
		rev.append(pts[i])
	return rev

func _ensure_layout(site: Dictionary) -> void:
	var id: String = site["id"]
	if _layouts.has(id):
		return
	# Reihenfolge der Kanten muss unabhängig von der Entdeckungs-Reihenfolge sein.
	var edges: Array = (_site_edges.get(id, []) as Array).duplicate()
	edges.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return String(p["key"]) < String(q["key"]))
	var incoming: Array = []
	for e: Dictionary in edges:
		incoming.append(_oriented_from(site, e))
	var layout: Dictionary = VillageKinds.kind_of_site(site).plan(_field, site, incoming)
	_layouts[id] = layout
	for s: Dictionary in layout["streets"]:
		_add_segment(s["a"] as Vector2, s["b"] as Vector2, float(s["w"]), COL_STREET)
	for p: Dictionary in layout["paths"]:
		_add_segment(p["a"] as Vector2, p["b"] as Vector2, float(p["w"]), COL_PATH)
	for b: Dictionary in layout["buildings"]:
		_add_building(b)

## Alle bisher bekannten Fernstraßen-Kanten, die an diesem Dorf enden (nach ensure_edges/ensure_cell).
func get_edges_of(site_id: String) -> Array:
	return (_site_edges.get(site_id, []) as Array).duplicate()

func get_layout(site_id: String) -> Dictionary:
	return _layouts.get(site_id, {})

# ─────────────────────────────────────────────
# Wegekreuze / Rasthäuser an Fernstraßen
# ─────────────────────────────────────────────

func _add_waysides(edge: Dictionary, low: Dictionary, high: Dictionary, key_hash: int) -> void:
	var pts: PackedVector2Array = edge["points"]
	var total: float = 0.0
	for i in range(pts.size() - 1):
		total += pts[i].distance_to(pts[i + 1])
	var rng: RandomNumberGenerator = SettlementMath.rng_for(_seed, key_hash, 9, 0xCA11)
	var s: float = 110.0 + rng.randf() * 40.0
	var index: int = 0
	while s < total - 110.0:
		var roll: float = rng.randf()
		var type_roll: float = rng.randf()
		var side: float = 1.0 if rng.randf() < 0.5 else -1.0
		var variant: int = rng.randi()
		if roll < WAYSIDE_CHANCE:
			var type_id: String = BuildingRecipes.T_WAYCROSS if type_roll < 0.65 else BuildingRecipes.T_WAYHOUSE
			var at: Dictionary = _point_at(pts, s)
			var p: Vector2 = at["p"]
			var near_village: bool = (
				p.distance_to(low["center"] as Vector2) < float(low["radius"]) + 30.0
				or p.distance_to(high["center"] as Vector2) < float(high["radius"]) + 30.0)
			if not near_village:
				var dir: Vector2 = at["dir"]
				var nrm: Vector2 = Vector2(-dir.y, dir.x) * side
				var half: Vector2 = BuildingRecipes.half_extents(type_id)
				var lot: Vector2 = p + nrm * (RoadPaths.WIDTH * 0.5 + 2.5 + half.y)
				var yaw: float = BuildingRecipes.facing_yaw(Vector2.ZERO, -nrm)
				var b: Dictionary = VillageLayout.make_building(_field, type_id, lot, yaw, variant, "", key_hash, index)
				if not b.is_empty():
					b["wayside"] = true
					_add_building(b)
		index += 1
		s += WAYSIDE_SPACING + rng.randf() * 50.0

## Punkt + Richtung bei Bogenlänge s entlang der Polylinie.
func _point_at(pts: PackedVector2Array, s: float) -> Dictionary:
	var acc: float = 0.0
	for i in range(pts.size() - 1):
		var seg: float = pts[i].distance_to(pts[i + 1])
		if acc + seg >= s and seg > 0.001:
			var t: float = (s - acc) / seg
			return {"p": pts[i].lerp(pts[i + 1], t), "dir": (pts[i + 1] - pts[i]).normalized()}
		acc += seg
	var n: int = pts.size()
	return {"p": pts[n - 1], "dir": (pts[n - 1] - pts[n - 2]).normalized()}

# ─────────────────────────────────────────────
# Räumliche Hashes
# ─────────────────────────────────────────────

func _add_segment(a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var seg: Dictionary = {"a": a, "b": b, "w": w, "col": col}
	var pad: float = w * 0.5 + 1.5
	var x0: int = floori((minf(a.x, b.x) - pad) / SEG_CELL)
	var x1: int = floori((maxf(a.x, b.x) + pad) / SEG_CELL)
	var z0: int = floori((minf(a.y, b.y) - pad) / SEG_CELL)
	var z1: int = floori((maxf(a.y, b.y) + pad) / SEG_CELL)
	for cz in range(z0, z1 + 1):
		for cx in range(x0, x1 + 1):
			var key := Vector2i(cx, cz)
			if not _segs.has(key):
				_segs[key] = []
			(_segs[key] as Array).append(seg)

func _add_building(b: Dictionary) -> void:
	var key := Vector2i(floori(float(b["x"]) / BUILD_CELL), floori(float(b["z"]) / BUILD_CELL))
	if not _builds.has(key):
		_builds[key] = []
	(_builds[key] as Array).append(b)

# ─────────────────────────────────────────────
# Abfragen für Gelände / Chunks / Vegetation
# ─────────────────────────────────────────────

## Straßen-Färbung: mischt `base` Richtung Weg-/Straßenfarbe, wo eine Straße liegt.
func road_tint(x: float, z: float, base: Color) -> Color:
	ensure_cell(SettlementSites.cell_of(x, z))
	var segs: Variant = _segs.get(Vector2i(floori(x / SEG_CELL), floori(z / SEG_CELL)))
	if segs == null:
		return base
	var p := Vector2(x, z)
	var best_w: float = 0.0
	var best_col: Color = base
	for s: Dictionary in (segs as Array):
		var half: float = float(s["w"]) * 0.5
		var d: float = SettlementMath.dist_to_segment(p, s["a"] as Vector2, s["b"] as Vector2)
		if d >= half + 0.9:
			continue
		var w: float = 1.0 - smoothstep(half - 0.3, half + 0.9, d)
		if w > best_w:
			best_w = w
			best_col = s["col"]
	if best_w <= 0.0:
		return base
	return base.lerp(best_col, best_w * 0.92)

## Liegt (x, z) auf einer Straße/einem Weg (innerhalb halber Breite + pad)?
func on_road(x: float, z: float, pad: float = 0.0) -> bool:
	ensure_cell(SettlementSites.cell_of(x, z))
	var segs: Variant = _segs.get(Vector2i(floori(x / SEG_CELL), floori(z / SEG_CELL)))
	if segs == null:
		return false
	var p := Vector2(x, z)
	for s: Dictionary in (segs as Array):
		if SettlementMath.dist_to_segment(p, s["a"] as Vector2, s["b"] as Vector2) <= float(s["w"]) * 0.5 + pad:
			return true
	return false

## Gebäude (Dorf + Wegesrand), deren Mittelpunkt in `rect` (erweitert um `margin`) liegt.
func buildings_in_rect(rect: Rect2, margin: float = 0.0) -> Array:
	var r: Rect2 = rect.grow(margin)
	var c0: Vector2i = SettlementSites.cell_of(r.position.x, r.position.y)
	var c1: Vector2i = SettlementSites.cell_of(r.end.x, r.end.y)
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			ensure_cell(Vector2i(cx, cz))
	var out: Array = []
	var b0 := Vector2i(floori(r.position.x / BUILD_CELL), floori(r.position.y / BUILD_CELL))
	var b1 := Vector2i(floori(r.end.x / BUILD_CELL), floori(r.end.y / BUILD_CELL))
	for bz in range(b0.y, b1.y + 1):
		for bx in range(b0.x, b1.x + 1):
			var list: Variant = _builds.get(Vector2i(bx, bz))
			if list == null:
				continue
			for b: Dictionary in (list as Array):
				if r.has_point(Vector2(float(b["x"]), float(b["z"]))):
					out.append(b)
	return out

## Blockiert Vegetation/Streu-Props an dieser Stelle? (Straße oder Grundstück)
func blocks_vegetation(x: float, z: float, pad: float = 0.5) -> bool:
	if on_road(x, z, pad):
		return true
	var bx: int = floori(x / BUILD_CELL)
	var bz: int = floori(z / BUILD_CELL)
	var p := Vector2(x, z)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var list: Variant = _builds.get(Vector2i(bx + dx, bz + dz))
			if list == null:
				continue
			for b: Dictionary in (list as Array):
				var half: Vector2 = BuildingRecipes.half_extents(String(b["type"]))
				if SettlementMath.point_in_obb(p, Vector2(float(b["x"]), float(b["z"])), half, float(b["yaw"]), pad):
					return true
	return false

# ─────────────────────────────────────────────
# Abfragen für die Karte
# ─────────────────────────────────────────────

## Bereits berechnete Fernstraßen (Polylinien), die `rect` berühren.
func known_roads_in_rect(rect: Rect2) -> Array:
	var out: Array = []
	for key: String in _edges:
		var pts: PackedVector2Array = (_edges[key] as Dictionary)["points"]
		var minp: Vector2 = pts[0]
		var maxp: Vector2 = pts[0]
		for p: Vector2 in pts:
			minp = Vector2(minf(minp.x, p.x), minf(minp.y, p.y))
			maxp = Vector2(maxf(maxp.x, p.x), maxf(maxp.y, p.y))
		if rect.intersects(Rect2(minp, maxp - minp).grow(2.0)):
			out.append(pts)
	return out

class_name LadderRegistry
extends RefCounted

## LadderRegistry — die WAHRHEIT darüber, wo Leitern stehen (Daten, keine Nodes).
##
## Gleiches Muster wie BuildRegistry: die 3D-Entities (Ladder) sind nur eine Ansicht, die
## WorldDigHandler beim Laden eines Chunks erzeugt. Gespeichert werden nur die Records.
## Zusätzlich hält die Registry je Leiter einen LadderPath (Geometrie) im Cache — den fragt
## der Spieler beim Klettern jeden Physik-Tick ab (find_attach()), deshalb bewusst ohne
## Dictionary-Zugriffe im heißen Pfad.
##
## Record: {key, x, y, z (Fuß), pts (PackedFloat32Array x,y,z,… von unten nach oben),
##          dx, dz (Richtung zur Wand), ex, ey, ez (Ausstieg oben), bx, by, bz (Ausstieg unten),
##          len (Länge m), cost (Leitern-Items), owner}
##
## Reine Datenklasse: kein Node, kein Service.

## Größte Entfernung Spieler ↔ Standpunkt, aus der er sich an eine Leiter hängen kann.
const ATTACH_DISTANCE: float = 1.8
## Eingabe-Schwelle (Skalarprodukt Laufrichtung · Richtung zur Wand) für "hinauf"/"hinab".
const INPUT_THRESHOLD: float = 0.3
## Wie weit unter dem Kopf man noch "von oben" einsteigen darf (Abstieg vom Rand).
const TOP_ENTRY_ZONE: float = 1.5
## Maximaler Abstand zweier Leitern, damit sie als verbunden gelten (Fuß der oberen ↔ Kopf der unteren).
const LINK_DISTANCE: float = 1.6

var _records: Dictionary = {}   # { key: Dictionary }
var _paths: Dictionary = {}     # { key: LadderPath }

func count() -> int:
	return _records.size()

func is_empty() -> bool:
	return _records.is_empty()

func has_key(key: String) -> bool:
	return _records.has(key)

func get_record(key: String) -> Dictionary:
	return (_records.get(key, {}) as Dictionary).duplicate()

func get_path_of(key: String) -> LadderPath:
	return _paths.get(key, null) as LadderPath

func get_all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k in _records.keys():
		out.append((_records[k] as Dictionary).duplicate())
	return out

## Fügt einen Record hinzu. false bei fehlendem Schlüssel, Doppelbelegung oder ungültiger Geometrie.
func add(record: Dictionary) -> bool:
	var key: String = String(record.get("key", ""))
	if key.is_empty() or _records.has(key):
		return false
	var path: LadderPath = LadderPath.from_record(record)
	if path == null:
		return false
	_records[key] = record.duplicate()
	_paths[key] = path
	return true

## Entfernt einen Record und gibt ihn zurück ({} wenn nicht vorhanden).
func remove(key: String) -> Dictionary:
	if not _records.has(key):
		return {}
	var rec: Dictionary = _records[key]
	_records.erase(key)
	_paths.erase(key)
	return rec

func clear() -> void:
	_records.clear()
	_paths.clear()

## Records, deren Fuß im Chunk mit Zentrum chunk_coord*chunk_size liegt.
func records_in_chunk(chunk_coord: Vector2i, chunk_size: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rec: Dictionary in _records.values():
		if BuildRegistry.chunk_of(float(rec.get("x", 0.0)), float(rec.get("z", 0.0)), chunk_size) == chunk_coord:
			out.append(rec.duplicate())
	return out

## Steht ein Leiterfuß in der Nähe von `pos` (waagerecht ≤ radius, senkrecht ≤ max_dy)?
## Der LadderPlanner nutzt das, um eine neue Leiter an eine vorhandene "anzuschließen"
## (zu tiefes Graben unter einer bestehenden Leiter → untere Leiter endet an deren Fuß).
func has_foot_near(pos: Vector3, radius: float, max_dy: float) -> bool:
	for path: LadderPath in _paths.values():
		var foot: Vector3 = path.points[0]
		if Vector2(foot.x - pos.x, foot.z - pos.z).length() <= radius and absf(foot.y - pos.y) <= max_dy:
			return true
	return false

# ─────────────────────────────────────────────
# Klettern
# ─────────────────────────────────────────────

## Sucht eine Leiter, an die sich ein Spieler an `pos` mit Laufrichtung `move_dir` hängen würde.
## Rückgabe: {} oder {key: String, s: float}.
##
## Einsteigen "nach oben": nahe genug am Standpunkt und Richtung Wand laufen (nicht ganz oben).
## Einsteigen "nach unten": am oberen Ende (Rand) von der Wand weg laufen — so geht man
## vom Rand aus in die Grube hinab.
func find_attach(pos: Vector3, move_dir: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_dist: float = INF
	for path: LadderPath in _paths.values():
		if not path.bounds.grow(ATTACH_DISTANCE).has_point(pos):
			continue
		var near: Dictionary = path.nearest(pos)
		var dist: float = float(near["dist"])
		if dist > ATTACH_DISTANCE or dist >= best_dist:
			continue
		var s: float = float(near["s"])
		var toward_wall: float = move_dir.dot(path.wall_dir)
		var up_ok: bool = toward_wall >= INPUT_THRESHOLD and s < path.length - 0.5
		var down_ok: bool = toward_wall <= -INPUT_THRESHOLD and s >= path.length - TOP_ENTRY_ZONE
		if not (up_ok or down_ok):
			continue
		best_dist = dist
		best = {"key": path.key, "s": s}
	return best

## Anschluss-Leiter am Ende von `from_key`: am Kopf (at_top) eine Leiter, deren Fuß dort
## liegt; am Fuß eine, deren Kopf dort liegt. Rückgabe: {} oder {key, s} (s = passendes Ende).
func find_link(from_key: String, at_top: bool) -> Dictionary:
	var from_path: LadderPath = get_path_of(from_key)
	if from_path == null:
		return {}
	var probe: Vector3 = from_path.point_at(from_path.length if at_top else 0.0)
	for path: LadderPath in _paths.values():
		if path.key == from_key:
			continue
		if at_top and probe.distance_to(path.points[0]) <= LINK_DISTANCE:
			return {"key": path.key, "s": 0.0}
		if not at_top and probe.distance_to(path.point_at(path.length)) <= LINK_DISTANCE:
			return {"key": path.key, "s": path.length}
	return {}

# ─────────────────────────────────────────────
# Persistenz
# ─────────────────────────────────────────────

func to_save() -> Array:
	var out: Array = []
	for rec: Dictionary in _records.values():
		out.append(rec.duplicate())
	return out

## Lädt aus to_save()-Format. Ungültige Einträge werden übersprungen.
func load_save(raw: Variant) -> void:
	clear()
	if not raw is Array:
		return
	for entry in (raw as Array):
		if entry is Dictionary:
			add(entry as Dictionary)

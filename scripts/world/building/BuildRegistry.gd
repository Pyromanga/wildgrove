class_name BuildRegistry
extends RefCounted

## BuildRegistry — die WAHRHEIT darüber, was gebaut wurde (Daten, keine Nodes).
##
## Die 3D-Entities (BuildPiece) sind nur eine Ansicht auf diese Daten: sie werden beim
## Laden eines Chunks aus den Records erzeugt und beim Entladen wieder entfernt
## (siehe WorldBuildHandler). Dadurch ist Speichern/Laden trivial (nur die Records) und
## später replizierbar (nur Records verschicken), ohne Nodes zu synchronisieren.
##
## Record: {key, piece_id, kind, x, y, z, yaw, owner, storey}
##   storey: Ebene (0 = Gelände; fehlt in alten Spielständen → 0)
##   x/y/z: Weltposition des Mittelpunkts der Basis-Oberkante, yaw: Drehung um Y,
##   owner: player_id des Erbauers (für spätere Berechtigungen/Claims reserviert).
##
## Reine Datenklasse: kein Node, kein Service.

## Auskragung oberer Böden (Wunsch "Balkone/Erker lockern"): ein Boden auf Ebene n>0 ohne eigene Wand darunter darf
## stehen, wenn über eine lückenlose Kette von Böden derselben Ebene höchstens so viele Zellen entfernt ein Boden liegt,
## der von einer Wand der Ebene n-1 getragen wird. Gilt auch für Treppen/Requisiten (_check_floor_upper).
const FLOOR_CANTILEVER_REACH: int = 3

var _records: Dictionary = {}   # { key: Dictionary }

func count() -> int:
	return _records.size()

func has_key(key: String) -> bool:
	return _records.has(key)

func get_record(key: String) -> Dictionary:
	return (_records.get(key, {}) as Dictionary).duplicate()

func get_all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k in _records.keys():
		out.append((_records[k] as Dictionary).duplicate())
	return out

## Fügt einen Record hinzu. false bei fehlendem Schlüssel oder Doppelbelegung.
func add(record: Dictionary) -> bool:
	var key: String = record.get("key", "")
	if key.is_empty() or _records.has(key):
		return false
	_records[key] = record.duplicate()
	return true

## Entfernt einen Record und gibt ihn zurück ({} wenn nicht vorhanden).
func remove(key: String) -> Dictionary:
	if not _records.has(key):
		return {}
	var rec: Dictionary = _records[key]
	_records.erase(key)
	return rec

## Boden-Record in Zelle `cell` auf Ebene `storey` ({} wenn keiner).
func floor_at(cell: Vector2i, storey: int = 0) -> Dictionary:
	return get_record(BuildGrid.floor_key(cell, storey))

## Wand-Record an der Kante (axis, cx, cz) auf Ebene `storey` ({} wenn keiner).
func wall_at(axis: int, cx: int, cz: int, storey: int = 0) -> Dictionary:
	return get_record(BuildGrid.wall_key(axis, cx, cz, storey))

## Alle Boden-Records (Ebene `storey`), die an die Wandkante grenzen.
func floors_adjacent_to_wall(axis: int, cx: int, cz: int, storey: int = 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for cell in BuildGrid.cells_adjacent_to_wall(axis, cx, cz):
		var rec: Dictionary = floor_at(cell, storey)
		if not rec.is_empty():
			out.append(rec)
	return out

## Alle Wand-Records (Ebene `storey`) auf den vier Kanten einer Zelle.
func walls_around_cell(cell: Vector2i, storey: int = 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var edges: Array = [[0, cell.x, cell.y], [0, cell.x, cell.y + 1], [1, cell.x, cell.y], [1, cell.x + 1, cell.y]]
	for e in edges:
		var rec: Dictionary = wall_at(int(e[0]), int(e[1]), int(e[2]), storey)
		if not rec.is_empty():
			out.append(rec)
	return out

## Steht auf diesem Bauteil noch etwas? Grundlage für "Abreißen gesperrt".
##   Wand (Ebene n): Wand auf derselben Kante oder Boden in einer Nachbarzelle auf Ebene n+1.
##   Boden (Ebene n>0): Wände der Ebene n auf seinen vier Kanten.
##   Boden auf Ebene 0 trägt nichts (Wände darauf stehen notfalls auch auf dem Gelände).
##   Dach trägt nie etwas (schließt ein Bauwerk nur nach oben ab) — immer abreißbar,
##   unabhängig von der Ebene.
func has_dependents(key: String) -> bool:
	if not has_key(key):
		return false
	var parts: Dictionary = BuildGrid.parse_key(key)
	if parts.is_empty():
		return false
	var storey: int = int(parts["storey"])
	var kind: int = int(parts["kind"])
	if kind == BuildPieceDefinition.Kind.WALL:
		var axis: int = int(parts["axis"])
		var cx: int = int(parts["x"])
		var cz: int = int(parts["z"])
		if has_key(BuildGrid.wall_key(axis, cx, cz, storey + 1)):
			return true
		return not floors_adjacent_to_wall(axis, cx, cz, storey + 1).is_empty()
	if kind == BuildPieceDefinition.Kind.FLOOR and storey > 0:
		var fcell := Vector2i(int(parts["x"]), int(parts["z"]))
		if not walls_around_cell(fcell, storey).is_empty():
			return true
		return _floor_carries_cantilever(fcell, storey, key)
	return false

## Obere Boden-Oberkante (y) für eine Zelle auf Ebene `storey` > 0, oder -INF ohne Halt: eigene Wand der Ebene
## storey-1 auf einer Kante ODER lückenlose Bodenkette bis FLOOR_CANTILEVER_REACH Zellen zu einem wandgetragenen
## Boden (Breitensuche über die vier Nachbarzellen; nächster Träger gewinnt, bei gleich nahen der höchste).
## `ignore_key`: dieser Boden zählt als nicht vorhanden (Abriss-Simulation in has_dependents()).
func floor_support_top(cell: Vector2i, storey: int, ignore_key: String = "") -> float:
	var own: Array[Dictionary] = walls_around_cell(cell, storey - 1)
	if not own.is_empty():
		var top: float = -INF
		for rec in own:
			top = maxf(top, float(rec.get("y", 0.0)) + BuildGrid.LEVEL_HEIGHT)
		return top
	var seen: Dictionary = {cell: true}
	var frontier: Array[Vector2i] = [cell]
	for _step in FLOOR_CANTILEVER_REACH:
		var next: Array[Vector2i] = []
		var best: float = -INF
		for c: Vector2i in frontier:
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n_cell: Vector2i = c + offset
				if seen.has(n_cell):
					continue
				seen[n_cell] = true
				var n_key: String = BuildGrid.floor_key(n_cell, storey)
				if n_key == ignore_key or not has_key(n_key):
					continue
				if walls_around_cell(n_cell, storey - 1).is_empty():
					next.append(n_cell)   # hängt selbst an einer Kette → weiter
				else:
					best = maxf(best, float((_records[n_key] as Dictionary).get("y", 0.0)))
		if not is_inf(best):
			return best
		frontier = next
	return -INF

## Würde das Entfernen des Bodens `key` einen anderen Boden derselben Ebene ohne Halt zurücklassen?
func _floor_carries_cantilever(cell: Vector2i, storey: int, key: String) -> bool:
	var r: int = FLOOR_CANTILEVER_REACH
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			if (dx == 0 and dz == 0) or absi(dx) + absi(dz) > r:
				continue
			var other := Vector2i(cell.x + dx, cell.y + dz)
			if not has_key(BuildGrid.floor_key(other, storey)):
				continue
			if is_inf(floor_support_top(other, storey, key)):
				return true
	return false

## Steht irgendein Bauteil innerhalb von `radius` (+ eine Zellhälfte Toleranz) um den Punkt?
## Genutzt, um Graben direkt an/unter Bauwerken zu sperren.
func is_area_occupied(world_x: float, world_z: float, radius: float) -> bool:
	var reach: float = radius + BuildGrid.CELL
	for rec: Dictionary in _records.values():
		var dx: float = float(rec.get("x", 0.0)) - world_x
		var dz: float = float(rec.get("z", 0.0)) - world_z
		if sqrt(dx * dx + dz * dz) <= reach:
			return true
	return false

## Records, deren Mittelpunkt im Chunk mit Zentrum chunk_coord*chunk_size liegt.
func records_in_chunk(chunk_coord: Vector2i, chunk_size: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rec: Dictionary in _records.values():
		if chunk_of(float(rec.get("x", 0.0)), float(rec.get("z", 0.0)), chunk_size) == chunk_coord:
			out.append(rec.duplicate())
	return out

## Chunk-Zuordnung — muss ChunkManager._world_to_chunk() entsprechen (Zentrum = coord*size).
static func chunk_of(world_x: float, world_z: float, chunk_size: float) -> Vector2i:
	return Vector2i(roundi(world_x / chunk_size), roundi(world_z / chunk_size))

func clear() -> void:
	_records.clear()

## Billige, tiefe Kopie für Trockenläufe (WorldBuildHandler.preview_house()): ein ganzes Haus
## wird gegen diese Kopie durchsimuliert, BEVOR am echten Bestand irgendetwas verändert wird —
## schlägt ein Teil mittendrin fehl, ist nichts angefasst (kein Rollback nötig).
func clone() -> BuildRegistry:
	var copy := BuildRegistry.new()
	for key: String in _records.keys():
		copy._records[key] = (_records[key] as Dictionary).duplicate()
	return copy

# ─────────────────────────────────────────────
# Persistenz
# ─────────────────────────────────────────────

func to_save() -> Array:
	var out: Array = []
	for rec: Dictionary in _records.values():
		out.append(rec.duplicate())
	return out

## Lädt aus to_save()-Format. Ungültige Einträge werden übersprungen (kaputter Save
## darf die Welt nicht killen).
func load_save(raw: Variant) -> void:
	_records.clear()
	if not raw is Array:
		return
	for entry in (raw as Array):
		if not entry is Dictionary:
			continue
		var rec: Dictionary = entry
		var key: Variant = rec.get("key", "")
		var piece_id: Variant = rec.get("piece_id", "")
		if not key is String or (key as String).is_empty():
			continue
		if not piece_id is String or (piece_id as String).is_empty():
			continue
		if not (rec.has("x") and rec.has("y") and rec.has("z")):
			continue
		_records[key] = rec.duplicate()

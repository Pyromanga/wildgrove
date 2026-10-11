class_name ZooLayout
extends RefCounted

## ZooLayout — reine Rechen-/Layout-Logik des Tier-Zoos am Spawn (keine Nodes, keine Engine-
## Abhängigkeit → per Unit-Test prüfbar, siehe test_zoo_layout.gd).
##
## Wunsch "alle Tiere in einem Glaskasten (groß genug fürs Tier) am Spawn, davor ein Schild":
##   - inner_size()   → Innenmaß eines Kastens aus der echten Bounding-Box des Tiermodells
##   - pack()         → Reihen-Layout (Regalpacking): Kästen links→rechts, Umbruch bei ROW_MAX_WIDTH
##   - clear_zone_*() → Kreise, in denen ChunkEntitySpawner keine Bäume/Tiere/Props würfelt
##
## Alle Kästen blicken nach +Z (Vorderseite + Schild), die Reihen liegen hintereinander.

## Weltrechteck des Zoos (x, z, Breite, Tiefe). Südlich vom Spawn (0,0), damit der Spieler
## nicht hineinläuft, aber nahe genug ist, um ihn zu sehen. NPC-Reihe (x 8..30, z -9..-3) und
## Ackerbeete (x -9..-6, z 3) liegen außerhalb. Innerhalb der Spawn-Glättzone des Terrains
## (spawn_blend_radius) → flach, und ChunkStructurePlanner setzt dort keine Gebäude.
const ZOO_RECT := Rect2(-36.0, 16.0, 72.0, 52.0)

const ROW_MAX_WIDTH: float = 68.0
## Abstand zwischen zwei Kästen derselben Reihe.
const CASE_GAP: float = 1.2
## Abstand zwischen Reihen (Platz für Schilder + Besucher vor jeder Reihe).
const AISLE: float = 3.4

## Rahmenstärke eines Kastens + Sockelüberstand (muss zu GlassCase.gd passen).
const FRAME: float = 0.10
const PLINTH: float = 0.12

## Luft zwischen Tier und Glas (je Seite) sowie über dem Tier.
const SIDE_MARGIN: float = 0.5
const HEAD_MARGIN: float = 0.7
const MIN_INNER := Vector3(1.6, 1.3, 1.6)
## Fische brauchen ein Becken: deutlich höher als das Tier selbst, damit Wasser drüber steht.
const AQUATIC_HEIGHT_FACTOR: float = 3.0
const AQUATIC_MIN_INNER := Vector3(1.8, 1.4, 1.8)

## Kreise der Freihaltezone (Spawner-Format: x, z, Radius).
const ZONE_RADIUS: float = 9.0
const ZONE_STEP: float = 12.0
const ZONE_PAD: float = 3.0

## Innenmaß eines Kastens für ein Tier mit der Modell-Bounding-Box `aabb`
## (Tier-lokal, Füße bei y≈0, Blick nach +Z).
static func inner_size(aabb: AABB, aquatic: bool) -> Vector3:
	var w: float = aabb.size.x + SIDE_MARGIN * 2.0
	var d: float = aabb.size.z + SIDE_MARGIN * 2.0
	var h: float = aabb.size.y + HEAD_MARGIN
	var min_inner: Vector3 = MIN_INNER
	if aquatic:
		h = aabb.size.y * AQUATIC_HEIGHT_FACTOR
		min_inner = AQUATIC_MIN_INNER
	return Vector3(maxf(w, min_inner.x), maxf(h, min_inner.y), maxf(d, min_inner.z))

## Grundfläche (x, z) eines Kastens inkl. Rahmen und Sockel.
static func footprint(inner: Vector3) -> Vector2:
	var extra: float = (FRAME + PLINTH) * 2.0
	return Vector2(inner.x + extra, inner.z + extra)

## Regalpacking. `footprints` = Grundflächen (x, z) in der gewünschten Reihenfolge.
## Rückgabe: {"centers": Array[Vector2] (relativ zur linken/hinteren Ecke des Zoos),
##            "size": Vector2 (Gesamtbreite/-tiefe)}. Rückseiten einer Reihe fluchten.
static func pack(footprints: Array[Vector2]) -> Dictionary:
	var centers: Array[Vector2] = []
	var cursor_x: float = 0.0
	var row_z: float = 0.0
	var row_depth: float = 0.0
	var max_x: float = 0.0
	for fp: Vector2 in footprints:
		if cursor_x > 0.0 and cursor_x + fp.x > ROW_MAX_WIDTH:
			row_z += row_depth + AISLE
			cursor_x = 0.0
			row_depth = 0.0
		centers.append(Vector2(cursor_x + fp.x * 0.5, row_z + fp.y * 0.5))
		cursor_x += fp.x + CASE_GAP
		row_depth = maxf(row_depth, fp.y)
		max_x = maxf(max_x, cursor_x - CASE_GAP)
	return {"centers": centers, "size": Vector2(max_x, row_z + row_depth)}

## Kreise, die ZOO_RECT (+ Rand) vollständig überdecken. Abstand ≤ ZONE_STEP, Radius
## ZONE_RADIUS: der Punkt mit größtem Abstand zu allen Mittelpunkten (Zellmitte-Ecke) liegt
## bei ≈ 8,5 m < 9 m — lückenlos.
static func clear_zone_circles() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var r := Rect2(ZOO_RECT.position - Vector2(ZONE_PAD, ZONE_PAD), ZOO_RECT.size + Vector2(ZONE_PAD, ZONE_PAD) * 2.0)
	var nx: int = maxi(1, ceili(r.size.x / ZONE_STEP))
	var nz: int = maxi(1, ceili(r.size.y / ZONE_STEP))
	var sx: float = r.size.x / float(nx)
	var sz: float = r.size.y / float(nz)
	for ix in range(nx):
		for iz in range(nz):
			out.append(Vector3(r.position.x + (float(ix) + 0.5) * sx, r.position.y + (float(iz) + 0.5) * sz, ZONE_RADIUS))
	return out

## Nur die Kreise, die den Chunk (Mitte `center`, Kantenlänge `chunk_size`) berühren —
## ChunkEntitySpawner prüft Props nur gegen die Zonen des EIGENEN Chunks.
static func zones_for_chunk(center: Vector2, chunk_size: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var half: float = chunk_size * 0.5
	for c: Vector3 in clear_zone_circles():
		if absf(c.x - center.x) <= half + c.z and absf(c.y - center.y) <= half + c.z:
			out.append(c)
	return out

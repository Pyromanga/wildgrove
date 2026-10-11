class_name ChunkSettlementBuilder
extends RefCounted

## ChunkSettlementBuilder — baut die Siedlungsgebäude (Dorf + Wegesrand) EINES Chunks.
##
## Die Planung (wo steht was, wie gedreht) liefert SettlementRegistry. Hier wird nur die
## Geometrie erzeugt: pro Gebäude ein Node3D aus genau einem Mesh + einem StaticBody3D
## (PartBatch). Ein Gebäude gehört dem Chunk, in dem sein Mittelpunkt liegt; ragt es über
## die Chunk-Kante, bleibt es trotzdem komplett (es hängt am Besitzer-Chunk).
##
## Die Geometrie hängt am Chunk-Node und verschwindet mit ihm; NPCs laufen über den
## ChunkEntitySpawner (gleiche Buchführung wie Bäume/Tiere).

const SLAB_TOP: float = 0.12
const SLAB_RESERVE: float = 1.4
## Größtmögliches Grundstück (halbe Diagonale) — Rand, in dem Nachbar-Chunks mitzählen müssen.
const MAX_FOOTPRINT_RADIUS: float = 20.0   # Riesenbäume (Baumdorf): Grundstück bis ~18 m halbe Diagonale

## Gebäude, die diesem Chunk gehören: Mittelpunkt in [center ± chunk_size/2).
static func buildings_for_chunk(gen: TerrainField, center: Vector2, chunk_size: float) -> Array:
	var rect := Rect2(center - Vector2(chunk_size, chunk_size) * 0.5, Vector2(chunk_size, chunk_size))
	return gen.get_settlements().buildings_in_rect(rect, 0.0)

## Baut alle Gebäude in `buildings` unter einen Node3D (Koordinaten relativ zu `center`).
static func build(buildings: Array, center: Vector2) -> Node3D:
	var root := Node3D.new()
	root.name = "Settlement"
	for b: Dictionary in buildings:
		var type_id: String = b["type"]
		if not BuildingRecipes.has_type(type_id):
			continue
		var batch := PartBatch.new()
		BuildingRecipes.build(type_id, batch, int(b["variant"]), float(b["spread"]) + SLAB_RESERVE, b)
		var node: Node3D = batch.build("%s_%d" % [type_id, absi(int(b["id"])) % 100000])
		node.position = Vector3(float(b["x"]) - center.x, float(b["y"]) + SLAB_TOP, float(b["z"]) - center.y)
		node.rotation.y = float(b["yaw"])
		root.add_child(node)
	return root

## Weltposition (x, y = Boden, z) eines NPC-Slots eines Gebäudes. Y = Plattenoberkante.
static func npc_world_pos(b: Dictionary, slot: Vector2) -> Vector3:
	var wp: Vector2 = SettlementMath.local_to_world(Vector2(float(b["x"]), float(b["z"])), float(b["yaw"]), slot)
	return Vector3(wp.x, float(b["y"]) + SLAB_TOP, wp.y)

class_name TerrainChunkBuilder
extends RefCounted

## TerrainChunkBuilder — baut aus dem TerrainField die Nodes EINES Chunks:
## Terrain-Mesh, Terrain-Kollision und (falls nötig) Wasseroberfläche.
##
## Ersetzt TerrainGenerator.create() + ChunkWaterPlacer. Kennt keinen Noise und keinen Seed:
## es SAMPELT nur TerrainField.get_height_at() an den Chunk-Vertices. Dadurch gilt
## automatisch alles, was das Feld weiß (Layer, Spieler-Änderungen) — und Mesh, Kollision
## und jede andere Höhenabfrage im Spiel stimmen exakt überein.
##
## Vertex-Layout: (Auflösung+1)² Punkte im Abstand config.get_vertex_spacing(), Chunk-Zentrum
## = Chunk-Koordinate × chunk_size. Randvertices liegen exakt auf dem Rand und werden von
## Nachbar-Chunks geteilt → nahtlose Übergänge (gleiche Weltkoordinate → gleiche Höhe).

const LOG_CAT := "TerrainChunk"

## Namen der erzeugten Kinder (für Neubau nach Gelände-Änderungen).
const NODE_TERRAIN: String = "Terrain"
const NODE_PHYSICS: String = "TerrainPhysics"
const NODE_WATER: String = "TerrainWater"

var _field: TerrainField
var _mesh_builder: TerrainMeshBuilder
var _water_builder: TerrainWaterBuilder

func _init(field: TerrainField) -> void:
	_field = field
	_mesh_builder = TerrainMeshBuilder.new()
	_water_builder = TerrainWaterBuilder.new()

func get_chunk_center(coord: Vector2i) -> Vector2:
	var size: float = _field.get_config().chunk_size
	return Vector2(float(coord.x) * size, float(coord.y) * size)

## Welcher Chunk enthält (world_x, world_z)? (Zentrum = coord * size → Rundung.)
func get_chunk_at(world_x: float, world_z: float) -> Vector2i:
	var size: float = _field.get_config().chunk_size
	return Vector2i(roundi(world_x / size), roundi(world_z / size))

## Höhen aller Vertices eines Chunks, Zeile für Zeile (z-Zeilen, x-Spalten) — das Format,
## das HeightMapShape3D und TerrainMeshBuilder erwarten.
func sample_heights(center: Vector2) -> PackedFloat32Array:
	var cfg: TerrainConfig = _field.get_config()
	var res: int = cfg.get_resolution()
	var n: int = res + 1
	var step: float = cfg.get_vertex_spacing()
	var half: float = cfg.chunk_size * 0.5

	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for z_i in range(n):
		var world_z: float = center.y - half + float(z_i) * step
		for x_i in range(n):
			var world_x: float = center.x - half + float(x_i) * step
			heights[z_i * n + x_i] = _field.get_height_at(world_x, world_z)
	return heights

## Wie sample_heights(), aber mit EINEM Vertex Rand rundherum: (res+3)² Werte, Zeile für Zeile.
## Index von Vertex (x_i, z_i) des Chunks: (z_i + 1) * (res + 3) + (x_i + 1). Dient nur der
## Normalenberechnung über Chunk-Grenzen (siehe TerrainMeshBuilder.build_terrain_mesh()).
func sample_heights_padded(center: Vector2) -> PackedFloat32Array:
	var cfg: TerrainConfig = _field.get_config()
	var res: int = cfg.get_resolution()
	var pn: int = res + 3
	var step: float = cfg.get_vertex_spacing()
	var half: float = cfg.chunk_size * 0.5

	var heights := PackedFloat32Array()
	heights.resize(pn * pn)
	for z_i in range(pn):
		var world_z: float = center.y - half + float(z_i - 1) * step
		for x_i in range(pn):
			var world_x: float = center.x - half + float(x_i - 1) * step
			heights[z_i * pn + x_i] = _field.get_height_at(world_x, world_z)
	return heights

## Schneidet aus sample_heights_padded() den Chunk-Innenbereich ((res+1)² Werte) heraus —
## identisch zu sample_heights(), aber ohne die Höhen ein zweites Mal zu berechnen.
func interior_of_padded(padded: PackedFloat32Array, res: int) -> PackedFloat32Array:
	var n: int = res + 1
	var pn: int = res + 3
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for z_i in range(n):
		for x_i in range(n):
			heights[z_i * n + x_i] = padded[(z_i + 1) * pn + (x_i + 1)]
	return heights

## Lokaler Wasserspiegel (TerrainField.get_water_level_at()) an denselben Gitterpunkten wie
## sample_heights() — Fluss-Abschnitte liegen dadurch je nach Chunk auf unterschiedlicher
## Höhe statt überall auf der globalen Konstante (siehe TerrainWaterBuilder-Kommentar).
func sample_water_levels(center: Vector2) -> PackedFloat32Array:
	var cfg: TerrainConfig = _field.get_config()
	var res: int = cfg.get_resolution()
	var n: int = res + 1
	var step: float = cfg.get_vertex_spacing()
	var half: float = cfg.chunk_size * 0.5

	var levels := PackedFloat32Array()
	levels.resize(n * n)
	for z_i in range(n):
		var world_z: float = center.y - half + float(z_i) * step
		for x_i in range(n):
			var world_x: float = center.x - half + float(x_i) * step
			levels[z_i * n + x_i] = _field.get_water_level_at(world_x, world_z)
	return levels

## Fügt Terrain, Kollision und ggf. Wasser als Kinder von `chunk_node` hinzu.
## chunk_node muss bei get_chunk_center(coord) stehen (Kinder nutzen lokale Koordinaten).
## Gibt das dabei ohnehin berechnete Raster zurück ({"heights", "water_levels"}, je (res+1)²
## Werte) — ChunkVegetationBuilder nutzt es, statt TerrainField pro Grasbüschel abzufragen.
func build(coord: Vector2i, chunk_node: Node3D) -> Dictionary:
	var cfg: TerrainConfig = _field.get_config()
	var center: Vector2 = get_chunk_center(coord)
	var res: int = cfg.get_resolution()
	var padded: PackedFloat32Array = sample_heights_padded(center)
	var heights: PackedFloat32Array = interior_of_padded(padded, res)
	# Wasserspiegel VOR dem Mesh: die Färbung braucht ihn (Flussbett/Ufer liegen über dem Meer).
	var water_levels: PackedFloat32Array = sample_water_levels(center)

	var terrain: MeshInstance3D = _mesh_builder.build_terrain_mesh(
		heights, res, cfg.chunk_size, cfg.max_height, cfg.water_level, center, _biome_color,
		water_levels, padded
	)
	terrain.name = NODE_TERRAIN
	chunk_node.add_child(terrain)

	var physics: StaticBody3D = _mesh_builder.build_physics_body(heights, res, cfg.chunk_size)
	physics.name = NODE_PHYSICS
	chunk_node.add_child(physics)

	if _water_builder.needs_surface(heights, water_levels):
		var water: MeshInstance3D = _water_builder.build_surface(heights, water_levels, res, cfg.chunk_size)
		water.name = NODE_WATER
		chunk_node.add_child(water)

	return {"heights": heights, "water_levels": water_levels}

## Ersetzt Terrain/Kollision/Wasser eines bestehenden Chunk-Nodes (nach Gelände-Änderungen).
## Andere Kinder des Chunk-Nodes bleiben unangetastet.
func rebuild(coord: Vector2i, chunk_node: Node3D) -> Dictionary:
	for child_name in [NODE_TERRAIN, NODE_PHYSICS, NODE_WATER]:
		var old: Node = chunk_node.get_node_or_null(child_name)
		if old != null:
			# Sofort aus dem Baum nehmen: queue_free() allein hält den Namen bis zum
			# Frame-Ende belegt, der Neubau würde sonst umbenannt ("Terrain2").
			chunk_node.remove_child(old)
			old.queue_free()
	return build(coord, chunk_node)

## Vertex-Farbe an dieser Weltposition — Bugfix 2026-09-26 ("überall nur Erde"):
## nutzt jetzt TerrainField.get_material_at() statt nur die Gras-Farbe des Bioms,
## damit Sand/Kies (natürlich ODER von einem Spieler abgelegt) auch sichtbar
## anders aussehen als der umgebende Boden — dieselbe Wahrheit wie
## WorldService.request_terrain_edit() (welches Item Graben liefert), kann also
## nicht von der Optik abweichen.
func _biome_color(world_x: float, world_z: float) -> Color:
	var base: Color
	match _field.get_material_at(world_x, world_z):
		"sand":
			base = TerrainColorizer.COL_SAND
		"gravel":
			base = TerrainColorizer.COL_GRAVEL
		_:
			var biome: BiomeDefinition = _field.get_biome_at(world_x, world_z)
			base = biome.terrain_color_grass if is_instance_valid(biome) else TerrainColorizer.COL_GRASS
	# Straßen/Gassen/Hauswege der Siedlungen (Feldweg-Farbe über dem Untergrund).
	return _field.get_settlements().road_tint(world_x, world_z, base)

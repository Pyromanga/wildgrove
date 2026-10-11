# res://tests/unit/test_terrain_mesh_builder.gd
extends GutTest

## Unit-Tests für TerrainMeshBuilder (Mesh- + Physics-Body-Assemblierung aus
## einer Heightmap).
##
## Strategie für build_terrain_mesh(): minimalstes Grid (resolution=1, also
## n=2 -> genau 1 Quad, 2 Dreiecke), alle Höhen 0.0 (flache Ebene) -> die
## Dreiecksnormalen sind für JEDES Dreieck exakt (0,1,0) (in Python
## vorgerechnet, siehe Kommentar unten), keine Rundungsunschärfe möglich.
## Godots ArrayMesh gibt über surface_get_arrays() die tatsächlich
## eingebauten Vertex-/Normal-/Farb-/Index-Arrays zurück — direkt inspizierbar
## statt nur "kein Crash".
##
## Abgedeckt:
##   - build_terrain_mesh(): Vertex-Positionen exakt, Normalen exakt (0,1,0)
##     für die flache Test-Ebene, Farben (biome_cb-Ergebnis übernommen),
##     Fallback auf TerrainColorizer.COL_GRASS bei ungültigem biome_cb,
##     Index-Reihenfolge/-Anzahl, Material-Eigenschaften, mesh.position.y
##   - build_physics_body(): HeightMapShape3D-Dimensionen, map_data-Referenz,
##     StaticBody3D.scale-Skalierung auf Weltgröße

const RESOLUTION := 1  # n=2 -> 1 Quad, 2 Dreiecke — kleinstmögliches Grid
const SIZE := 2.0       # step = 2.0/1 = 2.0, half = 1.0
const MAX_HEIGHT := 10.0
const SEA_LEVEL := -5.0  # weit unter 0 -> h=0 landet sicher im reinen Grass-Band
const FIXED_GRASS := Color(0.31, 0.61, 0.26, 1.0)

var _builder: TerrainMeshBuilder


func before_each() -> void:
	_builder = TerrainMeshBuilder.new()


func after_each() -> void:
	_builder = null


func _flat_heights() -> PackedFloat32Array:
	return PackedFloat32Array([0.0, 0.0, 0.0, 0.0])  # n*n = 4, alle 0.0

func _build_mesh(biome_cb: Callable, world_offset: Vector2 = Vector2.ZERO) -> MeshInstance3D:
	var mi := _builder.build_terrain_mesh(_flat_heights(), RESOLUTION, SIZE, MAX_HEIGHT, SEA_LEVEL, world_offset, biome_cb)
	add_child_autofree(mi)
	return mi

func _build_body() -> StaticBody3D:
	var body := _builder.build_physics_body(_flat_heights(), RESOLUTION, SIZE)
	add_child_autofree(body)
	return body


# ─────────────────────────────────────────────
# build_terrain_mesh() — Geometrie
# ─────────────────────────────────────────────

func test_mesh_vertex_positions_are_exact() -> void:
	var biome_cb := func(_wx, _wz): return FIXED_GRASS
	var mi := _build_mesh(biome_cb)
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_eq(verts.size(), 4)
	# Reihenfolge: (z=0,x=0),(z=0,x=1),(z=1,x=0),(z=1,x=1)
	assert_eq(verts[0], Vector3(-1.0, 0.0, -1.0))
	assert_eq(verts[1], Vector3(1.0, 0.0, -1.0))
	assert_eq(verts[2], Vector3(-1.0, 0.0, 1.0))
	assert_eq(verts[3], Vector3(1.0, 0.0, 1.0))

func test_mesh_normals_are_exactly_up_for_flat_plane() -> void:
	var biome_cb := func(_wx, _wz): return FIXED_GRASS
	var mi := _build_mesh(biome_cb)
	var arrays := mi.mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for n in normals:
		assert_eq(n, Vector3.UP, "Flache Ebene -> jede Vertex-Normale exakt (0,1,0), in Python vorgerechnet.")

func test_mesh_indices_form_two_triangles_with_expected_winding() -> void:
	var biome_cb := func(_wx, _wz): return FIXED_GRASS
	var mi := _build_mesh(biome_cb)
	var arrays := mi.mesh.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	assert_eq(indices, PackedInt32Array([0, 2, 1, 1, 2, 3]), "i00,i01,i10, i10,i01,i11 mit n=2 -> 0,2,1,1,2,3.")

func test_mesh_colors_use_biome_callback_result() -> void:
	var biome_cb := func(_wx, _wz): return FIXED_GRASS
	var mi := _build_mesh(biome_cb)
	var arrays := mi.mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for c in colors:
		assert_eq(c, FIXED_GRASS, "h=0 liegt im reinen Grass-Band -> Farbe kommt 1:1 von biome_cb.")

func test_mesh_colors_fall_back_to_default_grass_when_biome_cb_invalid() -> void:
	var mi := _build_mesh(Callable())
	var arrays := mi.mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for c in colors:
		assert_eq(c, TerrainColorizer.COL_GRASS, "Callable().is_valid()==false -> Fallback auf COL_GRASS-Konstante.")

func test_mesh_world_offset_shifts_biome_callback_coordinates() -> void:
	var received_coords: Array = []
	var biome_cb := func(wx, wz):
		received_coords.append(Vector2(wx, wz))
		return FIXED_GRASS
	_build_mesh(biome_cb, Vector2(100.0, 200.0))
	# vx/vz für Vertex 0 sind (-1,-1) -> world_x/world_z = offset + vx/vz = (99, 199)
	assert_eq(received_coords[0], Vector2(99.0, 199.0))


# ─────────────────────────────────────────────
# build_terrain_mesh() — MeshInstance3D/Material-Eigenschaften
# ─────────────────────────────────────────────

func test_mesh_instance_has_single_surface() -> void:
	var biome_cb := func(_wx, _wz): return FIXED_GRASS
	var mi := _build_mesh(biome_cb)
	assert_eq(mi.mesh.get_surface_count(), 1)

func test_mesh_instance_position_y_is_zero() -> void:
	var biome_cb := func(_wx, _wz): return FIXED_GRASS
	var mi := _build_mesh(biome_cb)
	assert_eq(mi.position.y, 0.0)

func test_material_properties() -> void:
	var biome_cb := func(_wx, _wz): return FIXED_GRASS
	var mi := _build_mesh(biome_cb)
	var mat: StandardMaterial3D = mi.material_override
	assert_not_null(mat)
	assert_true(mat.vertex_color_use_as_albedo)
	assert_almost_eq(mat.roughness, 0.9, 0.0001)
	assert_almost_eq(mat.metallic, 0.0, 0.0001)
	assert_eq(mat.cull_mode, BaseMaterial3D.CULL_DISABLED)


# ─────────────────────────────────────────────
# build_physics_body()
# ─────────────────────────────────────────────

func test_physics_body_shape_dimensions() -> void:
	var body := _build_body()
	var col: CollisionShape3D = null
	for child in body.get_children():
		if child is CollisionShape3D:
			col = child
	assert_not_null(col)
	var shape: HeightMapShape3D = col.shape
	assert_eq(shape.map_width, RESOLUTION + 1)
	assert_eq(shape.map_depth, RESOLUTION + 1)
	assert_eq(shape.map_data, _flat_heights())

func test_physics_body_scale_matches_world_size() -> void:
	var body := _build_body()
	# scale_xz = size/resolution = 2.0/1 = 2.0
	assert_eq(body.scale, Vector3(2.0, 1.0, 2.0))

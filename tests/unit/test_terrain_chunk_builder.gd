# res://tests/unit/test_terrain_chunk_builder.gd
extends GutTest

## Tests für TerrainChunkBuilder + TerrainWaterBuilder: aus dem TerrainField werden die Nodes
## eines Chunks. Schwerpunkt: Nahtlosigkeit (gleiche Weltkoordinate → gleiche Höhe), Wasser
## nur wo nötig, Neubau ohne Duplikate.

## Höhenfeld mit beliebiger Funktion.
class FuncField extends TerrainField:
	var fn: Callable
	func get_height_at(x: float, z: float) -> float:
		return float(fn.call(x, z))
	# Diese Test-Doppel wollen den GLOBALEN Spiegel testen, nicht die echte, seed-abhängige
	# Fluss-Platzierung von TerrainField.get_water_level_at() (die hat eigene Tests). Sonst
	# hinge das Ergebnis hier vom Zufall ab, ob bei seed 1337 zufällig ein Fluss durch den
	# getesteten Chunk läuft.
	func get_water_level_at(_x: float, _z: float) -> float:
		return get_water_level()

var _builder: TerrainChunkBuilder
var _field: TerrainField

func before_each() -> void:
	_field = TerrainField.new(null, 1337)
	_builder = TerrainChunkBuilder.new(_field)

func _flat_field(h: float) -> FuncField:
	var f := FuncField.new()
	f.fn = func(_x: float, _z: float) -> float: return h
	return f

func _make_chunk(coord: Vector2i) -> Node3D:
	var n := Node3D.new()
	var c := _builder.get_chunk_center(coord)
	n.position = Vector3(c.x, 0.0, c.y)
	autofree(n)
	return n

# ── Koordinaten ─────────────────────────────────

func test_chunk_center_is_coord_times_size() -> void:
	var size := _field.get_config().chunk_size
	assert_eq(_builder.get_chunk_center(Vector2i(2, -3)), Vector2(2.0 * size, -3.0 * size))

func test_chunk_at_roundtrip_and_negative() -> void:
	for coord in [Vector2i(0, 0), Vector2i(3, -2), Vector2i(-5, 7)]:
		var c := _builder.get_chunk_center(coord)
		assert_eq(_builder.get_chunk_at(c.x, c.y), coord)
	assert_eq(_builder.get_chunk_at(-70.0, 5.0), Vector2i(-1, 0))

# ── Höhen ───────────────────────────────────────

func test_sample_heights_has_full_grid() -> void:
	var res := _field.get_config().get_resolution()
	assert_eq(_builder.sample_heights(Vector2.ZERO).size(), (res + 1) * (res + 1))

func test_heights_equal_field_at_vertices() -> void:
	var cfg := _field.get_config()
	var center := _builder.get_chunk_center(Vector2i(2, 1))
	var heights := _builder.sample_heights(center)
	var n := cfg.get_resolution() + 1
	var step := cfg.get_vertex_spacing()
	for z_i in [0, 5, 16, 32]:
		for x_i in [0, 7, 20, 32]:
			var wx := center.x - cfg.chunk_size * 0.5 + float(x_i) * step
			var wz := center.y - cfg.chunk_size * 0.5 + float(z_i) * step
			assert_almost_eq(heights[z_i * n + x_i], _field.get_height_at(wx, wz), 0.0001)

func test_neighbor_chunks_share_border_vertices_exactly() -> void:
	# DER Nahtgarantie: rechte Spalte von Chunk (0,0) == linke Spalte von Chunk (1,0),
	# untere Zeile von (0,0) == obere Zeile von (0,1). Bit-genau, nicht nur ungefähr.
	var n := _field.get_config().get_resolution() + 1
	var a := _builder.sample_heights(_builder.get_chunk_center(Vector2i(0, 0)))
	var right := _builder.sample_heights(_builder.get_chunk_center(Vector2i(1, 0)))
	var below := _builder.sample_heights(_builder.get_chunk_center(Vector2i(0, 1)))
	for i in n:
		assert_eq(a[i * n + (n - 1)], right[i * n + 0], "Naht in x bei Zeile %d" % i)
		assert_eq(a[(n - 1) * n + i], below[0 * n + i], "Naht in z bei Spalte %d" % i)

func test_chunk_heights_include_player_edits() -> void:
	var layer := TerrainEditLayer.new()
	var center := _builder.get_chunk_center(Vector2i(0, 0))
	var before := _builder.sample_heights(center)
	layer.set_delta(Vector2i(0, 0), -1.5)   # Weltposition (0, 0) = Chunk-Zentrum
	_field.set_edit_layer(layer)
	var after := _builder.sample_heights(center)
	var n := _field.get_config().get_resolution() + 1
	var mid := (n / 2) * n + (n / 2)
	assert_almost_eq(after[mid], before[mid] - 1.5, 0.0001)
	assert_almost_eq(after[0], before[0], 0.0001, "Weit entfernte Vertices bleiben unberührt.")

# ── build() ─────────────────────────────────────

func test_build_adds_terrain_and_physics() -> void:
	var node := _make_chunk(Vector2i(0, 0))
	_builder.build(Vector2i(0, 0), node)
	assert_not_null(node.get_node_or_null(TerrainChunkBuilder.NODE_TERRAIN))
	assert_not_null(node.get_node_or_null(TerrainChunkBuilder.NODE_PHYSICS))

func test_physics_shape_matches_sampled_heights() -> void:
	var node := _make_chunk(Vector2i(1, 1))
	_builder.build(Vector2i(1, 1), node)
	var body := node.get_node(TerrainChunkBuilder.NODE_PHYSICS) as StaticBody3D
	var shape := (body.get_child(0) as CollisionShape3D).shape as HeightMapShape3D
	var expected := _builder.sample_heights(_builder.get_chunk_center(Vector2i(1, 1)))
	assert_eq(shape.map_data.size(), expected.size())
	assert_eq(shape.map_data[100], expected[100], "Kollision und Mesh nutzen dieselben Höhen.")

func test_dry_chunk_gets_no_water_surface() -> void:
	var field := _flat_field(5.0)
	var b := TerrainChunkBuilder.new(field)
	var node := Node3D.new()
	autofree(node)
	b.build(Vector2i(0, 0), node)
	assert_null(node.get_node_or_null(TerrainChunkBuilder.NODE_WATER))

func test_flooded_chunk_gets_water_surface_at_water_level() -> void:
	# Flaches Feld ohne Fluss darin → lokaler Spiegel (get_water_level_at) == globaler
	# Spiegel überall; jeder Wasser-Vertex muss also auf field.get_water_level() liegen.
	var field := _flat_field(-2.0)
	var b := TerrainChunkBuilder.new(field)
	var node := Node3D.new()
	autofree(node)
	b.build(Vector2i(0, 0), node)
	var water := node.get_node_or_null(TerrainChunkBuilder.NODE_WATER) as MeshInstance3D
	assert_not_null(water)
	var verts: PackedVector3Array = (water.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_true(verts.size() > 0)
	for v in verts:
		assert_eq(v.y, field.get_water_level())

func test_water_surface_has_no_collision() -> void:
	# Regression zum alten Verhalten: Wasser waren begehbare Rechtecke mit Kollision.
	var field := _flat_field(-2.0)
	var b := TerrainChunkBuilder.new(field)
	var node := Node3D.new()
	autofree(node)
	b.build(Vector2i(0, 0), node)
	var water := node.get_node(TerrainChunkBuilder.NODE_WATER)
	for child in water.get_children():
		assert_false(child is CollisionObject3D or child is CollisionShape3D, "Wasser darf keine Kollision haben.")
	assert_true(water is MeshInstance3D)

# ── rebuild() ───────────────────────────────────

func test_rebuild_replaces_without_duplicates() -> void:
	var node := _make_chunk(Vector2i(0, 0))
	_builder.build(Vector2i(0, 0), node)
	var first_terrain := node.get_node(TerrainChunkBuilder.NODE_TERRAIN)
	_builder.rebuild(Vector2i(0, 0), node)
	var terrain_count := 0
	for c in node.get_children():
		if c.name == TerrainChunkBuilder.NODE_TERRAIN:
			terrain_count += 1
	assert_eq(terrain_count, 1)
	assert_ne(node.get_node(TerrainChunkBuilder.NODE_TERRAIN), first_terrain, "Neue Instanz.")
	assert_eq(node.get_node(TerrainChunkBuilder.NODE_TERRAIN).name, TerrainChunkBuilder.NODE_TERRAIN, "Kein Umbenennen ('Terrain2').")

func test_rebuild_keeps_foreign_children() -> void:
	var node := _make_chunk(Vector2i(0, 0))
	var marker := Node3D.new()
	marker.name = "Marker"
	node.add_child(marker)
	_builder.build(Vector2i(0, 0), node)
	_builder.rebuild(Vector2i(0, 0), node)
	assert_not_null(node.get_node_or_null("Marker"), "Fremde Kinder (z.B. Entities) bleiben beim Neubau erhalten.")

func test_rebuild_removes_stale_water_when_ground_rises() -> void:
	var field := FuncField.new()
	field.fn = func(_x: float, _z: float) -> float: return -2.0
	var b := TerrainChunkBuilder.new(field)
	var node := Node3D.new()
	autofree(node)
	b.build(Vector2i(0, 0), node)
	assert_not_null(node.get_node_or_null(TerrainChunkBuilder.NODE_WATER))
	field.fn = func(_x: float, _z: float) -> float: return 4.0
	b.rebuild(Vector2i(0, 0), node)
	assert_null(node.get_node_or_null(TerrainChunkBuilder.NODE_WATER), "Aufgeschüttetes Gelände → kein Wasser mehr.")

# ── Padded Heights / nahtlose Normalen (2026-10-04, Gebirge) ──

func test_padded_heights_interior_equals_sample_heights() -> void:
	var res := _field.get_config().get_resolution()
	var center := _builder.get_chunk_center(Vector2i(3, -2))
	var padded := _builder.sample_heights_padded(center)
	assert_eq(padded.size(), (res + 3) * (res + 3))
	assert_eq(_builder.interior_of_padded(padded, res), _builder.sample_heights(center))

func test_neighbor_chunks_share_identical_border_normals() -> void:
	# Steile Berghänge: ohne Rand-Höhen schaute die Normale nur auf den eigenen Chunk, und an der
	# Chunk-Grenze entstand eine sichtbare Licht-/Farbnaht. Mit Padding muss sie bit-gleich sein.
	var f := FuncField.new()
	f.fn = func(x: float, z: float) -> float: return 6.0 * sin(x * 0.11) + 4.0 * cos(z * 0.09 + x * 0.03)
	var b := TerrainChunkBuilder.new(f)
	var left := Node3D.new()
	var right := Node3D.new()
	autofree(left)
	autofree(right)
	b.build(Vector2i(0, 0), left)
	b.build(Vector2i(1, 0), right)
	var res: int = f.get_config().get_resolution()
	var n := res + 1
	var nl: PackedVector3Array = ((left.get_node(TerrainChunkBuilder.NODE_TERRAIN) as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var nr: PackedVector3Array = ((right.get_node(TerrainChunkBuilder.NODE_TERRAIN) as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	for z_i in range(n):
		var a: Vector3 = nl[z_i * n + res]   # rechte Kante von Chunk (0,0)
		var c: Vector3 = nr[z_i * n]         # linke Kante von Chunk (1,0)
		assert_almost_eq(a.x, c.x, 0.0001)
		assert_almost_eq(a.y, c.y, 0.0001)
		assert_almost_eq(a.z, c.z, 0.0001)

func test_terrain_mesh_colors_see_rivers_as_water_bed() -> void:
	# Gelände bei h=1.0, aber lokaler Wasserspiegel 3.0 (Flussbett über dem Meeresspiegel):
	# die Färbung muss das als Gewässerboden erkennen, nicht als Wiese.
	var mb := TerrainMeshBuilder.new()
	var heights := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
	var water := PackedFloat32Array([3.0, 3.0, 3.0, 3.0])
	var mi := mb.build_terrain_mesh(heights, 1, 2.0, 85.0, 0.0, Vector2.ZERO, func(_x, _z): return Color(0.2, 0.6, 0.2), water)
	autofree(mi)
	var colors: PackedColorArray = (mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	for c in colors:
		assert_ne(c, Color(0.2, 0.6, 0.2), "Flussbett darf nicht als Wiese gefärbt sein.")

# ── Wasserfall-Normalen (2026-10-05) ────────────

func _water_normals(terrain: PackedFloat32Array, water: PackedFloat32Array, res: int) -> PackedVector3Array:
	var wb := TerrainWaterBuilder.new()
	var mi := wb.build_surface(terrain, water, res, float(res) * 2.0)
	autofree(mi)
	return (mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_NORMAL]

func test_flat_water_has_up_normals() -> void:
	var res := 4
	var n := res + 1
	var terrain := PackedFloat32Array()
	var water := PackedFloat32Array()
	terrain.resize(n * n)
	water.resize(n * n)
	for i in range(n * n):
		terrain[i] = -3.0
		water[i] = 0.0
	for nv in _water_normals(terrain, water, res):
		assert_almost_eq(nv.y, 1.0, 0.0001)

func test_waterfall_sheet_has_steep_normals_but_banks_do_not() -> void:
	# Spiegel springt in der Mitte von 12 auf 6 (Wasserfall, 6 m auf 2 m). Rechts davon liegt trockenes
	# Ufer mit "globalem" Spiegel 0 — der Sprung dorthin darf KEINE Fall-Normale erzeugen.
	var res := 6
	var n := res + 1
	var terrain := PackedFloat32Array()
	var water := PackedFloat32Array()
	terrain.resize(n * n)
	water.resize(n * n)
	for z_i in range(n):
		for x_i in range(n):
			var i := z_i * n + x_i
			if x_i <= 2:
				terrain[i] = 9.0
				water[i] = 12.0
			elif x_i <= 4:
				terrain[i] = 3.0
				water[i] = 6.0
			else:
				terrain[i] = 20.0   # trockenes Ufer, Spiegel (global) darunter
				water[i] = 0.0
	var normals := _water_normals(terrain, water, res)
	var fall_vertex: Vector3 = normals[3 * n + 2]
	assert_lt(fall_vertex.y, 0.65, "Wasserfall-Fläche muss steil sein (flach wäre 1.0).")
	var calm_vertex: Vector3 = normals[3 * n + 0]
	assert_gt(calm_vertex.y, 0.9, "Ruhiges Becken oberhalb bleibt flach.")
	var bank_vertex: Vector3 = normals[3 * n + 4]
	assert_gt(bank_vertex.y, 0.5, "Trockener Nachbar darf keinen Fall vortäuschen.")

# ── TerrainWaterBuilder ─────────────────────────

## Hilfskonstante: dieselbe (flache) Spiegelhöhe für alle drei Vertices.
func _flat_levels(level: float, n: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	a.fill(level)
	return a

func test_water_builder_needs_surface_only_below_level() -> void:
	var wb := TerrainWaterBuilder.new()
	assert_false(wb.needs_surface(PackedFloat32Array([1.0, 2.0, 3.0]), _flat_levels(0.0, 3)))
	assert_true(wb.needs_surface(PackedFloat32Array([1.0, -0.5, 3.0]), _flat_levels(0.0, 3)))

func test_water_builder_ignores_grazing_contact() -> void:
	var wb := TerrainWaterBuilder.new()
	assert_false(wb.needs_surface(PackedFloat32Array([1.0, -0.01]), _flat_levels(0.0, 2)),
		"Kaum unter dem Spiegel → keine Ebene (Z-Fighting).")

func test_water_surface_covers_chunk() -> void:
	# resolution=1 → 2x2 Vertices, genau die vier Chunk-Ecken.
	var wb := TerrainWaterBuilder.new()
	var terrain := PackedFloat32Array([-1.0, -1.0, -1.0, -1.0])
	var water := _flat_levels(0.5, 4)
	var mi := wb.build_surface(terrain, water, 1, 64.0)
	autofree(mi)
	var verts: PackedVector3Array = (mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(verts.size(), 4)
	for v in verts:
		assert_eq(v.y, 0.5)
		assert_true(absf(v.x) <= 32.0 and absf(v.z) <= 32.0, "Deckt genau den Chunk ab.")

func test_water_builder_fades_out_shallow_edges() -> void:
	# Vertex mit Tiefe 0 (trocken) muss unsichtbar sein (Alpha 0), sonst schwebt eine
	# sichtbare Wasserkante über trockenem Land am Chunk-Rand.
	var wb := TerrainWaterBuilder.new()
	var terrain := PackedFloat32Array([-1.0, 0.5, -1.0, -1.0])  # 2. Vertex = trocken
	var water := _flat_levels(0.5, 4)
	var mi := wb.build_surface(terrain, water, 1, 64.0)
	autofree(mi)
	var colors: PackedColorArray = (mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	assert_eq(colors[1].a, 0.0, "Trockener Vertex: keine sichtbare Wasserfläche.")
	assert_gt(colors[0].a, 0.0, "Nasser Vertex: sichtbar.")

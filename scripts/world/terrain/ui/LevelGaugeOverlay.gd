class_name LevelGaugeOverlay
extends Node3D

## LevelGaugeOverlay — der Wasserwagen als Farbnetz auf dem Gelände (Logik: LevelGauge).
##
## Ein einziges ArrayMesh, das dem Gelände folgt (Vertices = Geländehöhe + LIFT). Halbtransparent
## und unshaded, ohne Tiefenschreiben — Boden, Bauteile und Spieler bleiben sichtbar.
##
## Kein eigenes _process(): der Besitzer (BuildModeController / GroundToolController) ruft
## update_view() jeden Frame mit dem aktuellen Zielpunkt auf. Neu gebaut wird nur, wenn sich
## Zelle/Bezugshöhe ändern oder REFRESH_MSEC vergangen sind (das Gelände kann sich durch Graben
## ändern, ohne dass sich der Zielpunkt bewegt) — ein Netz hat nur wenige hundert Vertices.

## Mindestabstand zwischen zwei Neuaufbauten bei unverändertem Ziel (Millisekunden).
const REFRESH_MSEC: int = 300

var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D
var _last_cell: Vector2i = Vector2i(2147483647, 2147483647)
var _last_ref: float = NAN
var _last_cells: int = -1
var _last_build_msec: int = -1000000
var _stats: Dictionary = {}

func _init() -> void:
	name = "LevelGaugeOverlay"
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.no_depth_test = false
	_material.disable_receive_shadows = true
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "GaugeMesh"
	_mesh_instance.material_override = _material
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Weltkoordinaten stecken direkt in den Vertices — der Knoten selbst bleibt im Ursprung.
	add_child(_mesh_instance)
	visible = false

## Kennzahlen des letzten Aufbaus (LevelGauge.compute_stats()). Leer vor dem ersten Aufbau.
func get_stats() -> Dictionary:
	return _stats

## Zeigt das Netz um `center` (Weltkoordinaten x/z) relativ zu ref_y. cells: Halbkante in Zellen.
## stat_radius: Radius (Meter) für die Kennzahlen. Gibt die Kennzahlen zurück.
func update_view(
	height_fn: Callable, center: Vector2, ref_y: float, cells: int, stat_radius: float
) -> Dictionary:
	visible = true
	var cell := Vector2i(
		floori(center.x / TerrainEditLayer.SPACING), floori(center.y / TerrainEditLayer.SPACING))
	var now: int = Time.get_ticks_msec()
	var changed: bool = cell != _last_cell or cells != _last_cells \
		or is_nan(_last_ref) or not is_equal_approx(ref_y, _last_ref)
	if changed or now - _last_build_msec >= REFRESH_MSEC:
		_rebuild(height_fn, center, ref_y, cells, stat_radius)
		_last_cell = cell
		_last_ref = ref_y
		_last_cells = cells
		_last_build_msec = now
	return _stats

func hide_view() -> void:
	visible = false

func _rebuild(height_fn: Callable, center: Vector2, ref_y: float, cells: int, stat_radius: float) -> void:
	var grid: Dictionary = LevelGauge.build_grid(height_fn, center, ref_y, cells, stat_radius)
	_stats = grid["stats"]
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = grid["vertices"]
	arrays[Mesh.ARRAY_COLOR] = grid["colors"]
	arrays[Mesh.ARRAY_INDEX] = grid["indices"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_instance.mesh = mesh

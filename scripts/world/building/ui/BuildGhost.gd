class_name BuildGhost
extends Node3D

## BuildGhost — halbtransparente Vorschau des Bauteils im Baumodus.
##
## Geometrie kommt aus BuildPieceDefinition.get_box_size()/get_box_center() — dieselbe Quelle wie
## das fertige BuildPiece, die Vorschau kann also nie anders aussehen als das Ergebnis.
## Farbe zeigt den Zustand: grün = baubar, rot = geht nicht, gelb = Platz frei, aber Material fehlt.
## Keine Kollision, wirft keinen Schatten.

enum State { OK, BLOCKED, NO_MATERIALS }

const COL_OK        := Color(0.25, 0.90, 0.35, 0.45)
const COL_BLOCKED   := Color(0.95, 0.22, 0.22, 0.45)
const COL_NO_MATERIAL := Color(0.95, 0.80, 0.20, 0.45)

var _mesh: MeshInstance3D
var _material: StandardMaterial3D

func _init() -> void:
	name = "BuildGhost"
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh = MeshInstance3D.new()
	_mesh.name = "GhostMesh"
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)

func configure(def: BuildPieceDefinition) -> void:
	if def.is_roof():
		# Gleiche Geometrie-Quelle wie das fertige BuildPiece (BuildPieceDefinition.build_roof_
		# mesh) — der Geist kann dadurch nie anders aussehen als das Ergebnis.
		_mesh.mesh = BuildPieceDefinition.build_roof_mesh(BuildGrid.CELL, def.height, def.roof_shape, def.roof_ridge)
		_mesh.position = Vector3.ZERO
		return
	if def.is_stairs():
		_mesh.mesh = BuildPieceDefinition.build_stairs_mesh(BuildGrid.CELL, def.height, def.stairs_shape)
		_mesh.position = Vector3.ZERO
		return
	if def.is_target():
		_mesh.mesh = BuildPieceDefinition.build_prop_mesh(def.height, def.prop_shape)
		_mesh.position = Vector3.ZERO
		return
	if def.is_door():
		# Türöffnung sichtbar in der Vorschau: dieselbe Box-Liste wie das fertige Bauteil
		# (BuildPiece._add_framed), hier zu einem Mesh kombiniert (der Geist hat nur eine
		# MeshInstance3D).
		_mesh.mesh = BuildPieceDefinition.build_framed_mesh(def.get_door_boxes(BuildGrid.CELL))
		_mesh.position = Vector3.ZERO
		return
	if def.is_window():
		_mesh.mesh = BuildPieceDefinition.build_framed_mesh(def.get_window_boxes(BuildGrid.CELL))
		_mesh.position = Vector3.ZERO
		return
	if def.has_crenellations():
		_mesh.mesh = BuildPieceDefinition.build_framed_mesh(def.get_wall_boxes(BuildGrid.CELL))
		_mesh.position = Vector3.ZERO
		return
	var box := BoxMesh.new()
	box.size = def.get_box_size(BuildGrid.CELL)
	_mesh.mesh = box
	_mesh.position = def.get_box_center()

## Setzt Position (Basis-Mittelpunkt), Ausrichtung und Farbe.
func apply_state(pos: Vector3, yaw: float, state: int) -> void:
	position = pos
	rotation.y = yaw
	_material.albedo_color = color_for(state)

static func color_for(state: int) -> Color:
	match state:
		State.OK:           return COL_OK
		State.NO_MATERIALS: return COL_NO_MATERIAL
		_:                  return COL_BLOCKED

## Vorschau-Ergebnis (WorldService.preview_build) → Ghost-Zustand.
static func state_from_preview(preview: Dictionary) -> int:
	if bool(preview.get("ok", false)):
		return State.OK if bool(preview.get("affordable", false)) else State.NO_MATERIALS
	return State.BLOCKED

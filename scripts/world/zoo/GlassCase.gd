class_name GlassCase
extends Node3D

## GlassCase — Schaukasten aus Glas mit Sockel, Rahmen und davorstehendem Namensschild.
## Entity-Typ "glass_case" (siehe WorldEntityRegistry); gespawnt vom ZooPlacer.
##
## Spawn-Config:
##   inner      : Vector3 — Innenmaß (Breite x, Höhe y, Tiefe z) des Glasraums
##   label      : String  — Text des Schildes (Tiername)
##   water      : bool    — true → blaue, durchsichtige Wasserfüllung (Fischbecken)
##   foundation : float   — wie tief der Sockel unter die Bodenplatte reicht (gleicht Gelände aus)
##
## Koordinaten: Entity-Ursprung = Mittelpunkt der Grundfläche auf Bodenhöhe. Die begehbare
## Innenfläche (wo das Tier steht) liegt bei y = FLOOR_TOP. Vorderseite + Schild = +Z — dorthin
## blicken die Tiere (Modelle sind mit vorne = +Z gebaut, siehe AnimalVisualBuilder).
##
## Kollision: Sockel, Glaswände und Deckel sind StaticBody3D (Standard-Layer wie die Gebäude in
## ChunkStructureBuilder) — der Spieler läuft nicht hinein. Das Schild hat bewusst keine
## Kollision (reine Deko, soll nicht im Weg stehen). Alle Nodes entstehen in on_spawn() — kein
## Szenen-/Ressourcenpfad nötig. Geometrie ist rein lokal und deterministisch: jeder Peer baut
## sie selbst aus derselben Config (Entities werden pro Peer lokal gespawnt, siehe
## EntityOrchestrator).

const LOG_CAT := "GlassCase"

## Oberkante der Bodenplatte über dem Entity-Ursprung.
const FLOOR_TOP: float = 0.20
const GLASS_T: float = 0.04
const LID_T: float = 0.10
const WATER_FILL: float = 0.75
## Schild: Stehhöhe der Oberkante, Brettmaße, Abstand vor der Sockelkante.
const SIGN_BOARD_H: float = 0.34
const SIGN_BOARD_T: float = 0.05
const SIGN_CENTER_Y: float = 0.78
const SIGN_DISTANCE: float = 0.45
const SIGN_POST: float = 0.06
const LABEL_FONT_SIZE: int = 48
const LABEL_PIXEL_SIZE: float = 0.0045

const COL_WOOD := Color(0.36, 0.25, 0.14)
const COL_WOOD_DARK := Color(0.24, 0.16, 0.09)
const COL_PLINTH := Color(0.42, 0.40, 0.38)
const COL_GLASS := Color(0.72, 0.90, 1.0, 0.16)
const COL_WATER := Color(0.20, 0.50, 0.80, 0.38)
const COL_SIGN_TEXT := Color(0.97, 0.93, 0.80)

var _inner: Vector3 = Vector3(1.6, 1.3, 1.6)
var _label: String = ""

func _ready() -> void:
	set_multiplayer_authority(1)
	add_to_group("zoo_case")

func on_spawn(cfg: Dictionary = {}, _ctx: IEntityContext = null) -> void:
	_inner = cfg.get("inner", _inner) as Vector3
	_label = String(cfg.get("label", ""))
	_clear()
	build_geometry(
		self, _inner, _label, bool(cfg.get("water", false)), float(cfg.get("foundation", 0.8))
	)

func get_label() -> String:
	return _label

func get_inner_size() -> Vector3:
	return _inner

## Pool-Wiederverwendung: Geometrie ist pro Config einmalig — vor dem Neuaufbau leeren.
func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

## Breite des Schildbretts für einen Text (damit lange Namen wie "Rotbauch-Unterstrich" passen).
static func sign_width(text: String) -> float:
	return clampf(0.5 + float(text.length()) * 0.11, 1.0, 2.8)

## Baut alles unter `root`. Statisch, damit Tests es ohne EntityOrchestrator aufrufen können.
static func build_geometry(root: Node3D, inner: Vector3, label: String, water: bool, foundation: float) -> void:
	var half_w: float = inner.x * 0.5
	var half_d: float = inner.z * 0.5
	var top_y: float = FLOOR_TOP + inner.y

	var body := StaticBody3D.new()
	body.name = "CaseBody"
	root.add_child(body)

	# Sockel: reicht `foundation` Meter unter die Bodenplatte (Gelände darunter kann abfallen).
	var plinth_w: float = inner.x + (ZooLayout.FRAME + ZooLayout.PLINTH) * 2.0
	var plinth_d: float = inner.z + (ZooLayout.FRAME + ZooLayout.PLINTH) * 2.0
	var plinth_h: float = FLOOR_TOP + maxf(foundation, 0.2)
	_box(body, "Plinth", Vector3(plinth_w, plinth_h, plinth_d), Vector3(0.0, FLOOR_TOP - plinth_h * 0.5, 0.0), COL_PLINTH, true)

	# Vier Eckpfosten + Deckel (Holz).
	var f: float = ZooLayout.FRAME
	var post_h: float = inner.y
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var px: float = sx * (half_w + f * 0.5)
			var pz: float = sz * (half_d + f * 0.5)
			_box(body, "Post", Vector3(f, post_h, f), Vector3(px, FLOOR_TOP + post_h * 0.5, pz), COL_WOOD, true)
	_box(body, "Lid", Vector3(inner.x + f * 2.0 + 0.04, LID_T, inner.z + f * 2.0 + 0.04), Vector3(0.0, top_y + LID_T * 0.5, 0.0), COL_WOOD_DARK, true)

	# Vier Glasscheiben (durchsichtig, mit Kollision).
	var glass_mat := _glass_material(COL_GLASS)
	_pane(body, "GlassFront", Vector3(inner.x, inner.y, GLASS_T), Vector3(0.0, FLOOR_TOP + inner.y * 0.5, half_d), glass_mat)
	_pane(body, "GlassBack",  Vector3(inner.x, inner.y, GLASS_T), Vector3(0.0, FLOOR_TOP + inner.y * 0.5, -half_d), glass_mat)
	_pane(body, "GlassRight", Vector3(GLASS_T, inner.y, inner.z), Vector3(half_w, FLOOR_TOP + inner.y * 0.5, 0.0), glass_mat)
	_pane(body, "GlassLeft",  Vector3(GLASS_T, inner.y, inner.z), Vector3(-half_w, FLOOR_TOP + inner.y * 0.5, 0.0), glass_mat)

	# Fischbecken: Wasserkörper ohne Kollision (das Tier "schwimmt" darin).
	if water:
		var water_h: float = inner.y * WATER_FILL
		var water_mesh := MeshInstance3D.new()
		water_mesh.name = "Water"
		var bm := BoxMesh.new()
		bm.size = Vector3(inner.x - 0.02, water_h, inner.z - 0.02)
		water_mesh.mesh = bm
		water_mesh.material_override = _glass_material(COL_WATER)
		water_mesh.position = Vector3(0.0, FLOOR_TOP + water_h * 0.5, 0.0)
		water_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(water_mesh)

	_build_sign(root, label, half_d + ZooLayout.FRAME + ZooLayout.PLINTH + SIGN_DISTANCE)

static func _build_sign(root: Node3D, label: String, sign_z: float) -> void:
	var sign_root := Node3D.new()
	sign_root.name = "Sign"
	sign_root.position = Vector3(0.0, 0.0, sign_z)
	root.add_child(sign_root)

	var bw: float = sign_width(label)
	var post_h: float = 1.4  # reicht unter die Erde (Gelände vor dem Sockel kann tiefer liegen)
	var post_x: float = bw * 0.5 - SIGN_POST
	for sx in [-1.0, 1.0]:
		_visual_box(sign_root, "SignPost", Vector3(SIGN_POST, post_h, SIGN_POST), Vector3(sx * post_x, SIGN_CENTER_Y + SIGN_BOARD_H * 0.5 - post_h * 0.5, 0.0), COL_WOOD_DARK)
	_visual_box(sign_root, "SignBoard", Vector3(bw, SIGN_BOARD_H, SIGN_BOARD_T), Vector3(0.0, SIGN_CENTER_Y, 0.0), COL_WOOD)

	var text := Label3D.new()
	text.name = "SignText"
	text.text = label
	text.font_size = LABEL_FONT_SIZE
	text.pixel_size = LABEL_PIXEL_SIZE
	text.modulate = COL_SIGN_TEXT
	text.outline_size = 6
	text.outline_modulate = Color(0.10, 0.06, 0.02)
	text.shaded = false
	text.double_sided = false
	text.position = Vector3(0.0, SIGN_CENTER_Y, SIGN_BOARD_T * 0.5 + 0.004)
	sign_root.add_child(text)

# ─────────────────────────────────────────────
# Grundbausteine
# ─────────────────────────────────────────────

static func _opaque_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	return m

static func _glass_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic_specular = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

## Box mit Mesh + (optional) Kollision unter einem StaticBody3D.
static func _box(body: StaticBody3D, node_name: String, size: Vector3, pos: Vector3, color: Color, collide: bool) -> void:
	var inst := _mesh_box(node_name, size, pos, _opaque_material(color))
	body.add_child(inst)
	if collide:
		_add_collision(body, size, pos)

static func _pane(body: StaticBody3D, node_name: String, size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var inst := _mesh_box(node_name, size, pos, mat)
	body.add_child(inst)
	_add_collision(body, size, pos)

## Box nur zur Optik (Schild) unter einem normalen Node3D.
static func _visual_box(parent: Node3D, node_name: String, size: Vector3, pos: Vector3, color: Color) -> void:
	parent.add_child(_mesh_box(node_name, size, pos, _opaque_material(color)))

static func _mesh_box(node_name: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.name = node_name
	var bm := BoxMesh.new()
	bm.size = size
	inst.mesh = bm
	inst.material_override = mat
	inst.position = pos
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return inst

static func _add_collision(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = pos
	body.add_child(col)

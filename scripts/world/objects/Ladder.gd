class_name Ladder
extends Node3D

## Ladder — die 3D-ANSICHT einer Leiter (Wahrheit: LadderRegistry).
##
## Spawn-Config: {key: String, record: Dictionary}. Position = Fußpunkt der Leiter; die Geometrie
## liegt relativ dazu (Linienzug aus LadderPath). Klettern läuft NICHT über diesen Node,
## sondern über LadderRegistry/PlayerLadder (positionsbasiert, deterministisch).
## Interaktion: "Leiter abbauen" → EventBus ladder_remove_requested → WorldService.
## Nicht gepoolt (Geometrie ist pro Leiter einmalig, siehe EntityOrchestrator).

const LOG_CAT := "Ladder"
const ACTION_REMOVE: String = "remove_ladder"
const RAIL_HALF: float = 0.035
const RAIL_OFFSET: float = 0.30
const RUNG_HALF: float = 0.025
const RUNG_SPACING: float = 0.35
const COL_RAIL := Color(0.42, 0.28, 0.15)
const COL_RUNG := Color(0.55, 0.38, 0.20)

var _ctx: IEntityContext = null
var _key: String = ""
var _interactable_comp: InteractableComponent = null
var _mesh: MeshInstance3D = null

func _ready() -> void:
	set_multiplayer_authority(1)
	if name == get_class() or name.begins_with("@"):
		name = "Ladder_%d" % (get_instance_id() % 9999)
	_setup_interactable()

func on_spawn(cfg: Dictionary = {}, ctx: IEntityContext = null) -> void:
	_ctx = ctx
	_key = String(cfg.get("key", ""))
	if is_instance_valid(_interactable_comp):
		_interactable_comp.inject_context(_ctx)
	if is_instance_valid(_mesh):
		remove_child(_mesh)
		_mesh.free()
		_mesh = null
	var rec: Dictionary = cfg.get("record", {}) as Dictionary
	var path: LadderPath = LadderPath.from_record(rec)
	if path == null:
		AppLogger.log_error("Leiter '%s': ungültiger Record — keine Ansicht." % _key, LOG_CAT)
		return
	_mesh = MeshInstance3D.new()
	_mesh.mesh = build_mesh(path, Vector3(float(rec["x"]), float(rec["y"]), float(rec["z"])))
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = mat
	add_child(_mesh)

func on_despawn() -> void:
	if is_instance_valid(_interactable_comp):
		_interactable_comp.disconnect_world_events()

func get_ladder_key() -> String:
	return _key

## Baut Schienen + Sprossen als EIN Mesh. Punkte relativ zu `origin` (dem Entity-Ursprung).
static func build_mesh(path: LadderPath, origin: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var side: Vector3 = path.wall_dir.cross(Vector3.UP).normalized()
	for i in range(path.points.size() - 1):
		var a: Vector3 = path.points[i] - origin
		var b: Vector3 = path.points[i + 1] - origin
		var seg: Vector3 = b - a
		var seg_len: float = seg.length()
		if seg_len < 0.01:
			continue
		var u: Vector3 = seg / seg_len
		var x_axis: Vector3 = (side - u * side.dot(u)).normalized()
		var z_axis: Vector3 = x_axis.cross(u)
		var mid: Vector3 = (a + b) * 0.5
		_add_box(st, mid + x_axis * RAIL_OFFSET, x_axis, u, z_axis, Vector3(RAIL_HALF, seg_len * 0.5, RAIL_HALF), COL_RAIL)
		_add_box(st, mid - x_axis * RAIL_OFFSET, x_axis, u, z_axis, Vector3(RAIL_HALF, seg_len * 0.5, RAIL_HALF), COL_RAIL)
		var n: int = maxi(1, roundi(seg_len / RUNG_SPACING))
		for k in range(n):
			var t: float = (float(k) + 0.5) / float(n)
			_add_box(st, a + seg * t, x_axis, u, z_axis, Vector3(RAIL_OFFSET, RUNG_HALF, RUNG_HALF), COL_RUNG)
	return st.commit()

## Quader mit Halbmaßen `half` entlang der Achsen X/Y/Z (rechtshändig, Z = X × Y).
## Flächen im Uhrzeigersinn von außen gesehen (Godot-Frontface).
static func _add_box(st: SurfaceTool, c: Vector3, x: Vector3, y: Vector3, z: Vector3, half: Vector3, col: Color) -> void:
	var hx: Vector3 = x * half.x
	var hy: Vector3 = y * half.y
	var hz: Vector3 = z * half.z
	_add_face(st, c + hx, hy, hz, x, col)
	_add_face(st, c - hx, hz, hy, -x, col)
	_add_face(st, c + hy, hz, hx, y, col)
	_add_face(st, c - hy, hx, hz, -y, col)
	_add_face(st, c + hz, hx, hy, z, col)
	_add_face(st, c - hz, hy, hx, -z, col)

static func _add_face(st: SurfaceTool, c: Vector3, e1: Vector3, e2: Vector3, n: Vector3, col: Color) -> void:
	var v: Array[Vector3] = [c - e1 - e2, c - e1 + e2, c + e1 + e2, c + e1 - e2]
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(v[idx])

func _setup_interactable() -> void:
	var d := InteractableData.new()
	d.id = ACTION_REMOVE
	d.label = "Leiter abbauen"
	d.duration = 1.2
	d.xp_type = "none"
	d.xp_amount = 0
	d.loot_table = null
	d.inspect_text = ""
	_interactable_comp = InteractableComponent.new()
	_interactable_comp.data = d
	add_child(_interactable_comp)
	_interactable_comp.interacted.connect(_on_interacted)

func _on_interacted(action_id: String, peer_id: int) -> void:
	if action_id != ACTION_REMOVE or not is_multiplayer_authority():
		return
	if not is_instance_valid(_ctx):
		return
	var network: NetworkBridge = _ctx.get_network_bridge()
	var player_id: String = network.get_player_id_for_peer(peer_id) if is_instance_valid(network) else ""
	var bus: IEventBus = _ctx.get_event_bus()
	if player_id.is_empty() or bus == null:
		AppLogger.log_warn("Leiter abbauen: player_id/EventBus nicht verfügbar.", LOG_CAT)
		return
	bus.world().emit_ladder_remove_requested(player_id, _key)

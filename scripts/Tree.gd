extends Node3D

const InteractableScript := preload("res://scripts/Interactable.gd")

@export var tree_type: String = "normal"
@export var respawn_time: float = 10.0

# Datenstruktur muss exakt zu den Abfragen unten passen
const TREE_DATA: Dictionary = {
	"normal": { "id": "log_normal", "xp": 25, "req_level": 1,  "time": 3.0, "color": Color(0.1, 0.4, 0.1) },
	"oak":    { "id": "log_oak",    "xp": 45, "req_level": 15, "time": 5.0, "color": Color(0.05, 0.3, 0.05) }
}

var _data: Dictionary
var _visuals: Node3D
var _interactable: Node3D
var _is_felled: bool = false

func _ready() -> void:
	_data = TREE_DATA.get(tree_type, TREE_DATA["normal"])
	_build_tree_visuals()
	_setup_interactable()

func _build_tree_visuals() -> void:
	if _visuals: _visuals.queue_free()
	_visuals = Node3D.new()
	add_child(_visuals)

	# Stamm
	var trunk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.2; cyl.bottom_radius = 0.25; cyl.height = 1.8
	trunk.mesh = cyl
	var m1 := StandardMaterial3D.new()
	m1.albedo_color = Color(0.4, 0.2, 0.1)
	trunk.material_override = m1
	trunk.position.y = 0.9
	_visuals.add_child(trunk)

	# KRONE
	var crown := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.2; sphere.height = 2.4
	crown.mesh = sphere
	var m2 := StandardMaterial3D.new()
	m2.albedo_color = _data["color"]
	crown.material_override = m2
	crown.position.y = 2.5
	_visuals.add_child(crown)

	# Kollision für den Spieler (damit man nicht durchläuft)
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var caps := CapsuleShape3D.new()
	caps.radius = 0.3; caps.height = 1.8
	col.shape = caps
	col.position.y = 0.9
	body.add_child(col)
	_visuals.add_child(body)

func _setup_interactable() -> void:
	_interactable = Node3D.new()
	_interactable.set_script(InteractableScript)
	_interactable.interaction_label = "Fällen"
	_interactable.interaction_time = _data["time"]
	# Wichtig: Radius muss groß genug sein!
	_interactable.interaction_radius = 3.5 
	add_child(_interactable)
	_interactable.interaction_completed.connect(_on_chopped)

func _on_chopped(_src, _res) -> void:
	if _is_felled: return
	
	var ss = get_tree().get_first_node_in_group("skill_system")
	var inv = get_tree().get_first_node_in_group("inventory_system")
	
	# Hier muss _data["req_level"] stehen, passend zum Dictionary oben!
	if ss and ss.meets_requirement("woodcutting", _data["req_level"]):
		ss.add_xp("woodcutting", _data["xp"])
		if inv: 
			inv.add_item(_data["id"], 1)
		_start_respawn()
	else:
		print("Level zu niedrig oder SkillSystem fehlt!")

func _start_respawn() -> void:
	_is_felled = true
	_visuals.visible = false
	# Deaktiviert Kollision und Logik während er weg ist
	_visuals.process_mode = PROCESS_MODE_DISABLED 
	
	await get_tree().create_timer(respawn_time).timeout
	
	_is_felled = false
	_visuals.visible = true
	_visuals.process_mode = PROCESS_MODE_INHERIT
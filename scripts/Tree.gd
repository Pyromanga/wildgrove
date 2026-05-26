extends Node3D
## Tree.gd — Interagierbarer Baum
## Gibt Holzfällen-XP und log_normal ins Inventar

const InteractableScript := preload("res://scripts/Interactable.gd")

# Welches Holz & XP abhängig vom Baum-Typ
@export var tree_type: String = "normal"  # normal, oak, willow, maple

const TREE_DATA: Dictionary = {
	"normal": { "item": "log_normal", "xp": 25,  "req_level": 1,  "time": 4.0,
				"label": "Baum fällen", "color": Color(0.12, 0.48, 0.15) },
	"oak":    { "item": "log_oak",    "xp": 37,  "req_level": 15, "time": 6.0,
				"label": "Eiche fällen", "color": Color(0.08, 0.38, 0.10) },
	"willow": { "item": "log_willow", "xp": 67,  "req_level": 30, "time": 8.0,
				"label": "Weide fällen", "color": Color(0.15, 0.55, 0.20) },
	"maple":  { "item": "log_maple",  "xp": 100, "req_level": 45, "time": 12.0,
				"label": "Ahorn fällen", "color": Color(0.05, 0.28, 0.08) },
}

var _interactable: Node
var _data: Dictionary


func _ready() -> void:
	_data = TREE_DATA.get(tree_type, TREE_DATA["normal"])
	_build_mesh()
	_setup_interactable()


func _build_mesh() -> void:
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius    = 0.15
	tm.bottom_radius = 0.22
	tm.height        = 1.8
	trunk.mesh = tm
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.35, 0.22, 0.1)
	trunk.material_override = tmat
	trunk.position.y = 0.9
	add_child(trunk)

	var crown := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.1
	sm.height = 1.6
	crown.mesh = sm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = _data["color"]
	crown.material_override = cmat
	crown.position.y = 2.5
	add_child(crown)

	var body := StaticBody3D.new()
	var col  := CollisionShape3D.new()
	var caps := CapsuleShape3D.new()
	caps.radius = 0.22
	caps.height = 1.8
	col.shape = caps
	col.position.y = 0.9
	body.add_child(col)
	add_child(body)


func _setup_interactable() -> void:
	_interactable = Node3D.new()
	_interactable.set_script(InteractableScript)
	_interactable.interaction_label  = _data["label"]
	_interactable.interaction_radius = 2.5
	_interactable.requires_tool      = "axe"
	_interactable.interaction_time   = _data["time"]
	add_child(_interactable)
	_interactable.interaction_completed.connect(_on_chopped)
	_interactable.interaction_failed.connect(_on_failed)


func _on_chopped(_src: Node3D, _result: Dictionary) -> void:
	# Level-Check
	var skill_nodes: Array = get_tree().get_nodes_in_group("skill_system")
	if skill_nodes.size() > 0:
		var ss: Node = skill_nodes[0]
		if not ss.meets_requirement("woodcutting", _data["req_level"]):
			print("[Tree] Holzfällen Level %d benötigt!" % _data["req_level"])
			return
		ss.add_xp("woodcutting", _data["xp"])

	# Item ins Inventar
	var inv_nodes: Array = get_tree().get_nodes_in_group("inventory_system")
	if inv_nodes.size() > 0:
		inv_nodes[0].add_item(_data["item"], 1)

	# Visuelles Feedback
	var tween := create_tween()
	tween.tween_property(self, "rotation:z", deg_to_rad(8),  0.1)
	tween.tween_property(self, "rotation:z", deg_to_rad(-4), 0.1)
	tween.tween_property(self, "rotation:z", 0.0,            0.15)

	print("[Tree] %s +1, Holzfällen +%d XP" % [_data["item"], _data["xp"]])


func _on_failed(_src: Node3D, reason: String) -> void:
	print("[Tree] ", reason)

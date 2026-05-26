extends Node3D
## Tree.gd — Interagierbarer Baum

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
				"label": "Ahorn fällen", "color": Color(0.05, 0.25, 0.08) }
}

var _data: Dictionary
var _interactable: Node3D


func _ready() -> void:
	_data = TREE_DATA.get(tree_type, TREE_DATA["normal"])
	_build_visuals()
	_setup_interactable()


func _build_visuals() -> void:
	# Stamm
	var body := StaticBody3D.new()
	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.2
	cyl.bottom_radius = 0.25
	cyl.height = 1.8
	mesh_inst.mesh = cyl
	
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.24, 0.08)
	mesh_inst.material_override = mat
	mesh_inst.position.y = 0.9
	body.add_child(mesh_inst)
	
	var col := CollisionShape3D.new()
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
	# 1. Level-Check (MUSS zuerst kommen!)
	var skill_nodes: Array = get_tree().get_nodes_in_group("skill_system")
	if skill_nodes.size() > 0:
		var ss: Node = skill_nodes[0]
		if not ss.meets_requirement("woodcutting", _data["req_level"]):
			print("[Tree] Holzfällen Level %d benötigt! Du hast Level %d" % [_data["req_level"], ss.get_level("woodcutting")])
			return
		
		# Erst wenn das Level stimmt, gibt es XP
		ss.add_xp("woodcutting", _data["xp"])
	else:
		print("[Tree] Warnung: Kein SkillSystem gefunden.")

	# 2. Item ins neue Inventar-System legen
	var inv_nodes: Array = get_tree().get_nodes_in_group("inventory_system")
	if inv_nodes.size() > 0:
		var inv: Node = inv_nodes[0]
		if inv.has_method("add_item"):
			inv.add_item(_data["item"], 1)
	else:
		print("[Tree] Fehler: Kein InventorySystem in Gruppe 'inventory_system' gefunden!")

	# 3. Baum zerstören / entfernen
	queue_free()


func _on_failed(_src: Node3D, reason: String) -> void:
	print("[Tree] Interaktion fehlgeschlagen: ", reason)
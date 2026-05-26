extends Node3D
## Tree.gd — Beispiel-Interactable: Baum
## Erbt Interactable-Logik, gibt Holz und XP

const InteractableScript := preload("res://scripts/Interactable.gd")

var _interactable: Node


func _ready() -> void:
	_build_mesh()
	_setup_interactable()


func _build_mesh() -> void:
	# Stamm
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.15
	tm.bottom_radius = 0.22
	tm.height = 1.8
	trunk.mesh = tm
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.35, 0.22, 0.1)
	trunk.material_override = tmat
	trunk.position.y = 0.9
	add_child(trunk)

	# Krone
	var crown := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.1
	sm.height = 1.6
	crown.mesh = sm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.12, 0.48, 0.15)
	crown.material_override = cmat
	crown.position.y = 2.5
	add_child(crown)

	# Kollision
	var body := StaticBody3D.new()
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
	_interactable.interaction_label   = "Baum fällen"
	_interactable.interaction_radius  = 2.5
	_interactable.requires_tool       = "axe"
	_interactable.interaction_time    = 4.0
	add_child(_interactable)

	_interactable.interaction_completed.connect(_on_chopped)
	_interactable.interaction_failed.connect(_on_failed)


func _on_chopped(_src: Node3D, _result: Dictionary) -> void:
	# SkillSystem XP geben
	var skill_nodes: Array = get_tree().get_nodes_in_group("skill_system")
	# Inventar-Item hinzufügen
	if Engine.has_singleton("InventorySystem"):
		InventorySystem.add_item("log_normal", 1)
	# Visuelles Feedback — Baum wackelt kurz
	var tween := create_tween()
	tween.tween_property(self, "rotation:z", deg_to_rad(5), 0.1)
	tween.tween_property(self, "rotation:z", 0.0, 0.1)
	print("[Tree] Gefällt! log_normal +1")


func _on_failed(_src: Node3D, reason: String) -> void:
	print("[Tree] Interaktion fehlgeschlagen: ", reason)

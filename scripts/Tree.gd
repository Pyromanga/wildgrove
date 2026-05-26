extends Node3D
## Tree.gd — Nutzt die neue Architektur

const InteractableScript := preload("res://scripts/Interactable.gd")

@export var tree_type: String = "normal"
var _data: Dictionary

const TREE_DATA = {
	"normal": {"xp": 25, "level": 1, "time": 3.0, "color": Color(0.1, 0.4, 0.1)},
	"oak":    {"xp": 50, "level": 5, "time": 5.0, "color": Color(0.05, 0.3, 0.05)}
}

func _ready() -> void:
	_data = TREE_DATA.get(tree_type, TREE_DATA["normal"])
	_build_visuals()
	_add_interact_logic()

func _build_visuals() -> void:
	# Einfacher Stamm
	var trunk = MeshInstance3D.new()
	trunk.mesh = CylinderMesh.new(); trunk.mesh.height = 2.0; trunk.mesh.top_radius = 0.2
	var mat = StandardMaterial3D.new(); mat.albedo_color = Color(0.4, 0.2, 0.1)
	trunk.material_override = mat; trunk.position.y = 1.0
	add_child(trunk)

func _add_interact_logic() -> void:
	# Wir erstellen die Interactable-Komponente
	var interactable = Node3D.new()
	interactable.set_script(InteractableScript)
	interactable.label = "Fällen (" + tree_type + ")"
	interactable.duration = _data["time"]
	add_child(interactable)
	
	# Hier verbinden wir das Signal der Komponente mit der Baum-Logik
	interactable.completed.connect(_on_tree_cut)

func _on_tree_cut() -> void:
	# Der Baum sagt dem Bus: "Gib XP!"
	GameEvents.emit_xp("woodcutting", _data["xp"])
	GameEvents.log(tree_type + " gefällt!")
	
	# Visuelles Feedback: Baum verstecken (Respawn-Logik kann später rein)
	visible = false
	process_mode = PROCESS_MODE_DISABLED
	await get_tree().create_timer(10.0).timeout
	visible = true
	process_mode = PROCESS_MODE_INHERIT
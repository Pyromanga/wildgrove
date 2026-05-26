extends Node3D
## World.gd — Baut die 3D-Welt stabil auf

const TreeScript := preload("res://scripts/Tree.gd")

func _ready() -> void:
	_build_lighting()
	_build_terrain()
	_build_props()

func _build_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true # Ein bisschen Schatten hilft bei der Orientierung
	add_child(sun)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.4, 0.6, 0.9) # Ein schöneres Himmel-Blau
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.5
	env_node.environment = env
	add_child(env_node)

func _build_terrain() -> void:
	# Boden-Physik
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1.0, 200) # Etwas dickerer Boden ist stabiler
	col.shape = shape
	body.position.y = -0.5 # Oberfläche bleibt bei Y=0
	body.add_child(col)
	add_child(body)

	# Boden-Optik
	var mesh_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	mesh_inst.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.5, 0.2) # Saftiges Grün
	mesh_inst.material_override = mat
	add_child(mesh_inst)

func _build_props() -> void:
	var tree_positions: Array[Vector3] = [
		Vector3(5, 0, 5),   Vector3(-6, 0, 4),
		Vector3(8, 0, -5),  Vector3(-4, 0, -8),
		Vector3(12, 0, 2),  Vector3(-3, 0, 10),
	]
	
	for i in range(tree_positions.size()):
		var pos = tree_positions[i]
		var tree := Node3D.new()
		tree.name = "Tree_" + str(i)
		tree.set_script(TreeScript)
		tree.position = pos
		add_child(tree)
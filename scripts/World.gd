extends Node3D
## World.gd — Baut die 3D-Welt stabil auf

func _ready() -> void:
	_build_lighting()
	_build_terrain()
	_build_props()

func _build_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.4, 0.6, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.5
	env_node.environment = env
	add_child(env_node)

func _build_terrain() -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1.0, 200)
	col.shape = shape
	body.position.y = -0.5
	body.add_child(col)
	add_child(body)

	var mesh_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	mesh_inst.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.5, 0.2)
	mesh_inst.material_override = mat
	add_child(mesh_inst)

func _build_props() -> void:
	var tree_positions: Array[Vector3] = [
		Vector3(5, 0, 5),   Vector3(-6, 0, 4),
		Vector3(8, 0, -5),  Vector3(-4, 0, -8),
		Vector3(12, 0, 2),  Vector3(-3, 0, 10),
	]
	for pos in tree_positions:
		Kernel.world_factory.create_tree(pos, self)
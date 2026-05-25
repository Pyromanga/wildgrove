extends Node3D
## World.gd — Baut die 3D-Welt
## Zuständig für: Himmel, Licht, Boden, Platzhalter-Objekte
## Später: Welt-Generierung, Biome, Zonen

func _ready() -> void:
	_build_lighting()
	_build_terrain()
	_build_props()


func _build_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 1.2
	add_child(sun)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.3, 0.6, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.8
	env_node.environment = env
	add_child(env_node)


func _build_terrain() -> void:
	# Kollisions-Body
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 0.2, 200)
	col.shape = shape
	body.position.y = -0.1
	body.add_child(col)
	add_child(body)

	# Sichtbares Mesh
	var mesh_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	mesh_inst.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.6, 0.2)
	mesh_inst.material_override = mat
	add_child(mesh_inst)


func _build_props() -> void:
	# Platzhalter-Objekte (später: echte Bäume, Felsen, etc.)
	var positions: Array[Vector3] = [
		Vector3(5, 1, 5),   Vector3(-6, 1, 4),
		Vector3(8, 1, -5),  Vector3(-4, 1, -8),
		Vector3(3, 1, -3),  Vector3(-9, 1, 6),
		Vector3(12, 1, 2),  Vector3(-3, 1, 10),
	]
	for pos in positions:
		_spawn_box(pos)


func _spawn_box(pos: Vector3) -> void:
	var body := StaticBody3D.new()

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.5, 2.0, 1.5)
	col.shape = shape
	body.add_child(col)

	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.5, 2.0, 1.5)
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.42, 0.1)
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)

	body.position = pos
	add_child(body)

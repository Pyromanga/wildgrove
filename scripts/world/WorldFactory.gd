extends RefCounted
class_name WorldFactory

func create_world() -> Node3D:
	Logger.log_debug("create_world() start", "WorldFactory")
	var world := Node3D.new()
	world.name = "World"
	
	_add_environment(world)
	_add_ground(world)
	_add_player(world, Vector3(0, 1, 0))
	_add_trees(world, [Vector3(5, 0, 5), Vector3(-6, 0, 4)])
	
	Logger.log_debug("create_world() fertig", "WorldFactory")
	return world

func _add_environment(world: Node3D) -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	world.add_child(sun)

	var env_node := WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.2, 0.5, 0.9)
	sky_mat.sky_horizon_color = Color(0.6, 0.8, 1.0)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env_node.environment = env
	world.add_child(env_node)
	Logger.log_debug("Environment OK", "WorldFactory")

func _add_ground(world: Node3D) -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100, 0.2, 100)
	col.shape = shape
	ground.add_child(col)

	var mesh_inst := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(100, 0.2, 100)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.6, 0.25)
	mesh_inst.mesh = mesh
	mesh_inst.material_override = mat
	ground.add_child(mesh_inst)

	ground.position.y = -0.1
	world.add_child(ground)
	Logger.log_debug("Boden OK", "WorldFactory")

func _add_player(world: Node3D, pos: Vector3) -> void:
	var PlayerScript = load("res://scripts/player/Player.gd")
	if not PlayerScript:
		Logger.log_error("Player.gd fehlt!", "WorldFactory")
		return

	var player := CharacterBody3D.new()
	player.set_script(PlayerScript) 
	player.name = "Player"
	player.position = pos
	player.add_to_group("player") 
	world.add_child(player)
	Logger.log_debug("Player OK.", "WorldFactory")

func _add_trees(world: Node3D, positions: Array) -> void:
	# Wir laden das Skript für die Eiche
	var OakScript = load("res://scripts/world/objects/OakTree.gd")
	
	for pos in positions:
		# Wir erstellen einen einfachen Node3D als Container
		var tree = Node3D.new()
		tree.name = "OakTree"
		tree.position = pos
		
		# Wir hängen das OakTree-Skript ran. 
		# Dieses Skript (das du vorhin gepostet hast) erledigt den Rest:
		# 1. Es ruft Kernel.factory3d auf für die Grafik.
		# 2. Es erstellt die InteractableComponent.
		tree.set_script(OakScript)
		
		world.add_child(tree)
	
	Logger.log_debug(str(positions.size()) + " Bäume via Komponenten-System erstellt.", "WorldFactory")
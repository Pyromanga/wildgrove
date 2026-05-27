extends Node
## WorldFactory.gd — Zentrale Fabrik für die 3D-Welt

func create_world() -> Node3D:
	# Wir erstellen das World-Objekt und hängen das Skript an
	var world = Node3D.new()
	world.set_script(load("res://scripts/World.gd"))
	world.name = "World"
	
	# Initialisierung der Welt-Komponenten
	_build_lighting(world)
	_build_terrain(world)
	_build_props(world)
	
	create_player(world)
	
	Kernel.events.log("WorldFactory: Welt vollständig konfiguriert.")
	return world

func _build_lighting(parent: Node) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	parent.add_child(sun)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.4, 0.6, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.5
	env_node.environment = env
	parent.add_child(env_node)

func _build_terrain(parent: Node) -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1.0, 200)
	col.shape = shape
	body.position.y = -0.5
	body.add_child(col)
	parent.add_child(body)

	var mesh_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	mesh_inst.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.5, 0.2)
	mesh_inst.material_override = mat
	parent.add_child(mesh_inst)

func _build_props(parent: Node) -> void:
	var tree_positions: Array[Vector3] = [
		Vector3(5, 0, 5),   Vector3(-6, 0, 4),
		Vector3(8, 0, -5),  Vector3(-4, 0, -8),
		Vector3(12, 0, 2),  Vector3(-3, 0, 10),
	]
	for pos in tree_positions:
		create_tree(pos, parent)

func create_tree(pos: Vector3, parent: Node) -> void:
	var tree = Node3D.new()
	tree.name = "Tree"
	tree.set_script(load("res://scripts/Tree.gd"))
	tree.position = pos
	parent.add_child(tree)

func create_player(parent: Node) -> void:
    var player = CharacterBody3D.new() # Oder deine Player.tscn: load("res://scenes/Player.tscn").instantiate()
    player.name = "Player"    # WICHTIG: Hier setzt du den Namen für den Test!
    player.set_script(load("res://scripts/Player.gd"))
    player.position = Vector3(0, 1, 0)
    parent.add_child(player)
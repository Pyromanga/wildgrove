extends RefCounted
class_name WorldFactory # <--- DAS FEHLTE!

func create_world() -> Node3D:
	Logger.log_debug("create_world() start", "WorldFactory")
	var world := Node3D.new()
	world.name = "World"
	
	# Hier rufen wir deine Hilfsmethoden auf
	_add_environment(world)
	_add_ground(world)
	_add_player(world, Vector3(0, 1, 0))
	_add_trees(world, [Vector3(5, 0, 5), Vector3(-6, 0, 4)])
	
	Logger.log_debug("create_world() fertig", "WorldFactory")
	return world

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
	var TreeScript = load("res://scripts/world/objects/OakTree.gd")
	for i in positions.size():
		var tree := Node3D.new()
		tree.set_script(TreeScript)
		tree.position = positions[i]
		world.add_child(tree)
		tree.add_to_group("interactable")
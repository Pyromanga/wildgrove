extends CharacterBody3D
## Player.gd

func try_interact() -> void:
	var interactables = get_tree().get_nodes_in_group("interactable")
	var closest: Node3D = null
	var closest_dist: float = 4.0 

	for node in interactables:
		if node is Node3D:
			var d = global_position.distance_to(node.global_position)
			if d < closest_dist:
				closest_dist = d
				closest = node

	if closest and closest.has_method("interact"):
		closest.interact(self)

func _physics_process(_delta: float) -> void:
	# Deine Bewegungslogik hier...
	move_and_slide()
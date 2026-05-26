func get_touch_node() -> Node:
	var nodes = get_tree().get_nodes_in_group("touch_input")
	return nodes[0] if nodes.size() > 0 else null

func calculate_move_direction(camera_arm: Node3D, input: Vector2) -> Vector3:
	var basis = camera_arm.global_transform.basis
	var forward = Vector3(-basis.z.x, 0, -basis.z.z).normalized()
	var right = Vector3(basis.x.x, 0, basis.x.z).normalized()
	return (forward * -input.y + right * input.x).normalized()

func get_closest_node(origin: Vector3, group: String, max_dist: float) -> Node3D:
	var nodes = get_tree().get_nodes_in_group(group)
	var closest: Node3D = null
	var min_d = max_dist
	for n in nodes:
		var d = origin.distance_to(n.global_position)
		if d < min_d:
			min_d = d
			closest = n
	return closest
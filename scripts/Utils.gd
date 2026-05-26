extends Node

# Die klassische RuneScape-Levelformel
func get_xp_for_level(level: int) -> int:
	return int(pow(level, 2) * 100)

# Sucht das nächste Objekt in einer Gruppe
func get_closest_node(origin: Vector3, group_name: String, max_dist: float) -> Node3D:
	var nodes = get_tree().get_nodes_in_group(group_name)
	var closest: Node3D = null
	var min_d = max_dist
	
	for n in nodes:
		var d = origin.distance_to(n.global_position)
		if d < min_d:
			min_d = d
			closest = n
	return closest
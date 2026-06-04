# scripts/player/interaction_sensor.gd
class_name InteractionSensor extends Area3D


func get_closest() -> Node:
	var bodies = get_overlapping_bodies()
	var closest = null
	var min_dist = 999.0
	for b in bodies:
		if b.is_in_group("interactable"):
			var dist = global_position.distance_to(b.global_position)
			if dist < min_dist:
				min_dist = dist
				closest = b
	return closest

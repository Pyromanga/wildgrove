extends Node
## Utils.gd — Mathematische Hilfsfunktionen

## Sucht den nächsten Knoten in einer Gruppe
## Optimierung: Wir übergeben die Liste der Knoten direkt, wenn wir sie schon haben,
## um nicht jedes Mal den ganzen Baum zu durchsuchen.
func get_closest_node_from_list(origin: Vector3, nodes: Array, max_dist: float) -> Node3D:
	var closest: Node3D = null
	var min_d = max_dist
	for n in nodes:
		var d = origin.distance_to(n.global_position)
		if d < min_d:
			min_d = d
			closest = n
	return closest

## Kamera-relative Bewegung berechnen
func calculate_move_direction(camera_arm: Node3D, input: Vector2) -> Vector3:
	if not camera_arm: return Vector3.ZERO
	var basis = camera_arm.global_transform.basis
	var forward = Vector3(-basis.z.x, 0, -basis.z.z).normalized()
	var right = Vector3(basis.x.x, 0, basis.x.z).normalized()
	return (forward * -input.y + right * input.x).normalized()

## Touch-Input holen
func get_touch_input() -> Node:
	# Wir nutzen den Kernel, um die Instanz zu finden, falls sie registriert wurde
	# oder wir bleiben bei der Gruppensuche
	var nodes = get_tree().get_nodes_in_group("touch_input")
	return nodes[0] if nodes.size() > 0 else null
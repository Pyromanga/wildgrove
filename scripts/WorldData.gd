# res://scripts/WorldData.gd
class_name WorldData

var tree_positions: Array[Vector3] = []
var player_position: Vector3 = Vector3.ZERO

func add_tree(pos: Vector3):
    tree_positions.append(pos)

# NEU: Das ist die Logik-Prüfung für deine Tests!
func get_tree_count() -> int:
    return tree_positions.size()
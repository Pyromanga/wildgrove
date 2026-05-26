extends Node
## UIFactory.gd

func create_ui_pos(x: float, y: float) -> Vector2:
	# Vector2 braucht exakt 2 Parameter
	return Vector2(x, y)

func create_world_pos(x: float, y: float, z: float) -> Vector3:
	# Vector3 braucht exakt 3 Parameter
	return Vector3(x, y, z)
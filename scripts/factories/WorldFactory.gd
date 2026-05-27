extends Node
## WorldFactory.gd — Erzeugt alles, was im 3D-Raum existiert

# --- Konstanten ---
const TREE_POSITIONS = [
	Vector3(3, 0, 2),
	Vector3(-4, 0, 5),
	Vector3(6, 0, -3),
	Vector3(-2, 0, -6),
	Vector3(8, 0, 1),
]

## Erstellt die komplette Spielwelt mit Terrain und Bäumen
func create_world() -> Node3D:
	var world = Node3D.new()
	world.name = "World"
	
	# Terrain
	var terrain = _create_terrain()
	world.add_child(terrain)
	
	# Bäume
	for pos in TREE_POSITIONS:
		create_tree(pos, world)
	
	Kernel.events.log("WorldFactory: Welt erstellt mit " + str(TREE_POSITIONS.size()) + " Bäumen.")
	return world

## Erstellt ein einfaches Terrain (Placeholder-Mesh)
func _create_terrain() -> Node3D:
	var terrain = Node3D.new()
	terrain.name = "Terrain"
	
	var mesh_instance = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(50, 50)
	mesh_instance.mesh = plane
	
	# Collision
	var body = StaticBody3D.new()
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(50, 0.1, 50)
	col.shape = shape
	body.add_child(col)
	
	terrain.add_child(mesh_instance)
	terrain.add_child(body)
	return terrain

## Spawnt einen Baum an der gegebenen Position
func create_tree(pos: Vector3, parent: Node) -> Node3D:
	var tree = Node3D.new()
	tree.name = "Tree"
	tree.set_script(load("res://scripts/Tree.gd"))  # Script VOR add_child
	tree.position = pos
	parent.add_child(tree)
	return tree

## Erstellt ein interagierbares Objekt
func create_interactable(pos: Vector3, parent: Node, type: String) -> Node3D:
	var obj = Node3D.new()
	obj.name = "Interactable_" + type
	obj.set_script(null)
	obj.position = pos
	parent.add_child(obj)
	
	var data = Kernel.data.get_tree_data(type)
	
	var on_finish = func():
		Kernel.events.emit_xp(type, data.get("xp", 10))
		obj.queue_free()
	
	Kernel.builder.create(obj)\
		.set_label(data.get("label", "Unbekannt"))\
		.set_duration(data.get("time", 2.0))\
		.on_complete(on_finish)\
		.build()
	
	return obj
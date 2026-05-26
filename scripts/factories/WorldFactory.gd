extends Node
## WorldFactory.gd — Erzeugt alles, was im 3D-Raum existiert

## Hilfsfunktion für den schnellen Baum-Spawn
func create_tree(pos: Vector3, parent: Node) -> Node3D:
	var tree = Node3D.new()
	tree.position = pos
	parent.add_child(tree)
	tree.set_script(load("res://scripts/Tree.gd"))
	return tree

## Hilfsfunktion für Interaktionen
func create_interactable(pos: Vector3, parent: Node, type: String) -> Node3D:
	var obj = Node3D.new()
	obj.position = pos
	parent.add_child(obj)
	
	# Hole Daten aus dem DataService via Kernel
	var data = Kernel.data.get_tree_data(type)
	
	# Lambda-Funktion definiert, um den Code-Block sauber zu halten
	var on_finish = func(): 
		Kernel.events.emit_xp(type, data.get("xp", 10))
		obj.queue_free()
	
	# Nutze den Kernel.builder für die Logik-Konfiguration
	Kernel.builder.create(obj)\
		.set_label(data.get("label", "Unbekannt"))\
		.set_duration(data.get("time", 2.0))\
		.on_complete(on_finish)\
		.build()
		
	return obj
extends Node
## WorldFactory.gd — Erzeugt alles, was im 3D-Raum existiert

## Hilfsfunktion für den schnellen Baum-Spawn
func create_tree(pos: Vector3, parent: Node) -> Node3D:
	var tree = Node3D.new()
	tree.position = pos
	parent.add_child(tree)
	# Hier könntest du dein Tree-Script zuweisen
	tree.set_script(load("res://scripts/Tree.gd"))
	return tree

## Hilfsfunktion für Interaktionen (Erz, etc.)
func create_interactable(type: String, pos: Vector3, parent: Node) -> Node3D:
	var obj = Node3D.new()
	obj.position = pos
	parent.add_child(obj)
	# Konfiguration über den Builder, den wir jetzt über den Kernel steuern
	# Kernel.builder.create(obj)... (Falls du den Builder noch separat hältst)
	return obj
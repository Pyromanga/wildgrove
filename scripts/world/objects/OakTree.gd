# OakTree.gd
extends Node3D

func _ready() -> void:
	# 1. Grafik bauen
	Kernel.factory3d.create_simple_tree(self)
	
	# 2. Interaktions-Daten erstellen
	var d = InteractableData.new()
	d.id = "chop"
	d.label = "Eiche fällen"
	d.duration = 3.0
	d.xp_type = "woodcutting"
	d.xp_amount = 25
	d.drops = {"log_normal": 3}
	
	# 3. Komponente hinzufügen
	var comp = InteractableComponent.new()
	comp.data = d
	add_child(comp)

# Wird von der Komponente aufgerufen, wenn fertig
func _on_interacted(action_id: String) -> void:
	if action_id == "chop":
		# Respawn Logik hier...
		queue_free()
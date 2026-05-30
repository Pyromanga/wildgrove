extends InteractableObject

func _init() -> void:
    label = "Eiche fällen"
    duration = 3.5
    xp_type = "woodcutting"
    xp_amount = 25

func _setup_visuals() -> void:
    # Hier nutzt du jetzt die Factory über den Kernel!
    Kernel.factory3d.create_simple_tree(self)

# OakTree.gd
func _on_interaction_finished() -> void:
    # Neue Eiche nach 10 Sekunden an gleicher Position spawnen
    var pos = global_position
    var parent = get_parent()
    var timer = get_tree().create_timer(10.0)
    await timer.timeout
    var new_tree := Node3D.new()
    new_tree.set_script(load("res://scripts/world/objects/OakTree.gd"))
    new_tree.position = pos
    parent.add_child(new_tree)
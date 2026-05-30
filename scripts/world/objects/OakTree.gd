extends InteractableObject

func _init() -> void:
    label = "Eiche fällen"
    duration = 3.5
    xp_type = "woodcutting"
    xp_amount = 25

func _setup_visuals() -> void:
    Kernel.factory3d.create_simple_tree(self)

func _on_interaction_finished() -> void:
    var pos = global_position
    var parent = get_parent()
    var tree_script = load("res://scripts/world/objects/OakTree.gd")
    get_tree().create_timer(10.0).timeout.connect(
        func():
            if is_instance_valid(parent):
                var new_tree := Node3D.new()
                new_tree.set_script(tree_script)
                new_tree.position = pos
                parent.add_child(new_tree)
    )
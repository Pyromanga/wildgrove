extends InteractableObject

func _setup_visuals() -> void:
    Kernel.factory3d.create_simple_tree(self)

func _register_actions() -> void:
    default_action_id = "chop"

    var chop := InteractableAction.new("chop", "Eiche fällen")
    chop.duration  = 3.5
    chop.xp_type   = "woodcutting"
    chop.xp_amount = 25
    chop.drops     = { "log_normal": 3 }
    actions.append(chop)

    var inspect := InteractableAction.new("inspect", "Untersuchen")
    inspect.duration     = 0.5
    inspect.inspect_text = "Eine alte Eiche, etwa 50 Jahre alt."
    actions.append(inspect)

func _on_action_finished(action: InteractableAction) -> void:
    if action.id != "chop":
        return

    var pos            := global_position
    var parent         := get_parent()
    var tree_script    := load("res://scripts/world/objects/OakTree.gd")

    queue_free()  # sofort weg, Timer läuft unabhängig weiter

    get_tree().create_timer(10.0).timeout.connect(func():
        if not is_instance_valid(parent):
            Logger.log_debug("Respawn abgebrochen: Parent ungültig", "OakTree")
            return
        var new_tree       := Node3D.new()
        new_tree.set_script(tree_script)
        new_tree.position  = pos
        parent.add_child(new_tree)
        Logger.log_debug("Eiche nachgewachsen", "OakTree")
    )
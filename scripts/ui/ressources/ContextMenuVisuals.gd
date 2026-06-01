# ContextMenuController.gd
class_name ContextMenuController

func show(hud: CanvasLayer, actions: Array) -> void:
    # Aufräumen über die Gruppe
    for n in hud.get_tree().get_nodes_in_group("context_menu"): 
        n.queue_free()
    
    var visuals = ContextMenuVisuals.new(hud, actions)
    
    visuals.action_triggered.connect(func(action):
        visuals.destroy()
        Kernel.builder.execute_action(action)
    )
    
    hud.get_tree().create_timer(5.0).timeout.connect(func():
        if is_instance_valid(visuals): visuals.destroy()
    )
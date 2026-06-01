class_name ContextMenuController

func show(hud: CanvasLayer, actions: Array) -> void:
    # 1. Altes Menü weg
    for n in hud.get_tree().get_nodes_in_group("context_menu"): n.queue_free()
    
    # 2. Visuals bauen
    var visuals = ContextMenuVisuals.new(hud, actions)
    
    # 3. Klick verarbeiten
    visuals.action_triggered.connect(func(action):
        visuals.destroy()
        Kernel.builder.execute_action(action)
    )
    
    # 4. Timer (Logik)
    hud.get_tree().create_timer(5.0).timeout.connect(visuals.destroy)
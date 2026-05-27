extends "res://addons/gut/test.gd"

func test_interaction_executes_successfully():
    # 1. Setup: Stelle sicher, dass Kernel bereit ist
    if not Kernel.hud:
        Kernel.hud = CanvasLayer.new()
        add_child_autofree(Kernel.hud)
        
    var target = Node3D.new()
    add_child_autofree(target)
    
    var interaction_finished = false
    var task = Kernel.builder.create(target) \
        .set_duration(0.1) \
        .on_complete(func(): interaction_finished = true)
        
    Kernel.builder.execute_interaction(task)
    
    # 2. Warten: Timer + ein Frame Puffer
    await get_tree().create_timer(0.15).timeout
    await get_tree().process_frame 
    
    assert_true(interaction_finished, "Interaktion sollte fertig sein")
    
    # Cleanup
    Kernel.hud = null
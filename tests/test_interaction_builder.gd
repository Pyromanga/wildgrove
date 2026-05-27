extends "res://addons/gut/test.gd"

func test_interaction_executes_successfully():
    var target = Node3D.new()
    add_child_autofree(target)
    
    var interaction_finished = false
    var task = Kernel.builder.create(target) \
        .set_duration(0.1) \
        .on_complete(func(): interaction_finished = true)
        
    Kernel.builder.execute_interaction(task)
    
    # Warte kurz, bis der Tween/Timer fertig ist
    await get_tree().create_timer(0.2).timeout
    
    assert_true(interaction_finished, "Interaktion sollte nach der Zeit als 'done' markiert werden")
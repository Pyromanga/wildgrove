extends "res://addons/gut/test.gd"

func test_interaction_executes_successfully():
    var target = Node3D.new()
    add_child_autofree(target)
    
    var interaction_finished = false
    # Wir erstellen die Aufgabe und führen sie aus
    var task = Kernel.builder.create(target) \
        .set_duration(0.05) \
        .on_complete(func(): interaction_finished = true)
        
    Kernel.builder.execute_interaction(task)
    
    # Warte-Logik verbessern: 
    # Wir warten maximal 0.5 Sekunden auf das Flag, anstatt blind zu warten
    var time_passed = 0.0
    while not interaction_finished and time_passed < 0.5:
        await get_tree().process_frame
        time_passed += get_process_delta_time()
    
    assert_true(interaction_finished, "Interaktion sollte fertig sein")
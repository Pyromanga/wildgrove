extends "res://tests/IntegrationTest.gd"

func test_interaction_event_fires():
    # Setup
    var event_received = false
    Kernel.events.interaction_started.connect(func(_label, _dur): event_received = true)
    
    # Erstelle ein Node, das die Gruppen-Anforderungen erfüllt
    var target = Node3D.new()
    target.add_to_group("interactable")
    add_child_autofree(target)
    
    # Auslösen über den Kernel-Service
    # Da wir nun den echten Kernel nutzen, ist die builder-Referenz valide
    Kernel.builder.trigger_interaction(target) 
    
    # Warten auf Signal-Verarbeitung im nächsten Frame
    await get_tree().process_frame
    
    assert_true(event_received, "Das Signal wurde emittiert")
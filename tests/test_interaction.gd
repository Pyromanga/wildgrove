extends "res://addons/gut/test.gd"

func test_interaction_event_fires():
    var event_received = false
    # Signal-Bindung mit dem lokalen Event-Bus
    Kernel.events.interaction_started.connect(func(_label, _dur): event_received = true)
    
    # NEU: Wir erstellen ein echtes Node, das interagierbar ist
    var target = Node3D.new()
    target.add_to_group("interactable")
    add_child_autofree(target)
    
    # WICHTIG: Ändere deinen InteractionBuilder (siehe unten), damit er 
    # nicht einen String, sondern das Node erwartet!
    Kernel.builder.trigger_interaction(target) 
    
    await get_tree().process_frame
    assert_true(event_received, "Das Signal wurde emittiert")
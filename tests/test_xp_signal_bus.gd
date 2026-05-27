extends "res://addons/gut/test.gd"

func test_xp_signal_propagation():
    var received_xp = 0
    Kernel.events.xp_gained.connect(func(skill, amt): received_xp = amt)
    
    Kernel.events.emit_xp("mining", 50)
    
    # Kurz warten, damit das Signal durch den Bus geht
    await get_tree().process_frame 
    
    assert_eq(received_xp, 50, "Signal wurde vom Bus nicht korrekt durchgereicht")
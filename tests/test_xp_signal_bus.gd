extends "res://tests/IntegrationTest.gd"

func test_xp_signal_propagation():
    var received_xp = 0
    
    # Da wir in einer Integration-Umgebung sind, nutzen wir den echten GameEvents Service
    # Wir verbinden uns mit dem zentralen Bus im Kernel
    Kernel.events.xp_gained.connect(func(skill, amt): received_xp = amt)
    
    # Event auslösen
    Kernel.events.emit_xp("mining", 50)
    
    # Warten, bis die Signal-Queue im nächsten Frame abgearbeitet wurde
    await get_tree().process_frame 
    
    assert_eq(received_xp, 50, "Signal wurde vom Bus nicht korrekt durchgereicht")
extends "res://addons/gut/test.gd"

func test_xp_signal_propagation():
    var received_xp = 0
    # Lambda-Funktion als Empfänger
    Kernel.events.xp_gained.connect(func(skill, amt): received_xp = amt)
    
    Kernel.events.emit_signal("xp_gained", "mining", 50)
    assert_eq(received_xp, 50, "Signal wurde nicht korrekt empfangen")
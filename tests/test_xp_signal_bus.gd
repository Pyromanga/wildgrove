extends "res://addons/gut/test.gd"

func test_xp_signal_propagation():
    var received_amt = 0
    
    # 1. Sicherstellen, dass der Event-Service da ist
    var bus = Kernel.events
    assert_not_null(bus, "Bus-Service fehlt im Kernel!")
    
    # 2. Verbinden EXAKT mit der Instanz aus dem Kernel
    bus.xp_gained.connect(func(_skill, amt): received_amt = amt)
    
    # 3. Emittieren über die Instanz aus dem Kernel
    bus.emit_xp("mining", 50)
    
    # 4. Prüfen
    assert_eq(received_amt, 50, "Signal wurde vom Bus nicht korrekt durchgereicht")
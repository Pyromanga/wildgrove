func test_signal_emission():
    var inv = Kernel.inventory
    var signal_received = false
    
    # Korrekte Syntax für Godot 4 Signale:
    inv.inventory_changed.connect(func(): signal_received = true)
    
    inv.add_item("log_oak", 1)
    
    # Sicherstellen, dass das Signal angekommen ist
    assert_true(signal_received, "Inventory-System sollte bei Änderungen das Signal senden")
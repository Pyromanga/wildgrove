extends "res://tests/IntegrationTest.gd"

func test_signal_emission():
    # Wir greifen direkt auf den vom Kernel verwalteten Service zu
    var inv = Kernel.inventory
    var signal_received = false
    
    # Signal-Verbindung
    inv.inventory_changed.connect(func(): signal_received = true)
    
    # Aktion ausführen
    inv.add_item("log_oak", 1)
    
    # WICHTIG: Das Signal wird im nächsten Frame verarbeitet
    await get_tree().process_frame
    
    # Assertion
    assert_true(signal_received, "Inventory-System sollte bei Änderungen das Signal senden")
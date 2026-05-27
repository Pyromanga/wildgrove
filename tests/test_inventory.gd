extends "res://tests/IntegrationTest.gd"

func before_each():
    # Wir nutzen den Kernel-Service direkt
    if Kernel.inventory != null:
        Kernel.inventory.clear_inventory()

func test_add_item():
    assert_not_null(Kernel.inventory, "Service nicht geladen!")
    Kernel.inventory.add_item("log_normal", 5)
    assert_eq(Kernel.inventory.get_quantity("log_normal"), 5)
    
func test_add_item_creates_new_entry():
    # Wir manipulieren direkt das Daten-Backend des Kernels
    Kernel.inventory._inventory_data = [] 
    
    Kernel.inventory.add_item("log_normal", 5)
    
    var items = Kernel.inventory.get_all_items()
    assert_eq(items.size(), 1, "Inventar sollte genau einen Eintrag haben")
    assert_eq(items[0]["quantity"], 5, "Menge sollte 5 sein")
    assert_eq(items[0]["item_id"], "log_normal", "Item-ID sollte 'log_normal' sein")

func test_add_item_stacks_existing():
    Kernel.inventory._inventory_data = [{ "item_id": "log_normal", "quantity": 5 }]
    
    Kernel.inventory.add_item("log_normal", 3)
    
    var items = Kernel.inventory.get_all_items()
    assert_eq(items.size(), 1, "Inventar sollte nach dem Stacken immer noch nur einen Eintrag haben")
    assert_eq(items[0]["quantity"], 8, "Menge sollte sich auf 8 addiert haben")
 
func test_add_negative_amount():
    Kernel.inventory.add_item("wood", 10)
    Kernel.inventory.add_item("wood", -5)
    assert_eq(Kernel.inventory.get_quantity("wood"), 5, "Negative Werte sollten korrekt subtrahiert werden")

func test_get_unknown_item():
    var info = Kernel.inventory.get_item_info("non_existent_id")
    assert_eq(info["name"], "Unbekannt", "Sollte bei unbekannten Items einen Default-Wert liefern")

func test_signal_emission():
    var signal_received = false
    
    # Signal-Verbindung zum Kernel-Inventory
    Kernel.inventory.inventory_changed.connect(func(): signal_received = true)
    
    Kernel.inventory.add_item("log_oak", 1)
    
    # Kurz auf den Frame warten, in dem das Signal verarbeitet wird
    await get_tree().process_frame
    
    assert_true(signal_received, "Inventory-System sollte bei Änderungen das Signal senden")
extends "res://addons/gut/test.gd"
func before_each():
    Kernel.inventory.clear_inventory()
    
func test_add_item_creates_new_entry():
    var inv = Kernel.inventory
    inv._inventory_data = [] # Sicherstellen, dass es leer ist
    
    inv.add_item("log_normal", 5)
    
    var items = inv.get_all_items()
    assert_eq(items.size(), 1, "Inventar sollte genau einen Eintrag haben")
    assert_eq(items[0]["quantity"], 5, "Menge sollte 5 sein")
    assert_eq(items[0]["item_id"], "log_normal", "Item-ID sollte 'log_normal' sein")

func test_add_item_stacks_existing():
    var inv = Kernel.inventory
    inv._inventory_data = [{ "item_id": "log_normal", "quantity": 5 }]
    
    inv.add_item("log_normal", 3)
    
    var items = inv.get_all_items()
    assert_eq(items.size(), 1, "Inventar sollte nach dem Stacken immer noch nur einen Eintrag haben")
    assert_eq(items[0]["quantity"], 8, "Menge sollte sich auf 8 addiert haben")
 
func test_add_negative_amount():
    var inv = Kernel.inventory
    inv.add_item("wood", 10)
    inv.add_item("wood", -5)
    assert_eq(inv.get_quantity("wood"), 5, "Negative Werte sollten korrekt subtrahiert werden")

func test_get_unknown_item():
    var inv = Kernel.inventory
    var info = inv.get_item_info("non_existent_id")
    assert_eq(info["name"], "Unbekannt", "Sollte bei unbekannten Items einen Default-Wert liefern")

func test_signal_emission():
    var inv = Kernel.inventory
    var signal_received = false
    
    # Signal-Verbindung testen
    inv.inventory_changed.connect(func(): signal_received = true)
    
    inv.add_item("log_oak", 1)
    
    assert_true(signal_received, "Inventory-System sollte bei Änderungen das Signal senden")
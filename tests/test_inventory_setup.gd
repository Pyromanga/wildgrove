func test_inventory_add_and_remove():
    # Wir brauchen keine Szene, nur den Service
    var inv = Kernel.inventory
    inv.clear_inventory() # Du musst sicherstellen, dass dein Service eine Reset-Methode hat
    
    inv.add_item("wood", 10)
    assert_eq(inv.get_quantity("wood"), 10, "Inventar sollte 10 Holz haben")
    
    inv.remove_item("wood", 5)
    assert_eq(inv.get_quantity("wood"), 5, "Nach dem Entfernen sollten 5 Holz übrig sein")
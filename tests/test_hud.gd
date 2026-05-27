func test_controller_updates_hud():
    # Setup
    var hud = HUD.new()
    var inv = Inventory.new()
    var controller = InventoryUIController.new(hud, inv)
    
    # Test-Aktion
    inv.add_item("log_normal", 10)
    
    # Assertion
    assert_true("Holz: 10" in hud._inventory_label.text)
    
    # Aufräumen (keine Orphans mehr!)
    controller.queue_free()
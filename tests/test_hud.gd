extends "res://tests/IntegrationTest.gd"

func test_controller_updates_hud():
    # Setup: Wir greifen jetzt auf die Instanzen zu, die der Kernel bereits erstellt hat
    # Falls dein Controller manuell instanziiert werden muss:
    var controller = InventoryUIController.new(Kernel.hud, Kernel.inventory)
    add_child_autofree(controller)
    
    # Test-Aktion: Wir nutzen den Kernel-Inventory Service
    Kernel.inventory.add_item("log_normal", 10)
    
    # Warte einen Frame, damit die UI das Signal verarbeiten kann
    await get_tree().process_frame
    
    # Assertion: Prüfe gegen das HUD, das der Kernel verwaltet
    assert_true("Holz: 10" in Kernel.hud._inventory_label.text, "HUD sollte Holz: 10 anzeigen")
    
    # Controller wird durch add_child_autofree automatisch mit dem Test gelöscht
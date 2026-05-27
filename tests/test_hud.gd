extends "res://tests/IntegrationTest.gd"

func test_controller_updates_hud():
    # 1. Instanziiere das HUD
    var hud = HUD.new()
    # 2. Hinzufügen zum Baum ist ZWINGEND, damit _ready() läuft
    add_child_autofree(hud) 
    
    # Jetzt ist das Label durch HUD._ready() garantiert vorhanden
    
    # 3. Controller Setup
    var controller = InventoryUIController.new()
    add_child_autofree(controller)
    controller.setup(hud, Kernel.inventory)
    
    # Test-Aktion
    Kernel.inventory.add_item("log_normal", 10)
    await get_tree().process_frame
    
    # Assertion
    assert_true("Holz: 10" in hud._inventory_label.text, "HUD sollte Holz: 10 anzeigen")
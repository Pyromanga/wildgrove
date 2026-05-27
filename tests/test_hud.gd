extends "res://addons/gut/test.gd"

var hud: CanvasLayer

func before_each():
    # Wir instanziieren das HUD manuell für den Test
    hud = load("res://scripts/HUD.gd").new()
    add_child_autofree(hud)
    Kernel.inventory.clear_inventory()

func test_hud_updates_on_inventory_change():
    # 1. Startzustand prüfen
    assert_eq(hud._inventory_label.text, "Inventar:\n", "HUD sollte am Anfang leer sein")
    
    # 2. Inventar ändern
    Kernel.inventory.add_item("log_normal", 5)
    
    # 3. Warten, bis der Event-Bus das Signal verarbeitet hat
    await get_tree().process_frame
    
    # 4. Prüfen, ob das HUD die Änderung reflektiert
    var expected = "Inventar:\n- Holz: 5\n"
    assert_eq(hud._inventory_label.text, expected, "HUD-Label sollte den neuen Wert anzeigen")
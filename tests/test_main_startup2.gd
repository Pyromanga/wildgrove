extends "res://tests/IntegrationTest.gd"

var MainScene = preload("res://scenes/Main.tscn")
var main_node: Node

func before_each():
    # Wir laden die Main-Szene, um den Bootstrapping-Prozess zu prüfen
    main_node = MainScene.instantiate()
    add_child(main_node)
    await get_tree().process_frame

func test_bootstrap_sequence():
    # 1. Wurde die Welt erstellt?
    assert_not_null(main_node.get_node_or_null("World"), "Welt-Node fehlt in Main!")
    
    # 2. Wurde der Kernel korrekt mit dem HUD verbunden?
    assert_not_null(Kernel.hud, "HUD-Service im Kernel nicht gesetzt!")
    
    # 3. Ist der Controller aktiv?
    assert_true(main_node.has_node(str(main_node.inventory_ui_controller.get_path())), 
                "InventoryUIController nicht als Kind von Main gefunden!")

func test_interaction_flow():
    # Prüfung: Wenn wir im Spiel XP emittieren, reagiert das System?
    var xp_received = false
    Kernel.events.xp_gained.connect(func(_s, _a): xp_received = true)
    
    Kernel.events.emit_xp("woodcutting", 10)
    await get_tree().process_frame
    
    assert_true(xp_received, "XP-Signal kam nicht in Main an!")
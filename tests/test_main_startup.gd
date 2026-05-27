extends "res://tests/IntegrationTest.gd"

# Wir laden die Szene einmalig als Preload, um Parse-Errors zu vermeiden
var MainScene = preload("res://scenes/Main.tscn")
var main_node: Node

func before_each():
    # Rufe die Basis-Initialisierung auf (lädt den Kernel)
    # await super.before_all() # Falls du before_all dort nutzt
    
    # Jetzt instanziieren wir Main. 
    # Da der Kernel jetzt bereits läuft, wird Main alle Services finden.
    main_node = MainScene.instantiate()
    add_child_autofree(main_node)
    
    # Warte kurz, damit Main._ready() die Welt/HUD erstellen kann
    await get_tree().process_frame

func test_bootstrap_initialization():
    # 1. Prüfen, ob der Kernel alle Fabriken geladen hat
    assert_not_null(Kernel.world_factory, "WorldFactory fehlt!")
    assert_not_null(Kernel.ui_factory, "UIFactory fehlt!")
    
    # 2. Prüfen, ob Main die Welt und das HUD erstellt hat
    # Da wir nun den echten Kernel nutzen, greifen wir auf Kernel.hud zu
    assert_not_null(Kernel.hud, "Main hat kein HUD im Kernel registriert!")
    
    # Prüfen, ob die Welt als Kind von Main existiert
    var world = main_node.get_node_or_null("World") 
    assert_not_null(world, "Main hat keine Welt erstellt!")

func test_kernel_services_available():
    # Prüfen, ob die kritischen Services ohne Fehler laufen
    assert_not_null(Kernel.inventory, "InventoryService nicht geladen!")
    assert_not_null(Kernel.events, "GameEvents nicht geladen!")
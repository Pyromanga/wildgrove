extends "res://addons/gut/test.gd"

var main_scene = load("res://scenes/Main.tscn")
var main_node: Node

func before_each():
    # Wir instanziieren die Main-Szene manuell
    main_node = main_scene.instantiate()
    # Wir fügen sie dem Root-Baum hinzu, damit _ready() triggert
    add_child_autofree(main_node)

func test_bootstrap_initialization():
    # 1. Prüfen, ob der Kernel alle Fabriken geladen hat
    assert_not_null(Kernel.world_factory, "WorldFactory fehlt!")
    assert_not_null(Kernel.ui_factory, "UIFactory fehlt!")
    
    # 2. Prüfen, ob Main die Welt und das HUD erstellt hat
    # Da Main diese add_child() macht, müssen sie nun Kinder von main_node sein
    var world = main_node.get_node_or_null("World") # Annahme: Der Node heißt World
    var hud = main_node.get_node_or_null("HUD")     # Annahme: Der Node heißt HUD
    
    # Hinweis: Falls deine Factories die Namen anders setzen, 
    # passe die Strings hier einfach an (z.B. main_node.get_child(0))
    assert_not_null(world, "Main hat keine Welt erstellt!")
    assert_not_null(hud, "Main hat kein HUD erstellt!")

func test_kernel_services_available():
    # Prüfen, ob die kritischen Services ohne Fehler laufen
    assert_not_null(Kernel.inventory, "InventoryService nicht geladen!")
    assert_not_null(Kernel.events, "GameEvents nicht geladen!")
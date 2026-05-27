extends "res://addons/gut/test.gd"

func test_world_factory_spawns_content():
    # 1. Fabrik direkt aus dem Kernel holen
    var factory = Kernel.world_factory
    
    # 2. Welt erzeugen
    var world = factory.create_world()
    add_child_autofree(world)
    
    # 3. Validierung: Hat die Welt Kinder? 
    # (z.B. Spieler, Gelände, Ressourcen?)
    assert_gt(world.get_child_count(), 0, "Die Welt sollte bei der Erstellung Objekte enthalten")
    
    # 4. Spezifischer Test: Ist ein Spieler vorhanden?
    # (Angenommen, du hast einen Node namens 'Player')
    var player = world.get_node_or_null("Player")
    assert_not_null(player, "Welt-Spawn: Spieler-Node wurde nicht gefunden!")
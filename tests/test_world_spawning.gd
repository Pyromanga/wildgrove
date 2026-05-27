extends "res://tests/IntegrationTest.gd"

func test_world_factory_spawns_content():
    # 1. Wir nutzen die Factory aus dem Kernel-Service
    assert_not_null(Kernel.world_factory, "WorldFactory ist nicht im Kernel registriert!")
    
    # 2. Welt erzeugen
    var world = Kernel.world_factory.create_world()
    add_child_autofree(world)
    
    # 3. Validierung: Hat die Welt Kinder?
    assert_gt(world.get_child_count(), 0, "Die Welt sollte bei der Erstellung Objekte enthalten")
    
    # 4. Spezifischer Test: Ist ein Spieler vorhanden?
    # Hinweis: Da wir CharacterBody3D verwenden, prüfen wir auf den Typ 
    # oder den Namen, je nachdem wie du den Spieler benennst
    var player_found = false
    for child in world.get_children():
        if child is CharacterBody3D:
            player_found = true
            break
            
    assert_true(player_found, "Welt-Spawn: Spieler-Node (CharacterBody3D) wurde nicht gefunden!")
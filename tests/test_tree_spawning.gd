extends "res://tests/IntegrationTest.gd"

func test_tree_spawning_at_correct_position():
    # Wir nutzen die im Kernel initialisierte WorldFactory
    var world = Kernel.world_factory.create_world()
    add_child_autofree(world)
    
    # Da wir nun den Baum im Tree suchen, stellen wir sicher, 
    # dass er auch wirklich existiert
    var trees = []
    for child in world.get_children():
        # Falls deine Bäume einen bestimmten Namen haben oder in einer Gruppe sind
        if child.name.contains("Tree") or child.is_in_group("tree"):
            trees.append(child)
            
    assert_gt(trees.size(), 0, "Es sollten Bäume in der Welt existieren")
    
    # Prüfen, ob der Baum an der erwarteten Position (5, 0, 5) spawnt
    # Wir iterieren durch die Bäume, falls die Factory mehrere erstellt
    var found = false
    for tree in trees:
        if tree.position == Vector3(5, 0, 5):
            found = true
            break
            
    assert_true(found, "Baum sollte an Position (5, 0, 5) gefunden werden")
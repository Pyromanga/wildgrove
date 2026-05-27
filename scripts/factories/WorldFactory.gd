# res://scripts/WorldFactory.gd

# Diese Funktion baut die Logik-Objekte (Daten)
func create_world_data() -> WorldData:
    var data = WorldData.new()
    data.player_position = Vector3(0, 1, 0)
    data.add_tree(Vector3(5, 0, 5))
    data.add_tree(Vector3(-6, 0, 4))
    return data

# Diese Funktion baut die Nodes (Darstellung)
func build_world_nodes(data: WorldData) -> Node3D:
    var world = Node3D.new()
    world.name = "World"
    
    # Player aus Daten bauen
    var player = CharacterBody3D.new()
    player.position = data.player_position
    world.add_child(player)
    
    # Bäume aus Daten bauen
    for pos in data.tree_positions:
        var tree = Node3D.new()
        tree.position = pos
        world.add_child(tree)
        
    return world
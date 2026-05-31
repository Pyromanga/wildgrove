# WorldFactory.gd
func _add_player(world: Node3D, pos: Vector3) -> void:
    Logger.log_debug("Lade Player-Script...", "WorldFactory")
    var PlayerScript = load("res://scripts/player/Player.gd")
    if not PlayerScript:
        Logger.log_error("Player.gd konnte nicht geladen werden!", "WorldFactory")
        return

    # Sicherer Weg: Instanziiere direkt vom Script
    var player = CharacterBody3D.new()
    player.set_script(PlayerScript) 
    player.name = "Player"
    player.add_to_group("player") # WICHTIG für das HUD später
    player.position = pos
    world.add_child(player)
    Logger.log_debug("Player OK und im Tree.", "WorldFactory")

func _add_trees(world: Node3D, positions: Array) -> void:
    var TreeScript = load("res://scripts/world/objects/OakTree.gd")
    if not TreeScript:
        Logger.log_error("OakTree.gd fehlt!", "WorldFactory")
        return

    for i in positions.size():
        var tree = Node3D.new()
        tree.set_script(TreeScript)
        tree.name = "OakTree_" + str(i)
        tree.position = positions[i]
        world.add_child(tree)
        tree.add_to_group("interactable")
        Logger.log_debug("Baum " + str(i) + " platziert.", "WorldFactory")
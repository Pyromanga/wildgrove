extends "res://addons/gut/test.gd"

func before_each():
    # Wir erstellen ein minimales Setup, das der Builder erwartet
    var player = Node3D.new()
    player.name = "Player"
    # Anstatt add_child_autofree(player), legen wir es in den Root, 
    # damit get_node("World/Player") funktionieren würde - oder besser:
    # Passe den Test so an, dass er den Spieler als Dependency bekommt.
    add_child_autofree(player)

func test_interaction_logic():
    var builder = Kernel.builder
    
    var target = Node3D.new()
    target.add_to_group("interactable") # Das Objekt muss in der Gruppe sein
    add_child_autofree(target)
    
    var can_interact = builder.is_interactable(target)
    
    assert_true(can_interact, "Builder sollte den Baum als interactable erkennen")

func test_interaction_event_fires():
    var event_received = false
    # Signalbindung sicherstellen
    Kernel.events.interaction_started.connect(func(_l, _d): event_received = true)
    
    Kernel.builder.trigger_interaction("Tree")
    
    # Warte kurz, damit der EventBus das Signal verteilen kann
    await get_tree().process_frame
    
    assert_true(event_received, "Das Interaction-Started Signal wurde nicht gesendet")
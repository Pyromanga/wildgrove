extends "res://addons/gut/test.gd"
extends "res://addons/gut/test.gd"

func test_interaction_logic():
    var builder = Kernel.builder
    var player = get_tree().root.get_node("World/Player")
    
    # 1. Wir simulieren eine Interaktion mit einem Baum
    var target = Node3D.new()
    target.name = "Tree"
    
    # 2. Prüfen, ob der Builder das Objekt als "interactable" registriert
    var can_interact = builder.is_interactable(target)
    
    # 3. Wenn das false ist, haben wir unseren Fehler gefunden!
    assert_true(can_interact, "Builder sollte den Baum als interactable erkennen")

func test_interaction_event_fires():
    var event_received = false
    Kernel.events.interaction_started.connect(func(l, d): event_received = true)
    
    Kernel.builder.trigger_interaction("Tree")
    
    await get_tree().process_frame
    assert_true(event_received, "Das Interaction-Started Signal wurde nicht gesendet")
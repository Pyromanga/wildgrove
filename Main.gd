extends Node

func _ready() -> void:
    Logger.log_debug("Main-Orchestrator gestartet.", "Main")
    
    # 1. Hier könnten wir auf den Kernel warten, falls nötig
    # 2. Die Welt-Generierung triggern
    await get_tree().process_frame # Ein kleiner Moment für alle Services, sich zu registrieren
    
    _start_game()

func _start_game() -> void:
    # Jetzt ist der Kernel bereit, alle Services haben sich registriert.
    # Wir rufen die Fabrik auf.
    var world = Kernel.world_factory.create_world()
    add_child(world)
    
    Logger.log_debug("Spiel erfolgreich gestartet.", "Main")
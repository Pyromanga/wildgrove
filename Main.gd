extends Node
## Main.gd — Der Orchestrator

func _ready() -> void:
    Kernel.events.log("Spiel-Bootstrap gestartet.")
    
    # Welt erstellen
    var world = Kernel.world_factory.create_world()
    add_child(world)
    
    # HUD erstellen
    var hud_instance = Kernel.ui_factory.create_hud()
    add_child(hud_instance)
    Kernel.hud = hud_instance
    
    # --- NEU: Joystick-Verbindung ---
    var visuals = Kernel.ui_factory.create_joystick_visuals()
    # Joystick-Visuals dem HUD unterordnen, damit sie mit dem HUD verschwinden/erscheinen
    hud_instance.add_child(visuals[0]) # Base
    hud_instance.add_child(visuals[1]) # Knob
    
    # Dem Touch-Service die Visuals übergeben
    Kernel.touch.register_joystick_visuals(visuals[0], visuals[1])
    # --------------------------------
    
    Kernel.events.xp_gained.connect(_on_xp_gained)
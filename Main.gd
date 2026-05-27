extends Node
## Main.gd — Der Orchestrator

# Controller-Referenz
var inventory_ui_controller: InventoryUIController

func _ready() -> void:
    await Kernel.services_ready
    Kernel.events.log("Spiel-Bootstrap gestartet.")
    
    # 1. Welt erstellen
    var world = Kernel.world_factory.create_world()
    add_child(world)
    
    # 2. HUD erstellen (passiv)
    var hud_instance = Kernel.ui_factory.create_hud()
    add_child(hud_instance)
    Kernel.hud = hud_instance
    
    # 3. Controller einbinden (Der Klebstoff zwischen Inventory und HUD)
    var controller = InventoryUIController.new()
    add_child(controller) # Jetzt ist er im Baum!
    inventory_ui_controller = controller
    inventory_ui_controller.setup(hud_instance, Kernel.inventory)
    
    # --- Joystick-Verbindung ---
    var visuals = Kernel.ui_factory.create_joystick_visuals()
    hud_instance.add_child(visuals[0]) # Base
    hud_instance.add_child(visuals[1]) # Knob
    Kernel.touch.register_joystick_visuals(visuals[0], visuals[1])
    
    # Signale verbinden
    Kernel.events.xp_gained.connect(_on_xp_gained)

func _on_xp_gained(skill: String, amt: int) -> void:
    print("Main: XP erhalten für " + skill + ": " + str(amt))
    # Hier könntest du später einen weiteren Controller für XP-Popups einbinden

func _exit_tree() -> void:
    # Sauberer Abbau zur Vermeidung von Speicherlecks (Orphans)
    if inventory_ui_controller:
        inventory_ui_controller.queue_free()
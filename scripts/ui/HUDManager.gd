extends Node
class_name HUDManager

# Die Controller-Liste
var inventory_ctrl: InventoryUIController
var joystick_ctrl: JoystickController
var context_ctrl: ContextMenuController

func setup(hud: CanvasLayer) -> void:
    # 1. Visuals erstellen (aus deinen neuen Klassen)
    var js_visuals = JoystickVisuals.new(hud)
    
    # 2. Joystick-Logik verbinden
    joystick_ctrl = JoystickController.new()
    joystick_ctrl.setup(js_visuals)
    
    # 3. Andere Controller bleiben wie gehabt (oder werden später auch umgebaut)
    context_ctrl = ContextMenuController.new()
    context_ctrl.setup(hud)
    
    Logger.log_debug("HUDManager: Alle Controller bereit", "HUDManager")
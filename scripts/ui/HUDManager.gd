extends Node
class_name HUDManager

# Die Controller-Liste bleibt bestehen
var inventory_ctrl: InventoryUIController
var joystick_ctrl: JoystickController
var context_ctrl: ContextMenuController
var interact_ctrl: InteractionUIController

func setup(hud: CanvasLayer) -> void:
    # 1. Joystick
    joystick_ctrl = JoystickController.new()
    joystick_ctrl.setup(JoystickVisuals.new(hud))
    
    # 2. Inventar
    inventory_ctrl = InventoryUIController.new()
    inventory_ctrl.setup(InventoryVisuals.new(hud), Kernel.inventory)
    
    # 3. Interaktion
    interact_ctrl = InteractionUIController.new()
    interact_ctrl.setup(InteractionVisuals.new(hud))
    
    # 4. Kontextmenü (Hier kein "new()" für Visuals, da es dynamisch erzeugt wird)
    context_ctrl = ContextMenuController.new()
    
    Logger.log_debug("HUDManager: Alle Controller erfolgreich mit Visuals verheiratet.", "HUDManager")
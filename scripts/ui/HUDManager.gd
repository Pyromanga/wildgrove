extends Node
class_name HUDManager

var inventory_ctrl: InventoryUIController
var interact_ctrl: InteractionUIController
var context_ctrl: ContextMenuController

func setup(hud: CanvasLayer) -> void:
    # Hier werden alle Controller initialisiert
    inventory_ctrl = InventoryUIController.new()
    inventory_ctrl.setup(hud, Kernel.inventory)
    
    interact_ctrl = InteractionUIController.new()
    interact_ctrl.setup(hud)
    
    context_ctrl = ContextMenuController.new()
    context_ctrl.setup(hud)
    
    Logger.log_debug("HUDManager: Alle UI-Controller bereit", "HUDManager")

func toggle_inventory() -> void:
    if inventory_ctrl: inventory_ctrl.toggle()
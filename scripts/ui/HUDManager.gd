extends Node
class_name HUDManager

# Alle Controller
var inventory_ctrl: InventoryUIController
var joystick_ctrl: JoystickController
var context_ctrl: ContextMenuController
var interact_ctrl: InteractionUIController
var btn_ctrl: InteractionButtonController
var notif_ctrl: NotificationController
var float_text_ctrl: FloatingTextController

func setup(hud: HUD) -> void:
    # 1. Interaktion-System
    var interact_visuals = InteractionButtonVisuals.new(hud)
    interact_ctrl = InteractionButtonController.new()
    interact_ctrl.setup(interact_visuals) # Übergibt nur die Interaktions-Visuals
    
    # 2. Kontext-System
    var context_visuals = ContextButtonVisuals.new(hud)
    var context_btn_ctrl = ContextButtonController.new()
    context_btn_ctrl.setup(context_visuals, context_ctrl, hud)
    
    # 2. Joystick
    joystick_ctrl = JoystickController.new()
    joystick_ctrl.setup(JoystickVisuals.new(hud))
    
    # 3. Inventar
    inventory_ctrl = InventoryUIController.new()
    inventory_ctrl.setup(InventoryVisuals.new(hud), Kernel.inventory)
    
    # 4. Fortschrittsbalken (Interaction)
    interact_ctrl = InteractionUIController.new()
    interact_ctrl.setup(InteractionVisuals.new(hud))
    
    # 6. Globales Notif-System (Panels)
    notif_ctrl = NotificationController.new()
    notif_ctrl.setup(NotificationVisuals.new(hud))
    
    float_text_ctrl = FloatingTextController.new()
    float_text_ctrl.setup(FloatingTextVisuals.new(hud))
    
    Logger.log_debug("HUDManager: Alles modular bereit", "HUDManager")
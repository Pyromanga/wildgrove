extends Node
class_name HUDManager

# Alle Controller
var inventory_ctrl: InventoryUIController
var joystick_ctrl: JoystickController
var context_ctrl: ContextMenuController
var interact_ctrl: InteractionUIController
var btn_ctrl: InteractionButtonController
var notif_ctrl: NotificationController # Für Panels
var float_text_ctrl: FloatingTextController # Für XP/Level-Up

func setup(hud: HUD) -> void:
    # 1. Action Buttons (Interact/Context)
    btn_ctrl = InteractionButtonController.new()
    btn_ctrl.setup(ButtonVisuals.new(hud))
    
    # 2. Joystick
    joystick_ctrl = JoystickController.new()
    joystick_ctrl.setup(JoystickVisuals.new(hud))
    
    # 3. Inventar
    inventory_ctrl = InventoryUIController.new()
    inventory_ctrl.setup(InventoryVisuals.new(hud), Kernel.inventory)
    
    # 4. Fortschrittsbalken (Interaction)
    interact_ctrl = InteractionUIController.new()
    interact_ctrl.setup(InteractionVisuals.new(hud))
    
    # 5. Floating Texts (XP, etc.)
    float_text_ctrl = FloatingTextController.new()
    float_text_ctrl.setup(hud)
    
    # 6. Globales Notif-System (Panels)
    notif_ctrl = NotificationController.new()
    
    float_text_ctrl = FloatingTextController.new()
    float_text_ctrl.setup(FloatingTextVisuals.new(hud))
    
    Logger.log_debug("HUDManager: Alles modular bereit", "HUDManager")
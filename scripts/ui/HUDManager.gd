extends Node
class_name HUDManager

# Die Controller werden hier als Referenzen gehalten.
# Wir setzen sie initial auf null, damit wir später prüfen können, ob sie existieren.
var inventory_ctrl: InventoryUIController
var joystick_ctrl: JoystickController
var context_ctrl: ContextMenuController
var interact_ctrl: InteractionUIController
var btn_ctrl: InteractionButtonController
var notif_ctrl: NotificationController
var float_text_ctrl: FloatingTextController

func setup(hud: HUD) -> void:
    # Der Manager delegiert den Aufbau an den Builder
    var registry = HUDBuilder.build_all(hud)
    
    # Referenzen übernehmen (mit Fallback, um Crashes zu vermeiden)
    inventory_ctrl = registry.get("inventory")
    joystick_ctrl = registry.get("joystick")
    context_ctrl = registry.get("context")
    interact_ctrl = registry.get("interaction")
    btn_ctrl = registry.get("interaction_button")
    notif_ctrl = registry.get("notification")
    float_text_ctrl = registry.get("floating_text")
    
    Logger.log_debug("HUDManager: Initialisierung durch HUDBuilder abgeschlossen", "HUDManager")
# scripts/ui/components/context_component.gd
class_name ContextComponent extends BaseUIComponent

func build(hud: HUD) -> ContextButtonController:
    # 1. Visuals für den Button (Position kommt vom LayoutManager)
    var visuals = ContextButtonVisuals.new(hud)
    
    # 2. Den Menü-Controller instanziieren (wird für den Button-Controller gebraucht)
    var context_menu_ctrl = ContextMenuController.new()
    
    # 3. Den Button-Controller bauen
    var ctrl = ContextButtonController.new()
    ctrl.setup(visuals, context_menu_ctrl, hud)
    
    return ctrl
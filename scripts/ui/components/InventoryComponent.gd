# scripts/ui/components/inventory_component.gd
class_name InventoryComponent extends BaseUIComponent

func build(hud: HUD, inv_service: InventorySystem) -> InventoryUIController:
    var visuals = InventoryVisuals.new(hud)
    var ctrl = InventoryUIController.new()
    
    # Injection des Services
    ctrl.setup(visuals, inv_service)
    
    return ctrl
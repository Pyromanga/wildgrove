# scripts/ui/components/inventory_component.gd
class_name InventoryComponent extends BaseUIComponent

func build(hud: HUD) -> InventoryUIController:
    # Layout abfragen
    var zone = LayoutManager.get_zone_rect(LayoutManager.INVENTORY_ZONE)
    
    # Visuals bauen (Übergabe des Parents für die Node-Hierarchie)
    var visuals = InventoryVisuals.new(hud)
    
    # Controller instanziieren und die Abhängigkeit (Kernel.inventory) injizieren
    var ctrl = InventoryUIController.new()
    ctrl.setup(visuals, Kernel.inventory)
    
    return ctrl
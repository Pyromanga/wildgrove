class_name InventoryComponent extends BaseUIComponent

# FIX: Kein Override-Konflikt mehr, da BaseUIComponent kein build() hat.
func build(hud: HUD, inv_service: InventorySystem) -> InventoryUIController:
	var visuals := InventoryVisuals.new(hud)
	var ctrl    := InventoryUIController.new()
	ctrl.setup(visuals, inv_service)
	return ctrl
class_name InventoryComponent extends BaseUIComponent

func build(hud: HUD, ctx: IUIContext) -> InventoryUIController:
	var visuals := InventoryVisuals.new(hud)
	var ctrl := InventoryUIController.new()
	ctrl.setup(visuals, ctx.get_inventory(), ctx.get_equipment(), ctx.get_data(), ctx, ctx.get_currency(), ctx.get_item_protection())
	return ctrl

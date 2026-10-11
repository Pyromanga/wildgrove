class_name AuctionHouseComponent extends BaseUIComponent

func build(hud: HUD, ctx: IUIContext) -> AuctionHouseUIController:
	var visuals := AuctionHouseVisuals.new(hud)
	var ctrl := AuctionHouseUIController.new()
	hud.add_child(ctrl)
	ctrl.setup(visuals, ctx)
	return ctrl

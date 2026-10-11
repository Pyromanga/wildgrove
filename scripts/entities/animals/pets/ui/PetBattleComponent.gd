class_name PetBattleComponent extends BaseUIComponent

func build(hud: HUD, ctx: IUIContext) -> PetBattleController:
	var visuals := PetBattleVisuals.new(hud)
	var ctrl := PetBattleController.new()
	hud.add_child(ctrl)
	ctrl.setup(visuals, ctx)
	return ctrl

class_name CharacterCreationComponent extends BaseUIComponent

func build(hud: HUD, ctx: IUIContext) -> CharacterCreationController:
	var visuals := CharacterCreationVisuals.new(hud)
	var ctrl := CharacterCreationController.new()
	hud.add_child(ctrl)
	ctrl.setup(visuals, ctx)
	return ctrl

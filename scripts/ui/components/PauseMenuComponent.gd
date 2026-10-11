class_name PauseMenuComponent extends BaseUIComponent

## PauseMenuComponent — baut den PauseMenuController + Visuals.

func build(hud: HUD, ctx: IUIContext) -> PauseMenuController:
	var visuals := PauseMenuVisuals.new(hud)
	var ctrl := PauseMenuController.new()
	ctrl.setup(visuals, ctx)
	hud.add_child(ctrl)  # Pflicht: _ready() und _input() brauchen den Tree
	return ctrl

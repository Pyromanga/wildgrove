class_name MountComponent extends BaseUIComponent

func build(hud: HUD, ctx: IUIContext) -> MountController:
	var visuals := MountVisuals.new(hud)
	var ctrl := MountController.new()
	ctrl.setup(visuals, ctx)   # setup() VOR add_child() (siehe GroundToolComponent)
	hud.add_child(ctrl)
	return ctrl

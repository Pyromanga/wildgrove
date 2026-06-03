# scripts/ui/components/joystick_component.gd
class_name JoystickComponent extends BaseUIComponent

func build(hud: HUD) -> JoystickController:
	var visuals = JoystickVisuals.new(hud)
	var ctrl = JoystickController.new()
	
	# Nutzt den globalen EventBus statt Kernel
	ctrl.setup(visuals, EventBus.ui) 
	return ctrl
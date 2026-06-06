# ContextButtonComponent.gd
class_name ContextButtonComponent extends BaseUIComponent

## FIX: ContextButtonController extends jetzt Node und braucht _ready().
## Deshalb muss er explizit via hud.add_child(ctrl) in den Tree eingefügt werden.
## Identisches Pattern wie InteractionButtonComponent.


func build(hud: HUD, event_bus: UIEvents) -> ContextButtonController:
	var visuals := ContextButtonVisuals.new(hud)
	var ctrl := ContextButtonController.new()
	ctrl.setup(visuals, event_bus)
	hud.add_child(ctrl)  # Pflicht: sonst _ready() feuert nie
	return ctrl

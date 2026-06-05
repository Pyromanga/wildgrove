class_name InteractionButtonComponent extends BaseUIComponent

## InteractionButtonComponent — baut den InteractionButtonController.
##
## Bugfix: Der Controller extends Node und braucht _ready()/_process().
## Deshalb muss er explizit via hud.add_child(ctrl) in den Tree eingefügt werden.
## Vorher wurde er nur erstellt und in einem Dictionary gehalten — niemals im Tree,
## also feuerte _process() nie → Button war immer stumm.


func build(hud: HUD) -> InteractionButtonController:
	var pos := LayoutManager.get_action_button_position(0)
	var visuals := InteractionButtonVisuals.new(hud, pos)
	var ctrl := InteractionButtonController.new()
	ctrl.setup(visuals)
	hud.add_child(ctrl)  # ← Pflicht: sonst _ready()/_process() feuern nie
	return ctrl

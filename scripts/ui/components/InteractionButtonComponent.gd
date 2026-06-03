class_name InteractionButtonComponent extends BaseUIComponent

## InteractionButtonComponent — baut den InteractionButtonController.
##
## FIX 1: Kein Override-Konflikt mehr (BaseUIComponent hat kein build()).
## FIX 2: InteractionButtonController.setup() brauchte 2 Args (visuals, player),
##         aber hier haben wir keinen Player-Zugriff zur Build-Zeit.
##         Lösung: Controller holt sich den Player selbst via Gruppe "player"
##         in _process() — setup() braucht nur noch visuals.

func build(hud: HUD) -> InteractionButtonController:
	var pos     := LayoutManager.get_action_button_position(0)
	var visuals := InteractionButtonVisuals.new(hud, pos)
	var ctrl    := InteractionButtonController.new()
	ctrl.setup(visuals)
	return ctrl
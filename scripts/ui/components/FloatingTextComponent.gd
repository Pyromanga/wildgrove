class_name FloatingTextComponent extends BaseUIComponent

## FloatingTextComponent — baut den FloatingTextController.

# FIX: Kein Override-Konflikt mehr, da BaseUIComponent kein build() hat.
func build(hud: HUD, player_events: PlayerEvents) -> FloatingTextController:
	assert(player_events != null, "FloatingTextComponent.build: player_events ist null!")
	var visuals := FloatingTextVisuals.new(hud)
	var ctrl    := FloatingTextController.new()
	ctrl.setup(visuals, player_events)
	return ctrl
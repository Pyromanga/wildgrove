class_name InteractionComponent extends BaseUIComponent

## InteractionComponent — baut den Fortschrittsbalken für laufende Interaktionen.

# FIX: Kein Override-Konflikt mehr, da BaseUIComponent kein build() hat.
func build(hud: HUD, world_events: WorldEvents) -> InteractionUIController:
	assert(world_events != null, "InteractionComponent.build: world_events ist null!")
	var visuals := InteractionVisuals.new(hud)
	var ctrl    := InteractionUIController.new()
	ctrl.setup(visuals, world_events)
	return ctrl
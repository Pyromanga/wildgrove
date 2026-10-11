class_name FloatingTextComponent extends BaseUIComponent

## FloatingTextComponent — baut den FloatingTextController.

# FIX: Kein Override-Konflikt mehr, da BaseUIComponent kein build() hat.
func build(hud: HUD, ctx: IUIContext) -> FloatingTextController:
	assert(ctx != null, "FloatingTextComponent.build: ctx ist null!")
	var visuals := FloatingTextVisuals.new(hud)
	var ctrl := FloatingTextController.new()
	ctrl.setup(visuals, ctx)
	return ctrl

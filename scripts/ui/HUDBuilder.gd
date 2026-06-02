class_name HUDBuilder

## HUDBuilder — Baut alle HUD-Komponenten, gibt Controller-Registry zurück.
## Wird von HUDManager.setup() aufgerufen — immer nach bind_shortcuts().

static func build_all(hud: HUD) -> Dictionary:
	assert(Kernel.events    != null, "HUDBuilder: Kernel.events ist null — bind_shortcuts() noch nicht aufgerufen?")
	assert(Kernel.inventory != null, "HUDBuilder: Kernel.inventory ist null.")

	var registry: Dictionary = {}

	# Interaktion & Fortschritt
	registry["interaction"]        = InteractionComponent.new().build(hud, Kernel.events.world)
	registry["interaction_button"] = InteractionButtonComponent.new().build(hud)

	# Kontext-Menü
	registry["context_button"] = ContextButtonComponent.new().build(hud, Kernel.events.ui)
	registry["context_menu"]   = ContextMenuComponent.new().build(hud, Kernel.events.ui)

	# Joystick
	registry["joystick"] = JoystickComponent.new().build(hud, Kernel.events.ui)

	# Inventar
	registry["inventory"] = InventoryComponent.new().build(hud, Kernel.inventory)

	# Feedback
	registry["notification"]  = NotificationComponent.new().build(hud)

	# FloatingText braucht nur PlayerEvents —
	# level_up lebt in PlayerEvents, nicht in einem separaten SkillSystem-Namespace
	registry["floating_text"] = FloatingTextComponent.new().build(hud, Kernel.events.player)

	return registry
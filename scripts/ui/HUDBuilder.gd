class_name HUDBuilder

## HUDBuilder — Baut alle HUD-Komponenten und gibt ihre Controller zurück.
## Wird von HUDManager.setup() aufgerufen.
## Nutzt Kernel-Shortcuts (verfügbar ab Phase 4 / bind_shortcuts).

static func build_all(hud: HUD) -> Dictionary:
	assert(Kernel.events   != null, "HUDBuilder: Kernel.events ist null — bind_shortcuts() noch nicht aufgerufen?")
	assert(Kernel.inventory != null, "HUDBuilder: Kernel.inventory ist null.")

	var registry: Dictionary = {}

	# 1. Interaktion & Fortschritt
	registry["interaction"]        = InteractionComponent.new().build(hud, Kernel.events.world)
	registry["interaction_button"] = InteractionButtonComponent.new().build(hud)

	# 2. Kontext-Menü
	registry["context_button"] = ContextButtonComponent.new().build(hud, Kernel.events.ui)
	registry["context_menu"]   = ContextMenuComponent.new().build(hud, Kernel.events.ui)

	# 3. Joystick
	registry["joystick"] = JoystickComponent.new().build(hud, Kernel.events.ui)

	# 4. Inventar
	registry["inventory"] = InventoryComponent.new().build(hud, Kernel.inventory)

	# 5. Feedback
	registry["notification"]   = NotificationComponent.new().build(hud)
	registry["floating_text"]  = FloatingTextComponent.new().build(
		hud, Kernel.events.player, Kernel.events.skill_system if Kernel.events.has("skill_system") else null
	)

	return registry
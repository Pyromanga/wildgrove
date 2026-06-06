class_name HUDBuilder

## HUDBuilder — Instanziiert und verbindet alle HUD-Komponenten.
##
## Änderungen:
## - ContextButtonComponent.build() nimmt jetzt UIEvents statt Object (typsicher)
## - Alle build()-Aufrufe bleiben identisch, aber klar dokumentiert


static func build_all(hud: HUD, context: Dictionary) -> Dictionary:
	var registry: Dictionary = {}
	var ui_events: UIEvents = EventBus.ui

	# 1. Interaktions-Fortschrittsbalken
	registry["interaction"] = InteractionComponent.new().build(hud, EventBus.world)

	# 2. Interaktions-Button (muss im Tree sein → add_child intern)
	registry["interaction_button"] = InteractionButtonComponent.new().build(hud)

	# 3. Inventar
	registry["inventory"] = InventoryComponent.new().build(hud, Services.inventory)

	# 4. Floating Text (XP-Gains, Level-Ups)
	registry["floating_text"] = FloatingTextComponent.new().build(hud, EventBus.player)

	# 5. Benachrichtigungen (Reward-Texte nach Interaktionen)
	registry["notification"] = NotificationComponent.new().build(hud)

	# 6. Joystick-Visual
	registry["joystick"] = JoystickComponent.new().build(hud)

	# 7. Kontext-Button (muss im Tree sein → add_child intern) und Menü
	registry["context_button"] = ContextButtonComponent.new().build(hud, ui_events)
	registry["context_menu"] = ContextMenuComponent.new().build(hud, ui_events)

	return registry

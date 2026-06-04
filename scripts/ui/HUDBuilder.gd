class_name HUDBuilder

## HUDBuilder — Instanziiert und verbindet alle HUD-Komponenten.
##
## FIX: "Could not resolve external class member build" —
##   War ein Cascade-Fehler: die Component-Klassen hatten Parse Errors
##   (build()-Signatur-Konflikt), deshalb konnte HUDBuilder ihre build()-Methode
##   nicht auflösen. Seit BaseUIComponent kein build() mehr hat, compilieren
##   alle Components — und dieser Fehler verschwindet automatisch.


static func build_all(hud: HUD, context: Dictionary) -> Dictionary:
	var registry: Dictionary = {}

	# 1. Interaktions-Fortschrittsbalken — braucht WorldEvents
	registry["interaction"] = InteractionComponent.new().build(hud, EventBus.world)

	# 2. Interaktions-Button — Player wird lazy aufgelöst
	registry["interaction_button"] = InteractionButtonComponent.new().build(hud)

	# 3. Inventar — braucht den Service direkt
	registry["inventory"] = InventoryComponent.new().build(hud, Services.inventory)

	# 4. Floating Text — braucht PlayerEvents
	registry["floating_text"] = FloatingTextComponent.new().build(hud, EventBus.player)

	# 5. Benachrichtigungen
	registry["notification"] = NotificationComponent.new().build(hud)

	# 6. Joystick-Visual
	registry["joystick"] = JoystickComponent.new().build(hud)

	# 7. Kontext-Button und Menü — beide brauchen UIEvents
	registry["context_button"] = ContextButtonComponent.new().build(hud, EventBus.ui)
	registry["context_menu"] = ContextMenuComponent.new().build(hud, EventBus.ui)

	return registry

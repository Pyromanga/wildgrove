class_name HUDBuilder

static func build_all(hud: HUD, ctx: IUIContext) -> Dictionary:
	var registry: Dictionary = {}

	# ZUERST: Toolbar + Fenster-Verwaltung. Alle Visuals unten registrieren sich über
	# ihren `parent` (= hud) beim Dock. Die Reihenfolge der Toggle-Buttons in der Toolbar
	# ist die Reihenfolge der Component-Aufrufe: Inventar, Ausrüstung, Skills, Quests,
	# Pets, Erfolge, Wiki, Bauen.
	PanelDock.attach(hud)

	registry["interaction"] = InteractionComponent.new().build(hud, ctx.bus().world())
	registry["interaction_button"] = InteractionButtonComponent.new().build(hud, ctx)
	var inv_ctrl := InventoryComponent.new().build(hud, ctx)
	registry["inventory"] = inv_ctrl
	if inv_ctrl is InventoryUIController:
		inv_ctrl.refresh()
	registry["equipment"] = EquipmentComponent.new().build(hud, ctx)
	registry["floating_text"] = FloatingTextComponent.new().build(hud, ctx)
	registry["notification"] = NotificationComponent.new().build(hud, ctx)
	registry["joystick"] = JoystickComponent.new().build(hud, ctx)
	registry["context_button"] = ContextButtonComponent.new().build(hud, ctx)
	registry["context_menu"] = ContextMenuComponent.new().build(hud, ctx)
	registry["skill_panel"] = SkillPanelComponent.new().build(hud, ctx)
	registry["quest_panel"] = QuestPanelComponent.new().build(hud, ctx)
	# Pet-Menü (Wunsch "Pets auf Ressourcen sammeln usw. verteilen") — listet
	# eigene Pets + Fähigkeits-Toggles, siehe PetPanelController.
	registry["pet_panel"] = PetPanelComponent.new().build(hud, ctx)
	registry["achievement_panel"] = AchievementPanelComponent.new().build(hud, ctx)
	registry["wiki_panel"] = WikiPanelComponent.new().build(hud, ctx)
	# Bauen: Menü (Toolbar-Button 🔨, SHEET) + Baumodus (Geist + Steuerung). Die Wahl im Menü
	# startet den Baumodus — Verdrahtung hier, damit sich beide nicht kennen müssen.
	var build_panel := BuildPanelComponent.new().build(hud, ctx)
	var build_mode := BuildModeComponent.new().build(hud, ctx)
	build_panel.piece_selected.connect(build_mode.start)
	build_panel.house_selected.connect(build_mode.start_house)
	registry["build_panel"] = build_panel
	registry["build_mode"] = build_mode
	# Graben/Füllen mit der Schaufel (Buttons nur sichtbar mit ausgerüsteter Schaufel).
	registry["ground_tool"] = GroundToolComponent.new().build(hud, ctx)
	registry["character_creation"] = CharacterCreationComponent.new().build(hud, ctx)
	registry["appearance_panel"] = AppearancePanelComponent.new().build(hud, ctx)
	registry["shop_panel"] = ShopComponent.new().build(hud, ctx)
	registry["smithing_panel"] = SmithingComponent.new().build(hud, ctx)
	registry["bank_panel"] = BankComponent.new().build(hud, ctx)
	registry["trade_panel"] = TradeComponent.new().build(hud, ctx)
	registry["auction_house_panel"] = AuctionHouseComponent.new().build(hud, ctx)
	registry["player_hp"] = PlayerHPComponent.new().build(hud, ctx)
	registry["jump_button"] = JumpButtonComponent.new().build(hud, ctx)
	# Reiten (Pferd/Esel): Auf-/Absteigen-Knopf über dem Sprung-Knopf, nur mit Reittier in Reichweite.
	registry["mount"] = MountComponent.new().build(hud, ctx)
	# Pet-Kämpfe (Dorfbewohner herausfordern): Teamwahl, Kampf und Ergebnis in einem Modal-Fenster.
	registry["pet_battle"] = PetBattleComponent.new().build(hud, ctx)
	# Pause-Menü zuletzt: wird über den anderen Fenstern gezeichnet (Zeichenreihenfolge = Kind-Reihenfolge).
	registry["pause_menu"] = PauseMenuComponent.new().build(hud, ctx)

	return registry

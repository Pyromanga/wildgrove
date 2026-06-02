extends Node

## Main.gd — Einstiegspunkt. Delegiert alles an Services.

const LOG_CAT := "Main"

func _ready() -> void:
	Logger.log_info("Bootstrap startet...", LOG_CAT)
	_bootstrap()

func _bootstrap() -> void:
	var loader := ServiceLoader.new()

	# Phase 1: Instanziieren (synchron)
	loader.setup_services(self)

	# Einen Frame warten — alle ServiceNode._ready() müssen gelaufen sein
	# bevor init() aufgerufen wird.
	await get_tree().process_frame

	# Signal connecten BEVOR Phase 3 läuft (GameEvents.on_ready emittiert es)
	var events := Kernel.get_service("gameevents")
	if events:
		events.system.services_initialized.connect(_on_services_ready, CONNECT_ONE_SHOT)
	else:
		Logger.log_error("GameEvents fehlt — _on_services_ready wird nie aufgerufen!", LOG_CAT)

	# Phase 2 + 3
	loader.init_services()
	loader.on_ready_services()

	# Phase 4: Kernel-Shortcuts setzen
	loader.bind_shortcuts()

func _on_services_ready() -> void:
	Logger.log_info("Alle Services bereit.", LOG_CAT)

	if not Kernel.world:
		Logger.log_error("WorldService fehlt — Spiel kann nicht starten!", LOG_CAT)
		return

	var world_node := Kernel.world.create_world()
	add_child(world_node)

	# HUD aufbauen
	var hud := HUD.new()
	add_child(hud)
	var hud_manager := HUDManager.new()
	hud_manager.setup(hud)
	add_child(hud_manager)

	Logger.log_info("Spiel läuft.", LOG_CAT)
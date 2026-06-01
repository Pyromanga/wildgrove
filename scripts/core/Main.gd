extends Node

## Main.gd — Einstiegspunkt des Spiels.
## Verantwortlich für den Bootstrap-Prozess.
## Delegiert alles weitere an Services.

const LOG_CAT := "Main"

func _ready() -> void:
	Logger.log_info("Main._ready() — starte Bootstrap...", LOG_CAT)
	_bootstrap()

# ─────────────────────────────────────────────
# Bootstrap
# ─────────────────────────────────────────────

func _bootstrap() -> void:
	var loader := ServiceLoader.new()

	# Phase 1: Services instanziieren (synchron)
	loader.setup_services(self)

	# Einen Frame warten damit alle ServiceNode._ready() gelaufen sind.
	# KRITISCH: Wir connecten uns auf das services_initialized Signal BEVOR
	# Phase 3 (on_ready_services) läuft — sonst verpassen wir das Emit.
	await get_tree().process_frame

	# Signal connecten BEVOR Phase 2+3 laufen.
	# GameEvents.on_ready() emittiert services_initialized → _on_services_ready wird aufgerufen.
	var events := Kernel.get_service("gameevents") as GameEvents
	if events:
		events.system.services_initialized.connect(_on_services_ready)
	else:
		Logger.log_error("GameEvents nicht gefunden nach Phase 1 — _on_services_ready wird nie aufgerufen!", LOG_CAT)

	# Phase 2: init() in Dependency-Reihenfolge
	loader.init_services()

	# Phase 3: on_ready() in Dependency-Reihenfolge
	# GameEvents.on_ready() feuert services_initialized → _on_services_ready
	loader.on_ready_services()

# ─────────────────────────────────────────────
# Post-Bootstrap
# ─────────────────────────────────────────────

func _on_services_ready() -> void:
	Logger.log_info("Alle Services bereit — starte Game...", LOG_CAT)

	var world_manager = Kernel.get_service("worldmanager")
	if not world_manager:
		Logger.log_error("WorldManager nicht gefunden — Spiel kann nicht starten!", LOG_CAT)
		return
	var world = world_manager.create_world()
	add_child(world)

	var ui_factory = Kernel.get_service("uifactory")
	if not ui_factory:
		Logger.log_error("UIFactory nicht gefunden — HUD kann nicht erstellt werden!", LOG_CAT)
		return
	var hud = ui_factory.create_hud()
	add_child(hud)

	Logger.log_info("Game läuft.", LOG_CAT)
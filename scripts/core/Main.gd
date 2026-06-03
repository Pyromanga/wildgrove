extends Node

## Main.gd — Einstiegspunkt. Startet den ServiceOrchestrator.
##
## Main.tscn Struktur:
##   [node name="Main" type="Node"]
##     [node name="ServiceOrchestrator" type="Node"]
##       script = ServiceOrchestrator.gd

const LOG_CAT := "Main"

func _ready() -> void:
	Logger.log_info("Bootstrap startet...", LOG_CAT)

	# FIX: ServiceLoader existiert nicht im Projekt — ersetzte durch
	# ServiceOrchestrator der als Kind-Node in der Szene liegt.
	# FIX: Kernel existiert nicht als Autoload — EventBus.system wird direkt genutzt.
	var orch := get_node_or_null("ServiceOrchestrator")
	if orch == null:
		Logger.log_error(
			"ServiceOrchestrator nicht gefunden! Prüfe ob er als Kind-Node in Main.tscn eingehängt ist.",
			LOG_CAT
		)
		return

	# Signal connecten BEVOR der Orchestrator boot() ruft (passiert in _ready).
	# Da _ready() top-down läuft, haben wir hier noch Zeit.
	EventBus.system.services_initialized.connect(_on_services_ready, CONNECT_ONE_SHOT)
	EventBus.system.boot_failed.connect(_on_boot_failed, CONNECT_ONE_SHOT)

func _on_boot_failed(phase: String, reason: String) -> void:
	Logger.log_error("Boot fehlgeschlagen in Phase '%s': %s" % [phase, reason], LOG_CAT)

func _on_services_ready() -> void:
	Logger.log_info("Alle Services bereit.", LOG_CAT)

	# FIX: Kernel.world → Services.world
	if not is_instance_valid(Services.world):
		Logger.log_error("WorldService fehlt — Spiel kann nicht starten!", LOG_CAT)
		return

	# FIX: Kernel.world.create_world() → Services.world.create_world()
	var world_node: Node = Services.world.create_world()
	add_child(world_node)

	Logger.log_info("Spiel läuft.", LOG_CAT)
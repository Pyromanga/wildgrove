extends Node

## Main.gd — Einstiegspunkt. Startet den ServiceOrchestrator.
##
## Main.tscn Struktur:
##   [node name="Main" type="Node"]              <- dieses Script
##     [node name="ServiceOrchestrator" type="Node"]  <- ServiceOrchestrator.gd

const LOG_CAT := "Main"


func _ready() -> void:
	Logger.log_info("Bootstrap startet...", LOG_CAT)

	var orch := get_node_or_null("ServiceOrchestrator")
	if orch == null:
		Logger.log_error(
			"ServiceOrchestrator nicht gefunden! Prüfe ob er als Kind-Node in Main.tscn eingehängt ist.",
			LOG_CAT
		)
		return

	# Signals connecten BEVOR _ready() des Orchestrators feuert (top-down Reihenfolge)
	EventBus.system.services_initialized.connect(_on_services_ready, CONNECT_ONE_SHOT)
	EventBus.system.boot_failed.connect(_on_boot_failed, CONNECT_ONE_SHOT)


func _on_boot_failed(phase: String, reason: String) -> void:
	Logger.log_error("Boot fehlgeschlagen in Phase '%s': %s" % [phase, reason], LOG_CAT)


func _on_services_ready() -> void:
	# GameManager.start_game() übernimmt den Szenenwechsel zu MAIN_MENU.
	# Kein manuelles World-Erzeugen hier — das macht WorldService wenn PLAYING aktiv wird.
	Logger.log_info("Alle Services bereit — GameManager übernimmt.", LOG_CAT)

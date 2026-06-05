extends Node

## Main.gd — Optionaler Einstiegspunkt für Szenen, die explizit auf den Boot
## reagieren möchten. Die eigentliche Boot-Logik liegt im ServiceOrchestrator-Autoload.
##
## WICHTIG: ServiceOrchestrator ist ein Autoload (/root/ServiceOrchestrator),
## kein Kind-Node von Main.tscn. Er startet automatisch beim App-Start.
## Diese Datei ist daher optional und dient nur als Listener/Brücke.

const LOG_CAT := "Main"


func _ready() -> void:
	Logger.log_info("Main.gd _ready(). ServiceOrchestrator läuft als Autoload.", LOG_CAT)

	# Auf Boot-Events lauschen — beide werden einmalig gefeuert.
	# CONNECT_ONE_SHOT: nach dem ersten Aufruf automatisch trennen.
	if not EventBus.system.services_initialized.is_connected(_on_services_ready):
		EventBus.system.services_initialized.connect(_on_services_ready, CONNECT_ONE_SHOT)
	if not EventBus.system.boot_failed.is_connected(_on_boot_failed):
		EventBus.system.boot_failed.connect(_on_boot_failed, CONNECT_ONE_SHOT)

	# Falls der Boot bereits abgeschlossen ist (Szene wurde nach dem Boot geladen),
	# direkt weitermachen — das Signal wurde bereits emittiert.
	if is_instance_valid(Services.game_manager):
		Logger.log_info("Services bereits bereit — GameManager übernimmt.", LOG_CAT)
		_on_services_ready()


func _on_boot_failed(phase: String, reason: String) -> void:
	Logger.log_error("Boot fehlgeschlagen in Phase '%s': %s" % [phase, reason], LOG_CAT)


func _on_services_ready() -> void:
	# GameManager.start_game() übernimmt den Szenenwechsel zu MAIN_MENU.
	# Kein manuelles Szenen-Wechseln hier — das macht SceneManager.
	Logger.log_info("Alle Services bereit — GameManager übernimmt.", LOG_CAT)

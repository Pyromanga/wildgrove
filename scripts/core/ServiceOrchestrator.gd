extends Node

## ServiceOrchestrator — Zentrale Boot- und Teardown-Drehscheibe.

const LOG_CAT := "Orchestrator"

var registry := ServiceRegistry.new()
var validator := ServiceValidator.new()
var resolver := ServiceDependencyResolver.new()
var factory := ServiceFactory.new()
var initializer := ServiceInitializer.new()
var installer := ServiceInstaller.new()
var teardown := ServiceTeardownManager.new()


func _ready() -> void:
	# Als Autoload lebt dieser Node für die gesamte Laufzeit des Spiels.
	# Services werden einmal gebootet und überleben alle Szenenwechsel.
	boot()


func _notification(what: int) -> void:
	# Nur beim echten App-Exit teardown — NICHT bei Szenenwechseln.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_CRASH:
		_teardown()


func boot() -> void:
	Logger.log_info("╔══ BOOT START ══╗", LOG_CAT)
	var started := Time.get_ticks_msec()

	# --- Phase 1: Validierung ---
	var defs := validator.validate()
	if defs.is_empty():
		Logger.log_error("Validierung fehlgeschlagen — BootstrapConfig leer oder defekt.", LOG_CAT)
		EventBus.system.boot_failed.emit("validate", "BootstrapConfig ungültig")
		return

	# --- Phase 2: Dependency-Auflösung ---
	var ordered := resolver.resolve(defs)
	if ordered.is_empty():
		Logger.log_error("Resolving fehlgeschlagen — Zirkuläre Abhängigkeiten möglich?", LOG_CAT)
		EventBus.system.boot_failed.emit("resolve", "Dependency-Fehler")
		return

	# --- Phase 3: Instanziierung ---
	var ok := factory.instantiate_all(defs, registry, self)
	if not ok:
		Logger.log_error("Factory-Instanziierung fehlgeschlagen.", LOG_CAT)
		return

	# --- Phase 4: Init (Konfiguration) ---
	initializer.run(ordered, registry)

	# --- Phase 5: Activate (on_ready) ---
	initializer.run_on_ready(ordered, registry)

	# --- Phase 6: Service-Ticker Start ---
	# Hier fehlte in der kompakten Version die explizite Ticker-Registrierung!
	var ticker = registry.get_service("ticker") as ServiceTicker
	if ticker:
		ticker.start_ticking()
		Logger.log_info("Ticker-Service gestartet.", LOG_CAT)

	# --- Phase 7: Installation & Globaler Zugriff ---
	var final_registry := installer.install(registry)
	Services.populate(final_registry)

	# --- Phase 8: Gameloop Start ---
	var gm = registry.get_service("gamemanager")
	if gm is GameManager:
		gm.start_game()
	else:
		Logger.log_warn(
			"GameManager nicht in Registry gefunden — Spielstart übersprungen.", LOG_CAT
		)

	EventBus.system.services_initialized.emit()

	var elapsed := Time.get_ticks_msec() - started
	Logger.log_info("╚══ BOOT FERTIG (%d ms) ══╝" % elapsed, LOG_CAT)


func _teardown() -> void:
	Logger.log_info("── Teardown gestartet", LOG_CAT)
	Services.clear()
	teardown.execute(registry)
	Logger.log_info("── Teardown fertig", LOG_CAT)

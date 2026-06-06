extends Node

## ServiceOrchestrator — Zentrale Boot- und Teardown-Drehscheibe.
##
## AutoLoad #5 (nach Logger, EventBus, SimpleTerminal, Services).
## Lebt für die gesamte Spiellaufzeit und überlebt alle Szenenwechsel.
##
## Boot-Pipeline:
##   Phase 1 — Validate:    ServiceValidator prüft BootstrapConfig.tres
##   Phase 2 — Resolve:     ServiceDependencyResolver (Kahn's Algorithmus)
##   Phase 3 — Instantiate: ServiceFactory erzeugt Instanzen
##   Phase 4 — Configure:   ServiceInitializer ruft configure(deps) auf
##   Phase 5 — Activate:    ServiceInitializer ruft on_ready() auf
##   Phase 6 — Tick Start:  ServiceTicker wird gestartet
##   Phase 7 — Install:     Services-Container wird befüllt
##   Phase 8 — Game Start:  GameManager.start_game() löst Szenenwechsel aus

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


# ─────────────────────────────────────────────
# Boot
# ─────────────────────────────────────────────


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
		EventBus.system.boot_failed.emit("factory", "Instanziierung fehlgeschlagen")
		return

	# --- Phase 4: Init (Konfiguration + Dependency Injection) ---
	initializer.run(ordered, registry)

	# --- Phase 5: Activate (on_ready) ---
	initializer.run_on_ready(ordered, registry)

	# --- Phase 6: Service-Ticker Start ---
	var ticker := registry.get_service("ticker") as ServiceTicker
	if ticker:
		ticker.start_ticking()
		Logger.log_info("Ticker-Service gestartet.", LOG_CAT)
	else:
		Logger.log_warn(
			"Kein Ticker-Service in Registry — on_tick() wird nicht aufgerufen.", LOG_CAT
		)

	# --- Phase 7: Installation & Globaler Zugriff ---
	var final_registry := installer.install(registry)
	Services.populate(final_registry)

	# --- Phase 8: Gameloop Start ---
	var gm := registry.get_service("gamemanager")
	if gm is GameManager:
		gm.start_game()
	else:
		Logger.log_warn("GameManager nicht in Registry — Spielstart übersprungen.", LOG_CAT)

	EventBus.system.services_initialized.emit()

	var elapsed := Time.get_ticks_msec() - started
	Logger.log_info("╚══ BOOT FERTIG (%d ms) ══╝" % elapsed, LOG_CAT)


# ─────────────────────────────────────────────
# Teardown
# ─────────────────────────────────────────────


func _teardown() -> void:
	Logger.log_info("── Teardown gestartet", LOG_CAT)
	Services.clear()
	teardown.execute(registry)
	Logger.log_info("── Teardown fertig", LOG_CAT)


# ─────────────────────────────────────────────
# Debug API (für SimpleTerminal)
# ─────────────────────────────────────────────


## Gibt alle registrierten Service-Namen zurück. Nützlich für Debug-Commands.
func get_registered_names() -> Array[String]:
	return registry.get_all_names()


## Gibt Laufzeit-Info über einen einzelnen Service zurück.
func get_service_info(service_name: String) -> Dictionary:
	var svc := registry.get_service(service_name)
	var def := registry.get_definition(service_name)
	if svc == null:
		return {"error": "Service '%s' nicht gefunden." % service_name}
	return {
		"name": service_name,
		"class": svc.get_class(),
		"valid": is_instance_valid(svc),
		"deps": def.deps if def else [],
	}

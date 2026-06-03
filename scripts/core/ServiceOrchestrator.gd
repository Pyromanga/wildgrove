extends Node
class_name ServiceOrchestrator

## ServiceOrchestrator — Zentrale Boot- und Teardown-Drehscheibe.

const LOG_CAT := "Orchestrator"

# ─────────────────────────────────────────────
# Pipeline-Objekte
# ─────────────────────────────────────────────

var registry    := ServiceRegistry.new()
var validator   := ServiceValidator.new()
var resolver    := ServiceDependencyResolver.new()
var factory     := ServiceFactory.new()
var initializer := ServiceInitializer.new()
var activator   := ServiceActivator.new()
var installer   := ServiceInstaller.new()
var teardown    := ServiceTeardownManager.new()

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
	boot()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_teardown()

# ─────────────────────────────────────────────
# Boot
# ─────────────────────────────────────────────

func boot() -> void:
	Logger.log_info("╔══ BOOT START ══╗", LOG_CAT)
	var started := Time.get_ticks_msec()

	# Phase 1 — Validierung
	Logger.log_info("── Phase 1 · Validate", LOG_CAT)
	var defs := validator.validate()
	if defs.is_empty():
		Logger.log_error("Validierung fehlgeschlagen — Boot abgebrochen.", LOG_CAT)
		EventBus.system.boot_failed.emit("validate", "BootstrapConfig ungültig")
		return

	# Phase 2 — Dependency-Auflösung
	Logger.log_info("── Phase 2 · Resolve", LOG_CAT)
	var ordered := resolver.resolve(defs)
	if ordered.is_empty():
		Logger.log_error("Dependency-Auflösung fehlgeschlagen — Boot abgebrochen.", LOG_CAT)
		EventBus.system.boot_failed.emit("validate", "BootstrapConfig ungültig")
		return

	# Phase 3 — Instanziierung
	Logger.log_info("── Phase 3 · Instantiate", LOG_CAT)
	var ok := factory.instantiate_all(defs, registry, self)
	if not ok:
		Logger.log_error("Instanziierung fehlgeschlagen — Boot abgebrochen.", LOG_CAT)
		EventBus.system.boot_failed.emit("validate", "BootstrapConfig ungültig")
		return

	# Phase 4 — Init
	Logger.log_info("── Phase 4 · Init", LOG_CAT)
	initializer.run(ordered, registry)

	# Phase 5 — Activate
	Logger.log_info("── Phase 5 · Activate", LOG_CAT)
	activator.run(ordered, registry)

	# Phase 6 — Install
	Logger.log_info("── Phase 6 · Install", LOG_CAT)
	var final_registry = installer.install(registry)
	Services.populate(final_registry) 
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
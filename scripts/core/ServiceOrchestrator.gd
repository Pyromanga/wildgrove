# res://scripts/core/ServiceOrchestrator.gd
class_name ServiceOrchestrator extends Node

## ServiceOrchestrator — Zentrale Boot- und Teardown-Drehscheibe.
##
## Lebt als Node im SceneTree (z.B. als Child von Main.tscn).
## Hält alle Pipeline-Objekte und koordiniert die 6 Boot-Phasen + Teardown.
##
## AutoLoads (Logger, EventBus, SceneManager, GameSettings) existieren bereits
## wenn dieser Node _ready() erreicht — kein Timing-Problem.
##
## Boot-Reihenfolge:
##   Phase 1 · Validate    — BootstrapConfig auf Vollständigkeit prüfen
##   Phase 2 · Resolve     — Topologische Sortierung der Abhängigkeiten
##   Phase 3 · Instantiate — Services erstellen (ServiceFactory)
##   Phase 4 · Init        — service.init() in Dep-Reihenfolge
##   Phase 5 · Activate    — service.on_ready() in Dep-Reihenfolge
##   Phase 6 · Install     — DependencyContainer befüllen, services_initialized feuern
##   Phase 7 · Teardown    — beim Beenden sauber aufräumen

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
		return

	# Phase 2 — Dependency-Auflösung
	Logger.log_info("── Phase 2 · Resolve", LOG_CAT)
	var ordered := resolver.resolve(defs)
	if ordered.is_empty():
		Logger.log_error("Dependency-Auflösung fehlgeschlagen — Boot abgebrochen.", LOG_CAT)
		return

	# Phase 3 — Instanziierung
	Logger.log_info("── Phase 3 · Instantiate", LOG_CAT)
	var ok := factory.instantiate_all(defs, registry, self)
	if not ok:
		Logger.log_error("Instanziierung fehlgeschlagen — Boot abgebrochen.", LOG_CAT)
		return

	# Phase 4 — Init
	Logger.log_info("── Phase 4 · Init", LOG_CAT)
	initializer.run(ordered, registry)

	# Phase 5 — Activate
	Logger.log_info("── Phase 5 · Activate", LOG_CAT)
	activator.run(ordered, registry)

	# Phase 6 — Install (DependencyContainer + services_initialized)
	Logger.log_info("── Phase 6 · Install", LOG_CAT)
	installer.install(registry)

	var elapsed := Time.get_ticks_msec() - started
	Logger.log_info("╚══ BOOT FERTIG (%d ms) ══╝" % elapsed, LOG_CAT)

# ─────────────────────────────────────────────
# Teardown
# ─────────────────────────────────────────────

func _teardown() -> void:
	Logger.log_info("── Teardown gestartet", LOG_CAT)
	teardown.execute(registry, installer)
	Logger.log_info("── Teardown fertig", LOG_CAT)
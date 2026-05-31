extends Node

## Main.gd
## Orchestriert den gesamten Bootstrap-Prozess in klar getrennten Phasen.

const LOG_CAT := "Main"

enum BootstrapState {
	PENDING,    # Wartet auf Service-Registrierungen
	READY,      # Alle Services registriert — init() steht aus
	STARTING,   # Welt und HUD werden aufgebaut
	RUNNING,    # Spiel läuft
	ERROR       # Kritischer Fehler — Details im Log
}

var _state: BootstrapState = BootstrapState.PENDING
var _services_to_wait_for: Array[String] = []
var _loader: ServiceLoader

func _ready() -> void:
	Logger.log_info("=== WildGrove Bootstrap gestartet ===", LOG_CAT)
	Logger.log_debug("Godot Version: %s" % Engine.get_version_info(), LOG_CAT)
	Logger.log_debug("Initialer State: PENDING", LOG_CAT)

	_loader = ServiceLoader.new()

	_services_to_wait_for = _loader.get_required_names()
	Logger.log_info("Warte auf %d Services: %s" % [_services_to_wait_for.size(), str(_services_to_wait_for)], LOG_CAT)

	Logger.log_debug("Verbinde Kernel.service_registered Signal...", LOG_CAT)
	Kernel.service_registered.connect(_on_service_registered)

	Logger.log_info("Starte Phase 1: setup_services()...", LOG_CAT)
	_loader.setup_services(self)
	Logger.log_debug("setup_services() zurückgekehrt. Warte auf _ready()-Callbacks der Service-Nodes...", LOG_CAT)

func _on_service_registered(service_name: String) -> void:
	Logger.log_debug("Signal empfangen: service_registered('%s')" % service_name, LOG_CAT)

	if not _services_to_wait_for.has(service_name):
		Logger.log_warn("Unbekannter Service registriert: '%s' — nicht in der Warteliste." % service_name, LOG_CAT)
		return

	_services_to_wait_for.erase(service_name)
	Logger.log_debug("Verbleibende Services: %d — %s" % [_services_to_wait_for.size(), str(_services_to_wait_for)], LOG_CAT)

	if _services_to_wait_for.is_empty():
		Logger.log_info("Alle Services registriert. Trenne Signal...", LOG_CAT)
		Kernel.service_registered.disconnect(_on_service_registered)

		Logger.log_info("Starte Phase 2+3: init_services()...", LOG_CAT)
		_loader.init_services()

		Logger.log_debug("Setze State auf READY.", LOG_CAT)
		_state = BootstrapState.READY
		Logger.log_info("State: PENDING → READY", LOG_CAT)

func _process(_delta: float) -> void:
	if _state == BootstrapState.READY:
		# Frame-synchroner Start: aus dem Signal-Stack ausbrechen
		# bevor wir Szenen manipulieren
		Logger.log_debug("_process(): State READY erkannt → Wechsel zu STARTING", LOG_CAT)
		_state = BootstrapState.STARTING
		Logger.log_info("State: READY → STARTING", LOG_CAT)
		_start_game()

func _start_game() -> void:
	Logger.log_info("=== _start_game() gestartet ===", LOG_CAT)

	# Welt erstellen
	Logger.log_debug("Erstelle WorldFactory...", LOG_CAT)
	var factory = WorldFactory.new()
	if not factory:
		Logger.log_error("WorldFactory konnte nicht instanziiert werden!", LOG_CAT)
		_set_error_state()
		return
	Logger.log_debug("WorldFactory erstellt. Rufe create_world() auf...", LOG_CAT)

	var world = factory.create_world()
	if not world:
		Logger.log_error("create_world() gab null zurück!", LOG_CAT)
		_set_error_state()
		return
	Logger.log_debug("Welt-Instanz erstellt: '%s'. Füge zum SceneTree hinzu..." % world.name, LOG_CAT)

	add_child(world)
	Logger.log_info("Welt-Node erfolgreich im Tree.", LOG_CAT)

	# HUD erstellen
	Logger.log_debug("Prüfe ob 'ui_factory' Service verfügbar...", LOG_CAT)
	if not Kernel.has_service("ui_factory"):
		Logger.log_error("Service 'ui_factory' fehlt — HUD kann nicht erstellt werden!", LOG_CAT)
		_set_error_state()
		return
	Logger.log_debug("'ui_factory' gefunden. Erstelle HUD...", LOG_CAT)

	var hud = Kernel.ui_factory.create_hud()
	if not hud:
		Logger.log_error("create_hud() gab null zurück!", LOG_CAT)
		_set_error_state()
		return
	Logger.log_debug("HUD erstellt: '%s'. Füge zum SceneTree hinzu..." % hud.name, LOG_CAT)

	add_child(hud)
	Logger.log_debug("Rufe setup_inventory_controller() auf...", LOG_CAT)
	Kernel.ui_factory.setup_inventory_controller(hud)
	Logger.log_debug("setup_inventory_controller() abgeschlossen.", LOG_CAT)

	Logger.log_info("State: STARTING → RUNNING", LOG_CAT)
	_state = BootstrapState.RUNNING
	Logger.log_info("=== Bootstrap vollständig abgeschlossen. Spiel läuft. ===", LOG_CAT)

	set_process(false)
	Logger.log_debug("_process() deaktiviert.", LOG_CAT)

func _set_error_state() -> void:
	_state = BootstrapState.ERROR
	Logger.log_error("=== KRITISCHER FEHLER — Bootstrap abgebrochen. State: ERROR ===", LOG_CAT)
	set_process(false)
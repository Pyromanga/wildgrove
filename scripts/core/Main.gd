extends Node

# Zustände für den kontrollierten Startvorgang
enum BootstrapState { 
	PENDING,    # Wartet auf Services
	READY,      # Alles da, bereit für den nächsten Frame
	STARTING,   # Welt wird gerade gebaut
	RUNNING,    # Spiel läuft
	ERROR       # Etwas ist schiefgegangen
}

var _state: BootstrapState = BootstrapState.PENDING
var _services_to_wait_for: Array[String] = []

func _ready() -> void:
	Logger.log_debug("Bootstrapping initiiert...", "Main")
	
	var loader := ServiceLoader.new()
	_services_to_wait_for = loader.get_required_names()
	
	Logger.log_debug("Warte auf %d Services: %s" % [_services_to_wait_for.size(), str(_services_to_wait_for)], "Main")
	
	Kernel.service_registered.connect(_on_service_registered)
	loader.setup_services(self)

func _on_service_registered(service_name: String) -> void:
	_services_to_wait_for.erase(service_name)
	
	if _services_to_wait_for.is_empty():
		Kernel.service_registered.disconnect(_on_service_registered)
		Logger.log_debug("Check: Alle Service-Nodes im Kernel registriert.", "Main")
		_state = BootstrapState.READY

func _process(_delta: float) -> void:
	# Hier nutzen wir den regulären Game-Loop, um aus dem Signal-Stack auszubrechen
	if _state == BootstrapState.READY:
		_state = BootstrapState.STARTING
		Logger.log_debug("Zustandswechsel: STARTING (Frame-synchroner Start)", "Main")
		_start_game()

func _start_game() -> void:
	Logger.log_debug("Beginne Welt-Generierung...", "Main")
	
	var factory = WorldFactory.new()
	if not factory:
		Logger.log_error("Kritisch: WorldFactory konnte nicht erstellt werden", "Main")
		_state = BootstrapState.ERROR
		return

	var world = factory.create_world()
	if not world:
		Logger.log_error("Kritisch: create_world() lieferte null", "Main")
		_state = BootstrapState.ERROR
		return

	Logger.log_debug("Welt-Instanz erstellt. Füge zum SceneTree hinzu...", "Main")
	add_child(world)
	Logger.log_debug("Welt-Node erfolgreich im Tree.", "Main")

	# UI-Initialisierung
	if not Kernel.has_service("ui_factory"):
		Logger.log_error("Service fehlt: ui_factory wird für HUD benötigt", "Main")
		_state = BootstrapState.ERROR
		return

	Logger.log_debug("Erstelle HUD...", "Main")
	var hud = Kernel.ui_factory.create_hud()
	if not hud:
		Logger.log_error("HUD konnte nicht erstellt werden", "Main")
		_state = BootstrapState.ERROR
		return
	
	add_child(hud)
	Kernel.ui_factory.setup_inventory_controller(hud)

	Logger.log_debug("=== Bootstrapping erfolgreich abgeschlossen ===", "Main")
	_state = BootstrapState.RUNNING
	
	# Prozess stoppen, da wir ihn nur für den kontrollierten Start brauchten
	set_process(false)
extends Node

# Die Klasse GameConfig muss existieren (siehe unten)
var _config: GameConfig
var _services_to_wait_for: Array

func _ready() -> void:
	# 1. Konfiguration initialisieren: Hier legst du fest, wer VIP ist.
	# Wenn du einen Service nicht brauchst, löschst du ihn einfach aus dieser Liste.
	_config = GameConfig.new(["debug_service", "data", "world_factory"])
	
	# 2. Kopie der Liste für den Abgleich
	_services_to_wait_for = _config.required_services.duplicate()
	
	Logger.log_debug("Main: Initialisiere Start-Sequenz. Warte auf: " + str(_services_to_wait_for), "Main")
	
	# 3. Check: Welche der benötigten Services sind schon da?
	for s_name in _config.required_services:
		if Kernel.has_service(s_name):
			_services_to_wait_for.erase(s_name)
	
	# 4. Wenn die Liste leer ist -> Start. Sonst -> Auf Kernel hören.
	if _services_to_wait_for.is_empty():
		_start_game()
	else:
		Kernel.service_registered.connect(_on_service_registered)

func _on_service_registered(s_name: String) -> void:
	# Wenn ein Service registriert wird, prüfen wir, ob wir auf ihn gewartet haben
	if _services_to_wait_for.has(s_name):
		_services_to_wait_for.erase(s_name)
		Logger.log_debug("Main: Service '" + s_name + "' erhalten. Noch offen: " + str(_services_to_wait_for), "Main")
		
		# Wenn alle da sind, starten wir
		if _services_to_wait_for.is_empty():
			Kernel.service_registered.disconnect(_on_service_registered)
			_start_game()

func _start_game() -> void:
	Logger.log_debug("Main: Alle VIPs da. Starte Spiel.", "Main")
	# Ab hier: Spiel-Logik (z.B. WorldFactory aufrufen)
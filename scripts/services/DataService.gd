class_name DataService extends Service

## Service zum Laden und Verwalten der Player-Daten aus Ressourcen.
## Da keine Node-Funktionen benötigt werden, erbt er von RefCounted.

var player_data: PlayerData

## Initialisierung: Wird vom ServiceLoader aufgerufen.
func init() -> void:
	# Daten beim Start aus der Resource laden
	player_data = load("res://config/player_data.tres") as PlayerData
	
	if not player_data:
		Logger.log_error("Konnte PlayerData.tres nicht laden!", "DataService")
	else:
		Logger.log_info("PlayerData erfolgreich geladen.", "DataService")

## Holt einen Spieler-Statistikwert. 
## Gibt 'default_val' zurück, falls der Stat nicht existiert.
func get_player_stat(stat_name: String, default_val: float) -> float:
	# Sicherheitscheck: Existiert die Resource?
	if player_data == null:
		Logger.log_warn("PlayerData nicht geladen, verwende Default: %f" % default_val, "DataService")
		return default_val
		
	# Property-Check: Existiert der Stat in der Resource?
	if player_data.get(stat_name) != null:
		return player_data.get(stat_name)
	
	Logger.log_warn("Stat '%s' nicht in PlayerData gefunden. Nutze Default: %f" % [stat_name, default_val], "DataService")
	return default_val
extends Service
class_name DataService

## DataService — Verwaltet statische Spieler-Basisdaten.
## Lädt die PlayerData-Ressource als Single Source of Truth für Stats.

const LOG_CAT   := "DataService"
const DATA_PATH := "res://config/PlayerData.tres"

var player_data: PlayerData

func init() -> void:
	if not ResourceLoader.exists(DATA_PATH):
		Logger.log_error("PlayerData Ressource fehlt: '%s'" % DATA_PATH, LOG_CAT)
		return
	player_data = load(DATA_PATH) as PlayerData
	if player_data:
		Logger.log_info("PlayerData erfolgreich geladen.", LOG_CAT)
	else:
		Logger.log_error("PlayerData konnte nicht als Ressource interpretiert werden!", LOG_CAT)

func get_player_stat(stat_name: String, default_val: float = 0.0) -> float:
	if not player_data:
		Logger.log_error("Versuch Stat '%s' zu lesen, aber player_data ist NULL!" % stat_name, LOG_CAT)
		return default_val
	
	var value = player_data.get(stat_name)
	if value != null:
		# EXZESSIV: Wir loggen jeden Zugriff, damit du im Terminal siehst, wer was fragt
		Logger.log_trace("Stat-Abfrage", {"stat": stat_name, "value": value}, LOG_CAT)
		return float(value)
	
	Logger.log_warn("Stat '%s' fehlt in .tres!" % stat_name, LOG_CAT)
	return default_val

func set_player_stat(stat_name: String, value: float) -> void:
	if player_data and stat_name in player_data:
		player_data.set(stat_name, value)
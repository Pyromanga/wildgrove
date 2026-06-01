# res://scripts/services/DataService.gd
class_name DataService extends Service

var player_data: PlayerData

func init() -> void:
    super.init()
    # Daten beim Start laden
    player_data = load("res://config/player_data.tres") as PlayerData
    
    if not player_data:
        Logger.log_error("Konnte PlayerData.tres nicht laden!", _log_cat())
    else:
        Logger.log_info("PlayerData erfolgreich geladen.", _log_cat())

func get_player_stat(stat_name: String, default_val: float) -> float:
    # Jetzt greifen wir dynamisch auf die Resource-Properties zu
    if player_data and stat_name in player_data:
        return player_data.get(stat_name)
    return default_val
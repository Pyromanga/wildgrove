func get_player_stat(stat_name: String, default_val: float) -> float:
    if player_data and stat_name in player_data:
        return player_data.get(stat_name)
    
    Logger.log_warn("Stat '%s' nicht in PlayerData gefunden. Nutze Default: %f" % [stat_name, default_val], _log_cat())
    return default_val
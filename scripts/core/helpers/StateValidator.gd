class_name StateValidator

static func is_transition_allowed(from: GameEnums.State, to: GameEnums.State, config: GameConfig) -> bool:
    if not config:
        return true # Oder Fallback-Logik
        
    var from_str := GameEnums.State.keys()[from]
    var to_str   := GameEnums.State.keys()[to]
    var allowed: Array = config.valid_transitions.get(from_str, [])
    
    if not to_str in allowed:
        Logger.log_warn("Ungültiger Übergang: %s -> %s" % [from_str, to_str], "StateValidator")
        return false
        
    return true
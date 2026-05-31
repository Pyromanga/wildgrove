extends ServiceBase
class_name DataService

const PLAYER_STATS: Dictionary = {
    "speed":          6.0,
    "gravity":        12.0,
    "jump_force":     4.5,
    "interact_range": 4.0,
}

var settings: Dictionary = {
    "cam_relative":       true,
    "fixed_joystick":     true,
    "joystick_inverted":  false,
    "screen_rotation":    0,
    "cam_smooth":         14.0,
    "zoom_smooth":        8.0,
    "ui_offset_x":        0.0,
    "ui_offset_y":        0.0,
}

func get_player_stat(stat_name: String, default_val: float) -> float:
    return PLAYER_STATS.get(stat_name, default_val)

func get_setting(key: String) -> Variant:
    return settings.get(key)

func set_setting(key: String, value: Variant) -> void:
    if not settings.has(key):
        Logger.log_error("Unbekannter Setting-Key: " + key, "DataService")
        return
    settings[key] = value
    Kernel.events.system.emit_setting_changed(key, value)
    Logger.log_debug("Setting: %s = %s" % [key, str(value)], "DataService")
extends Node
## DataService.gd — Die Single-Source-of-Truth

const TREES = {
    "oak": {"label": "Eiche fällen", "xp": 50, "time": 3.5, "drop": "oak_log"},
    "birch": {"label": "Birke fällen", "xp": 20, "time": 2.0, "drop": "birch_log"}
}

const PLAYER_STATS = {
    "speed": 6.0,
    "gravity": 12.0,
    "jump_force": 4.5,
    "interact_range": 4.0
}

var settings = {
    "cam_relative": true,
    "fixed_joystick": true,
    "joystick_inverted": false,
    "screen_rotation": 0,
    "cam_smooth": 14.0,
    "zoom_smooth": 8.0,
    "ui_offset_x": 0.0,
    "ui_offset_y": 0.0,
}

# --- Baum-Daten ---
func get_tree_data(type: String) -> Dictionary:
    return TREES.get(type, {"label": "Baum", "xp": 10, "time": 1.0, "drop": "wood"})

# --- Player-Stats ---
func get_player_stat(stat_name: String, default: float) -> float:
    return PLAYER_STATS.get(stat_name, default)

# --- Settings ---
func get_setting(key: String):
    return settings.get(key)

func set_setting(key: String, value):
    settings[key] = value
    # Sicherstellen, dass das Event-System bereits initialisiert ist
    if Kernel.has_node("Events"):
        Kernel.events.setting_changed.emit(key, value)
extends ServiceBase
class_name GameEvents

var player := PlayerEvents.new()
var world  := WorldEvents.new()
var system := SystemEvents.new()

class PlayerEvents extends RefCounted:
    signal xp_gained(skill: String, amt: int)
    signal level_up(skill: String, new_level: int)

    func emit_xp(skill: String, amt: int) -> void:
        Logger.log_debug("XP: +%d %s" % [amt, skill], "Events")
        xp_gained.emit(skill, amt)

    func emit_level_up(skill: String, new_level: int) -> void:
        Logger.log_debug("Level Up: %s → %d" % [skill, new_level], "Events")
        level_up.emit(skill, new_level)

class WorldEvents extends RefCounted:
    signal interaction_started(label: String, duration: float)
    signal interaction_finished(label: String)
    signal interaction_cancelled(label: String)

    func emit_interaction_started(label: String, duration: float) -> void:
        Logger.log_debug("Interaktion gestartet: %s (%.1fs)" % [label, duration], "Events")
        interaction_started.emit(label, duration)

    func emit_interaction_finished(label: String) -> void:
        Logger.log_debug("Interaktion beendet: " + label, "Events")
        interaction_finished.emit(label)

    func emit_interaction_cancelled(label: String) -> void:
        Logger.log_debug("Interaktion abgebrochen: " + label, "Events")
        interaction_cancelled.emit(label)

class SystemEvents extends RefCounted:
    signal setting_changed(key: String, value: Variant)
    signal state_changed(state: int)

    func emit_setting_changed(key: String, value: Variant) -> void:
        Logger.log_debug("Setting: %s = %s" % [key, str(value)], "Events")
        setting_changed.emit(key, value)

    func emit_state_changed(state: int) -> void:
        Logger.log_debug("State → %d" % state, "Events")
        state_changed.emit(state)
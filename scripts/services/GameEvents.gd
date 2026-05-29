extends ServiceBase
class_name GameEvents

var player := PlayerEvents.new()
var world  := WorldEvents.new()
var system := SystemEvents.new()

class PlayerEvents extends RefCounted:
    signal xp_gained(skill: String, amt: int)
    func emit_xp(skill: String, amt: int) -> void:
        Logger.log_debug("XP: +%d %s" % [amt, skill], "Events")
        xp_gained.emit(skill, amt)

class WorldEvents extends RefCounted:
    signal interaction_started(label: String, duration: float)
    signal interaction_finished(label: String)

class SystemEvents extends RefCounted:
    signal debug_log(msg: String)
    signal setting_changed(key: String, value: Variant)
    signal state_changed(state: int)  # NEU
extends ServiceBase
class_name GameEvents

## GameEvents.gd — Der zentrale, modulare Nachrichten-Bus
## Zugriff via: Kernel.events.player.xp_gained.emit(...)

var player := PlayerEvents.new()
var world := WorldEvents.new()
var system := SystemEvents.new()

# RefCounted Objekte sind perfekt für Daten-Container/Bus-Strukturen,
# da sie automatisch gelöscht werden, wenn sie nicht mehr gebraucht werden.
class PlayerEvents extends RefCounted:
	signal xp_gained(skill: String, amt: int)
	
	func emit_xp(skill: String, amt: int) -> void:
		Logger.log_debug("XP erhalten: " + skill + " (" + str(amt) + ")", "Events")
		xp_gained.emit(skill, amt)

class WorldEvents extends RefCounted:
	signal interaction_started(label: String, duration: float)
	signal interaction_finished(label: String)

class SystemEvents extends RefCounted:
	signal debug_log(msg: String)
	signal setting_changed(key: String, value: Variant)
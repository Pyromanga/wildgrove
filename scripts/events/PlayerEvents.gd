class_name PlayerEvents extends BaseEvents

## PlayerEvents.gd
## Alle spielerbezogenen Signals.
## Neues Signal? Nur diese Datei anfassen.

signal xp_gained(skill: String, amount: int)
signal level_up(skill: String, new_level: int)
signal movement_interrupted()
signal player_died()
signal player_respawned()
signal inventory_changed(items: Array)
func _init() -> void:
	super._init("Events/Player")

func emit_xp(skill: String, amount: int) -> void:
	_log("XP: +%d in '%s'" % [amount, skill])
	xp_gained.emit(skill, amount)

func emit_level_up(skill: String, new_level: int) -> void:
	_log_info("Level Up: '%s' → Level %d" % [skill, new_level])
	level_up.emit(skill, new_level)

func emit_movement_interrupted() -> void:
	_log("Bewegung während Aktion unterbrochen.")
	movement_interrupted.emit()

func emit_player_died() -> void:
	_log_warn("Spieler gestorben.")
	player_died.emit()

func emit_player_respawned() -> void:
	_log_info("Spieler respawned.")
	player_respawned.emit()

func emit_inventory_changed(items: Array) -> void:
    _log("Inventar aktualisiert (%d Items)" % items.size())
    inventory_changed.emit(items)
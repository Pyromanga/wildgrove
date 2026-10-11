class_name WorldTimeService
extends RefCounted

const LOG_CAT := "WorldTime"

## Named statt anonym 0.05, damit Admin/Debug ("tick reset", siehe
## AdminMenuCommands._cmd_tick()) auf einen benannten Normalwert
## zurücksetzen kann, ohne die Zahl doppelt zu pflegen.
const DEFAULT_TIME_SPEED: float = 0.05

var day_time: float = 6.0
var day_count: int = 1
var time_speed: float = DEFAULT_TIME_SPEED

var _bus: IEventBus = null

func set_event_bus(bus: IEventBus) -> void:
	_bus = bus

func tick(delta: float) -> void:
	day_time += delta * time_speed
	if day_time >= 24.0:
		day_time = fmod(day_time, 24.0)
		day_count += 1
		if _bus != null:
			_bus.world().emit_time_of_day_changed(0)
		AppLogger.log_info("Neuer Tag: Tag %d." % day_count, LOG_CAT)

## Wunsch "Gegner nur bei Nacht spawnen" (ConditionalEncounterService):
## EINE Stelle für die Nacht-Schwelle statt jeder Aufrufer hardcodiert
## "< 6 oder >= 20" prüft — ändert sich die Schwelle später (z.B. Dämmerung
## als eigene Phase), muss nur hier etwas angepasst werden.
func is_night() -> bool:
	return day_time < 6.0 or day_time >= 20.0

func get_formatted_time() -> String:
	var hours: int = int(day_time)
	var minutes: int = int((day_time - hours) * 60)
	return "%02d:%02d" % [hours, minutes]

func restore(state: Dictionary) -> void:
	day_time = state.get("day_time", 6.0)
	day_count = state.get("day_count", 1)

func get_save_data() -> Dictionary:
	return {"day_time": day_time, "day_count": day_count}

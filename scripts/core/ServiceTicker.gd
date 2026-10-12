extends Node
# class_name entfernt (Legacy-Duplikat, Repo-Cleanup 2026-10-12 — Klassen-Registry-Konflikt s. Issue #5)

## ServiceTicker — verteilt Frame-/Physics-Ticks an alle registrierten Services.
##
## ERWEITERUNG (Performance-Fix, Issue #1): Intervall-basiertes Tick-Throttling.
## Services können optional `get_tick_interval() -> float` implementieren —
## Rückgabe: Sekunden zwischen zwei on_tick()-Aufrufen. Fehlt die Methode oder
## ist der Wert <= 0.0, tickt der Service wie bisher jeden Frame.
## on_tick(delta) bekommt bei gedrosselten Services die AUF SUMMIERTE Delta-Zeit
## des Intervalls — Timer-Logik (z.B. Respawn-Countdowns, Perioden-Sampling)
## funktioniert dadurch unverändert, ohne dass der Service mit 60 Hz durch den
## teuren dynamischen Dispatch (has_method/on_tick) muss.
##
## ERWEITERUNG (Performance-Fix, Issue #1): Tick-Statistiken. Pro Service wird
## die on_tick()-Dauer gemessen (Mikrosekunden); get_tick_stats() liefert Aufruf-
## zähler, Gesamt- und letzte Dauer. TelemetryService nimmt diese Werte in die
## Speicher-Snapshots auf — das nächste Log zeigt exakt, wer die Frame-Zeit frisst.

const LOG_CAT := "ServiceTicker"

var _tick_list: Array[Object] = []
var _intervals: Array[float] = []       # parallell zu _tick_list; 0.0 = jeden Frame
var _accumulators: Array[float] = []    # parallell zu _tick_list; aufsummiertes Delta
var _tick_stats: Array[Dictionary] = [] # parallell zu _tick_list; {"class","calls","total_us","last_us","interval"}
var _physics_tick_list: Array[Object] = []
var _running: bool = false


func start_ticking() -> void:
	_running = true
	Logger.log_debug("Ticker läuft.", LOG_CAT)


## Tick-Intervall eines Services ermitteln (0.0 = jeden Frame).
func _get_interval_for(svc: Object) -> float:
	if svc != null and svc.has_method("get_tick_interval"):
		var iv: float = svc.get_tick_interval()
		if iv > 0.0:
			return iv
	return 0.0


func register_service(svc: Object) -> void:
	if svc.has_method("on_tick") and not svc in _tick_list:
		var interval := _get_interval_for(svc)
		_tick_list.append(svc)
		_interval
s.append(interval)
		_accumulators.append(0.0)
		_tick_stats.append({
			"class": svc.get_class(),
			"calls": 0,
			"total_us": 0,
			"last_us": 0,
			"interval": interval,
		})
		Logger.log_debug(
			"Service '%s' registriert (Tick-Intervall: %s)."
			% [svc.get_class(), ("%.2f s" % interval) if interval > 0.0 else "jeden Frame"],
			LOG_CAT
		)

	if svc.has_method("on_physics_tick") and not svc in _physics_tick_list:
		_physics_tick_list.append(svc)
		Logger.log_debug("Service '%s' registriert (Physics-Tick)." % svc.get_class(), LOG_CAT)


## Statistik aller Frame-Tick-Services (Kopie) — für Telemetrie-Snapshots.
func get_tick_stats() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in _tick_stats:
		out.append(s.duplicate())
	return out


func _process(delta: float) -> void:
	if not _running:
		return
	for i in range(_tick_list.size() - 1, -1, -1):
		var svc = _tick_list[i]
		if not is_instance_valid(svc):
			_tick_list.remove_at(i)
			_intervals.remove_at(i)
			_accumulators.remove_at(i)
			_tick_stats.remove_at(i)
			continue

		var interval: float = _intervals[i]
		if interval <= 0.0:
			_tick_one(i, svc, delta)
		else:
			_accumulators[i] += delta
			if _accumulators[i] >= interval:
				_tick_one(i, svc, _accumulators[i])
				_accumulators[i] = 0.0


func _tick_one(index: int, svc: Object, delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	svc.on_tick(delta)
	var dt := Time.get_ticks_usec() - t0
	var stats: Dictionary = _tick_stats[index]
	stats["calls"] = int(stats["calls"]) + 1
	stats["total_us"] = int(stats["total_us"]) + dt
	stats["last_us"] = dt


func _physics_process(delta: float) -> void:
	if not _running:
		return
	for i in range(_physics_tick_list.size() - 1, -1, -1):
		var svc = _physics_tick_list[i]
		if is_instance_valid(svc):
			svc.on_physics_tick(delta)
		else:
			_physics_tick_list.remove_at(i)

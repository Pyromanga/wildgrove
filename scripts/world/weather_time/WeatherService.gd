class_name WeatherService
extends RefCounted

## WeatherService — verwaltet das aktuelle Wetter der Spielwelt.
##
## Sibling zu WorldTimeService (siehe dortiger Kommentar-Header in
## WorldService.gd) — gleiche Delegations-Idee, eigener Zustand.
##
## Design-Entscheidung (Round 95, siehe ADR-041): Wetter wird NICHT über ein
## eigenes RPC an alle Peers verteilt — das Projekt hat aktuell keinen
## "an alle Peers"-Broadcast-Mechanismus (siehe ADR-035 "Umsetzungsstand",
## gleiche Einschränkung dort für Auktionshaus-Listing-Änderungen). Stattdessen
## rollt jeder Peer das Wetter selbst, deterministisch aus `world_seed` +
## einem monoton steigenden Zyklus-Zähler — exakt dasselbe Prinzip wie
## `TerrainField`/`ChunkManager` (siehe TerrainSeed: Teil-Seeds aus dem world_seed):
## gleicher Seed + gleicher Zähler ⇒ überall identisches Ergebnis, ganz ohne
## Netzwerk-Traffic. Der Zyklus ist an `WorldTimeService.day_count` gekoppelt
## (ein Wetterwurf pro neuem Ingame-Tag) statt an eine eigene Echtzeit-Uhr —
## day_count wird bereits gespeichert/wiederhergestellt, eine zweite,
## unabhängig zu persistierende Uhr wäre hier unnötige Redundanz gewesen.
##
## Bewusst NICHT Teil dieser Runde: visuelle Wetter-Effekte (Partikel/Post-
## Processing), Gameplay-Auswirkungen (z.B. Angel-/Ernte-Boni bei Regen),
## Biom-Abhängigkeit (Wüste bekommt aktuell denselben Pool wie jedes andere
## Biom) — reiner Event-/Zustands-Layer, auf den künftige Systeme aufsetzen
## können. Siehe ADR-041 "Konsequenzen/Negativ".

const LOG_CAT := "Weather"

## Bewusst eine feste, globale Liste statt Biom-Abhängigkeit (siehe Klassenkommentar).
const WEATHER_TYPES: Array[String] = ["clear", "rain", "storm", "fog", "snow"]

const DEFAULT_WEATHER := "clear"

var current_weather: String = DEFAULT_WEATHER

## Der zuletzt für einen Wetterwurf verwendete day_count — verhindert einen
## zweiten Wurf für denselben Tag, falls roll_for_day() mehrfach mit demselben
## Wert aufgerufen wird (z.B. weil on_tick() öfter als einmal pro Frame-Grenze
## läuft, in der day_count gerade hochzählt).
var _last_rolled_day: int = -1

var _bus: IEventBus = null

func set_event_bus(bus: IEventBus) -> void:
	_bus = bus

## Rollt deterministisch ein neues Wetter für `day_count`, wenn dafür noch
## nicht gewürfelt wurde. `world_seed` kommt aus WorldData — pro Welt fest,
## damit alle Peers derselben Welt exakt denselben Wurf berechnen.
func roll_for_day(day_count: int, world_seed: int) -> void:
	if day_count == _last_rolled_day:
		return
	# BUGFIX (Wunsch "Spiel startet immer mit Regen, klares Wetter wäre nett"): der
	# allererste Aufruf (frische Welt, _last_rolled_day noch -1, nie zuvor gewürfelt) würfelte
	# bisher GENAUSO wie jeder spätere Tageswechsel — je nach world_seed konnte Tag 1 also auf
	# jedes der fünf WEATHER_TYPES fallen, inklusive "rain"/"storm" direkt beim Start. Jetzt
	# bleibt der allererste Tag deterministisch bei DEFAULT_WEATHER ("clear", siehe
	# current_weather-Startwert oben) statt gewürfelt zu werden — ab dem nächsten
	# Tageswechsel läuft der normale, seed-abhängige Wurf unverändert weiter (siehe unten).
	var is_first_roll := _last_rolled_day == -1
	_last_rolled_day = day_count
	if is_first_roll:
		if current_weather != DEFAULT_WEATHER:
			var old_weather := current_weather
			current_weather = DEFAULT_WEATHER
			if _bus != null:
				_bus.world().emit_weather_changed(current_weather, old_weather)
		AppLogger.log_info(
			"Erster Wettertag (Tag %d): bleibt bei '%s' statt zu würfeln." % [day_count, DEFAULT_WEATHER],
			LOG_CAT
		)
		return

	var rng := RandomNumberGenerator.new()
	# Analog TerrainSeed.derive() (Terrain): world_seed als
	# Basis, day_count als Zyklus-Index — deterministisch pro Welt+Tag, nie
	# von Time.get_ticks_*() oder echtem Zufall abhängig.
	rng.seed = world_seed * 1000003 + day_count

	var new_weather: String = WEATHER_TYPES[rng.randi_range(0, WEATHER_TYPES.size() - 1)]
	if new_weather == current_weather:
		return

	var old_weather := current_weather
	current_weather = new_weather
	if _bus != null:
		_bus.world().emit_weather_changed(current_weather, old_weather)
	AppLogger.log_info(
		"Wetter geändert (Tag %d): '%s' -> '%s'." % [day_count, old_weather, current_weather],
		LOG_CAT
	)

## Admin/Debug (siehe AdminMenuCommands._cmd_weather() über WorldService.
## admin_set_weather()): setzt das Wetter sofort und direkt, unabhängig vom
## deterministischen Tages-Wurf (roll_for_day()). Bewusst NICHT netzwerk-
## synchronisiert (siehe Klassenkommentar "kein Broadcast-Mechanismus") —
## jeder Peer müsste dies einzeln aufrufen. Für einen lokalen Solo/Host-
## Admin-Testbefehl reicht das (siehe AdminMenuCommands.gd "SCOPE (bewusst):
## nur lokal, Solo/Host"); für Multiplayer-weites Admin-Wetter bewusst nicht
## vorgesehen. Überschreibt _last_rolled_day NICHT — ein späterer, normaler
## roll_for_day() für einen neuen Tag würfelt unbeeinflusst weiter, auch wenn
## der aktuelle Tag hier manuell überschrieben wurde.
func force_weather(new_weather: String) -> bool:
	if new_weather not in WEATHER_TYPES:
		return false
	if new_weather == current_weather:
		return true  # schon dieses Wetter — kein Fehler, einfach nichts zu tun
	var old_weather := current_weather
	current_weather = new_weather
	if _bus != null:
		_bus.world().emit_weather_changed(current_weather, old_weather)
	AppLogger.log_info("Wetter manuell gesetzt: '%s' -> '%s'." % [old_weather, current_weather], LOG_CAT)
	return true

func restore(state: Dictionary) -> void:
	var restored: String = state.get("weather", DEFAULT_WEATHER)
	current_weather = restored if restored in WEATHER_TYPES else DEFAULT_WEATHER
	_last_rolled_day = state.get("weather_last_rolled_day", -1)

func get_save_data() -> Dictionary:
	return {"weather": current_weather, "weather_last_rolled_day": _last_rolled_day}

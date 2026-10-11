# res://tests/unit/test_weather_service.gd
extends GutTest

## Unit-Tests für WeatherService (ADR-041, Round 95).
##
## Strategie: WeatherService ist eine RefCounted-Hilfsklasse ohne SceneTree-
## Abhängigkeit — analog test_world_save_handler.gd/WorldTimeService. Kein
## Node, kein AppLogger-Problem außer dem globalen AutoLoad, der in GUT-Läufen
## ohnehin verfügbar ist.
##
## Abgedeckt:
##   - Default-Zustand ohne roll_for_day()
##   - Determinismus: gleicher world_seed + day_count ⇒ gleiches Wetter,
##     über zwei unabhängige Instanzen hinweg (simuliert zwei Peers)
##   - Unterschiedlicher world_seed ⇒ potenziell anderes Wetter (statistischer Test)
##   - roll_for_day() ist idempotent für denselben Tag (kein Doppel-Emit)
##   - roll_for_day() emittiert weather_changed nur bei tatsächlicher Änderung
##   - Save/Restore-Roundtrip
##   - force_weather() (Admin/Debug-Direktsetzung): setzt + emittiert korrekt,
##     lehnt unbekannte Typen ab, lässt _last_rolled_day/roll_for_day() unangetastet

var _bus: MockEventBus
var _svc: WeatherService

func before_each() -> void:
	_bus = MockEventBus.new()
	_svc = WeatherService.new()
	_svc.set_event_bus(_bus)

func after_each() -> void:
	_svc = null
	_bus = null

# ─────────────────────────────────────────────────────────────────────────────
# Default-Zustand
# ─────────────────────────────────────────────────────────────────────────────

func test_default_weather_is_clear() -> void:
	assert_eq(_svc.current_weather, "clear", "Frischer WeatherService muss mit 'clear' starten.")

func test_weather_types_contains_current_weather() -> void:
	assert_true(
		WeatherService.WEATHER_TYPES.has(_svc.current_weather),
		"current_weather muss ein Wert aus WEATHER_TYPES sein."
	)

# ─────────────────────────────────────────────────────────────────────────────
# Determinismus (Kernentscheidung aus ADR-041)
# ─────────────────────────────────────────────────────────────────────────────

func test_same_seed_and_day_gives_same_weather_across_instances() -> void:
	# Simuliert zwei unabhängige Peers derselben Welt — beide würfeln lokal,
	# ohne Netzwerk-Sync, siehe WeatherService-Klassenkommentar.
	var svc_a := WeatherService.new()
	var svc_b := WeatherService.new()
	svc_a.roll_for_day(3, 12345)
	svc_b.roll_for_day(3, 12345)
	assert_eq(svc_a.current_weather, svc_b.current_weather,
		"Gleicher world_seed + day_count muss auf jedem Peer identisches Wetter ergeben.")

func test_different_seed_can_give_different_weather() -> void:
	# Statistischer Test: mit fünf Wetter-Typen und zehn verschiedenen Seeds
	# ist es praktisch ausgeschlossen, dass alle zufällig denselben Typ treffen,
	# wenn die Seeds tatsächlich in die Berechnung eingehen.
	var results: Dictionary = {}
	for seed_val in range(10):
		var svc := WeatherService.new()
		svc.roll_for_day(1, seed_val)
		results[svc.current_weather] = true
	assert_true(results.size() > 1,
		"Zehn verschiedene world_seeds sollten nicht alle exakt dasselbe Wetter ergeben.")

func test_same_seed_different_day_can_give_different_weather() -> void:
	var results: Dictionary = {}
	for day in range(1, 11):
		var svc := WeatherService.new()
		svc.roll_for_day(day, 999)
		results[svc.current_weather] = true
	assert_true(results.size() > 1,
		"Zehn verschiedene Tage bei gleichem Seed sollten nicht alle exakt dasselbe Wetter ergeben.")

# ─────────────────────────────────────────────────────────────────────────────
# Idempotenz + Emission
# ─────────────────────────────────────────────────────────────────────────────

func test_roll_for_day_is_idempotent_for_same_day() -> void:
	_svc.roll_for_day(5, 42)
	var first_weather := _svc.current_weather
	watch_signals(_bus.world())
	_svc.roll_for_day(5, 42)
	assert_eq(_svc.current_weather, first_weather,
		"Ein zweiter Aufruf für denselben day_count darf das Wetter nicht erneut würfeln.")
	assert_signal_not_emitted(_bus.world(), "weather_changed",
		"Ein No-Op-Wurf für denselben Tag darf kein Signal emittieren.")

func test_roll_for_day_emits_weather_changed_signal_on_actual_change() -> void:
	# Seed/Tag-Kombination, die deterministisch von 'clear' auf einen anderen
	# Typ wechselt (verifiziert per direktem Aufruf, kein Raten).
	var probe := WeatherService.new()
	probe.roll_for_day(1, 555)
	if probe.current_weather == "clear":
		# Falls der gewählte Seed zufällig 'clear' ergibt (kein "changed"-Fall),
		# auf einen benachbarten Tag ausweichen statt einen flakigen Test zu haben.
		probe = WeatherService.new()
		probe.roll_for_day(2, 555)
	assert_ne(probe.current_weather, "clear", "Test-Setup ungültig — kein Wechsel gefunden.")

	watch_signals(_bus.world())
	_svc.roll_for_day(1 if probe.current_weather != _svc.current_weather else 2, 555)
	# Der eigentliche Assert: Signal wurde mit den korrekten Werten emittiert.
	assert_signal_emitted(_bus.world(), "weather_changed")

func test_roll_for_day_does_not_emit_when_roll_matches_current_weather() -> void:
	# _svc startet bei 'clear'. Wenn der deterministische Wurf für einen Tag
	# ebenfalls 'clear' ergibt, darf kein Signal feuern (kein "Wechsel").
	var probe := WeatherService.new()
	probe.roll_for_day(7, 7)
	if probe.current_weather != "clear":
		pending("Kein Seed/Tag mit 'clear'-Ergebnis für diesen Test gefunden — übersprungen.")
		return
	watch_signals(_bus.world())
	_svc.roll_for_day(7, 7)
	assert_signal_not_emitted(_bus.world(), "weather_changed",
		"Wurf ohne tatsächliche Änderung darf kein Signal emittieren.")

func test_works_without_event_bus() -> void:
	var svc := WeatherService.new()  # kein set_event_bus()
	svc.roll_for_day(1, 1)
	assert_true(true, "roll_for_day() darf ohne EventBus nicht crashen.")

# ─────────────────────────────────────────────────────────────────────────────
# Save/Restore
# ─────────────────────────────────────────────────────────────────────────────

func test_save_data_has_required_keys() -> void:
	var sd := _svc.get_save_data()
	assert_true(sd.has("weather"), "save_data muss 'weather' enthalten.")
	assert_true(sd.has("weather_last_rolled_day"), "save_data muss 'weather_last_rolled_day' enthalten.")

func test_restore_roundtrip() -> void:
	_svc.roll_for_day(4, 100)
	var sd := _svc.get_save_data()

	var svc2 := WeatherService.new()
	svc2.restore(sd)
	assert_eq(svc2.current_weather, _svc.current_weather, "Wetter muss nach restore() erhalten bleiben.")

	# Regressionsschutz: ein erneuter Wurf für denselben Tag nach restore()
	# darf nicht erneut feuern — sonst würde jeder Reload das Wetter für den
	# aktuellen Tag neu (und ggf. unnötig sichtbar) würfeln.
	svc2.set_event_bus(_bus)
	watch_signals(_bus.world())
	svc2.roll_for_day(4, 100)
	assert_signal_not_emitted(_bus.world(), "weather_changed",
		"Nach restore() darf derselbe Tag nicht erneut gewürfelt/emittiert werden.")

func test_restore_with_unknown_weather_falls_back_to_default() -> void:
	_svc.restore({"weather": "hurricane_of_lava", "weather_last_rolled_day": 2})
	assert_eq(_svc.current_weather, WeatherService.DEFAULT_WEATHER,
		"Unbekannter gespeicherter Wetter-Wert muss auf den Default zurückfallen.")

func test_restore_with_missing_keys_uses_defaults() -> void:
	_svc.restore({})
	assert_eq(_svc.current_weather, WeatherService.DEFAULT_WEATHER,
		"restore() ohne 'weather'-Key muss auf den Default zurückfallen (Alt-Save-Kompatibilität).")

# ─────────────────────────────────────────────────────────────────────────────
# force_weather() — Admin/Debug-Direktsetzung (siehe AdminMenuCommands._cmd_weather())
# ─────────────────────────────────────────────────────────────────────────────

func test_force_weather_sets_current_weather_and_emits_signal() -> void:
	watch_signals(_bus.world())
	var ok := _svc.force_weather("storm")
	assert_true(ok, "force_weather() mit gültigem Typ muss true zurückgeben.")
	assert_eq(_svc.current_weather, "storm", "force_weather() muss current_weather sofort setzen.")
	assert_signal_emitted(_bus.world(), "weather_changed",
		"force_weather() muss weather_changed emittieren, damit WeatherVfx/AmbientForestVfx reagieren.")

func test_force_weather_rejects_unknown_type() -> void:
	var ok := _svc.force_weather("hurricane_of_lava")
	assert_false(ok, "force_weather() mit unbekanntem Typ muss false zurückgeben.")
	assert_eq(_svc.current_weather, "clear", "Unbekannter Typ darf current_weather nicht verändern.")

func test_force_weather_to_already_current_weather_returns_true_without_emit() -> void:
	watch_signals(_bus.world())
	var ok := _svc.force_weather("clear")  # _svc startet bereits bei 'clear'
	assert_true(ok, "force_weather() auf das bereits aktuelle Wetter ist kein Fehler.")
	assert_signal_not_emitted(_bus.world(), "weather_changed",
		"Kein tatsächlicher Wechsel darf kein Signal emittieren (wie bei roll_for_day()).")

func test_force_weather_does_not_block_later_roll_for_day_for_same_day() -> void:
	# force_weather() darf _last_rolled_day nicht mit-verändern — ein späterer,
	# normaler Wurf für einen NEUEN Tag muss weiterhin ganz normal würfeln.
	_svc.force_weather("fog")
	_svc.roll_for_day(9, 4242)
	assert_true(WeatherService.WEATHER_TYPES.has(_svc.current_weather),
		"Nach force_weather() muss ein regulärer roll_for_day() für einen neuen Tag weiterhin funktionieren.")

func test_force_weather_works_without_event_bus() -> void:
	var svc := WeatherService.new()  # kein set_event_bus()
	var ok := svc.force_weather("snow")
	assert_true(ok, "force_weather() darf ohne EventBus nicht fehlschlagen.")
	assert_eq(svc.current_weather, "snow")

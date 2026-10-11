# res://tests/unit/test_service_ticker.gd
extends GutTest

## Unit-Tests für ServiceTicker (scripts/platform/ServiceTicker.gd) —
## bisher ungetestet (siehe architecture_overview.py-Fund, Round 113).
##
## Strategie: ServiceTicker extends ServiceNode -> add_child_autofree().
## _process()/_physics_process() sind normale (nicht wirklich private)
## GDScript-Methoden und werden hier direkt aufgerufen statt über
## simulate()/echte Frames zu warten — deterministisch, kein SceneTree-Timing
## nötig (analog test_respawn_service.gd: on_tick() wird auch direkt gerufen).
##
## Abgedeckt:
##   register_service() — nur Objekte mit on_tick() landen in _tick_list
##   register_service() — nur Objekte mit on_physics_tick() landen in _physics_tick_list
##   register_service() — ein Objekt mit beiden Methoden landet in beiden Listen
##   register_service() — doppelte Registrierung wird ignoriert (kein Doppel-Tick)
##   start_ticking() — vor dem Aufruf tickt nichts, danach schon
##   _process()/_physics_process() — ruft on_tick()/on_physics_tick() mit dem Delta auf
##   _process() — ungültig gewordene (freed) Referenzen werden automatisch entfernt,
##                ohne die verbleibenden Einträge zu überspringen

class TickSpy:
	extends RefCounted
	var tick_calls: Array = []
	func on_tick(delta: float) -> void:
		tick_calls.append(delta)

class PhysicsTickSpy:
	extends RefCounted
	var physics_tick_calls: Array = []
	func on_physics_tick(delta: float) -> void:
		physics_tick_calls.append(delta)

class BothTickSpy:
	extends RefCounted
	var tick_calls: Array = []
	var physics_tick_calls: Array = []
	func on_tick(delta: float) -> void:
		tick_calls.append(delta)
	func on_physics_tick(delta: float) -> void:
		physics_tick_calls.append(delta)

class NodeTickSpy:
	# Node statt RefCounted: RefCounted-Objekte werden erst ungültig, wenn
	# WIRKLICH keine Referenz mehr existiert — für den "freed während
	# registriert"-Testfall unten braucht es ein Node, das man per free()
	# sofort (ohne Frame-Delay wie bei queue_free()) ungültig machen kann.
	extends Node
	var tick_calls: Array = []
	func on_tick(delta: float) -> void:
		tick_calls.append(delta)

class PlainObject:
	extends RefCounted
	# Hat weder on_tick() noch on_physics_tick() — darf in keiner Liste landen.

var _ticker: ServiceTicker

func before_each() -> void:
	_ticker = add_child_autofree(ServiceTicker.new())

# ─────────────────────────────────────────────
# register_service() — Zuordnung nach vorhandenen Methoden
# ─────────────────────────────────────────────

func test_register_service_with_on_tick_ticks() -> void:
	var spy := TickSpy.new()
	_ticker.register_service(spy)
	_ticker.start_ticking()
	_ticker._process(0.1)
	assert_eq(spy.tick_calls.size(), 1, "on_tick() muss genau einmal aufgerufen werden")
	assert_eq(spy.tick_calls[0], 0.1, "Delta muss unverändert durchgereicht werden")

func test_register_service_with_on_physics_tick_ticks() -> void:
	var spy := PhysicsTickSpy.new()
	_ticker.register_service(spy)
	_ticker.start_ticking()
	_ticker._physics_process(0.02)
	assert_eq(spy.physics_tick_calls.size(), 1, "on_physics_tick() muss genau einmal aufgerufen werden")
	assert_eq(spy.physics_tick_calls[0], 0.02)

func test_register_service_without_matching_method_is_ignored() -> void:
	var plain := PlainObject.new()
	_ticker.register_service(plain)
	_ticker.start_ticking()
	# Darf nicht crashen (kein on_tick()/on_physics_tick() vorhanden) — reiner
	# Verhaltenstest, kein Rückgabewert zu prüfen.
	_ticker._process(0.1)
	_ticker._physics_process(0.02)
	pass_test("register_service() mit einem Objekt ohne Tick-Methoden crasht nicht")

func test_register_service_with_both_methods_lands_in_both_lists() -> void:
	var spy := BothTickSpy.new()
	_ticker.register_service(spy)
	_ticker.start_ticking()
	_ticker._process(0.1)
	_ticker._physics_process(0.02)
	assert_eq(spy.tick_calls.size(), 1)
	assert_eq(spy.physics_tick_calls.size(), 1)

func test_register_service_twice_does_not_double_tick() -> void:
	var spy := TickSpy.new()
	_ticker.register_service(spy)
	_ticker.register_service(spy)
	_ticker.start_ticking()
	_ticker._process(0.1)
	assert_eq(spy.tick_calls.size(), 1, "Doppelte Registrierung darf nicht zu doppeltem Tick führen")

# ─────────────────────────────────────────────
# start_ticking() — Gate für _process()/_physics_process()
# ─────────────────────────────────────────────

func test_process_before_start_ticking_does_nothing() -> void:
	var spy := TickSpy.new()
	_ticker.register_service(spy)
	_ticker._process(0.1)  # start_ticking() NICHT aufgerufen
	assert_eq(spy.tick_calls.size(), 0, "Vor start_ticking() darf nichts ticken")

func test_physics_process_before_start_ticking_does_nothing() -> void:
	var spy := PhysicsTickSpy.new()
	_ticker.register_service(spy)
	_ticker._physics_process(0.02)
	assert_eq(spy.physics_tick_calls.size(), 0)

# ─────────────────────────────────────────────
# Mehrere Services, Reihenfolge und rückwärtige Iteration
# ─────────────────────────────────────────────

func test_multiple_services_all_tick() -> void:
	var a := TickSpy.new()
	var b := TickSpy.new()
	_ticker.register_service(a)
	_ticker.register_service(b)
	_ticker.start_ticking()
	_ticker._process(0.5)
	assert_eq(a.tick_calls.size(), 1)
	assert_eq(b.tick_calls.size(), 1)

# ─────────────────────────────────────────────
# Automatische Bereinigung freigegebener Referenzen
# ─────────────────────────────────────────────

func test_process_removes_freed_service_without_skipping_others() -> void:
	var doomed := NodeTickSpy.new()
	_ticker.register_service(doomed)
	var survivor := TickSpy.new()
	_ticker.register_service(survivor)
	_ticker.start_ticking()

	doomed.free()  # sofort ungültig — kein SceneTree-Parent/Frame-Delay nötig

	assert_eq(_ticker._tick_list.size(), 2, "Vor _process() noch nicht bereinigt")
	_ticker._process(0.1)
	assert_eq(_ticker._tick_list.size(), 1, "Freigegebener Service muss entfernt werden")
	assert_eq(survivor.tick_calls.size(), 1, "Verbleibender Service muss trotzdem ticken, auch wenn ein anderer Eintrag ungültig war")

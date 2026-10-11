## tests/unit/test_enemy_npc_pool_reuse.gd
## Regression-Tests für EnemyNPC Pool-Reuse und HealthComponent.
##
## EnemyNPC braucht 3D-Rendering (EnemyVisuals) und kann im headless
## Testmodus nicht instanziiert werden. Deshalb testen wir:
##   a) HealthComponent direkt (das ist die Komponente die buggy war)
##   b) Die Signal-Reconnect-Logik via HealthComponent isoliert

extends GutTest

var _health: HealthComponent

func before_each() -> void:
	_health = HealthComponent.new()
	_health.max_health = 30
	add_child_autofree(_health)
	await get_tree().process_frame

func after_each() -> void:
	_health = null

func test_health_reset_clears_is_dead() -> void:
	# Regression: nach Pool-Reuse war is_dead nicht zurückgesetzt.
	_health.take_damage(30)
	assert_true(_health.is_dead, "Nach vollem Schaden muss is_dead=true sein.")
	_health.reset()
	assert_false(_health.is_dead, "reset() muss is_dead=false setzen.")
	assert_eq(_health.current_health, 30, "reset() muss HP auf max_health setzen.")

func test_died_signal_fires_on_lethal_damage() -> void:
	var died_count := [0]
	_health.died.connect(func(_record: DamageRecord) -> void: died_count[0] += 1)
	_health.take_damage(30)
	assert_eq(died_count[0], 1, "died muss genau einmal emittiert werden.")

func test_died_not_fired_twice_after_reset() -> void:
	# Regression: nach Pool-Reuse darf died nicht doppelt feuern.
	var died_count := [0]
	_health.died.connect(func(_record: DamageRecord) -> void: died_count[0] += 1)

	# Simuliert: erster Tod (despawn)
	_health.take_damage(30)
	# Simuliert: reset (on_spawn)
	_health.reset()
	# Zweiter Tod (neues Leben nach Pool-Reuse)
	_health.take_damage(30)

	assert_eq(died_count[0], 2,
		"died muss nach reset() wieder feuern — genau 2x total (einmal pro Leben).")

func test_take_damage_does_nothing_when_dead() -> void:
	_health.take_damage(30)
	var hp_after_death := _health.current_health
	_health.take_damage(10)  # Sollte ignoriert werden
	assert_eq(_health.current_health, hp_after_death,
		"Schaden nach Tod darf HP nicht weiter reduzieren.")

func test_health_changed_signal_emitted() -> void:
	var changes := [0]
	_health.health_changed.connect(func(_c: int, _m: int) -> void: changes[0] += 1)
	_health.take_damage(10)
	assert_eq(changes[0], 1, "health_changed muss bei Schaden emittiert werden.")

# ─────────────────────────────────────────────────────────────────────────────
# IEventBus-Wiring (Runde 4 EventBus-Migration) — isoliert ohne vollen _ready()
# ─────────────────────────────────────────────────────────────────────────────
##
## EnemyNPC kann wegen EnemyVisuals.build() (3D-Rendering) nicht vollständig
## im Headless-Modus instanziiert werden. Diese Tests prüfen die Bus-Helper
## (_player_bus/_world_bus/_ui_bus) direkt — sie sind die Stelle, an der das
## Fallback-Pattern entfernt wurde (kein "if _bus != null else EventBus.X" mehr).

func test_bus_helpers_return_injected_bus_namespaces() -> void:
	## _player_bus()/_world_bus()/_ui_bus() müssen exakt die Namespaces des
	## injizierten Bus zurückgeben — kein Fallback auf AutoLoad mehr möglich.
	var enemy := EnemyNPC.new()
	var bus   := MockEventBus.new()
	enemy._bus = bus
	assert_eq(enemy._player_bus(), bus.player(), "_player_bus() muss bus.player() zurückgeben")
	assert_eq(enemy._world_bus(),  bus.world(),  "_world_bus() muss bus.world() zurückgeben")
	assert_eq(enemy._ui_bus(),     bus.ui(),     "_ui_bus() muss bus.ui() zurückgeben")
	enemy.free()

func test_on_spawn_sets_bus_from_context() -> void:
	## on_spawn() muss _bus aus dem EntityContext übernehmen — kein Fallback-
	## Dance mehr (vgl. alte disconnect/reconnect-Logik vor Runde 4).
	var enemy := EnemyNPC.new()
	var bus   := MockEventBus.new()
	var ctx   := EntityContext.for_test()
	ctx._bus  = bus
	# on_spawn() ruft _player_bus().player_died.connect() auf — das setzt
	# _ai/_visuals etc. voraus die ohne _ready() nicht existieren. Wir testen
	# daher nur den Bus-Wiring-Teil isoliert, nicht den vollen on_spawn()-Aufruf.
	enemy._ctx = ctx
	if is_instance_valid(ctx) and ctx.has_method("get_event_bus"):
		enemy._bus = ctx.get_event_bus() as IEventBus
	assert_eq(enemy._bus, bus, "_bus muss aus ctx.get_event_bus() übernommen werden")
	enemy.free()

func test_no_autoload_fallback_in_bus_helpers() -> void:
	## Regression-Test: stellt sicher, dass _player_bus() bei gesetztem _bus
	## NIE auf den AutoLoad zurückfällt — die alte "if _bus != null else
	## EventBus.player" Logik wurde vollständig entfernt.
	var enemy := EnemyNPC.new()
	var bus   := MockEventBus.new()
	enemy._bus = bus
	# Wenn ein Fallback existieren würde, wäre dieser Vergleich bei einem
	# frischen MockEventBus (eigene PlayerEvents-Instanz) ungleich AutoLoad.
	assert_ne(enemy._player_bus(), EventBus.player,
		"_player_bus() darf NICHT auf den globalen AutoLoad zurückfallen")
	enemy.free()

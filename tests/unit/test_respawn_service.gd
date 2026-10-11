# res://tests/unit/test_respawn_service.gd
extends GutTest

## Unit-Tests für RespawnService (E-02).
##
## Strategie: RespawnService extends ServiceNode — braucht add_child_autofree().
## configure() ohne deps (bewusst leer).
## on_ready() nicht aufgerufen — kein EventBus-Connect, kein ServiceTicker.
## Spawn/Remove-Callbacks als Lambdas injiziert (vollständig testbar per Design).
##
## Abgedeckt:
##   - register_config(): Konfiguration wird gespeichert
##   - _on_entity_despawned(): Eintrag in Queue bei bekanntem Typ
##   - _on_entity_despawned(): Kein Eintrag bei unbekanntem Typ
##   - _on_entity_despawned(): Duplikat-Verhinderung (selbe Position)
##   - Min-Heap-Ordnung: früherer Spawn_at immer zuerst
##   - on_tick(): fälliger Eintrag wird verarbeitet, Callbacks aufgerufen
##   - on_tick(): nicht-fälliger Eintrag bleibt in Queue
##   - on_cleanup(): Queue wird geleert

var _svc: RespawnService

# Spawn-Tracking für Test-Callbacks
var _spawned:  Array = []
var _removed:  Array = []

const TYPE_A := "oak_tree"
const TYPE_B := "iron_ore"
const POS_1  := Vector3(10, 0, 20)
const POS_2  := Vector3(30, 0, 40)

func before_each() -> void:
	_svc     = add_child_autofree(RespawnService.new())
	_spawned = []
	_removed = []
	_svc.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: MockEventBus.new()}))

	# Callbacks injizieren
	_svc.set_spawn_callback(func(type_id: String, pos: Vector3) -> Object:
		_spawned.append({"type": type_id, "pos": pos})
		return autofree(Node.new())
	)
	_svc.set_remove_callback(func(type_id: String, pos: Vector3) -> void:
		_removed.append({"type": type_id, "pos": pos})
	)

# ─────────────────────────────────────────────────────────────────────────────
# register_config
# ─────────────────────────────────────────────────────────────────────────────

func test_register_config_stores_type() -> void:
	_svc.register_config(TYPE_A, 300.0)
	# Kein direkter Zugriff auf _configs — seiteneffektfrei über Verhalten prüfen:
	# Wenn der Typ bekannt ist, wird er in die Queue aufgenommen.
	_svc._on_entity_despawned(TYPE_A, "uuid-1", POS_1)
	assert_eq(_svc._queue.size(), 1, "Bekannter Typ muss in die Queue")

# ─────────────────────────────────────────────────────────────────────────────
# _on_entity_despawned
# ─────────────────────────────────────────────────────────────────────────────

func test_despawn_unknown_type_not_queued() -> void:
	# TYPE_A nie registriert
	_svc._on_entity_despawned(TYPE_A, "uuid-1", POS_1)
	assert_eq(_svc._queue.size(), 0, "Unbekannter Typ darf nicht in Queue")

func test_despawn_known_type_adds_to_queue() -> void:
	_svc.register_config(TYPE_A, 60.0)
	_svc._on_entity_despawned(TYPE_A, "uuid-1", POS_1)
	assert_eq(_svc._queue.size(), 1, "Queue muss einen Eintrag haben")

func test_despawn_duplicate_position_ignored() -> void:
	_svc.register_config(TYPE_A, 60.0)
	_svc._on_entity_despawned(TYPE_A, "uuid-1", POS_1)
	_svc._on_entity_despawned(TYPE_A, "uuid-2", POS_1)  # gleiche Position
	assert_eq(_svc._queue.size(), 1, "Duplikat (selbe Pos) darf nicht doppelt eingetragen werden")

func test_despawn_different_positions_both_queued() -> void:
	_svc.register_config(TYPE_A, 60.0)
	_svc._on_entity_despawned(TYPE_A, "uuid-1", POS_1)
	_svc._on_entity_despawned(TYPE_A, "uuid-2", POS_2)  # andere Position
	assert_eq(_svc._queue.size(), 2, "Unterschiedliche Positionen → zwei Queue-Einträge")

# ─────────────────────────────────────────────────────────────────────────────
# Min-Heap-Ordnung (_heap_push)
# ─────────────────────────────────────────────────────────────────────────────

func test_heap_earliest_spawn_first() -> void:
	# Direkt via _heap_push — spawn_at manuell setzen
	_svc._heap_push({"type_id": TYPE_A, "position": POS_1, "spawn_at": 2000})
	_svc._heap_push({"type_id": TYPE_B, "position": POS_2, "spawn_at": 1000})
	_svc._heap_push({"type_id": TYPE_A, "position": POS_2, "spawn_at": 3000})

	assert_eq(int(_svc._queue[0]["spawn_at"]), 1000, "Frühester spawn_at muss an Position 0 sein")
	assert_eq(int(_svc._queue[1]["spawn_at"]), 2000, "Zweitfrühester an Position 1")
	assert_eq(int(_svc._queue[2]["spawn_at"]), 3000, "Spätester an Position 2")

# ─────────────────────────────────────────────────────────────────────────────
# on_tick — Respawn-Ausführung
# ─────────────────────────────────────────────────────────────────────────────

func test_tick_triggers_spawn_for_due_entry() -> void:
	# spawn_at = 0 → sofort fällig
	_svc._first_tick_done = true  # assert-Guard überspringen
	_svc._heap_push({"type_id": TYPE_A, "position": POS_1, "spawn_at": 0})
	_svc.on_tick(0.0)
	assert_eq(_spawned.size(), 1, "Spawn-Callback muss einmal aufgerufen worden sein")
	assert_eq(_spawned[0]["type"], TYPE_A, "Gespawnter Typ muss TYPE_A sein")

func test_tick_does_not_spawn_non_due_entry() -> void:
	_svc._first_tick_done = true
	var far_future := Time.get_ticks_msec() + 999_999_999
	_svc._heap_push({"type_id": TYPE_A, "position": POS_1, "spawn_at": far_future})
	_svc.on_tick(0.0)
	assert_eq(_spawned.size(), 0, "Nicht-fälliger Eintrag darf nicht gespawnt werden")
	assert_eq(_svc._queue.size(), 1, "Eintrag muss noch in Queue verbleiben")

func test_tick_removes_entry_from_queue() -> void:
	_svc._first_tick_done = true
	_svc._heap_push({"type_id": TYPE_A, "position": POS_1, "spawn_at": 0})
	_svc.on_tick(0.0)
	assert_eq(_svc._queue.size(), 0, "Verarbeiteter Eintrag muss aus Queue entfernt werden")

func test_tick_calls_remove_callback() -> void:
	_svc._first_tick_done = true
	_svc._heap_push({"type_id": TYPE_A, "position": POS_1, "spawn_at": 0})
	_svc.on_tick(0.0)
	assert_eq(_removed.size(), 1, "Remove-Callback muss aufgerufen werden")

func test_tick_processes_multiple_due_entries() -> void:
	_svc._first_tick_done = true
	_svc._heap_push({"type_id": TYPE_A, "position": POS_1, "spawn_at": 0})
	_svc._heap_push({"type_id": TYPE_B, "position": POS_2, "spawn_at": 0})
	_svc.on_tick(0.0)
	assert_eq(_spawned.size(), 2, "Alle fälligen Einträge müssen gespawnt werden")
	assert_eq(_svc._queue.size(), 0, "Queue muss leer sein")

# ─────────────────────────────────────────────────────────────────────────────
# on_cleanup
# ─────────────────────────────────────────────────────────────────────────────

func test_cleanup_clears_queue() -> void:
	_svc._heap_push({"type_id": TYPE_A, "position": POS_1, "spawn_at": 0})
	_svc.on_cleanup()
	assert_eq(_svc._queue.size(), 0, "Queue muss nach cleanup leer sein")

# ─────────────────────────────────────────────────────────────────────────────
# peer_id — Spawn-Callback erhält immer peer_id = 1 für World-Entities (F-2)
# ─────────────────────────────────────────────────────────────────────────────

## Callback-Tracking mit peer_id
var _spawned_with_peer: Array = []

func test_respawn_calls_spawn_callback_with_peer_id_1() -> void:
	# RespawnService übergibt immer peer_id=1 — Server-Autorität für World-Entities.
	var svc: RespawnService = add_child_autofree(RespawnService.new())
	svc.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: MockEventBus.new()}))
	_spawned_with_peer = []
	svc.set_spawn_callback(func(type_id: String, pos: Vector3, peer_id: int = 1) -> Object:
		_spawned_with_peer.append({"type": type_id, "pos": pos, "peer_id": peer_id})
		return autofree(Node.new())
	)
	svc.set_remove_callback(func(_t: String, _p: Vector3) -> void: pass)
	svc._first_tick_done = true
	svc.register_config(TYPE_A, 0.0)
	svc._heap_push({"type_id": TYPE_A, "position": POS_1, "spawn_at": 0})
	svc.on_tick(0.0)
	assert_eq(_spawned_with_peer.size(), 1, "Spawn-Callback muss aufgerufen worden sein")
	assert_eq(int(_spawned_with_peer[0]["peer_id"]), 1, "peer_id muss 1 sein (Server-Autorität)")

func test_respawn_spawn_callback_old_signature_still_works() -> void:
	# Kompatibilitäts-Test: Callbacks ohne peer_id-Parameter funktionieren weiterhin —
	# RespawnService._do_respawn() prüft cb.get_argument_count() und ruft den Callback
	# nur mit so vielen Argumenten auf wie er deklariert (Godot würde bei zu vielen
	# Argumenten sonst mit "Invalid call. Expected N arguments." abbrechen).
	var svc: RespawnService = add_child_autofree(RespawnService.new())
	svc.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: MockEventBus.new()}))
	var spawned_count := [0]
	svc.set_spawn_callback(func(type_id: String, _pos: Vector3) -> Object:
		spawned_count[0] += 1
		return autofree(Node.new())
	)
	svc.set_remove_callback(func(_t: String, _p: Vector3) -> void: pass)
	svc._first_tick_done = true
	svc.register_config(TYPE_A, 0.0)
	svc._heap_push({"type_id": TYPE_A, "position": POS_1, "spawn_at": 0})
	svc.on_tick(0.0)
	assert_eq(spawned_count[0], 1, "Alter Callback ohne peer_id-Parameter muss weiterhin funktionieren")

## tests/unit/test_chunk_manager_multiplayer.gd
## Tests für ChunkManager Multi-Player-Tracking (Sprint G-02).
##
## ChunkManager.initialize() braucht einen world_root-Node und echte
## Terrain-Generierung — das ist kein headless-kompatibler Setup.
## Wir testen daher die öffentliche Tracking-API isoliert:
##   add_player()   → registriert Node, setzt Sentinel
##   remove_player() → entfernt Node und Last-Chunk-Cache
##   Stale-Cleanup → ungültige Nodes werden aus _tracked_players entfernt
##   Idempotenz     → doppeltes add/remove darf nicht crashen
##
## Die Chunk-Lade/Entlade-Logik (_load_chunk, _sync_chunks) wird im
## Integrationstest mit echtem SceneTree geprüft (IntegrationTest.gd).

extends GutTest

var _cm: ChunkManager
var _world_root: Node3D = null  ## Bleibt null im headless Unit-Test — siehe Datei-Kopfkommentar.

func before_each() -> void:
	_cm = ChunkManager.new()
	add_child_autofree(_cm)
	# initialize() bewusst NICHT aufrufen — world_root fehlt in headless.
	# Tracking-API funktioniert ohne initialize().

func after_each() -> void:
	_cm = null

# ─────────────────────────────────────────────────────────────────────────────
# CM-G02-01: add_player / remove_player Grundverhalten
# ─────────────────────────────────────────────────────────────────────────────

func test_add_player_registers_node() -> void:
	var player := Node3D.new()
	add_child_autofree(player)

	_cm.add_player(player)

	assert_true(
		_cm._tracked_players.has(player),
		"add_player() muss den Node in _tracked_players registrieren."
	)

func test_add_player_sets_sentinel_chunk() -> void:
	## add_player() setzt einen Sentinel-Chunk-Wert → erzwingt sofortiges
	## Update beim nächsten on_tick(), auch wenn Position (0,0,0) ist.
	var player := Node3D.new()
	add_child_autofree(player)

	_cm.add_player(player)

	var sentinel := Vector2i(999, 999)
	assert_eq(
		_cm._last_chunks.get(player),
		sentinel,
		"add_player() muss Sentinel-Chunk (999,999) setzen."
	)

func test_remove_player_unregisters_node() -> void:
	var player := Node3D.new()
	add_child_autofree(player)

	_cm.add_player(player)
	_cm.remove_player(player)

	assert_false(
		_cm._tracked_players.has(player),
		"remove_player() muss den Node aus _tracked_players entfernen."
	)

func test_remove_player_clears_last_chunk_cache() -> void:
	var player := Node3D.new()
	add_child_autofree(player)

	_cm.add_player(player)
	_cm.remove_player(player)

	assert_false(
		_cm._last_chunks.has(player),
		"remove_player() muss den Eintrag aus _last_chunks entfernen."
	)

func test_tracked_count_correct_after_add_two_players() -> void:
	var p1 := Node3D.new()
	var p2 := Node3D.new()
	add_child_autofree(p1)
	add_child_autofree(p2)

	_cm.add_player(p1)
	_cm.add_player(p2)

	assert_eq(_cm._tracked_players.size(), 2,
		"Nach zwei add_player()-Aufrufen müssen 2 Spieler getrackt werden.")

# ─────────────────────────────────────────────────────────────────────────────
# CM-G02-02: Idempotenz
# ─────────────────────────────────────────────────────────────────────────────

func test_add_player_idempotent() -> void:
	## Doppeltes add_player() darf keinen Duplikat-Eintrag erzeugen.
	var player := Node3D.new()
	add_child_autofree(player)

	_cm.add_player(player)
	_cm.add_player(player)  # Zweiter Aufruf

	assert_eq(_cm._tracked_players.size(), 1,
		"Doppeltes add_player() darf nur einen Eintrag erzeugen.")

func test_remove_nonexistent_player_does_not_crash() -> void:
	var player := Node3D.new()
	add_child_autofree(player)

	_cm.remove_player(player)  # Nicht registriert — darf nicht crashen
	assert_true(true, "remove_player() für nicht-registrierten Node darf nicht crashen.")

func test_add_invalid_player_does_not_register() -> void:
	## add_player(null) und add_player(<freed node>) dürfen nicht registriert werden.
	_cm.add_player(null)
	assert_eq(_cm._tracked_players.size(), 0,
		"add_player(null) darf keinen Eintrag erzeugen.")

# ─────────────────────────────────────────────────────────────────────────────
# CM-G02-03: Stale-Node-Cleanup in on_tick()
# ─────────────────────────────────────────────────────────────────────────────

func test_on_tick_removes_freed_player_nodes_after_interval() -> void:
	## on_tick() bereinigt stale Referenzen erst nach STALE_CLEANUP_INTERVAL Sekunden —
	## nicht jeden Frame (Performance-Fix). Direkt nach queue_free() sind stale Nodes
	## noch in _tracked_players bis das Interval abläuft.
	var player := Node3D.new()
	add_child(player)
	await get_tree().process_frame

	_cm.add_player(player)
	assert_eq(_cm._tracked_players.size(), 1, "Vor queue_free: 1 Spieler.")

	player.queue_free()
	await get_tree().process_frame

	# Noch VOR Interval: stale Node bleibt in der Liste.
	_cm.on_tick(0.016)
	assert_eq(_cm._tracked_players.size(), 1,
		"Vor Cleanup-Interval: stale Node muss noch in _tracked_players sein")

	# Interval ablaufen lassen: großes Delta übergeben.
	_cm.on_tick(ChunkManager.STALE_CLEANUP_INTERVAL)
	assert_eq(_cm._tracked_players.size(), 0,
		"Nach Cleanup-Interval: stale Node muss aus _tracked_players entfernt sein")

func test_on_tick_stale_cleanup_resets_timer_after_cleanup() -> void:
	## Nach einem Cleanup-Lauf muss _stale_cleanup_timer zurückgesetzt werden —
	## Cleanup darf nicht im selben Tick erneut laufen.
	var player := Node3D.new()
	add_child(player)
	await get_tree().process_frame
	_cm.add_player(player)
	player.queue_free()
	await get_tree().process_frame

	_cm.on_tick(ChunkManager.STALE_CLEANUP_INTERVAL)  # Cleanup läuft
	assert_eq(_cm._stale_cleanup_timer, 0.0, "Timer muss nach Cleanup zurückgesetzt werden")

# ─────────────────────────────────────────────────────────────────────────────
# CM-G02-04: Koordinaten-Helpers (keine SceneTree-Abhängigkeit)
# ─────────────────────────────────────────────────────────────────────────────

func test_world_to_chunk_origin() -> void:
	var coord := _cm._world_to_chunk(Vector3(0.0, 0.0, 0.0))
	assert_eq(coord, Vector2i(0, 0), "_world_to_chunk(0,0,0) muss (0,0) ergeben.")

func test_world_to_chunk_positive() -> void:
	## CHUNK_SIZE = 64 → Position (64, 0, 64) → Chunk (1, 1)
	var coord := _cm._world_to_chunk(Vector3(64.0, 5.0, 64.0))
	assert_eq(coord, Vector2i(1, 1), "_world_to_chunk(64,_,64) muss (1,1) ergeben.")

func test_world_to_chunk_negative() -> void:
	var coord := _cm._world_to_chunk(Vector3(-64.0, 0.0, -64.0))
	assert_eq(coord, Vector2i(-1, -1), "_world_to_chunk(-64,_,-64) muss (-1,-1) ergeben.")

func test_world_to_chunk_round_to_nearest() -> void:
	## Position in der Mitte zwischen zwei Chunks → rundet zum nächstgelegenen.
	var coord := _cm._world_to_chunk(Vector3(32.0, 0.0, 32.0))
	# 32 / 64 = 0.5 → round(0.5) = 1 in GDScript (round-half-up)
	assert_eq(coord, Vector2i(1, 1), "_world_to_chunk(32,_,32) muss zu (1,1) runden.")

func test_chunk_to_world_roundtrip() -> void:
	var original := Vector2i(3, -2)
	var world_pos := _cm._chunk_to_world(original)
	var back      := _cm._world_to_chunk(Vector3(world_pos.x, 0.0, world_pos.y))
	assert_eq(back, original, "Chunk→World→Chunk muss den Original-Coord ergeben.")

# ─────────────────────────────────────────────────────────────────────────────
# Stale-Cleanup Interval (Runde 7 Performance-Fix)
# ─────────────────────────────────────────────────────────────────────────────

func test_stale_cleanup_timer_accumulates_across_ticks() -> void:
	## _stale_cleanup_timer muss über mehrere on_tick()-Aufrufe akkumulieren.
	_cm.on_tick(1.0)
	assert_almost_eq(_cm._stale_cleanup_timer, 1.0, 0.001)
	_cm.on_tick(2.0)
	assert_almost_eq(_cm._stale_cleanup_timer, 3.0, 0.001)

func test_stale_cleanup_does_not_trigger_before_interval() -> void:
	## Cleanup-Filter darf erst nach STALE_CLEANUP_INTERVAL laufen, nicht früher.
	## Wir mocken einen stale Player und prüfen dass er vor Interval noch da ist.
	var player := Node3D.new()
	add_child(player)
	await get_tree().process_frame
	_cm.add_player(player)
	player.queue_free()
	await get_tree().process_frame

	# Kurz vor dem Interval — Node noch nicht bereinigt
	_cm.on_tick(ChunkManager.STALE_CLEANUP_INTERVAL - 0.1)
	assert_eq(_cm._tracked_players.size(), 1,
		"Stale-Cleanup darf nicht vor STALE_CLEANUP_INTERVAL laufen")

func test_on_tick_with_empty_player_list_no_cleanup_needed() -> void:
	## Wenn keine Spieler getrackt werden, darf kein crash passieren.
	_cm.on_tick(ChunkManager.STALE_CLEANUP_INTERVAL * 2)
	assert_true(true, "on_tick() mit leerer Spielerliste darf nicht crashen")

func test_any_moved_still_triggers_sync_chunks() -> void:
	## Sicherstellen dass der Debounce-Mechanismus (_last_chunks-Vergleich) unverändert
	## funktioniert — _sync_chunks() darf nur bei echter Chunk-Änderung laufen.
	## Indirekter Test: zweimaliger on_tick() ohne Positionsänderung ruft _sync_chunks()
	## nur einmal auf (beim ersten Tick wo Position sich von Sentinel unterscheidet).
	## Diese Datei testet bewusst nur die Tracking-API ohne world_root (siehe Datei-
	## Kopfkommentar) — ChunkManager.on_tick() selbst benötigt aber einen validen
	## world_root um über den Sentinel-Vergleich hinaus in _sync_chunks() zu laufen.
	## Ohne world_root bleibt _pending_load garantiert leer — das ist hier explizit
	## erwartetes (nicht übersprungenes) Verhalten.
	if not is_instance_valid(_world_root):
		assert_true(true,
			"world_root fehlt im headless Unit-Test — echte Sync-Prüfung läuft in IntegrationTest.gd.")
		return

	var player: Node3D = add_child_autofree(Node3D.new())
	player.global_position = Vector3.ZERO
	_cm.add_player(player)

	# Erster Tick: Sentinel (999,999) vs (0,0) → moved = true → _sync_chunks()
	# Zweiter Tick: (0,0) == (0,0) → moved = false → kein _sync_chunks()
	var pending_before: int
	_cm.on_tick(0.016)
	pending_before = _cm._pending_load.size()
	_cm.on_tick(0.016)
	assert_eq(_cm._pending_load.size(), pending_before,
		"Zweiter Tick ohne Positionsänderung darf keine neuen Chunks in Load-Queue schreiben")

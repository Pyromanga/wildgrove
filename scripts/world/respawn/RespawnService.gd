extends ServiceNode
# justified: ServiceTicker-Registrierung (add_child) und on_tick() brauchen Node-Lifecycle.
class_name RespawnService

## RespawnService — Nachhaltiges Respawn-System für World-Entities.
##
## ── DESIGN-ENTSCHEIDUNG (Abhängigkeitsproblem gelöst) ────────────────────────
## Problem: RespawnService braucht WorldService (spawn_entity, data),
##          WorldService braucht RespawnService (register_config).
##          → Zirkuläre DI-Abhängigkeit.
##
## Lösung: RespawnService kennt WorldService NICHT.
##   Stattdessen zwei schmale Callbacks, injiziert von WorldService.on_ready():
##     spawn_callback:   Callable(type_id: String, pos: Vector3) -> Node3D
##     remove_harvested: Callable(type_id: String, pos: Vector3) -> void
##
##   WorldService injiziert seine eigenen Methoden als Closures:
##
##   Ergebnis: Keine direkte Service-Referenz in RespawnService,
##   kein zirkulärer Graph. Vollständig testbar durch Mock-Callables.
## ─────────────────────────────────────────────────────────────────────────────
##
## Konfiguration (von WorldService.on_ready() aufgerufen):
##   respawn.register_config("oak_tree", 300.0)   # 5 Minuten
##   respawn.register_config("iron_ore", 600.0)   # 10 Minuten
##   respawn.set_spawn_callback(func(t, p): world.spawn_entity(t, p))
##   respawn.set_remove_callback(func(t, p): world.data.unmark_harvested(t, p))
##
## Abhängigkeiten (deps): [] — bewusst leer, alles via Callbacks

const LOG_CAT := "RespawnService"

## { type_id: RespawnConfig }
var _configs: Dictionary = {}

## Invariante: _queue[0] ist immer der früheste Respawn.
## on_tick() prüft NUR _queue[0] — wenn dieser nicht fällig ist, kann nichts anderes
## fällig sein. O(1) statt O(n) pro Tick.
##
## Heap-Operationen:
##   _heap_push(entry) — O(log n) sorted-insert
##   _heap_pop()       — O(1) remove from front (Array.pop_front)
## Für die erwarteten Queue-Größen (< 1000) ist sorted-insert ausreichend.
## Bei Bedarf auf einen echten Binary-Heap upgraden.
var _queue: Array = []  ## Min-Heap: sortiert nach spawn_at aufsteigend
## Dedup-Set: "type_id_x_y_z" → true.
## Ermöglicht O(1)-Prüfung in _on_entity_despawned() statt O(n)-Scan der Queue.
var _queue_set: Dictionary = {}

## Injizierte Callbacks — von WorldService.on_ready() gesetzt.
## Callable(type_id: String, position: Vector3, peer_id: int) -> Node3D
## peer_id: Multiplayer-Autorität — 1 für Server-Entities, echte Peer-ID für Player.
var _spawn_cb: Callable = Callable()
## Callable(type_id: String, position: Vector3) -> void
var _remove_cb: Callable = Callable()

## Beim ersten Tick mit leerem _spawn_cb → assert statt stiller return.
## So wird ein fehlendes WorldService.on_ready() sofort sichtbar, nicht erst
## wenn nach 5 Minuten der erste Respawn ausbleibt.
var _first_tick_done: bool = false
var _ticker: ServiceTicker = null
var _bus:    IEventBus

# ─────────────────────────────────────────────
# Phase 4: Configure
# ─────────────────────────────────────────────

func configure(deps: ServiceDeps) -> void:
	_ticker = deps.get_optional(ServiceKeys.TICKER) as ServiceTicker
	_bus    = deps.require(ServiceKeys.EVENT_BUS)   as IEventBus
	AppLogger.log_debug("RespawnService konfiguriert (wartet auf Callback-Injection).", LOG_CAT)

# ─────────────────────────────────────────────
# Phase 5: on_ready
# ─────────────────────────────────────────────

func on_ready() -> void:
	_bus.world().entity_despawned.connect(_on_entity_despawned)
	if is_instance_valid(_ticker):
		_ticker.register_service(self)
	AppLogger.log_info("RespawnService bereit.", LOG_CAT)

# ─────────────────────────────────────────────
# Phase 7: on_cleanup
# ─────────────────────────────────────────────

func on_cleanup() -> void:
	_queue.clear()
	_queue_set.clear()
	_spawn_cb = Callable()
	_remove_cb = Callable()
	AppLogger.log_debug("RespawnService bereinigt.", LOG_CAT)

# ─────────────────────────────────────────────
# Callback-Injection (von WorldService.on_ready())
# ─────────────────────────────────────────────

## Setzt den Spawn-Callback.
## cb: Callable(type_id: String, position: Vector3, peer_id: int = 1) -> Node3D
## peer_id ist optional — World-Entities (Bäume, Erze, Feinde) übergeben immer 1.
func set_spawn_callback(cb: Callable) -> void:
	assert(cb.is_valid(), "RespawnService.set_spawn_callback: Callable ist ungültig!")
	_spawn_cb = cb
	AppLogger.log_debug("Spawn-Callback injiziert.", LOG_CAT)

## Setzt den Remove-Callback (entfernt harvested-Marker aus WorldData).
## cb: Callable(type_id: String, position: Vector3) -> void
func set_remove_callback(cb: Callable) -> void:
	assert(cb.is_valid(), "RespawnService.set_remove_callback: Callable ist ungültig!")
	_remove_cb = cb
	AppLogger.log_debug("Remove-Callback injiziert.", LOG_CAT)

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

## Registriert Respawn-Konfiguration für einen Entity-Typ.
## Muss aufgerufen werden bevor die ersten entity_despawned-Events ankommen.
func register_config(entity_type: String, cooldown_secs: float, max_instances: int = 0) -> void:
	var cfg := RespawnConfig.new()
	cfg.entity_type   = entity_type
	cfg.cooldown_secs = cooldown_secs
	cfg.max_instances = max_instances
	_configs[entity_type] = cfg
	AppLogger.log_debug(
		"Config: '%s' → %.0fs (max: %s)" % [
			entity_type, cooldown_secs,
			str(max_instances) if max_instances > 0 else "∞"
		],
		LOG_CAT
	)

## Debug: Gibt ausstehende Respawn-Einträge zurück.
func get_queue_debug() -> Array:
	var now := Time.get_ticks_msec()
	var out := []
	for e in _queue:
		out.append({
			"type":    e["type_id"],
			"pos":     e["position"],
			"secs":    max(0.0, (e["spawn_at"] - now) / 1000.0)
		})
	return out

# ─────────────────────────────────────────────
# Tick — fällige Respawns ausführen
# ─────────────────────────────────────────────

func on_tick(_delta: float) -> void:
	# Beim ersten Tick prüfen ob der Callback injiziert wurde.
	# Fehlt er hier, wurde WorldService.on_ready() nicht vollständig ausgeführt —
	# assert macht das sofort sichtbar statt erst beim ersten ausbleibenden Respawn.
	if not _first_tick_done:
		_first_tick_done = true
		assert(_spawn_cb.is_valid(), \
			"RespawnService: _spawn_cb fehlt beim ersten on_tick()! " + \
			"WorldService.on_ready() hat set_spawn_callback() nicht aufgerufen.")

	# Wenn der früheste Eintrag noch nicht fällig ist, kann kein anderer es sein.
	if _queue.is_empty():
		return
	if not _spawn_cb.is_valid():
		return

	var now := Time.get_ticks_msec()
	# Tick-Budget: maximal 3 Respawns pro Frame.
	# Verhindert Frame-Spikes wenn viele Entities gleichzeitig fällig werden
	# (z.B. 40 Bäume alle nach 300s). Rest kommt beim nächsten Tick.
	var budget := 3
	while not _queue.is_empty() and now >= _queue[0]["spawn_at"] and budget > 0:
		var e: Dictionary = _queue.pop_front()
		_do_respawn(e["type_id"], e["position"])
		budget -= 1

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _on_entity_despawned(type_id: String, _uuid: String, position: Vector3) -> void:
	## entity_despawned übergibt bereits die Position (aus EntityOrchestrator.despawn_entity).
	## Wir nutzen sie direkt — kein fragiler WorldData-Scan mehr.

	if not _configs.has(type_id):
		return  # Kein Respawn für diesen Typ konfiguriert

	# O(1) Dedup-Prüfung via _queue_set (statt O(n)-Scan der Queue).
	var dedup_key := WorldData.make_key(type_id, position)
	if _queue_set.has(dedup_key):
		AppLogger.log_debug(
			"Respawn für '%s' @ %s bereits in Queue." % [type_id, str(position)], LOG_CAT
		)
		return

	var cfg: RespawnConfig = _configs[type_id]
	var spawn_at := Time.get_ticks_msec() + int(cfg.cooldown_secs * 1000.0)
	_heap_push({"type_id": type_id, "position": position, "spawn_at": spawn_at})
	_queue_set[dedup_key] = true

	AppLogger.log_info(
		"Respawn eingeplant: '%s' @ %s in %.0fs." % [type_id, str(position), cfg.cooldown_secs],
		LOG_CAT
	)

# ─────────────────────────────────────────────
# Min-Heap Hilfsfunktionen
# ─────────────────────────────────────────────

## Sorted-Insert in die Min-Heap (geordnet nach spawn_at aufsteigend).
## O(log n) via Binary-Search + insert.
## Für n < 1000 (realistisch pro Chunk) ist dies performant genug.
func _heap_push(entry: Dictionary) -> void:
	var spawn_at: int = entry["spawn_at"]
	# Binary search für die Einfügeposition
	var lo := 0
	var hi := _queue.size()
	while lo < hi:
		var mid := (lo + hi) / 2
		if int(_queue[mid]["spawn_at"]) <= spawn_at:
			lo = mid + 1
		else:
			hi = mid
	if lo >= _queue.size():
		_queue.append(entry)
	else:
		_queue.insert(lo, entry)

func _do_respawn(type_id: String, position: Vector3) -> void:
	# Dedup-Entry entfernen so dass die Position nach erneutem Harvest wieder eingereiht werden kann.
	var dedup_key := WorldData.make_key(type_id, position)
	_queue_set.erase(dedup_key)

	# Harvested-Marker entfernen (via injiziertem Callback)
	if _remove_cb.is_valid():
		_remove_cb.call(type_id, position)
	else:
		AppLogger.log_warn("remove_callback fehlt — harvested-Marker bleibt.", LOG_CAT)

	# Entity spawnen (via injiziertem Callback)
	# peer_id = 1: Respawn-Entities sind immer Server-autoritär.
	# Für Player-Respawn (zukünftig) müsste der Queue-Eintrag eine peer_id mitführen.
	if not _spawn_cb.is_valid():
		AppLogger.log_error("spawn_callback fehlt — Respawn abgebrochen!", LOG_CAT)
		return

	# peer_id ist optional in der Callback-Signatur (siehe set_spawn_callback) — nur
	# mitgeben wenn der Callback ihn tatsächlich entgegennimmt, sonst bricht der Call
	# bei altem 2-Parameter-Callback mit "Expected 2 arguments" ab.
	var entity
	if _spawn_cb.get_argument_count() >= 3:
		entity = _spawn_cb.call(type_id, position, 1)
	else:
		entity = _spawn_cb.call(type_id, position)
	if is_instance_valid(entity):
		AppLogger.log_info("Respawn: '%s' @ %s." % [type_id, str(position)], LOG_CAT)
	else:
		AppLogger.log_error("Respawn fehlgeschlagen: '%s' @ %s." % [type_id, str(position)], LOG_CAT)

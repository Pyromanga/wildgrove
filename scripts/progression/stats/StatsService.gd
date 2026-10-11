extends Service
class_name StatsService

## ADR-047: Statistiken (Vorstufe für stat-basierte Achievements).
##
## Trackt kumulative, pro Spieler geführte Zähler (`STAT_METERS_WALKED`/
## `STAT_METERS_JUMPED`/`STAT_METERS_FALLEN`/`STAT_NPCS_KILLED`, weitere
## künftig einfach ergänzbar — kein fixes Schema, `add_stat()` akzeptiert
## jeden `stat_name`-String). Zwei autoritative Quell-Signale, beide durch
## Konstruktion NUR auf der Autorität feuernd (kein `_require_authority()`-
## Guard hier nötig, siehe jeweiliger Kommentar):
##
##   - `EventBus.player().movement_stats_batch` — neu in Round 103
##     (`Player.gd._track_movement_stats()`), feuert AUSSCHLIESSLICH aus
##     `_loop_free_authoritative()` (nie aus `_loop_free_predicted()`/
##     `_resimulate_from()`) — durch Konstruktion also nur auf dem Prozess,
##     der `is_multiplayer_authority()` für den jeweiligen Player-Node ist.
##   - `EventBus.world().enemy_killed` — bereits seit Längerem bestehend,
##     von `QuestService` für Kill-Objectives genutzt (derselbe
##     Vertrauens-Präzedenzfall: `EnemyNPC._die()` läuft nur dort, wo
##     tatsächlich Schaden autoritativ appliziert wurde).
##
## Beide liefern `peer_id: int`, keine `player_id: String` — Übersetzung via
## `NetworkBridge.get_player_id_for_peer()`, identisches 5-Zeilen-Muster wie
## `QuestService._resolve_player_uuid()`/`RewardDispatcher._resolve_player_uuid()`.
##
## PERSISTENZ: `SAVE_KEY = "stats"` — überlebt Sitzungen, Save-Interface
## exakt nach `AuraService`/`ReportService`/`AchievementService`-Muster.
##
## `stat_changed(player_id, stat_name, delta, new_total)` ist die
## Trigger-Quelle für `AchievementService` (Round 103, siehe dort) — vierte
## Trigger-Quelle neben PvP-Kill/Auktion/Meldung.
##
## BEWUSST NICHT TEIL DIESER RUNDE: kein Snapshot-/Sync-Pfad für spät
## joinende Clients (analog `AchievementService`), kein UI-Panel/
## `UIContext`-Eintrag, keine weiteren Stat-Quellen über die zwei genannten
## hinaus (Angel-Fänge, Ernte-Mengen, Handwerk-Anzahl etc. wären künftige
## eigenständige Ergänzungen, kein struktureller Umbau nötig dafür).

const LOG_CAT := "StatsService"
const SAVE_KEY := "stats"

const STAT_METERS_WALKED := "meters_walked"
const STAT_METERS_JUMPED := "meters_jumped"
const STAT_METERS_FALLEN := "meters_fallen"
const STAT_NPCS_KILLED := "npcs_killed"

## Emittiert bei jeder Änderung eines Stat-Werts — die Trigger-Quelle für
## AchievementService.
signal stat_changed(player_id: String, stat_name: String, delta: float, new_total: float)

var _save_system: SaveSystem = null
var _network: NetworkBridge = null
var _bus: IEventBus = null

## player_id -> Dictionary(stat_name -> Zahlenwert (float, auch für reine
## Integer-Zähler wie npcs_killed — ein einheitlicher Typ vereinfacht
## Save-Rundlauf und add_stat()s Signatur)).
var _stats: Dictionary = {}

func configure(deps: ServiceDeps) -> void:
	_save_system = deps.get_optional(ServiceKeys.SAVE_SYSTEM)    as SaveSystem
	_network     = deps.get_optional(ServiceKeys.NETWORK_BRIDGE) as NetworkBridge
	_bus         = deps.get_optional(ServiceKeys.EVENT_BUS)      as IEventBus

	if is_instance_valid(_bus):
		_bus.player().movement_stats_batch.connect(_on_movement_stats_batch)
		_bus.world().enemy_killed.connect(_on_enemy_killed)
	else:
		AppLogger.log_error("Abhängigkeit 'event_bus' fehlt — Stat-Tracking inaktiv!", LOG_CAT)

	if _save_system:
		_save_system.register_save_provider(self)
		var saved: Variant = _save_system.get_state_for(SAVE_KEY)
		if saved is Dictionary and not (saved as Dictionary).is_empty():
			_restore_from_save(saved)
	else:
		AppLogger.log_error("Abhängigkeit 'savesystem' fehlt!", LOG_CAT)

	AppLogger.log_info("StatsService initialisiert.", LOG_CAT)

func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network

func on_cleanup() -> void:
	if is_instance_valid(_bus):
		if _bus.player().movement_stats_batch.is_connected(_on_movement_stats_batch):
			_bus.player().movement_stats_batch.disconnect(_on_movement_stats_batch)
		if _bus.world().enemy_killed.is_connected(_on_enemy_killed):
			_bus.world().enemy_killed.disconnect(_on_enemy_killed)

# ─────────────────────────────────────────────
# Trigger-Handler
# ─────────────────────────────────────────────

func _on_movement_stats_batch(peer_id: int, walked_m: float, jumped_m: float, fallen_m: float) -> void:
	var player_id := _resolve_player_uuid(peer_id)
	if player_id.is_empty():
		return
	if walked_m > 0.0:
		add_stat(player_id, STAT_METERS_WALKED, walked_m)
	if jumped_m > 0.0:
		add_stat(player_id, STAT_METERS_JUMPED, jumped_m)
	if fallen_m > 0.0:
		add_stat(player_id, STAT_METERS_FALLEN, fallen_m)

func _on_enemy_killed(_enemy_type_id: String, _position: Vector3, peer_id: int) -> void:
	var player_id := _resolve_player_uuid(peer_id)
	if player_id.is_empty():
		return
	add_stat(player_id, STAT_NPCS_KILLED, 1.0)

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

## Erhöht stat_name für player_id um delta (auch negativ möglich, falls
## künftig gebraucht — kein Clamp auf >= 0 in dieser Runde). Leere
## player_id/stat_name werden stillschweigend ignoriert.
func add_stat(player_id: String, stat_name: String, delta: float) -> void:
	if player_id.is_empty() or stat_name.is_empty():
		return
	if not _stats.has(player_id):
		_stats[player_id] = {}
	var bucket: Dictionary = _stats[player_id]
	var new_total: float = float(bucket.get(stat_name, 0.0)) + delta
	bucket[stat_name] = new_total
	stat_changed.emit(player_id, stat_name, delta, new_total)

func get_stat(player_id: String, stat_name: String) -> float:
	return float((_stats.get(player_id, {}) as Dictionary).get(stat_name, 0.0))

func get_all_stats(player_id: String) -> Dictionary:
	return (_stats.get(player_id, {}) as Dictionary).duplicate()

# ─────────────────────────────────────────────
# Save-Interface (analog AuraService/ReportService/AchievementService)
# ─────────────────────────────────────────────

func get_save_key() -> String:
	return SAVE_KEY

func get_save_data() -> Dictionary:
	return {"stats": _stats}

func _restore_from_save(saved: Dictionary) -> void:
	if saved.get("stats") is Dictionary:
		_stats = saved["stats"]

## Identisches 5-Zeilen-Muster wie QuestService/RewardDispatcher/
## CombatSystem._resolve_player_uuid() — bewusst keine gemeinsame Utility
## für eine weitere Call-Site, siehe dortige Diskussion (Round 63).
func _resolve_player_uuid(peer_id: int) -> String:
	if not is_instance_valid(_network):
		AppLogger.log_warn(
			"_resolve_player_uuid(%d): kein NetworkBridge injiziert — Übersetzung nicht möglich." % peer_id,
			LOG_CAT
		)
		return ""
	return _network.get_player_id_for_peer(peer_id)

extends ServiceNode
# justified: ServiceTicker-Registrierung (add_child) und on_tick() brauchen Node-Lifecycle.
class_name EnemyCullingService

## EnemyCullingService — räumt "verwilderte" Gegner auf, die weit von JEDEM
## Spieler entfernt sind, unabhängig davon WIE sie gespawnt wurden (Welt-
## Start-Grundbestand, ChunkEntitySpawner.enemy_chances, AmbientSpawnService,
## ConditionalEncounterService).
##
## WARUM NÖTIG (Wunsch "spawning generell optimieren, Dinge despawnen nicht
## korrekt"): AmbientSpawnService/ConditionalEncounterService spawnen Gegner
## DIREKT über die spawn_entity()-Closure, NICHT über ChunkEntitySpawner —
## sie landen deshalb nie in dessen `_spawned[coord]`-Tracking (siehe dort)
## und werden folglich NIE beim Chunk-Entladen aufgeräumt wie Bäume/Tiere/
## reguläre Gegner. Ohne diesen Dienst blieben sie für immer in der Welt,
## selbst wenn kein Spieler je wieder in ihre Nähe kommt — ein unbegrenzt
## wachsender Gegnerbestand über eine lange Spielsitzung, und (mit Grund für
## den Bug-Report) der Eindruck "Gegner despawnen nicht richtig".
##
## unload statt despawn: siehe EntityOrchestrator.unload_entity()
## Klassenkommentar — räumt die Node ab OHNE "im Spielsinn besiegt" zu
## bedeuten, exakt wie beim Chunk-Entladen. Insbesondere wichtig hier:
## despawn_entity() würde RespawnService einen Respawn AN DERSELBEN
## (unbeobachteten) Position einplanen — sinnlos für etwas, das gerade WEIL
## es unbeobachtet ist aufgeräumt wird.
##
## CULL_RADIUS bewusst GRÖSSER als AmbientSpawnService.DEFAULT_ACTIVATION_RADIUS
## (40m): verhindert Flackern an der Grenze — ein Spieler, der knapp um die
## Aktivierungsgrenze pendelt, würde sonst denselben Gegner-Slot ständig neu
## spawnen UND sofort wieder aufräumen lassen.
## SPAWN_GRACE_SECS: ein frisch gespawnter Gegner soll nicht im selben
## Prüf-Intervall wieder verschwinden, in dem der auslösende Spieler sich
## (kurzzeitig, z.B. kurzer Rückzug im Kampf) schon wieder wegbewegt hat.

const LOG_CAT := "EnemyCullingService"
const CULL_RADIUS: float        = 70.0
const CHECK_INTERVAL_SECS: float = 25.0
const SPAWN_GRACE_SECS: float    = 45.0
## Sicherheitsnetz pro Tick, analog zum "budget"-Gedanken in
## AmbientSpawnService.on_tick() — falls durch einen Bug plötzlich sehr viele
## Gegner gleichzeitig fällig würden, räumt ein einzelner Tick nicht alle auf
## einmal (würde in einem Multiplayer-Spiel als Ruckler sichtbar).
const MAX_CULLS_PER_CHECK: int = 5

var _ticker: ServiceTicker = null
var _rng := RandomNumberGenerator.new()
var _next_check_at: float = 0.0

## Callable(uuid: String) -> void — von WorldService.on_ready() injiziert,
## gebunden an EntityOrchestrator.unload_entity() (siehe Klassenkommentar
## "unload statt despawn").
var _unload_cb: Callable = Callable()

# ─────────────────────────────────────────────
# Phase 4/5/7
# ─────────────────────────────────────────────

func configure(deps: ServiceDeps) -> void:
	_ticker = deps.get_optional(ServiceKeys.TICKER) as ServiceTicker
	_rng.randomize()
	_next_check_at = Time.get_unix_time_from_system() + _rng.randf_range(0.0, CHECK_INTERVAL_SECS)

func on_ready() -> void:
	if is_instance_valid(_ticker):
		_ticker.register_service(self)
	AppLogger.log_info("EnemyCullingService bereit.", LOG_CAT)

func on_cleanup() -> void:
	_unload_cb = Callable()
	AppLogger.log_debug("EnemyCullingService bereinigt.", LOG_CAT)

func set_unload_callback(cb: Callable) -> void:
	assert(cb.is_valid(), "EnemyCullingService.set_unload_callback: Callable ist ungültig!")
	_unload_cb = cb
	AppLogger.log_debug("Unload-Callback injiziert.", LOG_CAT)

# ─────────────────────────────────────────────
# Tick
# ─────────────────────────────────────────────

func on_tick(_delta: float) -> void:
	if not _unload_cb.is_valid():
		return
	var now := Time.get_unix_time_from_system()
	if now < _next_check_at:
		return
	_next_check_at = now + CHECK_INTERVAL_SECS + _rng.randf_range(-5.0, 5.0)

	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var players: Array = tree.get_nodes_in_group("player")
	if players.is_empty():
		# Niemand online — nichts, wogegen sich "zu weit entfernt" sinnvoll
		# beurteilen ließe. Lieber nichts tun als grundlos den Gegnerbestand
		# räumen (z.B. im kurzen Fenster bevor der lokale Spieler-Node der
		# Gruppe beitritt).
		return

	var culled := 0
	for node in tree.get_nodes_in_group("enemies"):
		if culled >= MAX_CULLS_PER_CHECK:
			break
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		var entity := node as Node3D
		var spawned_at: float = entity.get_meta("spawned_at", 0.0)
		if spawned_at > 0.0 and now - spawned_at < SPAWN_GRACE_SECS:
			continue
		if _has_player_within(entity.global_position, players, CULL_RADIUS):
			continue
		var uuid: String = entity.get_meta("entity_uuid", "")
		if uuid.is_empty():
			continue
		_unload_cb.call(uuid)
		culled += 1
		AppLogger.log_debug(
			"Verwilderter Gegner aufgeräumt: '%s' (kein Spieler in %dm)." % [uuid, int(CULL_RADIUS)], LOG_CAT
		)

func _has_player_within(position: Vector3, players: Array, radius: float) -> bool:
	for p in players:
		if p is Node3D and (p as Node3D).global_position.distance_to(position) <= radius:
			return true
	return false

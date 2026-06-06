extends ServiceNode
class_name WorldService

## WorldService — Zentrale Anlaufstelle für Welt-Daten, Zeit und Entity-Verwaltung.
##
## Abhängigkeiten (deps): ["savesystem", "data"]
##
## WICHTIG: Nutzt on_tick() statt _process() — konform mit dem ServiceTicker-Vertrag.
##
## World-Initialisierung (garantierte Reihenfolge):
##   1. World.gd._ready() ruft Services.world.on_world_scene_ready(self)
##   2. WorldService erstellt statische Geometrie via WorldFactory
##   3. WorldService initialisiert EntityOrchestrator mit dem world_root
##   4. WorldService spawnt Entities über EntityOrchestrator
##   5. WorldService feuert EventBus.world.world_scene_ready für HUDManager
##
## Entity-Spawning-Pattern:
##   EntityOrchestrator ist ein Node-Child dieses Services.
##   Definitions werden in _register_entity_definitions() eingetragen.
##   Positionen kommen aus WorldData (persistiert via SaveSystem).

const LOG_CAT := "World"
const SAVE_KEY := "world_state"

## Standard-Startpositionen wenn kein Savegame vorhanden
const DEFAULT_TREE_POSITIONS: Array[Vector3] = [
	Vector3(5, 0, 5),
	Vector3(-6, 0, 4),
	Vector3(8, 0, -3),
]
const DEFAULT_ORE_POSITIONS: Array[Vector3] = [
	Vector3(-4, 0, 6),
]

var _save_system: SaveSystem

var data: WorldData
var factory: WorldFactory

## Factory3D lebt als Instanz in WorldService — kein Service-Overhead mehr.
## Entities (OakTree, IronOre) und InteractableComponent greifen via
## Services.world.factory3d darauf zu.
var factory3d: Factory3D

## EntityOrchestrator lebt als Child-Node dieses Services.
## Wird in configure() erstellt, in on_world_scene_ready() initialisiert.
var _entity_orchestrator: EntityOrchestrator

var day_time: float = 6.0
var day_count: int = 1
@export var time_speed: float = 0.05


# ─────────────────────────────────────────────
# Phase 4: Configure
# ─────────────────────────────────────────────
func configure(deps: Dictionary) -> void:
	var t := Logger.log_begin("WorldService.configure()", LOG_CAT)

	_save_system = deps.get("savesystem") as SaveSystem
	if not is_instance_valid(_save_system):
		Logger.log_error("SaveSystem fehlt in den Dependencies!", LOG_CAT)
	else:
		_save_system.register_save_provider(self)
		var saved: Dictionary = _save_system.get_state_for(SAVE_KEY)
		if not saved.is_empty():
			_restore_world(saved)
		else:
			Logger.log_info("Kein World-Save — nutze Standardwerte.", LOG_CAT)

	data     = WorldData.new()
	factory  = WorldFactory.new()
	factory3d = Factory3D.new()

	# EntityOrchestrator als Child erstellen — wird in on_world_scene_ready() genutzt.
	# Er lebt hier statt als Autoload, da Entities an den Welt-Lebenszyklus gebunden sind.
	_entity_orchestrator = EntityOrchestrator.new()
	_entity_orchestrator.name = "EntityOrchestrator"
	add_child(_entity_orchestrator)

	_register_entity_definitions()

	Logger.log_end("WorldService.configure()", t, LOG_CAT)
	Logger.log_info(
		"WorldService konfiguriert (Tag %d, %02d:00)." % [day_count, int(day_time)], LOG_CAT
	)


# ─────────────────────────────────────────────
# Phase 5: on_ready
# ─────────────────────────────────────────────
func on_ready() -> void:
	if Services.ticker:
		Services.ticker.register_service(self)
		Logger.log_debug("Bei ServiceTicker registriert.", LOG_CAT)
	else:
		Logger.log_warn("ServiceTicker fehlt — on_tick() wird nicht aufgerufen!", LOG_CAT)

	Logger.log_info("WorldService bereit.", LOG_CAT)


# ─────────────────────────────────────────────
# Phase 7: Cleanup
# ─────────────────────────────────────────────
func on_cleanup() -> void:
	Logger.log_info("WorldService Cleanup.", LOG_CAT)
	# EntityOrchestrator ist ein Child-Node, wird automatisch freigegeben.
	# Explizit aufräumen falls wir mitten in einer Welt sind.
	if is_instance_valid(_entity_orchestrator) and _entity_orchestrator.get_entity_count() > 0:
		_entity_orchestrator.on_world_unloaded()


# ─────────────────────────────────────────────
# Tick (via ServiceTicker — kein direktes _process()!)
# ─────────────────────────────────────────────
func on_tick(delta: float) -> void:
	if is_instance_valid(Services.game_manager) and Services.game_manager.is_playing():
		_update_time(delta)


# ─────────────────────────────────────────────
# Welt-Initialisierung (von World.gd._ready() aufgerufen)
# ─────────────────────────────────────────────


## Wird von World.gd._ready() aufgerufen.
## Zu diesem Zeitpunkt ist World.tscn garantiert im SceneTree —
## sicher Kinder hinzuzufügen ohne call_deferred.
func on_world_scene_ready(world_root: Node3D) -> void:
	var t := Logger.log_begin("on_world_scene_ready()", LOG_CAT)
	Logger.log_info(
		"World-Init gestartet. Scene: '%s'." % world_root.name, LOG_CAT
	)

	# Vorherige Welt aufräumen falls vorhanden (bei Szenenwechsel zurück zur Welt)
	if _entity_orchestrator.get_entity_count() > 0:
		Logger.log_info("Vorherige Entity-Session aufräumen...", LOG_CAT)
		_entity_orchestrator.on_world_unloaded()
		EventBus.world.emit_world_scene_unloaded()

	# --- Statische Geometrie (Factory) ---
	var generated_world: Node3D = factory.create_world()
	# Kinder in die echte Szene verschieben (Factory-Container ist temporär)
	for child in generated_world.get_children():
		generated_world.remove_child(child)
		world_root.add_child(child)
	generated_world.queue_free()
	Logger.log_debug("Statische Geometrie in World.tscn eingefügt.", LOG_CAT)

	# --- EntityOrchestrator initialisieren ---
	_entity_orchestrator.initialize(world_root)

	# --- Entities spawnen ---
	_spawn_world_entities()

	# --- Welt bereit signalisieren ---
	# HUDManager lauscht auf dieses Signal und hängt das HUD ein.
	# WorldService kennt damit kein UI mehr — saubere Trennung.
	EventBus.world.emit_world_scene_ready(world_root)

	Logger.log_end("on_world_scene_ready()", t, LOG_CAT)
	Logger.log_info(
		"Welt bereit. Entities aktiv: %d." % _entity_orchestrator.get_entity_count(),
		LOG_CAT
	)


# ─────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────


func get_save_key() -> String:
	return SAVE_KEY


func get_save_data() -> Dictionary:
	# Aktuelle Entity-Positionen für den Save sammeln
	var tree_pos_strings: Array[String] = []
	for pos in data.tree_positions:
		tree_pos_strings.append(var_to_str(pos))

	return {
		"day_time": day_time,
		"day_count": day_count,
		"tree_positions": tree_pos_strings,
		"ore_positions": var_to_str(data.ore_positions),
		"player_pos": var_to_str(data.player_position),
		"harvested": var_to_str(data.harvested_objects),
	}


# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────


func get_formatted_time() -> String:
	var hours: int = int(day_time)
	var minutes: int = int((day_time - hours) * 60)
	return "%02d:%02d" % [hours, minutes]


## Spawnt eine Entity über den EntityOrchestrator.
## Öffentliche API für anderen Code (z.B. zukünftiger ChunkLoader).
func spawn_entity(type_id: String, position: Vector3, config: Dictionary = {}) -> Node3D:
	if not is_instance_valid(_entity_orchestrator):
		Logger.log_error("EntityOrchestrator fehlt!", LOG_CAT)
		return null
	return _entity_orchestrator.spawn_entity(type_id, position, config)


## Despawnt eine Entity über die UUID.
func despawn_entity(uuid: String) -> void:
	if not is_instance_valid(_entity_orchestrator):
		Logger.log_error("EntityOrchestrator fehlt!", LOG_CAT)
		return
	_entity_orchestrator.despawn_entity(uuid)


## Gibt Debug-Info über aktive Entities zurück (für SimpleTerminal).
func get_entity_debug_info() -> Dictionary:
	if not is_instance_valid(_entity_orchestrator):
		return {"error": "EntityOrchestrator fehlt"}
	return _entity_orchestrator.get_debug_info()


# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────


func _register_entity_definitions() -> void:
	var t := Logger.log_begin("_register_entity_definitions()", LOG_CAT)

	_entity_orchestrator.register_definition(
		"oak_tree",
		"res://scripts/world/objects/OakTree.gd",
		"trees"
	)
	_entity_orchestrator.register_definition(
		"iron_ore",
		"res://scripts/world/objects/IronOre.gd",
		"ores"
	)

	Logger.log_end("_register_entity_definitions()", t, LOG_CAT)
	Logger.log_debug("Entity-Definitionen registriert: oak_tree, iron_ore.", LOG_CAT)


func _spawn_world_entities() -> void:
	var t := Logger.log_begin("_spawn_world_entities()", LOG_CAT)

	# Baum-Positionen aus Save oder Default
	var tree_positions: Array[Vector3] = data.tree_positions
	if tree_positions.is_empty():
		tree_positions = DEFAULT_TREE_POSITIONS
		data.tree_positions = DEFAULT_TREE_POSITIONS
		Logger.log_debug(
			"Keine gespeicherten Baum-Positionen — nutze %d Defaults." % tree_positions.size(),
			LOG_CAT
		)
	else:
		Logger.log_debug(
			"Baum-Positionen aus Save: %d Bäume." % tree_positions.size(), LOG_CAT
		)

	for pos in tree_positions:
		if not data.is_tree_harvested(pos):
			_entity_orchestrator.spawn_entity("oak_tree", pos)
		else:
			Logger.log_debug("Baum bei %s bereits geerntet — überspringen." % str(pos), LOG_CAT)

	# Erz-Positionen
	var ore_positions: Array[Vector3] = data.ore_positions
	if ore_positions.is_empty():
		ore_positions = DEFAULT_ORE_POSITIONS
		data.ore_positions = DEFAULT_ORE_POSITIONS
		Logger.log_debug(
			"Keine gespeicherten Erz-Positionen — nutze %d Defaults." % ore_positions.size(),
			LOG_CAT
		)

	for pos in ore_positions:
		if not data.is_ore_harvested(pos):
			_entity_orchestrator.spawn_entity("iron_ore", pos)
		else:
			Logger.log_debug("Erz bei %s bereits abgebaut — überspringen." % str(pos), LOG_CAT)

	Logger.log_end("_spawn_world_entities()", t, LOG_CAT)
	Logger.log_info(
		"Entity-Spawning abgeschlossen. Aktive Entities: %d." % _entity_orchestrator.get_entity_count(),
		LOG_CAT
	)


func _update_time(delta: float) -> void:
	day_time += delta * time_speed
	if day_time >= 24.0:
		day_time = fmod(day_time, 24.0)
		day_count += 1
		EventBus.world.emit_time_of_day_changed(0)
		Logger.log_info("Neuer Tag: Tag %d beginnt." % day_count, LOG_CAT)


func _restore_world(state: Dictionary) -> void:
	day_time  = state.get("day_time",  6.0)
	day_count = state.get("day_count", 1)

	# Baum-Positionen aus String-Array wiederherstellen
	var tree_strings: Variant = state.get("tree_positions", [])
	if tree_strings is Array:
		data.tree_positions = []
		for s in tree_strings:
			var pos: Variant = str_to_var(s)
			if pos is Vector3:
				data.tree_positions.append(pos)

	# BUG-FIX: str_to_var kann null/falsch-typisierte Werte zurückgeben wenn der
	# Save korrupt ist. Immer Type-Guard verwenden, nie direkt zuweisen.
	var ore_raw: Variant = str_to_var(state.get("ore_positions", "[]"))
	if ore_raw is Array:
		data.ore_positions = []
		for p in ore_raw:
			if p is Vector3:
				data.ore_positions.append(p)
	else:
		Logger.log_warn("ore_positions im Save korrupt — nutze leeres Array.", LOG_CAT)
		data.ore_positions = []

	var player_pos_raw: Variant = str_to_var(state.get("player_pos", "Vector3(0,0,0)"))
	data.player_position = player_pos_raw if player_pos_raw is Vector3 else Vector3.ZERO

	var harvested_raw: Variant = str_to_var(state.get("harvested", "{}"))
	data.harvested_objects = harvested_raw if harvested_raw is Dictionary else {}

	Logger.log_info(
		"Welt-Zustand geladen: Tag %d, %02d:00, %d Bäume, %d Erze, %d geerntete Objekte."
		% [
			day_count, int(day_time),
			data.tree_positions.size(),
			data.ore_positions.size(),
			data.harvested_objects.size()
		],
		LOG_CAT
	)

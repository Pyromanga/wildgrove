class_name CharacterScope extends RefCounted

## CharacterScope — Lebt solange ein Spieler eingeloggt ist.
##
## Owned by: AppScope.
## Kennt: AppScope (nach oben), nicht WorldScope (nach unten).
## Erzeugt und owned: WorldScope wenn World.tscn geladen ist.
##
## Abhängigkeitsregel:
##   CharacterScope kennt AppScope   ✅
##   CharacterScope kennt WorldScope ❌ — er erzeugt ihn, ruft aber nicht in ihn rein

const LOG_CAT := "CharacterScope"

var registry:     ServiceRegistry
var app_registry: ServiceRegistry  ## AppScope-Registry — nur für Cross-Scope-Deps
var player_id:    String
var parent:       Node

var _world_scope: WorldScope = null

## Signalisiert dass ein WorldScope erfolgreich gebootet wurde.
## ServiceOrchestrator connectet sich hier um post-boot Wiring zu machen.
signal world_scope_ready(world_scope: WorldScope)

func _init(
	r:          ServiceRegistry,
	app_reg:    ServiceRegistry,
	pid:        String,
	p:          Node
) -> void:
	registry     = r
	app_registry = app_reg
	player_id    = pid
	parent       = p

# ─────────────────────────────────────────────
# World-Scope Lifecycle
# ─────────────────────────────────────────────

## Erzeugt WorldScope wenn World.tscn geladen und bereit ist.
## Wird von WorldScopeInitializer (Node in World.tscn) via Signal getriggert —
## kein Pull, kein AutoLoad-Zugriff, kein EventBus für Lifecycle.
func create_world_scope(world_root: Node3D, p: Node) -> WorldScope:
	if _world_scope != null:
		AppLogger.log_info("CharacterScope: bestehender WorldScope wird zerstört.", LOG_CAT)
		destroy_world_scope()

	var world_registry := ServiceRegistry.new()
	_world_scope = WorldScope.new(world_registry, registry, app_registry, world_root, p)
	AppLogger.log_info("CharacterScope: WorldScope erzeugt.", LOG_CAT)
	world_scope_ready.emit(_world_scope)
	return _world_scope

## Zerstört WorldScope.
func destroy_world_scope() -> void:
	if _world_scope == null:
		return
	_world_scope.destroy()
	_world_scope = null
	AppLogger.log_info("CharacterScope: WorldScope zerstört.", LOG_CAT)

func has_world_scope() -> bool:
	return _world_scope != null

func get_world_scope() -> WorldScope:
	return _world_scope

# ─────────────────────────────────────────────
# Teardown
# ─────────────────────────────────────────────

## Zerstört WorldScope (falls aktiv) dann sich selbst.
## Wird von AppScope.destroy_character_scope() aufgerufen.
func destroy() -> void:
	destroy_world_scope()
	AppLogger.log_info("CharacterScope: wird zerstört für '%s'." % player_id, LOG_CAT)

# ─────────────────────────────────────────────
# Service-Zugriff
# ─────────────────────────────────────────────

func get_service(key: String) -> Object:
	return registry.get_service(key)

class_name AppScope extends RefCounted

## AppScope — Lebt solange die App läuft.
##
## Owned by: ServiceOrchestrator (AutoLoad).
## Erzeugt und owned: CharacterScope wenn eine Session startet.
##
## Abhängigkeitsregel: AppScope kennt niemanden über sich.
## CharacterScope und WorldScope sind ihm unbekannt — er erzeugt sie,
## aber er ruft nie in sie rein nachdem sie gebootet sind.

const LOG_CAT := "AppScope"

var registry: ServiceRegistry
var _character_scope: CharacterScope = null

func _init(r: ServiceRegistry) -> void:
	registry = r

# ─────────────────────────────────────────────
# EventBus-Zugriff für App-Scope-Consumer (IAppContext, Round 109)
# ─────────────────────────────────────────────

## Trägt IEventBus in die App-Registry ein — derselbe Registry-Key
## (ServiceKeys.EVENT_BUS) wie Session-Services und UIContext nutzen, nur
## eine Scope-Ebene früher. EventBusAdapter hat keine Session-Abhängigkeit
## (delegiert nur an den globalen EventBus-AutoLoad), daher ist nichts dagegen
## einzuwenden ihn hier zusätzlich zu registrieren.
##
## Aufgerufen von ServiceOrchestrator._ready(), direkt nach AppScope.new() —
## noch vor boot_app(), damit IAppContext für MainMenuController (existiert
## vor jedem Session-Boot) verfügbar ist, sobald MenuScopeInitializer signalisiert.
func register_event_bus(bus: IEventBus) -> void:
	registry.register_resource(bus, ServiceKeys.EVENT_BUS)

# ─────────────────────────────────────────────
# Character-Scope Lifecycle
# ─────────────────────────────────────────────

## Erzeugt einen neuen CharacterScope für player_id.
## Bestehender CharacterScope (inkl. WorldScope) wird zuerst zerstört.
func create_character_scope(player_id: String, parent: Node) -> CharacterScope:
	if _character_scope != null:
		AppLogger.log_info("AppScope: bestehender CharacterScope wird zerstört.", LOG_CAT)
		destroy_character_scope()

	var char_registry := ServiceRegistry.new()
	_character_scope = CharacterScope.new(char_registry, registry, player_id, parent)
	AppLogger.log_info("AppScope: CharacterScope für '%s' erzeugt." % player_id, LOG_CAT)
	return _character_scope

## Zerstört CharacterScope (und damit auch WorldScope).
func destroy_character_scope() -> void:
	if _character_scope == null:
		return
	_character_scope.destroy()
	_character_scope = null
	AppLogger.log_info("AppScope: CharacterScope zerstört.", LOG_CAT)

func has_character_scope() -> bool:
	return _character_scope != null

func get_character_scope() -> CharacterScope:
	return _character_scope

# ─────────────────────────────────────────────
# Service-Zugriff
# ─────────────────────────────────────────────

func get_service(key: String) -> Object:
	return registry.get_service(key)

class_name WorldScope extends RefCounted

## WorldScope — Lebt solange eine Welt geladen ist.
##
## Owned by: CharacterScope.
## Kennt: CharacterScope-Registry + AppScope-Registry (nach oben).
## Kennt niemanden unter sich — es gibt keinen Scope unter World.
##
## Abhängigkeitsregel:
##   WorldScope kennt CharacterScope ✅
##   WorldScope kennt AppScope       ✅
##   Niemand kennt WorldScope außer CharacterScope (der ihn erzeugt)

const LOG_CAT := "WorldScope"

var registry:          ServiceRegistry
var char_registry:     ServiceRegistry  ## CharacterScope-Registry
var app_registry:      ServiceRegistry  ## AppScope-Registry
var world_root:        Node3D
var parent:            Node

func _init(
	r:         ServiceRegistry,
	char_reg:  ServiceRegistry,
	app_reg:   ServiceRegistry,
	root:      Node3D,
	p:         Node
) -> void:
	registry      = r
	char_registry = char_reg
	app_registry  = app_reg
	world_root    = root
	parent        = p
	AppLogger.log_info("WorldScope: erzeugt mit root '%s'." % root.name, LOG_CAT)

# ─────────────────────────────────────────────
# Teardown
# ─────────────────────────────────────────────

## Wird von CharacterScope.destroy_world_scope() aufgerufen.
func destroy() -> void:
	AppLogger.log_info("WorldScope: wird zerstört.", LOG_CAT)
	world_root = null

# ─────────────────────────────────────────────
# Service-Zugriff
# ─────────────────────────────────────────────

func get_service(key: String) -> Object:
	return registry.get_service(key)

## Cross-Scope: holt einen Character-Service (z.B. InventorySystem aus WorldService heraus)
func get_character_service(key: String) -> Object:
	return char_registry.get_service(key)

## Cross-Scope: holt einen App-Service (z.B. SaveSystem)
func get_app_service(key: String) -> Object:
	return app_registry.get_service(key)

func get_world_root() -> Node3D:
	return world_root

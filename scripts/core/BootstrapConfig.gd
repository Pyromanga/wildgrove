# res://scripts/core/BootstrapConfig.gd
class_name BootstrapConfig extends Resource

@export var services: Array[ServiceDefinition]

# Hilfsklasse für den Editor
class ServiceDefinition:
    @export var name: String
    @export var path: String
    @export var deps: Array[String]
    
const SERVICES: Array[Dictionary] = [
	# Fundament — keine Abhängigkeiten
	{ "name": "savesystem",    "path": "res://scripts/services/SaveSystem.gd",          "deps": [] },
	{ "name": "events",        "path": "res://scripts/events/GameEvents.gd",           "deps": [] },
	{ "name": "data",          "path": "res://scripts/services/DataService.gd",          "deps": [] },
	{ "name": "utils",         "path": "res://scripts/services/Utils.gd",                "deps": [] },
	{ "name": "debug_service", "path": "res://scripts/debug/DebugService.gd",         "deps": [] },

	# Abhängig von Fundament
	{ "name": "states",        "path": "res://scripts/services/StateService.gd",         "deps": ["savesystem"] },
	{ "name": "debug_console", "path": "res://scripts/debug/DebugConsole.gd",         "deps": ["debug_service"] },
	{ "name": "skill_system",  "path": "res://scripts/services/SkillSystem.gd",          "deps": ["data"] },
	{ "name": "factory3d",     "path": "res://scripts/services/Factory3D.gd",            "deps": ["data"] },
	{ "name": "builder",       "path": "res://scripts/interaction/InteractionBuilder.gd",   "deps": [] },

	# Abhängig von mehreren
	{ "name": "gamemanager",   "path": "res://scripts/services/GameManager.gd",          "deps": ["savesystem", "states"] },
	{ "name": "inventory",     "path": "res://scripts/services/InventorySystem.gd",      "deps": ["data", "savesystem"] },

	# Abhängig von gameplay-nahen Services
	{ "name": "ui_factory",    "path": "res://scripts/services/UIFactory.gd",            "deps": ["inventory"] },
]
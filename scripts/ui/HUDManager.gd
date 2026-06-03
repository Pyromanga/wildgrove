extends ServiceNode
class_name HUDManager

## HUDManager — Verwaltet das UI-System und die Controller.
## Abhängigkeiten: ["inventory", "playerstates"]
##
## HINWEIS: HUDManager ist nicht in bootstrap_config.tres eingetragen —
## entweder dort hinzufügen oder manuell in Main._on_services_ready() instanziieren.

const LOG_CAT := "HUD"

var hud:         HUD        = null
var controllers: Dictionary = {}

func init() -> void:
	hud      = HUD.new()
	hud.name = "GameHUD"
	get_parent().add_child(hud)
	Logger.log_debug("HUD Instanz erstellt.", LOG_CAT)

func on_ready() -> void:
	_setup_ui()
	Logger.log_info("HUD-System vollständig initialisiert.", LOG_CAT)

func get_controller(id: String) -> Variant:
	return controllers.get(id)

func _setup_ui() -> void:
	controllers = HUDBuilder.build_all(hud)
	Logger.log_debug("Controller-Registry befüllt: %d Einheiten." % controllers.size(), LOG_CAT)
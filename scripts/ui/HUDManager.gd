extends ServiceNode
class_name HUDManager

## HUDManager — Verwaltet das UI-System und die Controller.
## Abhängigkeiten: ["inventory", "playerstates"]

const LOG_CAT := "HUD"

var hud:         HUD        = null
var controllers: Dictionary = {}

# ─────────────────────────────────────────────
# Phase 4: Init (Reine Daten & Instanziierung)
# ─────────────────────────────────────────────
func init() -> void:
	# Wir erstellen das Objekt im Speicher, hängen es aber noch nicht in den Baum.
	if hud == null:
		hud = HUD.new()
		hud.name = "GameHUD"
		Logger.log_debug("HUD Instanz im Speicher erstellt (noch nicht im Tree).", LOG_CAT)

# ─────────────────────────────────────────────
# Phase 5: Activate (Ready-Phase des Orchestrators)
# ─────────────────────────────────────────────
func on_ready() -> void:
	# Erst jetzt ist es sicher, auf den Parent zuzugreifen
	if hud and not hud.is_inside_tree():
		add_child(hud) 
		# Nutze add_child(hud) direkt, da der HUDManager selbst 
		# vom ServiceFactory bereits in den Baum gehängt wurde.
		
		_setup_ui()
		Logger.log_info("HUD-System vollständig initialisiert und im Baum aktiv.", LOG_CAT)
	else:
		Logger.log_warn("HUD konnte nicht aktiviert werden oder ist bereits im Baum.", LOG_CAT)

func get_controller(id: String) -> Variant:
	return controllers.get(id)

func _setup_ui() -> void:
	# HUDBuilder braucht ein HUD, das idealerweise schon "ready" ist
	controllers = HUDBuilder.build_all(hud)
	Logger.log_debug("Controller-Registry befüllt: %d Einheiten." % controllers.size(), LOG_CAT)
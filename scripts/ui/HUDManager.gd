extends ServiceNode
class_name HUDManager

## HUDManager — Verwaltet das UI-System und die Controller.
## Abhängigkeiten: ["savesystem", "inventory", "player_states"]

const LOG_CAT := "HUD"

var hud: HUD
var controllers: Dictionary = {}

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func init() -> void:
    # Wir erstellen das HUD (CanvasLayer)
    hud = HUD.new()
    hud.name = "GameHUD"
    # Wir hängen es an den Orchestrator (damit es im Baum ist)
    get_parent().add_child(hud)
    
    Logger.log_debug("HUD Instanz erstellt.", LOG_CAT)

func on_ready() -> void:
    # Erst jetzt, wo alle Services (Inventory, Skills etc.) bereit sind,
    # bauen wir die Komponenten zusammen.
    _setup_ui()
    Logger.log_info("HUD-System vollständig initialisiert.", LOG_CAT)

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _setup_ui() -> void:
    # Der Builder nutzt jetzt die 'Services' statt 'Kernel'
    controllers = HUDBuilder.build_all(hud)
    Logger.log_debug("Controller-Registry befüllt: %d Einheiten." % controllers.size(), LOG_CAT)

func get_controller(id: String):
    return controllers.get(id)
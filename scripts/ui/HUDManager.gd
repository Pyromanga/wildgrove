# res://scripts/core/HUDManager.gd
extends ServiceNode
class_name HUDManager

const LOG_CAT := "HUD"

var hud:         HUD        = null
var controllers: Dictionary = {}

# Abhängigkeiten, die wir via DI bekommen
var _inventory: InventorySystem
var _player_states: PlayerStateService

# ─────────────────────────────────────────────
# Phase 4: Configure (Enterprise DI)
# ─────────────────────────────────────────────
func configure(deps: Dictionary) -> void:
	# Abhängigkeiten sicher wegspeichern
	_inventory = deps.get("inventory") as InventorySystem
	_player_states = deps.get("playerstates") as PlayerStateService
	
	# HUD Instanz im Speicher vorbereiten
	if hud == null:
		hud = HUD.new()
		hud.name = "GameHUD"
		Logger.log_debug("HUD Instanz im Speicher erstellt.", LOG_CAT)

# ─────────────────────────────────────────────
# Phase 5: Activate
# ─────────────────────────────────────────────
func on_ready() -> void:
	if hud and not hud.is_inside_tree():
		add_child(hud) 
		_setup_ui()
		
		# Hier kommt der ServiceTicker ins Spiel!
		# Wenn der HUDManager Ticks bräuchte, würden wir ihn hier registrieren:
		# Services.ticker.register_service(self)
		
		Logger.log_info("HUD-System aktiv.", LOG_CAT)

func _setup_ui() -> void:
	# Wir geben dem HUDBuilder vielleicht sogar die deps mit, 
	# wenn die Controller direkt Zugriff brauchen
	controllers = HUDBuilder.build_all(hud)
	Logger.log_debug("Controller-Registry befüllt: %d Einheiten." % controllers.size(), LOG_CAT)
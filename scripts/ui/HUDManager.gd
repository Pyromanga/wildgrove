# res://scripts/core/HUDManager.gd
extends ServiceNode
class_name HUDManager

const LOG_CAT := "HUD"

var hud: HUD = null
var controllers: Dictionary = {}

# Abhängigkeiten, die wir via DI bekommen
var _inventory: InventorySystem
var _player_states: PlayerStateService
var _uifactory: UIFactory

# ─────────────────────────────────────────────
# Phase 4: Configure (Enterprise DI)
# ─────────────────────────────────────────────
func configure(deps: Dictionary) -> void:
	_inventory = deps.get("inventory") as InventorySystem
	_player_states = deps.get("playerstates") as PlayerStateService
	_uifactory = deps.get("ui_factory") as UIFactory

	# HUD-Node im Speicher vorbereiten, aber NOCH NICHT in den Tree einhängen.
	# Das passiert erst in attach_to_scene(), wenn die Ziel-Szene bereit ist.
	if hud == null:
		hud = HUD.new()
		hud.name = "GameHUD"
		Logger.log_debug("HUD-Node im Speicher erstellt (noch nicht im Tree).", LOG_CAT)
	else:
		Logger.log_warn("configure() erneut aufgerufen — HUD-Node bereits vorhanden.", LOG_CAT)


# ─────────────────────────────────────────────
# Phase 5: on_ready
# ─────────────────────────────────────────────
func on_ready() -> void:
	# HUDManager selbst ist ein ServiceNode (Kind des ServiceOrchestrators in Main.tscn).
	# Wir fügen das HUD hier NICHT ein — Main.tscn wird beim Wechsel zu World.tscn
	# zerstört, und alle Kinder sterben mit. Das HUD wird stattdessen über
	# attach_to_scene() in die jeweilige Spielwelt-Szene eingehängt.
	Logger.log_info(
		"HUDManager bereit. HUD-Node wartet auf attach_to_scene()-Aufruf.", LOG_CAT
	)


# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────


## Hängt das HUD-Node als CanvasLayer in die übergebene Szene ein und initialisiert
## alle Controller. Wird von WorldService.on_world_scene_ready() aufgerufen,
## nachdem World.tscn vollständig im SceneTree ist.
# HUDManager.gd
func attach_to_scene(scene_root: Node) -> void:
  # 1. Wir fragen die UIFactory nach dem Container, anstatt selbst zu suchen
  var canvas = _uifactory.get_main_canvas()

  # 2. HUD-Node sauber einhängen
  if not hud.get_parent():
    canvas.add_child(hud)

  _setup_controllers()
	Logger.log_info("HUD-System aktiv. %d Controller initialisiert." % controllers.size(), LOG_CAT)


func _setup_controllers() -> void:
	var context := {"inventory": _inventory, "player_states": _player_states}
	Logger.log_debug("Baue HUD-Controller mit Kontext...", LOG_CAT)
	controllers = HUDBuilder.build_all(hud, context)
	Logger.log_debug(
		"HUD-Controller gebaut: %d Einheiten." % controllers.size(), LOG_CAT
	)


# Optional: Falls das HUD auf Ticks reagieren muss (z.B. für Animationen oder Timer)
func on_tick(_delta: float) -> void:
	pass

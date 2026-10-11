extends ServiceNode
# justified: on_ready() verbindet EventBus-Signals; change_state() braucht Lifecycle-Kontext.
class_name GameManager

const LOG_CAT := "GameManager"

var _current_state: GameEnums.State = GameEnums.State.BOOT
var _scene_manager: SceneManager
var _config:        GameConfig
var _bus:           IEventBus

func configure(deps: ServiceDeps) -> void:
	_scene_manager = deps.get_optional(ServiceKeys.SCENE) as SceneManager
	_config = deps.require(ServiceKeys.GAME_CONFIG) as GameConfig
	_bus    = deps.require(ServiceKeys.EVENT_BUS)    as IEventBus
	if not _config:
		AppLogger.log_warn("GameConfig nicht in deps — Übergänge unkontrolliert.", LOG_CAT)

func on_ready() -> void:
	# Session-Ready-Signal: Charakter-Services stehen, Welt wird jetzt gebootet → LOADING.
	# world_scene_ready: WorldService.on_world_scene_ready() ist fertig (Entities gespawnt,
	# ggf. nach asynchroner Welt-Generierung im Hintergrund-Thread) → PLAYING.
	_bus.session().session_ready.connect(_on_session_ready)
	_bus.world().world_scene_ready.connect(_on_world_scene_ready)
	_bus.ui().main_menu_requested.connect(
		func() -> void: change_state(GameEnums.State.MAIN_MENU)
	)
	# Kein Host-Migration-Konzept (siehe ADR-028) — Autorität verloren = geordnetes
	# Session-Ende statt eines undefinierten "eingefroren"-Zustands. Feuert nur auf
	# Clients (network_peer_disconnected entspricht Godots multiplayer.server_disconnected,
	# siehe SessionManager._on_server_disconnected()) — der Host/Server selbst bekommt
	# dieses Signal nie. MAIN_MENU ist von PLAYING/LOADING/PAUSED/CUTSCENE/GAME_OVER aus
	# erlaubt (siehe GameConfig.valid_transitions) — deckt jeden Punkt ab, an dem der
	# Host mitten in der Session wegbrechen kann.
	_bus.networking().network_peer_disconnected.connect(_on_host_connection_lost)
	AppLogger.log_debug("GameManager lauscht auf session_ready / world_scene_ready.", LOG_CAT)

## start_game() setzt den initialen State ohne einen Szenenwechsel auszulösen.
## MainMenu.tscn ist bereits die laufende Startszene (project.godot: run/main_scene).
## Keine Session wird hier gestartet — der Spieler wählt im Hauptmenü einen Charakter.
func start_game() -> void:
	_current_state = GameEnums.State.MAIN_MENU
	AppLogger.log_info("State initialisiert: MAIN_MENU (warte auf Charakter-Auswahl).", LOG_CAT)
	_bus.system().emit_state_changed(_current_state)

func _on_session_ready() -> void:
	# Charakter-Services stehen — World-Boot läuft jetzt (WorldScopeInitializer/
	# boot_world()), unter Umständen asynchron. Bis world_scene_ready ankommt
	# sind Terrain/Entities nicht garantiert vorhanden, daher LOADING statt PLAYING.
	AppLogger.log_info("Session bereit — wechsle zu LOADING (Welt wird gebootet).", LOG_CAT)
	change_state(GameEnums.State.LOADING)

func _on_world_scene_ready(_world_root: Node) -> void:
	AppLogger.log_info("Welt-Szene bereit — wechsle zu PLAYING.", LOG_CAT)
	change_state(GameEnums.State.PLAYING)

## ADR-028: kein Host-Migration-Konzept — Autorität verloren beendet die Session
## geordnet, statt sie in einem eingefrorenen State hängen zu lassen.
## change_state() → MAIN_MENU löst über ServiceOrchestrator._on_state_changed()
## den bereits existierenden Teardown-Pfad aus (CharacterScope/WorldScope
## abbauen, SaveSystem.end_session()) — derselbe Pfad wie beim regulären
## "Zurück zum Hauptmenü". Kein zweiter, paralleler Teardown-Mechanismus nötig.
func _on_host_connection_lost() -> void:
	AppLogger.log_warn(
		"Verbindung zur Autorität verloren — Session wird beendet, kein Host-Migration-Versuch (ADR-028).",
		LOG_CAT
	)
	change_state(GameEnums.State.MAIN_MENU)

func change_state(new_state: GameEnums.State) -> void:
	if new_state == _current_state:
		AppLogger.log_debug(
			"change_state ignoriert — bereits in State %s." % GameEnums.State.keys()[new_state],
			LOG_CAT
		)
		return

	# StateValidator behandelt null-config selbst (fail-closed + Logging) —
	# kein zweiter Null-Check hier mit abweichendem Verhalten.
	if not StateValidator.is_transition_allowed(_current_state, new_state, _config):
		AppLogger.log_error(
			"Uebergang BLOCKIERT: %s -> %s (nicht in valid_transitions oder Config fehlt)." % [
				GameEnums.State.keys()[_current_state], GameEnums.State.keys()[new_state]
			],
			LOG_CAT
		)
		return

	AppLogger.log_info(
		(
			"State: %s → %s"
			% [GameEnums.State.keys()[_current_state], GameEnums.State.keys()[new_state]]
		),
		LOG_CAT
	)
	_current_state = new_state

	if _scene_manager:
		_scene_manager.transition_to_state(_current_state)

	_bus.system().emit_state_changed(_current_state)

func get_state() -> GameEnums.State:
	return _current_state

func is_playing() -> bool:
	return _current_state == GameEnums.State.PLAYING

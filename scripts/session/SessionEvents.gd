class_name SessionEvents extends BaseEvents

## SessionEvents — EventBus-Namespace für Session-Lifecycle-Signale (ADR-009).
##
## ADR-018: Aus SystemEvents herausgelöst. Gehört fachlich zu scripts/session/
## (wo SessionManager bereits lebt), nicht in den domänenlosen eventbus/-Ordner.
##
## Einbinden in EventBus.gd:
##   var session: SessionEvents
##   # in _ready():
##   session = SessionEvents.new()
##
## Verwendung:
##   EventBus.session.session_ready.connect(_on_session_ready)
##   EventBus.session.emit_session_requested("player_1")

## Emittiert von MainMenuController wenn Spieler einen Charakter auswählt.
## ServiceOrchestrator lauscht hierauf und startet boot_session(player_id).
signal session_requested(player_id: String)
## Emittiert von ServiceOrchestrator wenn boot_session() abgeschlossen ist.
## GameManager lauscht hierauf und wechselt in PLAYING-State.
signal session_ready
## Emittiert von ServiceOrchestrator wenn teardown_session() abgeschlossen ist.
## MainMenuController lauscht hierauf für UI-Refresh.
signal session_unloaded

func _init() -> void:
	super._init("Events/Session")

func emit_session_requested(player_id: String) -> void:
	_log_info("Session angefordert für Charakter '%s'." % player_id)
	session_requested.emit(player_id)

func emit_session_ready() -> void:
	_log_info("Session bereit — Spiel kann starten.")
	session_ready.emit()

func emit_session_unloaded() -> void:
	_log_info("Session beendet — zurück zum Hauptmenü.")
	session_unloaded.emit()

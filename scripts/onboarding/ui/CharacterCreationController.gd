class_name CharacterCreationController
extends Node

## CharacterCreationController — orchestriert die Fragenreihe und wendet das
## abgeleitete Aussehen auf den lokalen Player an. Round 105 (ADR-048),
## Round 106: request_submit_answers()/request_skip_creation() statt
## submit_answers()/skip_creation() direkt — auf Tier 1/Host läuft das
## weiterhin synchron (character_creation_confirmed feuert noch im selben
## Aufruf), auf einem Nicht-Host-Client aber erst nach dem RPC-Rückkanal.
## Deshalb hängt die "fertig"-Logik (Aussehen anwenden, Panel schließen,
## Toast zeigen) jetzt an _on_creation_confirmed() statt direkt nach dem
## Service-Aufruf zu laufen — funktioniert für beide Fälle identisch, weil
## GDScript-Signale synchron ausgeliefert werden (Tier 1/Host: Handler läuft
## noch innerhalb desselben Aufrufs).
##
## AUSSEHEN-ANWENDUNG: läuft über `IUIContext.get_local_player()` →
## `PlayerVisuals.apply_appearance()`, sowohl beim initialen `setup()`
## (deckt wiederkehrende Spieler ab, deren Erstellung schon in einer
## früheren Sitzung abgeschlossen wurde) als auch direkt nach Abschluss/
## Überspringen. BEKANNTE LÜCKE (bewusst nicht Teil dieser Runde): wenn der
## Player-Node erst NACH dem HUD-Build spawnt, läuft der initiale
## `_apply_current_appearance()`-Aufruf ins Leere — kein Retry, kein
## Signal-Listener auf Spawn-Events. In der bisher beobachteten Boot-
## Reihenfolge (Player spawnt als Teil des World-Boots vor dem HUD) tritt
## das nicht auf, wurde aber nicht gegen echte Godot-Startreihenfolge
## verifiziert (kein Editor-Zugriff, wie bei jeder UI-Runde in diesem
## Projekt).

var _visuals: CharacterCreationVisuals
var _ctx: IUIContext
var _questions: Array = []
var _current_index: int = 0
var _answers: Dictionary = {}
## Round 106: welche Aktion gerade auf character_creation_confirmed()
## wartet — bestimmt den Toast-Text in _on_creation_confirmed(). Leer,
## solange keine Anfrage läuft.
var _pending_action: String = ""

func setup(visuals: CharacterCreationVisuals, ctx: IUIContext) -> void:
	_visuals = visuals
	_ctx     = ctx

	_apply_current_appearance()

	var svc := _svc()
	if is_instance_valid(svc) and not svc.character_creation_confirmed.is_connected(_on_creation_confirmed):
		svc.character_creation_confirmed.connect(_on_creation_confirmed)

	var pid := _pid()
	if not is_instance_valid(svc) or pid.is_empty() or svc.has_seen_creation(pid):
		return

	_questions = svc.get_questions()
	_answers = {}
	_current_index = 0

	_visuals.option_selected.connect(_on_option_selected)
	_visuals.skip_pressed.connect(_on_skip_pressed)

	_render_current()
	_visuals.show_panel()

func _svc() -> CharacterCreationService:
	return _ctx.get_character_creation_service() if is_instance_valid(_ctx) else null

func _pid() -> String:
	return _ctx.get_local_player_id() if is_instance_valid(_ctx) else ""

func _apply_current_appearance() -> void:
	var svc := _svc()
	var pid := _pid()
	if not is_instance_valid(svc) or pid.is_empty():
		return
	var color := svc.get_appearance_color(pid)
	var player_node := _ctx.get_local_player() if is_instance_valid(_ctx) else null
	if player_node is Player:
		var player := player_node as Player
		if is_instance_valid(player.visuals):
			player.visuals.apply_appearance(color)

func _render_current() -> void:
	if _current_index >= _questions.size():
		return
	_visuals.render_question(_questions[_current_index], _current_index, _questions.size())

func _on_option_selected(option_id: String) -> void:
	if _current_index >= _questions.size():
		return
	var question: Dictionary = _questions[_current_index]
	_answers[String(question.get("id", ""))] = option_id
	_current_index += 1

	if _current_index >= _questions.size():
		_finish_with_answers()
	else:
		_render_current()

func _on_skip_pressed() -> void:
	var svc := _svc()
	var pid := _pid()
	if is_instance_valid(svc) and not pid.is_empty():
		_pending_action = "skip"
		svc.request_skip_creation(pid)
	else:
		_apply_current_appearance()
		_visuals.hide_panel()
		_show_toast("Charaktererstellung übersprungen — du kannst später jederzeit neu entscheiden.")

func _finish_with_answers() -> void:
	var svc := _svc()
	var pid := _pid()
	if is_instance_valid(svc) and not pid.is_empty():
		_pending_action = "submit"
		svc.request_submit_answers(pid, _answers)
	else:
		_apply_current_appearance()
		_visuals.hide_panel()
		_show_toast("Willkommen in Wildgrove!")

## Round 106: läuft für Tier 1/Host noch synchron innerhalb von
## request_submit_answers()/request_skip_creation() (siehe Klassenkommentar),
## für einen Nicht-Host-Client erst nach dem RPC-Rückkanal. Filtert auf die
## lokale player_id — die Autorität kann character_creation_confirmed auch
## für ANDERE Spieler emittieren (deren eigene request_*()-Aufrufe liefen
## über RPC auf dem Host durch), die dürfen hier nicht reagieren.
func _on_creation_confirmed(player_id: String) -> void:
	if player_id != _pid():
		return
	_apply_current_appearance()
	_visuals.hide_panel()
	if _pending_action == "skip":
		_show_toast("Charaktererstellung übersprungen — du kannst später jederzeit neu entscheiden.")
	else:
		_show_toast("Willkommen in Wildgrove!")
	_pending_action = ""

func _show_toast(text: String) -> void:
	if is_instance_valid(_ctx) and is_instance_valid(_ctx.bus()):
		_ctx.bus().ui().emit_notification_requested(text)

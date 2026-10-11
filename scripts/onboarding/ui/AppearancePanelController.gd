class_name AppearancePanelController
extends Node

## AppearancePanelController — verdrahtet AppearancePanelVisuals mit
## CharacterCreationService.request_set_look()/get_look() und wendet den Look
## live auf den lokalen Player an (PlayerVisuals.apply_look()), analog zu
## CharacterCreationController._apply_current_appearance() für die Farbe.
##
## LIVE-VORSCHAU: jeder ◀/▶-Klick baut sofort lokal einen Kandidaten-Look
## (CharacterLook.step()) und wendet ihn testweise auf den lokalen Player an,
## BEVOR die Autorität bestätigt hat — fühlt sich beim Klicken direkt an.
## Läuft die Bestätigung (look_changed) für die eigene player_id ein, wird der
## bestätigte Look übernommen; er ist identisch bis auf Netzwerk-Edge-Cases
## (siehe _on_look_changed()). Bei einer laufenden Anfrage werden weitere
## Klicks auf denselben lokalen Kandidaten-Look aufgesetzt (kein Warten pro
## Klick nötig) — der letzte gesendete Stand gewinnt serverseitig ohnehin.
##
## Denselben bekannten Spawn-Reihenfolge-Vorbehalt wie
## CharacterCreationController (Player kann beim Öffnen noch nicht existieren)
## — hier zusätzlich abgefedert: _apply_to_player() wird bei JEDEM Öffnen des
## Panels erneut versucht, nicht nur einmalig bei setup().

var _visuals: AppearancePanelVisuals
var _ctx: IUIContext
var _candidate: Dictionary = {}

func setup(visuals: AppearancePanelVisuals, ctx: IUIContext) -> void:
	_visuals = visuals
	_ctx     = ctx

	# Nur Körper-Felder (inkl. Geschlecht): Kleidung/Rüstung sind echte Items (Inventar → Anziehen).
	_visuals.build_fields(CharacterLook.editor_fields())
	_visuals.field_stepped.connect(_on_field_stepped)
	_visuals.opened.connect(_on_opened)

	var svc := _svc()
	if is_instance_valid(svc) and not svc.look_changed.is_connected(_on_look_changed):
		svc.look_changed.connect(_on_look_changed)

	_candidate = _current_look()
	_refresh_labels()

func _svc() -> CharacterCreationService:
	return _ctx.get_character_creation_service() if is_instance_valid(_ctx) else null

func _pid() -> String:
	return _ctx.get_local_player_id() if is_instance_valid(_ctx) else ""

func _current_look() -> Dictionary:
	var svc := _svc()
	var pid := _pid()
	if is_instance_valid(svc) and not pid.is_empty():
		return svc.get_look(pid)
	return CharacterLook.default_look()

func _on_opened() -> void:
	_candidate = _current_look()
	_refresh_labels()
	_apply_to_player(_candidate)

func _on_field_stepped(field: String, delta: int) -> void:
	_candidate = CharacterLook.step(_candidate, field, delta)
	_refresh_labels()
	_apply_to_player(_candidate)

	var svc := _svc()
	var pid := _pid()
	if is_instance_valid(svc) and not pid.is_empty():
		svc.request_set_look(pid, _candidate)

## Läuft für JEDEN Spieler, dessen Look sich ändert (eigener request_set_look()
## ODER seit Round 114 auch ein Broadcast von einem anderen Peer, siehe
## CharacterCreationService._on_broadcast_event_received()). Wendet nur für
## die lokale player_id an; andere player_ids ignoriert dieser Controller
## bewusst — deren Visual-Anwendung übernimmt bereits CharacterCreationService
## selbst (_apply_look_to_visuals(), löst über einen beliebigen player_id auf,
## dieser Controller kennt dagegen nur den lokalen Player-Node).
func _on_look_changed(player_id: String) -> void:
	if player_id != _pid():
		return
	_candidate = _current_look()
	_refresh_labels()
	_apply_to_player(_candidate)

func _refresh_labels() -> void:
	for field in CharacterLook.editor_fields():
		var key: String = String((field as Dictionary)["key"])
		var id: String = String(_candidate.get(key, ""))
		_visuals.update_field(key, CharacterLook.label_of(key, id))

func _apply_to_player(look: Dictionary) -> void:
	var player_node := _ctx.get_local_player() if is_instance_valid(_ctx) else null
	if player_node is Player:
		var player := player_node as Player
		if is_instance_valid(player.visuals):
			player.visuals.apply_look(look)

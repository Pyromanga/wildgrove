class_name MountController
extends Node

## MountController — Aufsteigen/Absteigen per Knopf (Reittiere: Pferd, Esel; siehe MountDefinitions).
##
## Alle 0.2 s wird geprüft, ob ein eigenes, besteigbares Pet in Reichweite steht (oder der Spieler
## schon reitet) und der Knopf entsprechend ein-/ausgeblendet. Die eigentlichen Regeln (Solo,
## Besitzer, Reichweite, nicht tot) liegen in Player.try_mount()/PlayerMount.can_mount() —
## der Knopf zeigt nur an, was auch funktionieren würde.

const REFRESH_INTERVAL: float = 0.2
const LOG_CAT := "Mount"

var _visuals: MountVisuals
var _ctx: IUIContext
var _cooldown: float = 0.0
var _target: PetComponent = null

func setup(visuals: MountVisuals, ctx: IUIContext = null) -> void:
	_visuals = visuals
	_ctx = ctx
	_visuals.connect_pressed(_on_pressed)

func _process(delta: float) -> void:
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	_cooldown = REFRESH_INTERVAL
	refresh()

## Nächstes besteigbares Pet des Spielers in Reichweite (reine Auswahl, ohne UI — testbar).
## peer_id: Besitzer-Peer des Spielers. Pets, die schon geritten werden, zählen nicht.
static func find_nearest_mountable(player_pos: Vector3, peer_id: int, pets: Array) -> PetComponent:
	var best: PetComponent = null
	var best_d := INF
	for p in pets:
		var pet := p as PetComponent
		if pet == null or not is_instance_valid(pet):
			continue
		if PlayerMount.can_mount(player_pos, peer_id, pet, false) != "":
			continue
		var d := pet.global_position.distance_to(player_pos)
		if d < best_d:
			best_d = d
			best = pet
	return best

func refresh() -> void:
	var player := _get_player()
	if player == null or not is_instance_valid(_visuals):
		if is_instance_valid(_visuals):
			_visuals.hide_button()
		return
	if player.is_mounted():
		var ridden := player.get_mount()
		_target = null
		_visuals.show_dismount(MountDefinitions.label_for(ridden.get_species_id()) if ridden != null else "")
		return
	_target = find_nearest_mountable(player.global_position, int(player.get_meta("owner_peer_id", 1)),
		get_tree().get_nodes_in_group("pets"))
	if _target == null:
		_visuals.hide_button()
	else:
		_visuals.show_mount(MountDefinitions.label_for(_target.get_species_id()))

func _on_pressed() -> void:
	var player := _get_player()
	if player == null:
		return
	if player.is_mounted():
		player.dismount()
	else:
		refresh()
		if _target != null:
			var reason := player.try_mount(_target)
			if reason != "":
				AppLogger.log_debug("Aufsteigen abgelehnt: %s" % reason, LOG_CAT)
				_notify(reason)
	refresh()

func _notify(reason: String) -> void:
	if reason == "not_solo" and is_instance_valid(_ctx) and is_instance_valid(_ctx.bus()):
		_ctx.bus().world().emit_interaction_reward_text("Reiten geht nur im Einzelspieler-Modus.")

func _get_player() -> Player:
	var p: Node = _ctx.get_local_player() if is_instance_valid(_ctx) else null
	return p as Player

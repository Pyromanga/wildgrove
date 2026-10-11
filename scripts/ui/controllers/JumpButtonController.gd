class_name JumpButtonController
extends Node

const JUMP_VELOCITY: float = 6.0
const LOG_CAT := "JumpBtn"

var _visuals: JumpButtonVisuals
var _ctx: IUIContext

func setup(visuals: JumpButtonVisuals, ctx: IUIContext = null) -> void:
	_visuals = visuals
	_ctx = ctx
	_visuals.connect_pressed(_on_jump_pressed)

func _on_jump_pressed() -> void:
	# ADR-015: ctx.get_local_player() statt get_nodes_in_group("player")[0] —
	# sonst könnte der Sprung-Button in Multiplayer den falschen Spieler
	# springen lassen.
	var player: Node = _ctx.get_local_player() if is_instance_valid(_ctx) else null
	if not is_instance_valid(player):
		return
	# request_jump() setzt nur ein Flag — das wird im nächsten _loop_free()
	# NACH calculate_velocity() angewendet, damit der Impuls nicht sofort durch
	# vel.y=0 (wenn on_floor) überschrieben wird.
	if player.has_method("request_jump"):
		player.request_jump()
	AppLogger.log_debug("Sprung angefordert.", LOG_CAT)

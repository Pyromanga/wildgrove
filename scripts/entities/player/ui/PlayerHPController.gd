class_name PlayerHPController
extends Node

var _visuals: PlayerHPVisuals
var _ctx: IUIContext

func setup(visuals: PlayerHPVisuals, ctx: IUIContext) -> void:
	_visuals = visuals
	_ctx = ctx
	_ctx.bus().player().player_health_changed.connect(_on_health_changed)
	_ctx.bus().player().player_respawned.connect(_on_respawned)
	# Initialen Stand per EventBus — Player.gd emittiert ihn nach add_child(health)
	# Bei Reconnect nach HUD-Rebuild: Stand unbekannt bis nächster Treffer/Heal.
	# Daher: refresh über Gruppe falls Player bereits im Tree
	call_deferred("_try_initial_sync")

func _try_initial_sync() -> void:
	# ADR-015: ctx.get_local_player() statt get_nodes_in_group("player")[0] —
	# sonst kann dieser HP-Balken in Multiplayer den Health-Stand des
	# falschen Spielers anzeigen.
	var player: Node3D = _ctx.get_local_player() if is_instance_valid(_ctx) else null
	if not is_instance_valid(player):
		return
	var hc := player.get_node_or_null("HealthComponent") as HealthComponent
	if is_instance_valid(hc):
		_visuals.update(hc.current_health, hc.max_health)

func _on_health_changed(current: int, maximum: int) -> void:
	_visuals.update(current, maximum)

func _on_respawned() -> void:
	_try_initial_sync()

class_name SkillPanelController
extends Node

var _visuals: SkillPanelVisuals
var _ctx: IUIContext

## R-7 (ADR-022): war doppelt falsch — (1) `EventBus.player().xp_gained`/
## `level_up` feuern NUR auf dem Prozess, der die Mutation tatsächlich ausführt
## (die Autorität, C-02-Guard in `SkillSystem.on_xp_add_confirmed()`) — für
## jeden Nicht-Host-Spieler feuerten diese Events lokal nie, unabhängig vom
## Rücksync. (2) `get_level(skill_id)`/`get_xp(skill_id)` ohne player_id-Argument
## lasen implizit immer Spieler 1s Daten. Jetzt: `SkillSystem.skill_changed`
## (feuert auf JEDEM Prozess, inkl. nach Rücksync-Empfang) + expliziter
## `_local_player_id()`.
## ADR-029 Round 65: SkillSystem ist auf player_id: String migriert —
## `_local_peer_id()` (int) ersetzt durch `_local_player_id()` (String).
func setup(visuals: SkillPanelVisuals, ctx: IUIContext) -> void:
	_visuals = visuals
	_ctx     = ctx
	var ss := _ctx.get_skill_system()
	if is_instance_valid(ss):
		ss.skill_changed.connect(_on_skill_changed)
	_refresh_all()

func _local_player_id() -> String:
	return _ctx.get_local_player_id() if is_instance_valid(_ctx) else ""

func _refresh_all() -> void:
	var ss := _ctx.get_skill_system()
	if not is_instance_valid(ss):
		return
	for skill_id in ss.get_skill_ids(_local_player_id()):
		_refresh_skill(skill_id)

func _refresh_skill(skill_id: String) -> void:
	var ss := _ctx.get_skill_system()
	if not is_instance_valid(ss):
		return
	var pid := _local_player_id()
	_visuals.update_skill(
		skill_id,
		ss.get_level(skill_id, pid),
		ss.get_xp(skill_id, pid),
		ss.get_xp_to_next_level(skill_id, pid)
	)

func _on_skill_changed(skill_id: String, player_id: String) -> void:
	if player_id != _local_player_id():
		return
	_refresh_skill(skill_id)

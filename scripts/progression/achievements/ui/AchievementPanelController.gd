class_name AchievementPanelController
extends Node

## AchievementPanelController — analog SkillPanelController/
## QuestPanelController. Round 104.
##
## Lauscht auf ALLE drei Signale, die AchievementService für den lokalen
## Spieler emittiert — unabhängig davon, ob sie autoritätsseitig direkt
## (grant_progress()/_unlock()) oder client-seitig über die Round-104-
## Empfangspfade (_on_remote_unlock_received()/_on_remote_snapshot_received())
## ausgelöst wurden. Der Controller selbst muss den Unterschied nicht kennen —
## exakt der Punkt von AchievementService's "CLIENT-EMPFANG"-Design.

var _visuals: AchievementPanelVisuals
var _ctx: IUIContext

func setup(visuals: AchievementPanelVisuals, ctx: IUIContext) -> void:
	_visuals = visuals
	_ctx     = ctx

	var svc := _ctx.get_achievement_service() if is_instance_valid(_ctx) else null
	if is_instance_valid(svc):
		svc.achievement_unlocked.connect(_on_achievement_unlocked)
		svc.achievement_progress.connect(_on_achievement_progress)
		svc.achievements_synced.connect(_on_achievements_synced)
		# Round 103 (ADR-046 "SNAPSHOT-SYNC"): eigenen Stand beim Öffnen der
		# Session anfragen — deckt sowohl den späten-Client-Fall (Server hat
		# schon Fortschritt, Client startet leer) als auch einen simplen
		# Neustart auf demselben Prozess ab. No-Op-sicher auf Tier 1
		# (request_snapshot() ruft dort synchron on_snapshot_requested() lokal).
		svc.request_snapshot(_local_player_id())

	_refresh_all()

func _local_player_id() -> String:
	return _ctx.get_local_player_id() if is_instance_valid(_ctx) else ""

func _refresh_all() -> void:
	var svc := _ctx.get_achievement_service() if is_instance_valid(_ctx) else null
	if not is_instance_valid(svc):
		return
	var pid := _local_player_id()
	var unlocked_ids: Array = svc.get_unlocked(pid)
	for achievement_id in svc.get_all_definitions().keys():
		var definition: Dictionary = svc.get_definition(achievement_id)
		var current: float = svc.get_progress(pid, achievement_id)
		_visuals.update_achievement(achievement_id, definition, current, achievement_id in unlocked_ids)

func _on_achievement_unlocked(player_id: String, achievement_id: String) -> void:
	if player_id != _local_player_id():
		return
	var svc := _ctx.get_achievement_service()
	var definition: Dictionary = svc.get_definition(achievement_id)
	_visuals.update_achievement(achievement_id, definition, float(definition.get("target", 0.0)), true)
	_show_unlock_toast(definition)

func _on_achievement_progress(player_id: String, achievement_id: String, current: float, _target: float) -> void:
	if player_id != _local_player_id():
		return
	var svc := _ctx.get_achievement_service()
	var definition: Dictionary = svc.get_definition(achievement_id)
	_visuals.update_achievement(achievement_id, definition, current, svc.is_unlocked(player_id, achievement_id))

func _on_achievements_synced(player_id: String) -> void:
	if player_id != _local_player_id():
		return
	_refresh_all()

## Kurznotiz über den bestehenden NotificationController (UIEvents.
## notification_requested) — bewusst kein eigenes Toast-System, exakt das
## bereits vorhandene Muster für "kurze, pro Peer sichtbare Meldung"
## (siehe WeatherService-Klassenkommentar, gleiches Prinzip).
func _show_unlock_toast(definition: Dictionary) -> void:
	if not is_instance_valid(_ctx) or not is_instance_valid(_ctx.bus()):
		return
	var text := "🏆 Achievement freigeschaltet: %s" % String(definition.get("name", "?"))
	var reward: int = int(definition.get("reward_gold", 0))
	if reward > 0:
		text += " (+%d Gold)" % reward
	_ctx.bus().ui().emit_notification_requested(text)

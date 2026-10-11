class_name WikiPanelController
extends Node

## WikiPanelController — analog AchievementPanelController. Round 108.
##
## Lauscht auf beide Signale, die WikiService für den lokalen Spieler
## emittiert — unabhängig davon, ob sie autoritätsseitig direkt
## (discover()) oder client-seitig über den Round-107-Empfangspfad
## (_on_remote_entry_discovered_received()/_on_remote_snapshot_received())
## ausgelöst wurden. Der Controller selbst muss den Unterschied nicht
## kennen — exakt derselbe Punkt wie bei AchievementService.
##
## KATALOG: WikiService selbst kennt nur ENTDECKTE Einträge
## (`get_all_discovered()`), keinen vollständigen Katalog aller
## MÖGLICHEN Einträge — das wäre ein Leck (ein Client könnte aus der
## Anzahl der Zeilen auf Inhalte schließen, die er noch nicht entdeckt
## hat). Der Controller baut den Katalog stattdessen selbst aus
## `DataService` (`get_all_combat_profiles()`/`get_all_loot_tables()`/
## `get_all_skills()`/`get_all_quests()`) — dieselben Daten liegen dem
## Client ohnehin bereits vor (Gameplay-Systeme laden sie clientseitig),
## kein zusätzliches Leck gegenüber dem Status quo. Unentdeckte Zeilen
## zeigen nur "???" (siehe `WikiPanelVisuals` "UNENTDECKT") — der Name
## selbst bleibt also durchaus sichtbar (aus dem Katalog), NICHT aber
## Beschreibung/Werte (aus `get_entry_details()`, nur bei `is_discovered`
## abgefragt). Das ist ein bewusster Kompromiss: vollständige Verschleierung
## selbst des Namens würde bedeuten, den Katalog serverseitig zu filtern
## und den Client bei jeder Entdeckung neu zu befüllen — für ein reines
## Info-Wiki ohne Wettbewerbs-Charakter (anders als z.B. ein Auktionshaus)
## nicht den Mehraufwand wert. Siehe ADR-049 "Bewusst nicht Teil dieser
## Runde" für die Abgrenzung.

var _visuals: WikiPanelVisuals
var _ctx: IUIContext

func setup(visuals: WikiPanelVisuals, ctx: IUIContext) -> void:
	_visuals = visuals
	_ctx     = ctx

	var svc := _ctx.get_wiki_service() if is_instance_valid(_ctx) else null
	if is_instance_valid(svc):
		svc.wiki_entry_discovered.connect(_on_wiki_entry_discovered)
		svc.wiki_synced.connect(_on_wiki_synced)
		# Round 107 (ADR-049 "SNAPSHOT-SYNC"): eigenen Stand beim Öffnen der
		# Session anfragen — deckt sowohl den späten-Client-Fall als auch
		# einen simplen Neustart auf demselben Prozess ab. No-Op-sicher auf
		# Tier 1 (request_snapshot() ruft dort synchron on_snapshot_requested()
		# lokal auf).
		svc.request_snapshot(_local_player_id())

	_refresh_all()

func _local_player_id() -> String:
	return _ctx.get_local_player_id() if is_instance_valid(_ctx) else ""

func _refresh_all() -> void:
	var svc := _ctx.get_wiki_service() if is_instance_valid(_ctx) else null
	var data := _ctx.get_data() if is_instance_valid(_ctx) else null
	if not is_instance_valid(svc) or not is_instance_valid(data):
		return
	var pid := _local_player_id()

	for category in WikiService.CATEGORIES:
		for entry_id in _catalog_ids(category, data):
			var discovered := svc.is_discovered(pid, category, entry_id)
			var details := svc.get_entry_details(category, entry_id) if discovered else {}
			_visuals.update_entry(category, entry_id, discovered, details)

## Siehe Klassenkommentar "KATALOG".
func _catalog_ids(category: String, data: DataService) -> Array:
	match category:
		WikiService.CATEGORY_ENEMIES: return data.get_all_combat_profiles().keys()
		WikiService.CATEGORY_DROPS:   return data.get_all_loot_tables().keys()
		WikiService.CATEGORY_SKILLS:  return data.get_all_skills().keys()
		WikiService.CATEGORY_QUESTS:  return data.get_all_quests().keys()
		_: return []

func _on_wiki_entry_discovered(player_id: String, category: String, entry_id: String) -> void:
	if player_id != _local_player_id():
		return
	var svc := _ctx.get_wiki_service()
	var details := svc.get_entry_details(category, entry_id)
	_visuals.update_entry(category, entry_id, true, details)
	_show_discovery_toast(category, details, entry_id)

func _on_wiki_synced(player_id: String) -> void:
	if player_id != _local_player_id():
		return
	_refresh_all()

## Kurznotiz über den bestehenden NotificationController (UIEvents.
## notification_requested) — bewusst kein eigenes Toast-System, analog
## AchievementPanelController._show_unlock_toast().
func _show_discovery_toast(category: String, details: Dictionary, entry_id: String) -> void:
	if not is_instance_valid(_ctx) or not is_instance_valid(_ctx.bus()):
		return
	var name_text: String = String(
		details.get("display_name", details.get("title", entry_id))
	)
	_ctx.bus().ui().emit_notification_requested("📖 Wiki-Eintrag entdeckt: %s" % name_text)

extends Service
class_name WikiService

## ADR-049: Spielerbefülltes Wiki — Round 107.
##
## SCOPING (siehe TODO-offene-probleme.md, Antworten des Auftraggebers):
##   - PRO SPIELER LOKAL, nicht geteilt — jeder Spieler hat seine eigene
##     Wissensbasis. Kein Auktionshaus-artiges Broadcast an alle Peers.
##     Architektonisch bedeutet das NICHT "kein Netzwerkcode" — es bedeutet
##     "derselbe Per-Player-Bucket + gezielte Ein-Empfänger-RPC wie
##     AchievementService", nur eben NIE an andere Spieler weitergereicht.
##   - BEFÜLLUNG: automatisch aus vorhandenen autoritativen Quellen
##     ABGELEITET (Kombat-Profile/Loot-Tabellen/Quest-Katalog/Skill-
##     Definitionen über DataService — dieselben Ressourcen, die die
##     jeweiligen Gameplay-Systeme selbst nutzen), UND an tatsächliche
##     Entdeckung durch den Spieler GEKOPPELT (kein Full-Unlock beim
##     Boot) — kein manuelles Eintragen durch den Spieler.
##   - ALLE VIER Kategorien in dieser Runde: "enemies", "drops", "skills",
##     "quests".
##
## DATENMODELL: `_discovered[player_id][category]` = Array[String] von
## entry_ids. Eine entry_id ist die jeweilige domänen-eigene ID (z.B.
## CombatProfile.id für "enemies", LootTable-Dateiname ohne .tres für
## "drops", SkillDefinition.id für "skills", QuestDefinition.id für
## "quests") — kein eigenes Wiki-ID-Schema, um Divergenz von der
## eigentlichen Datenquelle zu vermeiden.
##
## TRIGGER-QUELLEN (drei, alle nachweislich autoritäts-only — exakt
## dieselben Vertrauens-Argumente wie AchievementService/StatsService):
##   - `EventBus.world().enemy_killed(enemy_type_id, position, peer_id)` —
##     entdeckt sowohl den Gegner ("enemies") als auch dessen Loot-Tabelle
##     ("drops", via `ENEMY_LOOT_TABLE_MAP`, siehe dort). Peer_id→player_id
##     via `NetworkBridge.get_player_id_for_peer()`, identisches 5-Zeilen-
##     Muster wie StatsService._resolve_player_uuid().
##   - `EventBus.quest().quest_started_for_player(player_id, quest_id)` —
##     neu in dieser Runde (QuestEvents.gd) als player_id-tragendes
##     Gegenstück zu `quest_started(quest_id)`, das selbst KEINE player_id
##     trägt (QuestPanelController brauchte sie bisher nie). Emittiert an
##     derselben Stelle wie `quest_started` (`on_quest_start_confirmed()`,
##     läuft nur auf der Autorität) — kein zusätzlicher Trigger-Pfad, nur
##     ein zusätzliches Signal am bestehenden.
##   - `SkillSystem.skill_changed(skill_id, player_id)` — bereits
##     bestehend, feuert aus `on_xp_add_confirmed()` (Autorität) UND beim
##     Economy-Sync-Empfang auf dem Client selbst. Harmlos für WikiService:
##     `discover()` läuft trotzdem hinter `_require_authority()` — ein
##     Client, der skill_changed über den Sync-Pfad empfängt, entscheidet
##     hier nichts neu, er bekommt den Unlock stattdessen über die eigene
##     gezielte Wiki-RPC von der Autorität (siehe unten).
##
## GEGNER→LOOT-TABELLE-ZUORDNUNG (`ENEMY_LOOT_TABLE_MAP`): es gibt noch
## keine strukturierte `EnemyDefinition`-Ressource, die Gegnertyp auf
## Loot-Tabelle abbildet (siehe TODO-offene-probleme.md — das war explizit
## als offene Frage vermerkt, "sofern es diese Quellen bereits strukturiert
## gibt"). Aktuell ist genau ein Gegnertyp verdrahtet (`EnemyNPC._type_id
## = "goblin"`, `_loot_table_id = "goblin_loot"`). Statt eine neue
## Ressourcenklasse für diese Runde zu erfinden (Scope-Creep), folgt
## `ENEMY_LOOT_TABLE_MAP` demselben Muster wie
## `AchievementService.DEFAULT_DEFINITIONS`: ein eingebauter Fallback,
## additiv erweiterbar, kein Datenmodell-Umbau nötig sobald eine echte
## `EnemyDefinition`-Ressource kommt (dann würde `_loot_table_for_enemy()`
## zuerst dort nachschlagen, siehe Kommentar an der Funktion selbst).
##
## MULTIPLAYER-KORREKTHEIT: `discover()` läuft nur auf der Autorität
## (`_require_authority()`). Der Host sieht seinen eigenen Unlock direkt
## über das lokal emittierte `wiki_entry_discovered`-Signal. Ein entfernter
## Client wird zusätzlich per RPC benachrichtigt
## (`NetworkBridge.send_wiki_entry_discovered_for_player()`) — NUR an den
## betroffenen Spieler, nie an andere (siehe "PRO SPIELER LOKAL" oben).
##
## SNAPSHOT-SYNC: `request_snapshot()`/`on_snapshot_requested()` +
## `NetworkBridge.send_wiki_snapshot_request()`/
## `send_wiki_snapshot_for_player()` — Pull-statt-Push für spät joinende/
## neu gestartete Clients, exakt dasselbe Muster wie AchievementService
## (dort Round 103, hier gleich in der Grundrunde mitgezogen statt als
## eigene Folge-Lücke offen zu lassen).
##
## PERSISTENZ: `SAVE_KEY = "wiki"` — entdeckte Einträge überleben Sitzungen.
##
## BEWUSST NICHT TEIL DIESER RUNDE:
##   - Kein UI-Panel (analog AchievementService: erst Grundgerüst, dann
##     Panel in einer Folge-Runde — Round 102→104-Vorbild). `get_entry_
##     details()` liefert bereits die vollständigen Anzeige-Daten, ein
##     künftiges Panel muss keine neue Service-API dafür bauen.
##   - Keine echte `EnemyDefinition`-Ressource — siehe "GEGNER→LOOT-
##     TABELLE-ZUORDNUNG" oben.
##   - `get_drop_chances()`s Prozentzahlen sind eine Näherung
##     (weight / total_weight), NICHT die exakte Wahrscheinlichkeit unter
##     `LootTable.roll()`s `max_rolls`-Abbruch — für eine Wiki-Anzeige
##     ausreichend, aber kein Ersatz für eine Simulation.
##   - Kein Telemetrie-Event (anders als AchievementService — Entdeckungen
##     sind kein Balancing-relevantes Ereignis in dieser Runde).
##   - Kein Zwei-Peer-Integrationstest für den RPC-Rückkanal (wie immer in
##     dieser Umgebung: nur gegen Spy-/Stub-Doubles geprüft).

const LOG_CAT := "WikiService"
const SAVE_KEY := "wiki"

const CATEGORY_ENEMIES := "enemies"
const CATEGORY_DROPS   := "drops"
const CATEGORY_SKILLS  := "skills"
const CATEGORY_QUESTS  := "quests"

const CATEGORIES: Array[String] = [CATEGORY_ENEMIES, CATEGORY_DROPS, CATEGORY_SKILLS, CATEGORY_QUESTS]

## Eingebauter Fallback enemy_type_id -> loot_table_id — siehe
## Klassenkommentar "GEGNER→LOOT-TABELLE-ZUORDNUNG". Nur "goblin" ist
## aktuell tatsächlich im Spiel verdrahtet (EnemyNPC-Defaults); "skeleton"
## ist als CombatProfile bereits vorhanden (data/combat_profiles/
## skeleton.tres), aber noch nicht gespawnt — hier trotzdem ergänzt, damit
## ein künftiger Spawn ohne Wiki-Anpassung funktioniert.
const ENEMY_LOOT_TABLE_MAP: Dictionary = {
	"goblin": "goblin_loot",
}

## Emittiert, sobald ein Eintrag für player_id in category entdeckt wird.
signal wiki_entry_discovered(player_id: String, category: String, entry_id: String)

## Emittiert, wenn ein Wiki-Snapshot vom Server angekommen ist und
## _discovered[player_id] neu gesetzt wurde (analog
## AchievementService.achievements_synced).
signal wiki_synced(player_id: String)

var _save_system:     SaveSystem     = null
var _network:         NetworkBridge  = null
var _data:             DataService   = null
var _bus:              IEventBus     = null
var _skill_system:     SkillSystem   = null
## Nur für _local_player_id() auf dem Client — analog AchievementService.
var _session_manager:  SessionManager = null

## player_id -> { category: String -> Array[String] entdeckter entry_ids }
var _discovered: Dictionary = {}

func configure(deps: ServiceDeps) -> void:
	_save_system  = deps.get_optional(ServiceKeys.SAVE_SYSTEM)   as SaveSystem
	_data         = deps.get_optional(ServiceKeys.DATA)          as DataService
	_bus          = deps.get_optional(ServiceKeys.EVENT_BUS)     as IEventBus
	_skill_system = deps.get_optional(ServiceKeys.SKILL_SYSTEM)  as SkillSystem
	_session_manager = deps.get_optional(ServiceKeys.SESSION_MANAGER) as SessionManager

	if is_instance_valid(_bus):
		_bus.world().enemy_killed.connect(_on_enemy_killed)
		_bus.quest().quest_started_for_player.connect(_on_quest_started_for_player)
	else:
		AppLogger.log_error("Abhängigkeit 'event_bus' fehlt — Wiki-Trigger 'enemies'/'drops'/'quests' inaktiv!", LOG_CAT)

	if is_instance_valid(_skill_system):
		_skill_system.skill_changed.connect(_on_skill_changed)
	else:
		AppLogger.log_error("Abhängigkeit 'skill_system' fehlt — Wiki-Trigger 'skills' inaktiv!", LOG_CAT)

	_connect_network_receive()

	if _save_system:
		_save_system.register_save_provider(self)
		var saved: Variant = _save_system.get_state_for(SAVE_KEY)
		if saved is Dictionary and not (saved as Dictionary).is_empty():
			_restore_from_save(saved)
	else:
		AppLogger.log_error("Abhängigkeit 'savesystem' fehlt!", LOG_CAT)

	AppLogger.log_info("WikiService initialisiert.", LOG_CAT)

func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network
	_connect_network_receive()

func on_cleanup() -> void:
	if is_instance_valid(_bus):
		if _bus.world().enemy_killed.is_connected(_on_enemy_killed):
			_bus.world().enemy_killed.disconnect(_on_enemy_killed)
		if _bus.quest().quest_started_for_player.is_connected(_on_quest_started_for_player):
			_bus.quest().quest_started_for_player.disconnect(_on_quest_started_for_player)
	if is_instance_valid(_skill_system) and _skill_system.skill_changed.is_connected(_on_skill_changed):
		_skill_system.skill_changed.disconnect(_on_skill_changed)
	if is_instance_valid(_network):
		if _network.wiki_entry_discovered_received.is_connected(_on_remote_entry_discovered_received):
			_network.wiki_entry_discovered_received.disconnect(_on_remote_entry_discovered_received)
		if _network.wiki_snapshot_received.is_connected(_on_remote_snapshot_received):
			_network.wiki_snapshot_received.disconnect(_on_remote_snapshot_received)

## Gegenstück zu discover()/on_snapshot_requested() (beide hinter
## _require_authority() gesperrt) — übernimmt Server-Payloads auf dem
## Client OHNE den Authority-Guard, exakt das Verdrahtungsmuster von
## AchievementService._connect_network_receive().
func _connect_network_receive() -> void:
	if not is_instance_valid(_network):
		return
	if not _network.wiki_entry_discovered_received.is_connected(_on_remote_entry_discovered_received):
		_network.wiki_entry_discovered_received.connect(_on_remote_entry_discovered_received)
	if not _network.wiki_snapshot_received.is_connected(_on_remote_snapshot_received):
		_network.wiki_snapshot_received.connect(_on_remote_snapshot_received)

# ─────────────────────────────────────────────
# Trigger-Handler (siehe Klassenkommentar "TRIGGER-QUELLEN")
# ─────────────────────────────────────────────

func _on_enemy_killed(enemy_type_id: String, _position: Vector3, peer_id: int) -> void:
	var player_id := _resolve_player_uuid(peer_id)
	if player_id.is_empty():
		return
	discover(player_id, CATEGORY_ENEMIES, enemy_type_id)
	var loot_table_id := _loot_table_for_enemy(enemy_type_id)
	if not loot_table_id.is_empty():
		discover(player_id, CATEGORY_DROPS, loot_table_id)

func _on_quest_started_for_player(player_id: String, quest_id: String) -> void:
	discover(player_id, CATEGORY_QUESTS, quest_id)

func _on_skill_changed(skill_id: String, player_id: String) -> void:
	discover(player_id, CATEGORY_SKILLS, skill_id)

## Siehe Klassenkommentar "GEGNER→LOOT-TABELLE-ZUORDNUNG". Fällt auf
## "<enemy_type_id>_loot" zurück, falls eine künftige EnemyDefinition/neue
## Gegnertypen dem Namensschema von "goblin"/"goblin_loot" folgen — besser
## als stillschweigend NICHTS zu entdecken.
func _loot_table_for_enemy(enemy_type_id: String) -> String:
	if ENEMY_LOOT_TABLE_MAP.has(enemy_type_id):
		return String(ENEMY_LOOT_TABLE_MAP[enemy_type_id])
	return "%s_loot" % enemy_type_id

## Identisches 5-Zeilen-Muster wie StatsService._resolve_player_uuid()/
## QuestService._resolve_player_uuid() — bewusst keine gemeinsame Utility,
## siehe dortige Diskussion (Round 63).
func _resolve_player_uuid(peer_id: int) -> String:
	if not is_instance_valid(_network):
		AppLogger.log_warn(
			"_resolve_player_uuid(%d): kein NetworkBridge injiziert — Übersetzung nicht möglich." % peer_id,
			LOG_CAT
		)
		return ""
	return _network.get_player_id_for_peer(peer_id)

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

## Markiert (player_id, category, entry_id) als entdeckt. No-Op wenn bereits
## entdeckt, wenn category unbekannt ist, oder wenn player_id/entry_id leer
## ist. Autoritäts-only (siehe Klassenkommentar "MULTIPLAYER-KORREKTHEIT").
func discover(player_id: String, category: String, entry_id: String) -> void:
	if not _require_authority("discover"):
		return
	if player_id.is_empty() or entry_id.is_empty():
		return
	if category not in CATEGORIES:
		AppLogger.log_error("discover(): unbekannte Kategorie '%s'." % category, LOG_CAT)
		return
	if is_discovered(player_id, category, entry_id):
		return

	if not _discovered.has(player_id):
		_discovered[player_id] = {}
	var bucket: Dictionary = _discovered[player_id]
	if not bucket.has(category):
		bucket[category] = []
	(bucket[category] as Array).append(entry_id)

	AppLogger.log_info("Wiki-Eintrag entdeckt: '%s' -> %s/%s." % [player_id, category, entry_id], LOG_CAT)
	wiki_entry_discovered.emit(player_id, category, entry_id)

	if is_instance_valid(_network):
		_network.send_wiki_entry_discovered_for_player(player_id, {
			"category": category, "entry_id": entry_id,
		})

func is_discovered(player_id: String, category: String, entry_id: String) -> bool:
	var bucket: Dictionary = _discovered.get(player_id, {})
	return entry_id in (bucket.get(category, []) as Array)

func get_discovered(player_id: String, category: String) -> Array:
	var bucket: Dictionary = _discovered.get(player_id, {})
	return (bucket.get(category, []) as Array).duplicate()

func get_all_discovered(player_id: String) -> Dictionary:
	return (_discovered.get(player_id, {}) as Dictionary).duplicate(true)

## Liefert die Anzeige-Daten für einen entry_id — UNABHÄNGIG davon, ob er
## entdeckt wurde (der Aufrufer, z.B. ein künftiges UI-Panel, filtert selbst
## über is_discovered() bevor er das anzeigt). Rein lesend aus DataService,
## keine eigene Wiki-Datenkopie — bleibt automatisch aktuell, wenn sich
## Balance-Werte ändern.
func get_entry_details(category: String, entry_id: String) -> Dictionary:
	if not is_instance_valid(_data):
		return {}
	match category:
		CATEGORY_ENEMIES:
			var profile: CombatProfile = _data.get_combat_profile(entry_id)
			return {
				"id": entry_id, "display_name": profile.display_name,
				"armor": profile.armor, "magic_resist": profile.magic_resist,
				"loot_table_id": _loot_table_for_enemy(entry_id),
			}
		CATEGORY_DROPS:
			var table: LootTable = _data.get_loot_table(entry_id)
			if not is_instance_valid(table):
				return {}
			return {
				"id": entry_id, "gold_min": table.gold_min, "gold_max": table.gold_max,
				"drop_chances": get_drop_chances(entry_id),
			}
		CATEGORY_SKILLS:
			var skill: SkillDefinition = _data.get_all_skills().get(entry_id) as SkillDefinition
			if not is_instance_valid(skill):
				return {}
			return {
				"id": entry_id, "display_name": skill.display_name,
				"description": skill.description, "max_level": skill.max_level,
			}
		CATEGORY_QUESTS:
			var quest: QuestDefinition = _data.get_quest(entry_id)
			if not is_instance_valid(quest):
				return {}
			return {
				"id": entry_id, "title": quest.title, "description": quest.description,
				"category": quest.category, "objective_count": quest.objectives.size(),
				"repeatable": quest.repeatable,
			}
		_:
			return {}

## Näherungsweise Drop-Chance pro Item in Prozent — siehe Klassenkommentar
## "BEWUSST NICHT TEIL DIESER RUNDE". item_id -> Prozentwert (0-100).
func get_drop_chances(loot_table_id: String) -> Dictionary:
	if not is_instance_valid(_data):
		return {}
	var table: LootTable = _data.get_loot_table(loot_table_id)
	if not is_instance_valid(table) or table.entries.is_empty():
		return {}
	var total_weight := 0.0
	for e in table.entries:
		total_weight += max(e.weight, 0.0)
	if total_weight <= 0.0:
		return {}
	var chances: Dictionary = {}
	for e in table.entries:
		chances[e.item_id] = (max(e.weight, 0.0) / total_weight) * 100.0
	return chances

# ─────────────────────────────────────────────
# Snapshot-Sync — Pull-statt-Push, analog AchievementService (Round 103)
# ─────────────────────────────────────────────

## Client-seitiger Einstiegspunkt: eigenen Stand anfragen.
func request_snapshot(player_id: String) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.send_wiki_snapshot_request(player_id)
	else:
		on_snapshot_requested(player_id)

## Autoritätsseitig: baut den Snapshot für player_id und schickt ihn gezielt zurück.
func on_snapshot_requested(player_id: String) -> void:
	if not _require_authority("on_snapshot_requested"):
		return
	if player_id.is_empty():
		return
	if is_instance_valid(_network):
		_network.send_wiki_snapshot_for_player(player_id, get_all_discovered(player_id))

# ─────────────────────────────────────────────
# Client-Empfang — Gegenstück zu discover()/on_snapshot_requested() auf
# einem Nicht-Autoritäts-Peer. Übernimmt Server-Payloads direkt in
# _discovered statt über discover() zu laufen (das _require_authority()
# erzwingt) — hier wird nichts neu entschieden, nur ein bereits von der
# Autorität getroffenes Ergebnis gespiegelt.
# ─────────────────────────────────────────────

func _local_player_id() -> String:
	return _session_manager.get_local_player_id() if is_instance_valid(_session_manager) else ""

## Payload trägt keine player_id (Adressierung läuft bereits über rpc_id an
## den Ziel-Peer, siehe NetworkBridge.send_wiki_entry_discovered_for_player())
## — der Empfänger IST der betroffene Spieler.
func _on_remote_entry_discovered_received(payload: Dictionary) -> void:
	var player_id := _local_player_id()
	if player_id.is_empty():
		AppLogger.log_error("_on_remote_entry_discovered_received: lokale player_id unbekannt (SessionManager fehlt?).", LOG_CAT)
		return
	var category := String(payload.get("category", ""))
	var entry_id := String(payload.get("entry_id", ""))
	if category.is_empty() or entry_id.is_empty():
		return

	if not _discovered.has(player_id):
		_discovered[player_id] = {}
	var bucket: Dictionary = _discovered[player_id]
	if not bucket.has(category):
		bucket[category] = []
	var list: Array = bucket[category]
	if entry_id not in list:
		list.append(entry_id)

	wiki_entry_discovered.emit(player_id, category, entry_id)

func _on_remote_snapshot_received(payload: Dictionary) -> void:
	var player_id := _local_player_id()
	if player_id.is_empty():
		AppLogger.log_error("_on_remote_snapshot_received: lokale player_id unbekannt (SessionManager fehlt?).", LOG_CAT)
		return
	_discovered[player_id] = (payload as Dictionary).duplicate(true)
	wiki_synced.emit(player_id)

# ─────────────────────────────────────────────
# Save-Interface (analog AchievementService/StatsService)
# ─────────────────────────────────────────────

func get_save_key() -> String:
	return SAVE_KEY

func get_save_data() -> Dictionary:
	return {"discovered": _discovered}

func _restore_from_save(saved: Dictionary) -> void:
	if saved.get("discovered") is Dictionary:
		_discovered = saved["discovered"]

func _require_authority(caller: String) -> bool:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		AppLogger.log_error("%s: Aufruf auf Nicht-Autorität — verweigert." % caller, LOG_CAT)
		return false
	return true

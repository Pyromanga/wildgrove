extends Service
class_name QuestService
## implements ISaveProvider

## QuestService — Verwaltet den Fortschritt aller Quests.
##
## Abhängigkeiten (deps): ["data", "savesystem", "skill_system", "reward_dispatcher", "network_bridge"]
##
## ADR-029 Plan-Schritt 4 (Round 64): auf player_id: String migriert (analog zu
## InventorySystem, Round 63). State ist jetzt per player_id (String,
## player_uuid) verschachtelt statt per peer_id (int, ENet-Routing-Identität).
## player_id ist auf allen öffentlichen Methoden Pflichtparameter ohne Default —
## kein stiller Fallback auf einen falschen Bucket, siehe InventorySystem-
## Klassenkommentar für dieselbe Begründung.
##
## Zwei Klassen von Übersetzungsstellen bleiben, weil SkillSystem/
## EquipmentService/RewardDispatcher noch nicht migriert sind (eigene Runden):
##   - EINGEHEND: loot_collected/xp_gained/enemy_killed/domain_event_received
##     liefern weiterhin peer_id (int) — _resolve_player_uuid() übersetzt an
##     der Empfangsgrenze in _on_*().
##   - AUSGEHEND: RewardDispatcher.dispatch() erwartet weiterhin peer_id (int) —
##     _resolve_peer_id() übersetzt in on_quest_complete_confirmed() zurück.
## Beide Helfer nutzen NetworkBridge.get_player_id_for_peer()/
## get_peer_id_for_player(), dieselben kanonischen Getter wie
## RewardDispatcher._resolve_player_uuid() bzw. EquipmentService. Sobald
## SkillSystem/EquipmentService selbst migriert sind, entfallen die jeweiligen
## Übersetzungszeilen ersatzlos (siehe ADR-029 Round 63 "Vorab-Recherche").
##
## Delegiert Event→Objective-Auflösung → QuestObjectiveHandler (statische Helfer-Klasse)
##
## ARCHITEKTUR:
##   - Keine Referenz auf InventorySystem
##   - skill_system per DI für Level-Checks in SKILL-Objectives
##   - Reward-Auszahlung über RewardDispatcher
##   - Quest-Unlock via EventBus.quest.quest_unlock_requested

const LOG_CAT  := "Quest"
const SAVE_KEY := "quest_progress"

var _data_service:      DataService
var _save_system:       SaveSystem
var _skill_system:      SkillSystem
var _reward_dispatcher: RewardDispatcher
var _network:           NetworkBridge = null
var _bus:               IEventBus

var _definitions: Dictionary = {}   # { quest_id: QuestDefinition }

## Multi-Tenant State: { player_id (String): { "active": {}, "completed": [], "available": [] } }
var _players: Dictionary = {}

# ─────────────────────────────────────────────
# Intern: Player-Bucket
# ─────────────────────────────────────────────

func _ensure_player(player_id: String) -> Dictionary:
	if not _players.has(player_id):
		var completed_arr: Array[String] = []
		var available_arr: Array[String] = []
		_players[player_id] = {
			"active":    {},
			"completed": completed_arr,
			"available": available_arr,
			"history":   {},   # quest_id -> QuestProgressRecord, überlebt Abschluss (siehe get_objective_progress)
		}
	return _players[player_id]

## ADR-029 Round 64: die früheren parameterlosen `active_quests`/
## `completed_quests`/`available_quests`-Properties (fest auf player_id=1)
## sind echte Methoden geworden — eine `get =`-Property kann keinen
## player_id-Parameter entgegennehmen, und ein stiller Tier-1-Default wäre
## genau der "falscher Bucket bei vergessenem Aufrufer"-Fehler, den die
## gesamte Migration vermeiden soll. Aufrufer (QuestPanelController, Tests)
## übergeben jetzt explizit die player_id.
func get_active_quests(player_id: String)    -> Dictionary:    return (_ensure_player(player_id)["active"]    as Dictionary)
func get_completed_quests(player_id: String) -> Array[String]: return (_ensure_player(player_id)["completed"] as Array[String])
func get_available_quests(player_id: String) -> Array[String]: return (_ensure_player(player_id)["available"] as Array[String])

## Übersetzt die lokale peer_id in die stabile player_id über NetworkBridge/
## SessionManager — für Aktionen, die inhärent "der lokale Spieler" meinen
## (Auto-Start-Quests, quest_start_requested/quest_unlock_requested vom
## lokalen EventBus). Leerer String wenn kein NetworkBridge injiziert ODER
## SessionManager den lokalen Peer (noch) keinem Slot zugeordnet hat.
func _local_player_id() -> String:
	if is_instance_valid(_network):
		return _network.get_local_player_id()
	return ""

## Übersetzt eine peer_id in die stabile player_id über NetworkBridge (die
## selbst nur an SessionManager delegiert) — für eingehende Events aus noch
## nicht migrierten Quellen (loot_collected/xp_gained/enemy_killed/
## domain_event_received liefern weiterhin peer_id: int). Identisches Muster
## zu RewardDispatcher._resolve_player_uuid().
func _resolve_player_uuid(peer_id: int) -> String:
	if not is_instance_valid(_network):
		AppLogger.log_warn(
			"_resolve_player_uuid(%d): kein NetworkBridge injiziert — Übersetzung nicht möglich." % peer_id,
			LOG_CAT
		)
		return ""
	return _network.get_player_id_for_peer(peer_id)

## Rückwärts-Auflösung zu _resolve_player_uuid() — für ausgehende Aufrufe in
## noch nicht migrierte Services (RewardDispatcher.dispatch() erwartet
## weiterhin peer_id: int). -1 wenn kein NetworkBridge injiziert ODER
## player_id gerade keinem verbundenen Peer zugeordnet ist.
func _resolve_peer_id(player_id: String) -> int:
	if not is_instance_valid(_network):
		AppLogger.log_warn(
			"_resolve_peer_id('%s'): kein NetworkBridge injiziert — Übersetzung nicht möglich." % player_id,
			LOG_CAT
		)
		return -1
	return _network.get_peer_id_for_player(player_id)

# ─────────────────────────────────────────────
# Phase 4: Configure
# ─────────────────────────────────────────────

func configure(deps: ServiceDeps) -> void:
	var t := AppLogger.log_begin("QuestService.configure()", LOG_CAT)

	_data_service      = deps.get_optional(ServiceKeys.DATA)              as DataService
	_save_system       = deps.require(ServiceKeys.SAVE_SYSTEM)            as SaveSystem
	_skill_system      = deps.get_optional(ServiceKeys.SKILL_SYSTEM)      as SkillSystem
	_reward_dispatcher = deps.get_optional(ServiceKeys.REWARD_DISPATCHER) as RewardDispatcher
	_network           = deps.get_optional(ServiceKeys.NETWORK_BRIDGE)    as NetworkBridge
	_bus               = deps.require(ServiceKeys.EVENT_BUS)              as IEventBus

	if is_instance_valid(_data_service):
		_definitions = _data_service.get_all_quests()
		AppLogger.log_debug("Quest-Definitionen geladen: %d" % _definitions.size(), LOG_CAT)
	else:
		AppLogger.log_warn("DataService fehlt — Quest-Definitionen nicht geladen.", LOG_CAT)

	# ADR-029 Round 64: kein initiales _ensure_player(1) mehr hier. player_id
	# ist jetzt Pflichtparameter ohne Default, und zum Zeitpunkt von
	# configure() (Phase C5) ist die lokale player_id (über NetworkBridge/
	# SessionManager, erst ab Phase C9 auflösbar) noch nicht verfügbar —
	# derselbe Grund wie bei InventorySystem.configure() (Round 63). Buckets
	# entstehen jetzt ausschließlich lazy über _ensure_player() bei der
	# ersten tatsächlichen Aktion.

	if is_instance_valid(_save_system):
		_save_system.register_save_provider(self)
		var saved: Dictionary = _save_system.get_state_for(SAVE_KEY)
		if not saved.is_empty():
			_restore_from_save(saved)
	else:
		AppLogger.log_warn("SaveSystem fehlt — Quest-Fortschritt nicht gespeichert.", LOG_CAT)

	AppLogger.log_end("QuestService.configure()", t, LOG_CAT)
	AppLogger.log_info(
		"Konfiguriert. Definitionen: %d." % _definitions.size(),
		LOG_CAT
	)

# ─────────────────────────────────────────────
# Phase 5: Activate
# ─────────────────────────────────────────────

## Phase S8.6 Late-Inject — NetworkBridge wird nach vollem Session-Boot injiziert.
## ADR-021 (R-5): ab hier ist auch domain_event_received() verfügbar — das ist
## der früheste Zeitpunkt, an dem der Connect passieren kann (vorher ist
## _network null). interaction_finished/npc_talked_to/custom_objective_triggered
## werden NICHT mehr direkt auf dem lokalen EventBus abonniert (siehe on_ready()) —
## nur noch über diesen Kanal, der auf der Autorität mit echtem player_id feuert.
func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network
	if is_instance_valid(_network) and not _network.domain_event_received.is_connected(_on_domain_event_received):
		_network.domain_event_received.connect(_on_domain_event_received)

## ADR-029 Round 64 — Phase C9.5 Hook (BootPipeline, duck-typed wie
## inject_network_bridge() bei Phase C8): aufgerufen NACHDEM
## SessionManager.register_player_slot() (Phase C9) gelaufen ist.
##
## Warum ein eigener Hook nötig ist, statt die Auto-Start-Quests einfach in
## on_ready() oder inject_network_bridge() zu belassen: _local_player_id()
## bleibt an BEIDEN Stellen leer. on_ready() läuft in Phase C6, lange vor
## jeder Identitäts-Auflösung. inject_network_bridge() läuft in Phase C8 —
## einen Schritt VOR Phase C9, die den Slot überhaupt erst einträgt, den
## get_local_player_id() braucht (siehe BootPipeline.boot_character(),
## Phasenreihenfolge C8 → C9). Ein Aufruf an einer der beiden alten Stellen
## hätte _local_player_id() also strukturell IMMER leer gesehen — Auto-Start-
## Quests wären beim Boot nie gestartet. Gefunden vor dem Testen beim Abgleich
## gegen BootPipeline.gd (derselbe Vorab-Recherche-Schritt wie bei den beiden
## in Round 63 gefundenen Kopplungsstellen).
func on_local_identity_ready() -> void:
	_start_auto_start_quests()

func _start_auto_start_quests() -> void:
	if not is_instance_valid(_data_service):
		return
	var local_id := _local_player_id()
	if local_id.is_empty():
		AppLogger.log_warn(
			"_start_auto_start_quests(): keine lokale player_id verfügbar — übersprungen.", LOG_CAT
		)
		return
	for quest_id in _data_service.get_auto_start_quests():
		if not is_quest_completed(quest_id, local_id) and not is_quest_active(quest_id, local_id):
			request_start_quest(quest_id, local_id)

func on_ready() -> void:
	_bus.world().loot_collected.connect(_on_loot_collected)
	_bus.player().xp_gained.connect(_on_xp_gained)
	_bus.world().enemy_killed.connect(_on_enemy_killed)
	# ADR-021 (R-5): interaction_finished/npc_talked_to/custom_objective_triggered
	# werden NICHT mehr hier direkt abonniert — die Emissionsstellen laufen ohne
	# Autoritäts-Guard auf JEDEM Peer lokal (siehe ADR-021 "Befund"), ein direkter
	# Connect würde für einen Nicht-Host-Spieler nie die Autorität erreichen.
	# Stattdessen: inject_network_bridge() verbindet _on_domain_event_received()
	# mit NetworkBridge.domain_event_received, das nur auf der Autorität feuert.
	_bus.quest().quest_unlock_requested.connect(_on_quest_unlock_requested)
	_bus.quest().quest_start_requested.connect(_on_quest_start_requested)

	# ADR-029 Round 64: Auto-Start-Quests NICHT mehr hier — siehe
	# on_local_identity_ready() für den Grund (Phasenreihenfolge, _local_player_id()
	# wäre an dieser Stelle strukturell immer leer).

	AppLogger.log_info("QuestService aktiv.", LOG_CAT)

## quest_start_requested/quest_unlock_requested (EventBus.quest()) tragen
## bewusst KEINE player_id (siehe QuestEvents.gd) — sie sind reine "der lokale
## Prozess will X"-Signale (z.B. DialogueTreeController._apply_choice()).
## Diese Wrapper lösen "der lokale Spieler" erst beim tatsächlichen Feuern auf
## statt beim Connect (zum Connect-Zeitpunkt, Phase C6, ist _network ohnehin
## noch null — siehe on_local_identity_ready()-Kommentar).
##
## Bekannte, nicht in dieser Runde behobene Einschränkung: RewardDispatcher.
## dispatch() emittiert quest_unlock_requested ebenfalls (für Folge-Quest-
## Unlocks) — dort ist "player_id" eigentlich der Spieler, dessen Quest gerade
## den Reward ausgelöst hat, nicht zwingend "der lokale Prozess". Bereits vor
## dieser Migration verhielt sich unlock_quest() hier identisch (fester
## Tier-1-Default statt echter Ziel-player_id) — kein Verhaltens-Downgrade
## durch diese Runde, aber weiterhin ein offener Punkt für eine künftige Runde,
## sobald quest_unlock_requested selbst eine player_id trägt.
func _on_quest_start_requested(quest_id: String) -> void:
	var player_id := _local_player_id()
	if player_id.is_empty():
		AppLogger.log_error(
			"quest_start_requested('%s'): keine lokale player_id verfügbar — verworfen." % quest_id, LOG_CAT
		)
		return
	request_start_quest(quest_id, player_id)

func _on_quest_unlock_requested(quest_id: String) -> void:
	var player_id := _local_player_id()
	if player_id.is_empty():
		AppLogger.log_error(
			"quest_unlock_requested('%s'): keine lokale player_id verfügbar — verworfen." % quest_id, LOG_CAT
		)
		return
	unlock_quest(quest_id, player_id)

func on_cleanup() -> void:
	if _bus.world().loot_collected.is_connected(_on_loot_collected):
		_bus.world().loot_collected.disconnect(_on_loot_collected)
	if _bus.player().xp_gained.is_connected(_on_xp_gained):
		_bus.player().xp_gained.disconnect(_on_xp_gained)
	if _bus.world().enemy_killed.is_connected(_on_enemy_killed):
		_bus.world().enemy_killed.disconnect(_on_enemy_killed)
	if _bus.quest().quest_unlock_requested.is_connected(_on_quest_unlock_requested):
		_bus.quest().quest_unlock_requested.disconnect(_on_quest_unlock_requested)
	if _bus.quest().quest_start_requested.is_connected(_on_quest_start_requested):
		_bus.quest().quest_start_requested.disconnect(_on_quest_start_requested)
	if is_instance_valid(_network) and _network.domain_event_received.is_connected(_on_domain_event_received):
		_network.domain_event_received.disconnect(_on_domain_event_received)
	AppLogger.log_info("QuestService cleanup.", LOG_CAT)

# ─────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────

func get_save_key() -> String: return SAVE_KEY

func get_save_data() -> Dictionary:
	# Format: { "p1": { active: {...}, completed: [...], available: [...] }, "p2": {...} }
	var out: Dictionary = {}
	for pid in _players:
		var bucket: Dictionary = _players[pid]
		var active_src: Dictionary = bucket["active"]
		var active_out: Dictionary = {}
		for quest_id in active_src.keys():
			var rec: QuestProgressRecord = active_src[quest_id]
			active_out[quest_id] = rec.to_save_dict()
		out[pid] = {
			"active":    active_out,
			"completed": (bucket["completed"] as Array).duplicate(),
			"available": (bucket["available"] as Array).duplicate(),
		}
	return out

# ─────────────────────────────────────────────
# Öffentliche API — request_/on_*_confirmed Pattern (ADR-004)
# ─────────────────────────────────────────────

## Client-seitige Anfrage: Quest starten. player_id: Pflichtparameter (ADR-029
## Round 64) — kein Default mehr, siehe Klassenkommentar.
func request_start_quest(quest_id: String, player_id: String) -> bool:
	if quest_id.is_empty():
		AppLogger.log_error("request_start_quest(): quest_id ist leer!", LOG_CAT)
		return false
	var bucket := _ensure_player(player_id)
	var c_quests: Array[String] = bucket["completed"] as Array[String]
	var a_quests: Dictionary = bucket["active"]
	if c_quests.has(quest_id):
		_bus.quest().emit_quest_start_failed(quest_id, "already_completed")
		return false
	if a_quests.has(quest_id):
		_bus.quest().emit_quest_start_failed(quest_id, "already_active")
		return false

	var def: QuestDefinition = _definitions.get(quest_id)
	if def:
		for prereq in def.prerequisites:
			if not c_quests.has(prereq):
				_bus.quest().emit_quest_start_failed(quest_id, "prereq_missing:%s" % prereq)
				return false

	# Tier 1: direkter Aufruf. Tier 2/3: via NetworkBridge an die Autorität senden.
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.rpc_id(1, "_rpc_start_quest", quest_id)
	else:
		on_quest_start_confirmed(quest_id, player_id)
	return true

## Authority-Mutation: schreibt Quest-State für player_id. Public (ADR-004) — direkt via RPC aufrufbar.
## C-02: Authority Guard — verweigert auf Nicht-Autorität wenn Peer gesetzt.
func on_quest_start_confirmed(quest_id: String, player_id: String) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		AppLogger.log_error(
			"on_quest_start_confirmed: Aufruf auf Nicht-Autorität — verweigert.", LOG_CAT
		)
		return
	if quest_id.is_empty():
		AppLogger.log_error("on_quest_start_confirmed: quest_id ist leer!", LOG_CAT)
		return

	var bucket := _ensure_player(player_id)
	var def: QuestDefinition = _definitions.get(quest_id)
	var rec: QuestProgressRecord
	if def:
		rec = QuestProgressRecord.create_new(def)
		# BUGFIX (Bug #5, Teil 2): SKILL-Objectives starten sonst immer bei 0,
		# selbst wenn der Skill vom Spieler schon vor Annahme der Quest auf
		# das Ziel-Level (oder darüber) war — QuestProgressRecord.create_new()
		# initialisiert pauschal mit 0, und ein weiteres update_objective()
		# kommt erst beim NÄCHSTEN xp_gained-Event (siehe QuestObjectiveHandler.
		# resolve_xp()). Bis dahin zeigt die UI fälschlich 0/required statt des
		# bereits vorhandenen Fortschritts. Direkt bei Queststart einmalig mit
		# dem aktuellen Skill-Level synchronisieren, geclamped auf required.
		if is_instance_valid(_skill_system):
			for obj in def.objectives:
				if obj.type == QuestObjective.Type.SKILL:
					var cur_level: int = _skill_system.get_level(obj.target_id, player_id)
					if cur_level > 0:
						rec.objectives[obj.id] = clamp(cur_level, 0, obj.required)
	else:
		# BUGFIX ("Friedhof-Quest hängt für immer bei 0/5" — siehe DataManifest.QUESTS-
		# Kommentar zu quest_talia_graveyard_watch): eine Quest ganz ohne Definition zu
		# starten war bisher VÖLLIG STILL — kein Log, keine Fehlermeldung, einfach ein
		# leerer Record ohne Objectives, der nie als abgeschlossen erkannt werden kann
		# (is_complete() braucht `def`, update_objective()/QuestObjectiveHandler.resolve_*()
		# brechen alle sofort ab, sobald _definitions.get(quest_id) null liefert). Dieser
		# Fall bedeutet praktisch immer: die .tres existiert, fehlt aber in
		# DataManifest.QUESTS (dieselbe Fehlerklasse wie die vier bereits einmal
		# gefundenen fehlenden Einträge dort) — jetzt laut und sofort sichtbar, statt
		# erst wenn ein Spieler sich wundert, warum der Fortschritt nie steigt.
		AppLogger.log_error(
			"on_quest_start_confirmed('%s'): keine QuestDefinition gefunden — Quest startet ohne Objectives und kann NIE abgeschlossen werden. Fehlt die .tres in DataManifest.QUESTS?" % quest_id,
			LOG_CAT
		)
		rec = QuestProgressRecord.new()
		rec.quest_id = quest_id
	bucket["active"][quest_id] = rec
	(bucket["history"] as Dictionary)[quest_id] = rec
	(bucket["available"] as Array).erase(quest_id)
	_bus.quest().emit_quest_started(quest_id)
	_bus.quest().emit_quest_started_for_player(player_id, quest_id)
	AppLogger.log_info("Quest gestartet: '%s' (Spieler '%s')." % [quest_id, player_id], LOG_CAT)

func request_complete_quest(quest_id: String, player_id: String) -> void:
	var bucket := _ensure_player(player_id)
	if not (bucket["active"] as Dictionary).has(quest_id):
		return
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.rpc_id(1, "_rpc_complete_quest", quest_id)
	else:
		on_quest_complete_confirmed(quest_id, player_id)

## Authority-Mutation: schreibt Quest-Complete-State für player_id. Public (ADR-004) — direkt via RPC aufrufbar.
## C-02: Authority Guard — verweigert auf Nicht-Autorität wenn Peer gesetzt.
func on_quest_complete_confirmed(quest_id: String, player_id: String) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		AppLogger.log_error(
			"on_quest_complete_confirmed: Aufruf auf Nicht-Autorität — verweigert.", LOG_CAT
		)
		return
	if quest_id.is_empty():
		AppLogger.log_error("on_quest_complete_confirmed: quest_id ist leer!", LOG_CAT)
		return

	var bucket := _ensure_player(player_id)
	var active: Dictionary = bucket["active"]
	if not active.has(quest_id):
		return

	var def: QuestDefinition = _definitions.get(quest_id)

	# SEC-03: Autorität vertraut nicht dem Completion-Claim des Aufrufers — sie
	# verifiziert gegen den serverseitig getrackten Objective-Fortschritt (record.
	# is_complete()). Vorher konnte jeder Aufrufer (inkl. ein modifizierter Client
	# per RPC) jede aktive Quest sofort abschließen und den vollen Reward kassieren,
	# unabhängig vom tatsächlichen Fortschritt — request_complete_quest()/die RPC
	# nahmen die Vollständigkeit ungeprüft an.
	# Ist die Definition unbekannt (z.B. Legacy-/Test-Quest ohne registrierte
	# QuestDefinition), bleibt das Verhalten wie zuvor: kein Reward möglich (siehe
	# unten, reward leitet sich aus def.reward ab), also auch kein Exploit-Vektor —
	# in dem Fall wird nicht blockiert, um bestehende Aufrufer nicht zu brechen.
	var record: QuestProgressRecord = active[quest_id]
	if def != null and not record.is_complete(def):
		AppLogger.log_warn(
			"on_quest_complete_confirmed: Quest '%s' (Spieler '%s') — Objectives nicht erfüllt. Abschluss abgelehnt." % [quest_id, player_id],
			LOG_CAT
		)
		return

	active.erase(quest_id)
	(bucket["completed"] as Array).append(quest_id)

	var reward: QuestReward = def.reward if (def and def.reward) else null

	if reward and is_instance_valid(_reward_dispatcher):
		# ADR-029 Round 64: RewardDispatcher.dispatch() erwartet weiterhin
		# peer_id (int) — SkillSystem/EquipmentService/StatModifierService
		# sind noch nicht migriert. Übersetzung an genau dieser einen Grenze,
		# analog zu RewardDispatchers eigener _resolve_player_uuid()-Zeile für
		# den InventorySystem-Call (Round 63).
		var peer_id := _resolve_peer_id(player_id)
		if peer_id == -1:
			AppLogger.log_error(
				"Reward für '%s' (Spieler '%s'): konnte peer_id nicht auflösen — Reward übersprungen." % [quest_id, player_id],
				LOG_CAT
			)
		else:
			_reward_dispatcher.dispatch(reward, quest_id, peer_id)
	elif reward:
		AppLogger.log_warn("RewardDispatcher fehlt — Reward für '%s' nicht ausgezahlt!" % quest_id, LOG_CAT)

	_bus.quest().emit_quest_completed(quest_id, reward)
	AppLogger.log_info("Quest abgeschlossen: '%s' (Spieler '%s')." % [quest_id, player_id], LOG_CAT)
	_unlock_followup_quests(quest_id, player_id)

func fail_quest(quest_id: String, player_id: String) -> void:
	var bucket := _ensure_player(player_id)
	if not (bucket["active"] as Dictionary).has(quest_id):
		return
	(bucket["active"] as Dictionary).erase(quest_id)
	_bus.quest().emit_quest_failed(quest_id)

func unlock_quest(quest_id: String, player_id: String) -> void:
	var bucket := _ensure_player(player_id)
	var completed: Array[String] = bucket["completed"] as Array[String]
	var active: Dictionary = bucket["active"]
	var available: Array[String]   = bucket["available"] as Array[String]
	if completed.has(quest_id) or active.has(quest_id):
		return
	if not available.has(quest_id):
		available.append(quest_id)
		_bus.quest().emit_quest_unlocked(quest_id)
		AppLogger.log_info("Quest freigeschaltet: '%s' (Spieler '%s')." % [quest_id, player_id], LOG_CAT)

## ADR-021 (R-5): player_id ist Pflichtparameter, kein Default mehr. Der Default
## war die Root Cause des Bugs (jeder Aufrufer ohne player_id landete unbemerkt
## in Spieler 1's Bucket) — kein Kompatibilitäts-Fallback, jeder Call-Ort muss
## den echten Wert übergeben.
func update_objective(quest_id: String, objective_id: String, delta: int, player_id: String) -> void:
	var bucket := _ensure_player(player_id)
	var active: Dictionary = bucket["active"]
	if not active.has(quest_id):
		return

	var record: QuestProgressRecord = active[quest_id]
	var def: QuestDefinition        = _definitions.get(quest_id)
	if def == null:
		return

	var required := 1
	for obj in def.objectives:
		if obj.id == objective_id:
			required = obj.required
			break

	var new_val := record.update_progress(objective_id, delta, required)

	AppLogger.log_debug(
		"Objective '%s/%s': %d (+%d) / %d (Spieler '%s')." % [quest_id, objective_id, new_val, delta, required, player_id],
		LOG_CAT
	)
	_bus.quest().emit_quest_objective_updated(quest_id, objective_id, new_val, required)

	var record2: QuestProgressRecord = active.get(quest_id)
	var def2: QuestDefinition = _definitions.get(quest_id)
	if record2 != null and def2 != null and record2.is_complete(def2):
		request_complete_quest(quest_id, player_id)

func is_quest_active(quest_id: String, player_id: String)    -> bool:
	return (_players.get(player_id, {"active": {}}) as Dictionary).get("active", {}).has(quest_id)

func is_quest_completed(quest_id: String, player_id: String) -> bool:
	return ((_players.get(player_id, {"completed": []}) as Dictionary).get("completed", []) as Array).has(quest_id)

func get_quest_definition(quest_id: String) -> QuestDefinition:
	return _definitions.get(quest_id)

func get_objective_progress(quest_id: String, objective_id: String, player_id: String) -> int:
	var rec := get_quest_record(quest_id, player_id)
	if rec == null:
		return 0
	return rec.objectives.get(objective_id, 0)

## BUGFIX ("Questschritte werden alle sofort angezeigt obwohl der Schritt
## nicht erreicht ist"): QuestPanelController._build_obj_data() braucht das
## QuestProgressRecord-Objekt selbst (nicht nur den Fortschritt EINES
## Objectives wie get_objective_progress()), um über
## QuestObjectiveHandler.is_objective_unlocked() zu entscheiden, welche
## zukünftigen Schritte noch verborgen bleiben müssen. Extrahiert aus
## get_objective_progress()'s Lookup-Logik, damit beide dieselbe
## active-dann-history-Quelle verwenden.
func get_quest_record(quest_id: String, player_id: String) -> QuestProgressRecord:
	var bucket: Dictionary = _players.get(player_id, {})
	var active: Dictionary = bucket.get("active", {})
	if active.has(quest_id):
		return active[quest_id]
	var history: Dictionary = bucket.get("history", {})
	if history.has(quest_id):
		return history[quest_id]
	return null

# ─────────────────────────────────────────────
# Event-Handler → delegiert an QuestObjectiveHandler
# ─────────────────────────────────────────────

## ADR-029 Round 64: loot_collected liefert weiterhin peer_id (int) — WorldService
## ist noch nicht migriert. Übersetzung an der Empfangsgrenze über
## _resolve_player_uuid(), dann konsistent String für den eigenen Bucket.
func _on_loot_collected(item_id: String, quantity: int, peer_id: int) -> void:
	var player_id := _resolve_player_uuid(peer_id)
	if player_id.is_empty():
		return
	var bucket := _ensure_player(player_id)
	for upd in QuestObjectiveHandler.resolve_loot(item_id, quantity, bucket["active"], _definitions):
		update_objective(upd["quest_id"], upd["obj_id"], upd["delta"], player_id)

## xp_gained liefert weiterhin peer_id (int) an der Signal-Grenze — Round 67:
## Korrektur. Der vorherige Kommentar hier behauptete, SkillSystem.get_level()
## sei "noch nicht migriert" und bräuchte deshalb den rohen peer_id — das war
## seit Round 65 nicht mehr wahr (SkillSystem läuft auf player_id: String) und
## wurde beim Schreiben dieser Zeile schlicht nicht nachgezogen. Bug-Fund
## während der peer_id/player_id-Namensbereinigung (siehe
## TODO-offene-probleme.md): resolve_xp() bekommt jetzt die bereits übersetzte
## String-player_id, nicht mehr die rohe int-peer_id.
func _on_xp_gained(skill_name: String, _amount: int, peer_id: int) -> void:
	var player_id := _resolve_player_uuid(peer_id)
	if player_id.is_empty():
		return
	var bucket := _ensure_player(player_id)
	for upd in QuestObjectiveHandler.resolve_xp(skill_name, bucket["active"], _definitions, _skill_system, player_id):
		update_objective(upd["quest_id"], upd["obj_id"], upd["delta"], player_id)

func _on_enemy_killed(enemy_type_id: String, _position: Vector3, peer_id: int) -> void:
	var player_id := _resolve_player_uuid(peer_id)
	if player_id.is_empty():
		return
	var bucket := _ensure_player(player_id)
	for upd in QuestObjectiveHandler.resolve_kill(enemy_type_id, bucket["active"], _definitions):
		update_objective(upd["quest_id"], upd["obj_id"], upd["delta"], player_id)

## ADR-021 (R-5), Option C: einziger Einstiegspunkt für interaction_finished/
## npc_talked_to/custom_objective_triggered — kommt über NetworkBridge.
## domain_event_received, feuert also nur auf der Autorität, mit peer_id
## bereits fälschungssicher aus dem RPC-Sender ermittelt (oder, Tier 1, direkt
## vom lokalen Aufrufer). NetworkBridge.domain_event_received liefert weiterhin
## peer_id (int) — Übersetzung an der Empfangsgrenze wie bei den drei
## EventBus-Handlern oben. Dispatcht anhand event_name an dieselbe
## QuestObjectiveHandler-Logik wie die drei anderen Event-Typen oben.
func _on_domain_event_received(event_name: String, payload: Dictionary, peer_id: int) -> void:
	var player_id := _resolve_player_uuid(peer_id)
	if player_id.is_empty():
		return
	var bucket := _ensure_player(player_id)
	match event_name:
		"interaction_finished":
			var action_id: String = payload.get("action_id", "")
			for upd in QuestObjectiveHandler.resolve_interaction(action_id, bucket["active"], _definitions):
				update_objective(upd["quest_id"], upd["obj_id"], upd["delta"], player_id)
		"npc_talked_to":
			var npc_id: String = payload.get("npc_id", "")
			for upd in QuestObjectiveHandler.resolve_talk(npc_id, bucket["active"], _definitions):
				update_objective(upd["quest_id"], upd["obj_id"], upd["delta"], player_id)
		"custom_objective_triggered":
			var signal_key: String = payload.get("signal_key", "")
			for upd in QuestObjectiveHandler.resolve_custom(signal_key, bucket["active"], _definitions):
				update_objective(upd["quest_id"], upd["obj_id"], upd["delta"], player_id)
		_:
			AppLogger.log_warn(
				"_on_domain_event_received: unbekannter event_name '%s' (Spieler '%s') — ignoriert."
				% [event_name, player_id],
				LOG_CAT
			)

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _unlock_followup_quests(completed_id: String, player_id: String) -> void:
	var bucket := _ensure_player(player_id)
	var completed: Array[String]    = bucket["completed"] as Array[String]
	var active: Dictionary  = bucket["active"]
	for quest_id in _definitions:
		var def: QuestDefinition = _definitions[quest_id]
		if completed.has(quest_id) or active.has(quest_id):
			continue
		if not def.prerequisites.has(completed_id):
			continue
		var all_met := true
		for prereq in def.prerequisites:
			if not completed.has(prereq):
				all_met = false
				break
		if all_met:
			unlock_quest(quest_id, player_id)
			if def.auto_start:
				request_start_quest(quest_id, player_id)

func _restore_from_save(saved_data: Dictionary) -> void:
	# Format: { "p1": { active: {...}, completed: [...], available: [...] }, ... }
	# ADR-029 Round 64: pid_str ist bereits die player_id — keine int()-
	# Konvertierung mehr, keine Übergangslogik für alte peer_id-Saves (siehe
	# InventorySystem._restore_from_save(), Round 63, "Save-Migration entfällt").
	for pid_str in saved_data:
		var pid: String = str(pid_str)
		var raw: Dictionary = saved_data[pid_str] as Dictionary if saved_data[pid_str] is Dictionary else {}
		var bucket := _ensure_player(pid)

		var saved_active: Variant = raw.get("active", {})
		if saved_active is Dictionary:
			for quest_id in (saved_active as Dictionary).keys():
				var def: QuestDefinition = _definitions.get(quest_id)
				if def == null:
					AppLogger.log_warn("Quest '%s' nicht in Definitionen — Save-Eintrag verworfen." % quest_id, LOG_CAT)
					continue
				var raw_entry: Variant = (saved_active as Dictionary)[quest_id]
				var entry_dict := raw_entry as Dictionary if raw_entry is Dictionary else {}
				var restored_rec := QuestProgressRecord.from_save(quest_id, entry_dict, def)
				bucket["active"][quest_id] = restored_rec
				(bucket["history"] as Dictionary)[quest_id] = restored_rec

		var saved_completed: Variant = raw.get("completed", [])
		var completed_arr: Array[String] = []
		if saved_completed is Array:
			for v in (saved_completed as Array):
				completed_arr.append(str(v))
		bucket["completed"] = completed_arr

		var saved_available: Variant = raw.get("available", [])
		var available_arr: Array[String] = []
		if saved_available is Array:
			for v in (saved_available as Array):
				available_arr.append(str(v))
		bucket["available"] = available_arr

	AppLogger.log_info(
		"Quest-State geladen: %d Spieler-Buckets." % _players.size(),
		LOG_CAT
	)

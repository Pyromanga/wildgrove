extends Service
class_name SkillSystem
## implements ISaveProvider

## SkillSystem — Berechnet XP-Fortschritt und Level-Ups.
## Abhängigkeiten (deps): ["data", "savesystem", "network_bridge"]
##
## ADR-029 Plan-Schritt 4 (Round 65): auf player_id: String migriert (dritter
## Vertikalschnitt nach InventorySystem Round 63, QuestService Round 64).
## player_id ist auf allen öffentlichen Methoden Pflichtparameter ohne Default
## — kein stiller Fallback auf einen falschen Bucket, siehe InventorySystem-
## Klassenkommentar für dieselbe Begründung. Kein Parameter-Reordering nötig,
## `player_id` stand überall bereits als letzter Parameter.
##
## Zwei Übersetzungsstellen bleiben, weil PlayerEvents (xp_gained/level_up)
## noch nicht migriert sind (eigene Runde, betrifft mehrere Systeme):
##   - EINGEHEND: xp_gained liefert weiterhin peer_id (int) —
##     _resolve_player_uuid() übersetzt in _on_xp_gained().
##   - AUSGEHEND: level_up wird weiterhin mit peer_id (int) emittiert —
##     _resolve_peer_id() übersetzt in _check_level_up().
##
## Zusätzlich zwei EXTERNE Aufrufer, die selbst noch nicht migriert sind und
## deshalb ihrerseits übersetzen müssen (nicht in dieser Datei, siehe dort):
##   - RewardDispatcher.dispatch() (skill_name/amount/player_id an
##     request_add_xp()) — nutzt seine bereits aus Round 63 vorhandene
##     _resolve_player_uuid()-Zeile ein zweites Mal.
##   - CombatSystem.player_melee_damage() (get_level() für den Waffen-/
##     Skill-Bonus) — bekommt dafür NEU inject_network_bridge() + eigenen
##     _resolve_player_uuid()-Helfer (Round 65, siehe dortiger Kommentar).
##     Gefunden vor dem Coden: CombatSystem hatte bisher gar keine
##     NetworkBridge-Referenz — ohne diesen Fund hätte
##     player_melee_damage()/apply_weapon_on_hit() nach dieser Migration
##     schlicht nicht mehr kompiliert (int an einen String-Parameter).

const LOG_CAT := "SkillSystem"
const SAVE_KEY := "skills"

## R-7 (ADR-022): fehlte bisher komplett — `SkillPanelController` hing stattdessen
## an `EventBus.player().xp_gained`/`level_up`, die NUR auf dem Prozess feuern,
## der `_check_level_up()` tatsächlich ausführt (die Autorität, siehe C-02-Guard
## in `on_xp_add_confirmed()`). Für jeden Nicht-Host-Spieler feuerten diese
## Events lokal nie — das Skill-Panel konnte Fortschritt nie sehen, unabhängig
## vom Rücksync-Problem selbst. Dieses Signal feuert zusätzlich, lokal auf JEDEM
## Prozess, bei jeder XP/Level-Änderung für player_id — inklusive nach Anwendung
## eines Rücksyncs (`_on_economy_state_received()`), damit das UI in beiden
## Fällen (eigene Mutation als Autorität, empfangener Rücksync als Client)
## denselben einen Reaktionspfad hat.
signal skill_changed(skill_id: String, player_id: String)

var _data_service: DataService
var _save_system:  SaveSystem
var _network:      NetworkBridge = null
var _bus:          IEventBus
var _stat_modifiers: StatModifierService = null   ## optional: Ausrüstungs-Bonus auf Aktions-XP (add_action_xp)
var _definitions:  Dictionary = {}   # { skill_id: SkillDefinition }

## Multi-Tenant State: { player_id (String): { skill_id: { "xp": int, "level": int } } }
var _players: Dictionary = {}

# ─────────────────────────────────────────────
# Intern: Bucket per Player
# ─────────────────────────────────────────────

func _ensure_player(player_id: String) -> Dictionary:
	if not _players.has(player_id):
		_players[player_id] = {}
		_init_player_skills(player_id)
	return _players[player_id]

func _init_player_skills(player_id: String) -> void:
	# _definitions ist ab _init_definitions() garantiert nicht leer (sonst hat
	# assert() dort bereits geblockt) — kein hardcodierter Skill-Fallback mehr.
	for skill_id in _definitions:
		_players[player_id][skill_id] = {"xp": 0, "level": 1}

## Übersetzt eine peer_id in die stabile player_id über NetworkBridge (die
## selbst nur an SessionManager delegiert) — für eingehende Events aus noch
## nicht migrierten Quellen (xp_gained liefert weiterhin peer_id: int).
## Identisches Muster zu QuestService._resolve_player_uuid().
func _resolve_player_uuid(peer_id: int) -> String:
	if not is_instance_valid(_network):
		AppLogger.log_warn(
			"_resolve_player_uuid(%d): kein NetworkBridge injiziert — Übersetzung nicht möglich." % peer_id,
			LOG_CAT
		)
		return ""
	return _network.get_player_id_for_peer(peer_id)

## Rückwärts-Auflösung — für ausgehende Aufrufe in noch nicht migrierte Stellen
## (level_up wird weiterhin mit peer_id: int emittiert). -1 wenn kein
## NetworkBridge injiziert ODER player_id gerade keinem verbundenen Peer
## zugeordnet ist.
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
	_data_service = deps.require(ServiceKeys.DATA)                as DataService
	_save_system  = deps.require(ServiceKeys.SAVE_SYSTEM)         as SaveSystem
	_network      = deps.get_optional(ServiceKeys.NETWORK_BRIDGE) as NetworkBridge
	_bus          = deps.require(ServiceKeys.EVENT_BUS)           as IEventBus
	_stat_modifiers = deps.get_optional(ServiceKeys.STAT_MODIFIERS) as StatModifierService

	_init_definitions()

	# ADR-029 Round 65: kein initiales _ensure_player(1) mehr hier — player_id
	# ist jetzt Pflichtparameter ohne Default, und zum Zeitpunkt von
	# configure() (Phase C5) ist die lokale player_id (über NetworkBridge/
	# SessionManager, erst ab Phase C9 auflösbar) noch nicht verfügbar —
	# derselbe Grund wie InventorySystem/QuestService (Round 63/64). Buckets
	# entstehen jetzt ausschließlich lazy über _ensure_player().

	## R-7 (ADR-022): siehe identischer Kommentar in InventorySystem.configure().
	_connect_economy_sync()

	if _save_system:
		_save_system.register_save_provider(self)
		var saved: Dictionary = _save_system.get_state_for(SAVE_KEY)
		if not saved.is_empty():
			_restore_from_save(saved)

	AppLogger.log_info(
		"Initialisiert. %d Skill-Definitionen." % _definitions.size(), LOG_CAT
	)

# ─────────────────────────────────────────────
# Phase 5: Activate
# ─────────────────────────────────────────────

## Phase S8.6 Late-Inject — NetworkBridge wird nach vollem Session-Boot injiziert.
## R-7 (ADR-022): siehe identischer Kommentar in InventorySystem.inject_network_bridge()
## — Phase C6 (on_ready) läuft vor Phase C8 (dieser Late-Inject), `_network`
## ist zum Zeitpunkt von on_ready() garantiert noch null.
func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network
	_connect_economy_sync()

## R-7 (ADR-022): gemeinsamer, idempotenter Connect-Helfer für configure() und
## inject_network_bridge().
func _connect_economy_sync() -> void:
	if is_instance_valid(_network) and not _network.economy_state_received.is_connected(_on_economy_state_received):
		_network.economy_state_received.connect(_on_economy_state_received)



func on_ready() -> void:
	_bus.player().xp_gained.connect(_on_xp_gained)
	AppLogger.log_info("SkillSystem mit EventBus verbunden.", LOG_CAT)

func on_cleanup() -> void:
	if _bus.player().xp_gained.is_connected(_on_xp_gained):
		_bus.player().xp_gained.disconnect(_on_xp_gained)
	if is_instance_valid(_network) and _network.economy_state_received.is_connected(_on_economy_state_received):
		_network.economy_state_received.disconnect(_on_economy_state_received)
	AppLogger.log_info("SkillSystem cleanup.", LOG_CAT)

## ADR-029 Round 65: xp_gained liefert weiterhin peer_id (int) — PlayerEvents
## ist noch nicht migriert. Übersetzung an der Empfangsgrenze, dann Aufruf von
## request_add_xp() mit der stabilen player_id (String). Vorher war
## request_add_xp() selbst direkt mit xp_gained verbunden — ging nicht mehr,
## weil ein int-emittierendes Signal nicht direkt an einen String-Parameter
## verbunden werden kann.
func _on_xp_gained(skill_name: String, amount: int, peer_id: int) -> void:
	var player_id := _resolve_player_uuid(peer_id)
	if player_id.is_empty():
		return
	add_action_xp(skill_name, amount, player_id)

## R-7 (ADR-022), Client-Seite: wendet einen von der Autorität gesendeten
## Skill-Bucket (ein einzelner skill_id-Eintrag, nicht der ganze Spieler-Bucket —
## kleinere Payload, da meist nur ein Skill pro Mutation betroffen ist) auf den
## eigenen lokalen State an und feuert `skill_changed()` fürs UI.
func _on_economy_state_received(kind: String, payload: Dictionary) -> void:
	if kind != "skill":
		return
	if not is_instance_valid(_network):
		return
	var local_id := _network.get_local_player_id()
	if local_id.is_empty():
		return
	var skill_id: String = payload.get("skill_id", "")
	if skill_id.is_empty() or not _definitions.has(skill_id):
		return
	var bucket := _ensure_player(local_id)
	bucket[skill_id] = {"xp": payload.get("xp", 0), "level": payload.get("level", 1)}
	skill_changed.emit(skill_id, local_id)

# ─────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────

func get_save_key() -> String:
	return SAVE_KEY

func get_save_data() -> Dictionary:
	# Format: { "p1": { skill_id: {xp, level} }, "p2": {...} }
	var out: Dictionary = {}
	for pid in _players:
		out[pid] = (_players[pid] as Dictionary).duplicate(true)
	return out

# ─────────────────────────────────────────────
# Öffentliche API — request_/on_*_confirmed Pattern (ADR-004)
# ─────────────────────────────────────────────

## Anfrage: XP zu einem Skill addieren. Kein RPC-Zweig mehr (Root-Cause-Fund, siehe
## TODO-offene-probleme.md "Server validiert RPC-Werte nicht", Option A): wird
## ausschließlich authority-seitig aufgerufen (InteractionResolver, RewardDispatcher,
## EnemyNPC._die() — alle bereits hinter is_multiplayer_authority()-Guards), nie von
## einem Client, der selbst einen amount über das Netz senden will. Der frühere
## `_network.rpc_id(1, "_rpc_add_xp", …)`-Zweig war damit unbenutzte, aber trotzdem
## angreifbare Netzwerkfläche — entfernt statt nachträglich validiert.
func request_add_xp(skill_name: String, amount: int, player_id: String) -> void:
	var bucket := _ensure_player(player_id)
	if not bucket.has(skill_name):
		AppLogger.log_warn("Unbekannter Skill: '%s'" % skill_name, LOG_CAT)
		return
	if amount <= 0:
		return
	on_xp_add_confirmed(skill_name, amount, player_id)

## XP für eine AKTION (Ernten, Schmieden, Kochen, Kämpfen ...) — wie request_add_xp(), aber mit
## Ausrüstungs-Bonus: alle "xp_gain"- und "xp_gain_<skill>"-Modifier des Spielers (PERCENT_ADD,
## Quelle ItemDefinition.xp_bonus) skalieren `amount`. EINZIGE Stelle, an der der Bonus rechnet —
## jeder Skill, der XP über Aktionen vergibt, ruft diese Methode (statt request_add_xp()), dann
## gilt der Bonus automatisch. Quest-/Admin-Belohnungen bleiben bewusst bei request_add_xp()
## (feste Belohnung, kein Ausrüstungsbonus). Gibt die tatsächlich vergebene XP zurück.
func add_action_xp(skill_name: String, amount: int, player_id: String) -> int:
	if amount <= 0:
		return 0
	var final_amount := amount
	if is_instance_valid(_stat_modifiers) and not player_id.is_empty():
		var scaled := _stat_modifiers.get_effective_stat(EquipmentService.STAT_XP_GAIN, float(amount), player_id)
		scaled = _stat_modifiers.get_effective_stat(EquipmentService.xp_stat_for(skill_name), scaled, player_id)
		final_amount = maxi(1, roundi(scaled))
	request_add_xp(skill_name, final_amount, player_id)
	return final_amount

## Authority-Mutation: schreibt XP für player_id. Public (ADR-004). Kein
## NetworkBridge._rpc_add_xp() mehr, das hierher delegierte — entfernt (siehe
## request_add_xp()-Kommentar).
## C-02: Authority Guard — verweigert auf Nicht-Autorität wenn Peer gesetzt (Verteidigung
## in der Tiefe, falls künftiger Code diese Methode je aus Nicht-Autoritäts-Kontext ruft).
func on_xp_add_confirmed(skill_name: String, amount: int, player_id: String) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		AppLogger.log_error(
			"on_xp_add_confirmed: Aufruf auf Nicht-Autorität — verweigert.", LOG_CAT
		)
		return
	var bucket := _ensure_player(player_id)
	if skill_name.is_empty() or not bucket.has(skill_name):
		AppLogger.log_error("on_xp_add_confirmed: Skill '%s' unbekannt!" % skill_name, LOG_CAT)
		return
	bucket[skill_name]["xp"] += amount
	AppLogger.log_debug("+%d XP in '%s' für Spieler '%s' (gesamt: %d)" % [amount, skill_name, player_id, bucket[skill_name]["xp"]], LOG_CAT)
	_check_level_up(skill_name, player_id)
	skill_changed.emit(skill_name, player_id)
	## R-7 (ADR-022): Rücksync an einen entfernten Client — analog zu
	## InventorySystem._on_inventory_state_changed(). ADR-029 Round 65:
	## send_economy_update() erwartet peer_id (int) für sein rpc_id()-Routing —
	## send_economy_update_for_player() (String-Pendant, seit Round 63
	## vorbereitet) löst das Ziel-peer_id selbst auf. Verwirft den Aufruf
	## selbst still, wenn dieser Prozess keine Autorität ist oder player_id
	## der lokale Spieler ist.
	if is_instance_valid(_network):
		_network.send_economy_update_for_player(
			player_id, "skill",
			{"skill_id": skill_name, "xp": bucket[skill_name]["xp"], "level": bucket[skill_name]["level"]}
		)

## Admin-Tool-Eintrittspunkt (siehe AdminMenuCommands._cmd_setskilllevel()):
## setzt Level DIREKT statt über request_add_xp()-Zuwächse, weil ein Admin
## einen konkreten Ziel-Level will ("setz mich auf Level 50"), nicht eine
## XP-Menge, die je nach Kurve unterschiedlich weit reicht. XP wird auf 0
## zurückgesetzt (sauberer Zustand exakt an der Levelgrenze, kein Rest-XP
## aus der alten Kurve, das sich seltsam mit dem neuen Level verhält).
## Gleicher C-02-Authority-Guard + Sync-Pfad wie on_xp_add_confirmed().
func request_set_level(skill_name: String, level: int, player_id: String) -> bool:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		AppLogger.log_error(
			"request_set_level: Aufruf auf Nicht-Autorität — verweigert.", LOG_CAT
		)
		return false
	var bucket := _ensure_player(player_id)
	if skill_name.is_empty() or not bucket.has(skill_name):
		AppLogger.log_warn("request_set_level: unbekannter Skill '%s'." % skill_name, LOG_CAT)
		return false
	var def: SkillDefinition = _definitions.get(skill_name)
	if def == null:
		AppLogger.log_error("request_set_level: keine SkillDefinition für '%s'." % skill_name, LOG_CAT)
		return false
	var clamped: int = max(1, level)
	if def.max_level >= 0:
		clamped = min(clamped, def.max_level)
	bucket[skill_name]["level"] = clamped
	bucket[skill_name]["xp"] = 0
	AppLogger.log_info("Level von '%s' in '%s' auf %d gesetzt (Admin)." % [skill_name, player_id, clamped], LOG_CAT)
	skill_changed.emit(skill_name, player_id)
	if is_instance_valid(_network):
		_network.send_economy_update_for_player(
			player_id, "skill",
			{"skill_id": skill_name, "xp": bucket[skill_name]["xp"], "level": bucket[skill_name]["level"]}
		)
	return true

func get_level(skill_name: String, player_id: String) -> int:
	var bucket: Dictionary = _players.get(player_id, {})
	return (bucket.get(skill_name, {"level": 1}) as Dictionary)["level"]

func get_xp(skill_name: String, player_id: String) -> int:
	var bucket: Dictionary = _players.get(player_id, {})
	return (bucket.get(skill_name, {"xp": 0}) as Dictionary)["xp"]

func get_xp_to_next_level(skill_name: String, player_id: String) -> int:
	var def: SkillDefinition = _definitions.get(skill_name)
	if not def:
		return 100
	return def.get_xp_required(get_level(skill_name, player_id))

func has_skill(skill_name: String, player_id: String) -> bool:
	var bucket: Dictionary = _players.get(player_id, {})
	return bucket.has(skill_name)

func get_skill_ids(player_id: String) -> Array[String]:
	## Gibt die IDs aller Skills für player_id zurück.
	## Einziger erlaubter Weg um über Skills zu iterieren — schützt vor
	## direktem Zugriff auf die interne Multi-Tenant-Struktur (B-05).
	var bucket: Dictionary = _players.get(player_id, {})
	var result: Array[String] = []
	for key in bucket:
		result.append(key as String)
	return result

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _init_definitions() -> void:
	_definitions = _data_service.get_all_skills()

	if _definitions.is_empty():
		# Kein Fallback mehr: fehlende SkillDefinitions sind ein Datenlade-Bug
		# (data/skills/*.tres nicht gefunden/geladen), kein Zustand, mit dem das
		# Spiel sinnvoll weiterlaufen kann — Level-Kurven, max_level etc. wären
		# überall geraten statt designed. Gleicher Härte-Grad wie ServiceDeps.require().
		AppLogger.fatal(
			"SkillSystem._init_definitions(): keine SkillDefinitions in DataService gefunden — "
			+ "data/skills/*.tres fehlt oder wurde nicht geladen. SkillSystem kann "
			+ "nicht ohne echte Skill-Definitionen starten.",
			LOG_CAT
		)
		return

	AppLogger.log_debug("Skills aus DataService geladen: %s" % str(_definitions.keys()), LOG_CAT)

func _check_level_up(skill_name: String, player_id: String) -> void:
	var bucket := _ensure_player(player_id)
	var entry: Dictionary = bucket[skill_name]
	var def:   SkillDefinition = _definitions.get(skill_name)

	if def == null:
		# Kann nur passieren wenn skill_name nicht aus _definitions.keys() stammt
		# (z.B. Tippfehler an einer request_add_xp()-Call-Site) — kein Fallback
		# auf eine geratene XP-Kurve mehr, das maskiert genau diesen Bug.
		AppLogger.fatal("SkillSystem._check_level_up(): unbekannter Skill '%s' — keine SkillDefinition dafür." % skill_name, LOG_CAT)
		return

	while true:
		if def.max_level >= 0 and entry["level"] >= def.max_level:
			return
		var xp_needed: int = def.get_xp_required(entry["level"])

		if entry["xp"] < xp_needed:
			break

		entry["xp"]   -= xp_needed
		entry["level"] += 1
		AppLogger.log_info(
			"LEVEL UP! Spieler '%s' — '%s' ist jetzt Level %d." % [player_id, skill_name, entry["level"]], LOG_CAT
		)
		# ADR-029 Round 65: level_up (PlayerEvents) wird weiterhin mit peer_id
		# (int) emittiert — SkillPanelController/andere Konsumenten sind noch
		# nicht migriert. Übersetzung an genau dieser einen Stelle, analog zu
		# QuestService._resolve_peer_id() für den RewardDispatcher-Call.
		var peer_id := _resolve_peer_id(player_id)
		if peer_id == -1:
			AppLogger.log_warn(
				"_check_level_up: konnte peer_id für '%s' nicht auflösen — level_up-Signal übersprungen." % player_id,
				LOG_CAT
			)
		else:
			_bus.player().emit_level_up(skill_name, entry["level"], peer_id)

func _restore_from_save(saved: Dictionary) -> void:
	# Format: { "p1": { skill_id: {xp, level} }, "p2": {...} }
	# ADR-029 Round 65: pid_str ist bereits die player_id — keine int()-
	# Konvertierung mehr, keine Übergangslogik für alte peer_id-Saves (siehe
	# InventorySystem/QuestService, Round 63/64, "Save-Migration entfällt").
	for pid_str in saved:
		var pid: String = str(pid_str)
		var raw: Dictionary = saved[pid_str] as Dictionary if saved[pid_str] is Dictionary else {}
		var bucket := _ensure_player(pid)
		for skill_name in raw:
			if bucket.has(skill_name):
				bucket[skill_name] = raw[skill_name]
			else:
				AppLogger.log_warn("Veralteter Skill im Save: '%s' (Spieler '%s') — übersprungen." % [skill_name, pid], LOG_CAT)

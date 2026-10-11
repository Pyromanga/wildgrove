extends Service
class_name AchievementService

## ADR-046: Achievement-System — Round 102 (Grundgerüst) + Round 103
## (Statistiken/Belohnungen/Datengetriebene Definitionen/Sync-Pfad).
##
## DATENMODELL: `DEFAULT_DEFINITIONS` bleibt als eingebauter Fallback
## bestehen (immer verfügbar, auch ohne DataService — z. B. in Unit-Tests
## ohne vollen Service-Graphen). Ist `DataService` (optional-dep) verfügbar,
## werden dessen `AchievementDefinition`-.tres-Ressourcen (`data/
## achievements/*.tres`, siehe `AchievementDefinition.gd`) beim `configure()`
## zusätzlich geladen und legen sich ÜBER die Defaults (Ergänzung UND
## Override, kein kompletter Ersatz) — echter datengetriebener Workflow,
## exakt das Muster, das Quests/Items/Skills/CombatProfiles bereits nutzen
## (`DataManifest`+`DataService`). Fortschritt wird pro `player_id` UND
## `achievement_id` als Fließkomma-Zähler geführt (`grant_progress()`, seit
## Round 103 `float` statt `int` — nötig für Stat-Achievements wie "Meter
## gelaufen"), bei Erreichen von `target` automatisch freigeschaltet
## (`_unlock()`).
##
## TRIGGER-QUELLEN (sechs, alle nachweislich autoritäts-only):
## `PvPDeathLossService.death_loss_applied`, `AuctionHouseService.
## listing_created`, `ReportService.report_submitted`,
## `StatsService.stat_changed` (Round 103, siehe `STAT_ACHIEVEMENT_MAP`
## für die stat_name → achievement_id-Zuordnung), `CharacterCreationService.
## character_created`/`character_creation_skipped` (Round 105, ADR-048 —
## beide hinter `_require_authority()` in `CharacterCreationService`, exakt
## dasselbe Vertrauens-Argument wie die ersten drei Quellen). Alle sechs
## feuern ausschließlich auf der Autorität — die ersten drei und die beiden
## Round-105-Quellen hinter einem `_require_authority()`-Guard in ihrem
## jeweiligen `on_..._confirmed()`/Aufrufer, `StatsService.stat_changed`
## transitiv, weil dessen beide EIGENEN Quell-Signale
## (`movement_stats_batch`/`enemy_killed`) durch Konstruktion nur auf der
## Autorität feuern (siehe `StatsService.gd`-Klassenkommentar).
## BEWUSST NICHT `ChatService.message_received` als Trigger-Quelle — feuert
## auf JEDEM Client, nicht nur der Autorität (Multiplayer-inkonsistent).
##
## MULTIPLAYER-KORREKTHEIT: `grant_progress()`/`_unlock()` laufen nur auf
## der Autorität (`_require_authority()`). Der Host sieht sein eigenes
## Unlock direkt über das lokal emittierte `achievement_unlocked`-Signal.
## Ein entfernter Client wird zusätzlich per RPC benachrichtigt
## (`NetworkBridge.send_achievement_unlocked_for_player()`).
##
## BELOHNUNGEN (Round 103): optionales `reward_gold` pro Definition, direkt
## über `CurrencyService.request_add_gold()` vergeben — bewusst NICHT über
## `RewardDispatcher` (dessen `dispatch()` ist an `QuestReward`/`quest_id`
## gekoppelt, ein fachfremder Typ für Achievements; ein Item-/XP-Reward-Feld
## wäre der nächste Schritt, wenn das gebraucht wird, siehe "Bewusst nicht
## Teil dieser Runde").
##
## CLIENT-EMPFANG (Round 104): bis hierhin kam auf einem Nicht-Autoritäts-Peer
## nichts an — `NetworkBridge.achievement_unlocked_received`/
## `achievement_snapshot_received` feuerten, aber niemand hörte zu.
## `_on_remote_unlock_received()`/`_on_remote_snapshot_received()` übernehmen
## Server-Payloads jetzt direkt in `_progress`/`_unlocked` (ohne
## `_require_authority()` — hier wird nichts neu entschieden, nur gespiegelt)
## und re-emittieren dieselben lokalen Signale, die auch die Autorität
## emittiert (`achievement_unlocked`/`achievement_progress`), plus ein neues
## `achievements_synced` für den Snapshot-Fall (voller Re-Render statt
## Einzel-Diff). Damit reagiert `AchievementPanelController` identisch,
## unabhängig davon ob er auf dem Host oder einem Client läuft.
##
## SNAPSHOT-SYNC (Round 103): `request_snapshot()`/`on_snapshot_requested()`
## + `NetworkBridge.send_achievement_snapshot_request()`/
## `_rpc_achievement_snapshot_request()` (Client→Autorität) und
## `send_achievement_snapshot_for_player()`/`achievement_snapshot_received`
## (Autorität→Ziel-Spieler) — Pull-statt-Push, exakt wie `AuctionHouseService.
## request_listings_snapshot()` (ADR-035). Schließt die in Round 102 offen
## gelassene Lücke für spät joinende/neu gestartete Clients.
##
## PERSISTENZ: `SAVE_KEY = "achievements"` — Fortschritt UND freigeschaltete
## IDs überleben Sitzungen.
##
## BEWUSST NICHT TEIL DIESER RUNDE:
##   - Kein echter Editor-Inspector-Test — die .tres-Dateien folgen exakt
##     dem Quest/Item/Skill-Muster und SOLLTEN im Editor normal als
##     AchievementDefinition-Ressourcen erscheinen, aber ohne Godot-Editor
##     in dieser Umgebung nicht verifizierbar.
##   - Kein Item-/XP-Reward-Feld, nur Gold — siehe "BELOHNUNGEN" oben.
##   - Kein Kill-Feed-artiges "alle sehen jedes Achievement"-Broadcast
##     (Unlocks bleiben privat zum jeweiligen Spieler). UI-Panel siehe
##     Round 104 (`scripts/progression/achievements/ui/`).
##   - Kein Chat/Social als Trigger-Quelle (siehe oben).
##
## EASTER EGGS (Round 107): `hidden`-Flag auf AchievementDefinition (siehe
## dort) — Name/Beschreibung bleiben in der UI "???", bis freigeschaltet.
## Erste zwei Easter Eggs (`sun_gazer`, `firefly_watcher`) brauchen eine
## SIEBTE Trigger-Quelle, die sich von den bisherigen sechs grundsätzlich
## unterscheidet: die beobachtete Bedingung (Kamera-Blickrichtung + Zoomstufe
## fürs Egoperspektive-Sonnenschauen; "wie lange stehen Glühwürmchen-Partikel
## schon an") existiert NUR lokal auf dem Client (`PlayerCamera`/
## `AmbientForestVfx` sind reine Optik, kein Netzwerk-Zustand) — anders als
## z.B. `movement_stats_batch`, wo der Server über die Spielerposition
## bereits die Ground-Truth hat. Es gibt also nichts, das der Server selbst
## prüfen könnte; er muss dem Client zwangsläufig glauben.
## `on_client_observed_achievement()` + `CLIENT_REPORTABLE_ACHIEVEMENTS`
## (Whitelist, siehe dort) begrenzen dieses Vertrauen auf genau diese
## bewusst niedrig dotierten (10 Gold), rein kosmetischen Easter Eggs — ein
## manipulierter Client kann sich darüber NICHT "pvp_veteran" o.ä. erschleichen,
## weil `on_client_observed_achievement()` jede nicht gelistete achievement_id
## ablehnt. Client-Seite: `SunGazeWatcher.gd` (neuer Kind-Node am lokalen
## `Player`, siehe dort) und `AmbientForestVfx._check_ambient_state()`
## (erweitert um einen 5-Sekunden-Timer auf `_fireflies_active`). Übertragen
## über `NetworkBridge.send_client_observed_achievement()` — im Tier-1/
## Solo-Fall (kein Peer oder bereits Server) ruft diese Funktion
## `on_client_observed_achievement()` direkt lokal auf, exakt das
## Fallback-Muster von `send_achievement_snapshot_request()`.

const LOG_CAT := "AchievementService"
const SAVE_KEY := "achievements"

## Eingebauter Fallback — IMMER verfügbar, auch ohne DataService (siehe
## Klassenkommentar "DATENMODELL"). achievement_id -> {name, description,
## target, category, reward_gold}.
const DEFAULT_DEFINITIONS: Dictionary = {
	"first_blood": {
		"name": "Erstes Blut", "description": "Besiege einen anderen Spieler im PvP-Kampf.",
		"target": 1.0, "category": "combat", "reward_gold": 50,
	},
	"pvp_veteran": {
		"name": "PvP-Veteran", "description": "Besiege 10 andere Spieler im PvP-Kampf.",
		"target": 10.0, "category": "combat", "reward_gold": 250,
	},
	"first_sale": {
		"name": "Erster Verkauf", "description": "Erstelle dein erstes Auktionshaus-Angebot.",
		"target": 1.0, "category": "economy", "reward_gold": 25,
	},
	"auctioneer": {
		"name": "Auktionator", "description": "Erstelle 10 Auktionshaus-Angebote.",
		"target": 10.0, "category": "economy", "reward_gold": 150,
	},
	"community_watch": {
		"name": "Wachsames Auge", "description": "Reiche deine erste Meldung ein.",
		"target": 1.0, "category": "social", "reward_gold": 25,
	},
	"wanderer": {
		"name": "Wanderer", "description": "Lege insgesamt 1000 Meter zu Fuß zurück.",
		"target": 1000.0, "category": "stats", "reward_gold": 100,
	},
	"high_jumper": {
		"name": "Hochspringer", "description": "Springe insgesamt 100 Meter hoch.",
		"target": 100.0, "category": "stats", "reward_gold": 100,
	},
	"gravity_defier": {
		"name": "Schwerkraft-Trotzer", "description": "Falle insgesamt 500 Meter.",
		"target": 500.0, "category": "stats", "reward_gold": 100,
	},
	"monster_hunter": {
		"name": "Monsterjäger", "description": "Besiege 50 NPCs.",
		"target": 50.0, "category": "stats", "reward_gold": 200,
	},
	"character_creator_complete": {
		"name": "Wer bist du?", "description": "Schließe die Charaktererstellung ab.",
		"target": 1.0, "category": "social", "reward_gold": 20,
	},
	"character_creator_skipped": {
		"name": "Keine Zeit für Fragen", "description": "Überspringe die Charaktererstellung.",
		"target": 1.0, "category": "social", "reward_gold": 10,
	},
	"sun_gazer": {
		"name": "Ikarus' Neugier",
		"description": "Schau 5 Sekunden am Stück in Egoperspektive direkt in die Sonne.",
		"target": 1.0, "category": "easter_egg", "reward_gold": 10, "hidden": true,
	},
	"firefly_watcher": {
		"name": "Lichterspiel",
		"description": "Beobachte 5 Sekunden am Stück die Glühwürmchen im dichten Wald bei Nacht.",
		"target": 1.0, "category": "easter_egg", "reward_gold": 10, "hidden": true,
	},
}

## Easter-Egg-Achievements, die NUR der Client selbst beobachten kann (siehe
## Klassenkommentar "EASTER EGGS") — feste Whitelist statt freiem
## achievement_id-Durchreichen aus dem Netzwerk, damit ein manipulierter
## Client sich nicht z.B. "pvp_veteran" erschleichen kann. Jede neue
## Easter-Egg-Achievement-ID, die über on_client_observed_achievement()
## laufen soll, muss hier eingetragen werden — sonst wird sie abgelehnt.
const CLIENT_REPORTABLE_ACHIEVEMENTS: Array[String] = ["sun_gazer", "firefly_watcher"]

## stat_name (StatsService-Konstanten) -> Array[String] betroffener
## achievement_ids. Round 103.
const STAT_ACHIEVEMENT_MAP: Dictionary = {
	"meters_walked": ["wanderer"],
	"meters_jumped": ["high_jumper"],
	"meters_fallen": ["gravity_defier"],
	"npcs_killed": ["monster_hunter"],
}

## Emittiert, sobald ein Achievement für player_id freigeschaltet wird.
signal achievement_unlocked(player_id: String, achievement_id: String)

## Emittiert bei jeder Fortschritts-Änderung, auch ohne Unlock.
signal achievement_progress(player_id: String, achievement_id: String, current: float, target: float)

## Emittiert, wenn ein Achievement-Snapshot vom Server angekommen ist und
## `_progress`/`_unlocked` für player_id neu gesetzt wurden (Round 104,
## siehe Klassenkommentar "CLIENT-EMPFANG"). AchievementPanelController
## nutzt das für einen vollständigen Re-Render statt einzelner Diffs.
signal achievements_synced(player_id: String)

var _save_system: SaveSystem = null
var _network: NetworkBridge = null
var _telemetry: TelemetryService = null
var _currency: CurrencyService = null
## Round 104: nur für _local_player_id() auf dem Client — bestimmt, für wen
## ankommende achievement_unlocked_received/achievement_snapshot_received-
## RPCs lokal übernommen werden. App-scoped (ADR-009), daher optional +
## fallback_registry-auflösbar wie bei WorldService/anderen Session-Services.
var _session_manager: SessionManager = null

var _pvp_death_loss: PvPDeathLossService = null
var _auction: AuctionHouseService = null
var _report: ReportService = null
var _stats: StatsService = null
var _character_creation: CharacterCreationService = null

## Aktive Definitionen — DEFAULT_DEFINITIONS + ggf. DataService-Overrides
## (siehe Klassenkommentar). achievement_id -> Dictionary.
var _definitions: Dictionary = {}

## player_id -> {achievement_id -> Fließkomma-Zähler}
var _progress: Dictionary = {}
## player_id -> Array[String] freigeschalteter achievement_ids
var _unlocked: Dictionary = {}

func configure(deps: ServiceDeps) -> void:
	_save_system = deps.get_optional(ServiceKeys.SAVE_SYSTEM)    as SaveSystem
	_network     = deps.get_optional(ServiceKeys.NETWORK_BRIDGE) as NetworkBridge
	_telemetry   = deps.get_optional(ServiceKeys.TELEMETRY)      as TelemetryService
	_currency    = deps.get_optional(ServiceKeys.CURRENCY)       as CurrencyService

	_definitions = DEFAULT_DEFINITIONS.duplicate(true)
	var data: DataService = deps.get_optional(ServiceKeys.DATA) as DataService
	if is_instance_valid(data):
		for achievement_id in data.get_all_achievements():
			var def: AchievementDefinition = data.get_achievement(achievement_id)
			_definitions[achievement_id] = {
				"name": def.display_name, "description": def.description,
				"target": def.target, "category": def.category, "reward_gold": def.reward_gold,
				"hidden": def.hidden,
			}

	_session_manager = deps.get_optional(ServiceKeys.SESSION_MANAGER) as SessionManager
	_connect_network_receive()

	_pvp_death_loss = deps.get_optional(ServiceKeys.PVP_DEATH_LOSS) as PvPDeathLossService
	if is_instance_valid(_pvp_death_loss):
		_pvp_death_loss.death_loss_applied.connect(_on_pvp_death_loss_applied)

	_auction = deps.get_optional(ServiceKeys.AUCTION_HOUSE) as AuctionHouseService
	if is_instance_valid(_auction):
		_auction.listing_created.connect(_on_auction_listing_created)

	_report = deps.get_optional(ServiceKeys.REPORT) as ReportService
	if is_instance_valid(_report):
		_report.report_submitted.connect(_on_report_submitted)

	_stats = deps.get_optional(ServiceKeys.STATS) as StatsService
	if is_instance_valid(_stats):
		_stats.stat_changed.connect(_on_stat_changed)

	_character_creation = deps.get_optional(ServiceKeys.CHARACTER_CREATION) as CharacterCreationService
	if is_instance_valid(_character_creation):
		_character_creation.character_created.connect(_on_character_created)
		_character_creation.character_creation_skipped.connect(_on_character_creation_skipped)

	if _save_system:
		_save_system.register_save_provider(self)
		var saved: Variant = _save_system.get_state_for(SAVE_KEY)
		if saved is Dictionary and not (saved as Dictionary).is_empty():
			_restore_from_save(saved)
	else:
		AppLogger.log_error("Abhängigkeit 'savesystem' fehlt!", LOG_CAT)

	AppLogger.log_info(
		"AchievementService initialisiert (%d Definitionen)." % _definitions.size(),
		LOG_CAT
	)

func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network
	_connect_network_receive()

func on_cleanup() -> void:
	if is_instance_valid(_pvp_death_loss) and _pvp_death_loss.death_loss_applied.is_connected(_on_pvp_death_loss_applied):
		_pvp_death_loss.death_loss_applied.disconnect(_on_pvp_death_loss_applied)
	if is_instance_valid(_auction) and _auction.listing_created.is_connected(_on_auction_listing_created):
		_auction.listing_created.disconnect(_on_auction_listing_created)
	if is_instance_valid(_report) and _report.report_submitted.is_connected(_on_report_submitted):
		_report.report_submitted.disconnect(_on_report_submitted)
	if is_instance_valid(_stats) and _stats.stat_changed.is_connected(_on_stat_changed):
		_stats.stat_changed.disconnect(_on_stat_changed)
	if is_instance_valid(_character_creation):
		if _character_creation.character_created.is_connected(_on_character_created):
			_character_creation.character_created.disconnect(_on_character_created)
		if _character_creation.character_creation_skipped.is_connected(_on_character_creation_skipped):
			_character_creation.character_creation_skipped.disconnect(_on_character_creation_skipped)
	if is_instance_valid(_network):
		if _network.achievement_unlocked_received.is_connected(_on_remote_unlock_received):
			_network.achievement_unlocked_received.disconnect(_on_remote_unlock_received)
		if _network.achievement_snapshot_received.is_connected(_on_remote_snapshot_received):
			_network.achievement_snapshot_received.disconnect(_on_remote_snapshot_received)

## Round 104: Gegenstück zu grant_progress()/_unlock() (die beide über
## _require_authority() für Nicht-Autorität gesperrt sind) — übernimmt
## Server-Antworten auf dem Client OHNE den Authority-Guard, weil hier keine
## eigene Mutation stattfindet, nur Übernahme eines bereits autoritativ
## entschiedenen Zustands. Exakt das Verdrahtungsmuster von
## AuctionHouseService._connect_economy_sync().
func _connect_network_receive() -> void:
	if not is_instance_valid(_network):
		return
	if not _network.achievement_unlocked_received.is_connected(_on_remote_unlock_received):
		_network.achievement_unlocked_received.connect(_on_remote_unlock_received)
	if not _network.achievement_snapshot_received.is_connected(_on_remote_snapshot_received):
		_network.achievement_snapshot_received.connect(_on_remote_snapshot_received)

# ─────────────────────────────────────────────
# Trigger-Handler (siehe Klassenkommentar "TRIGGER-QUELLEN")
# ─────────────────────────────────────────────

func _on_pvp_death_loss_applied(_victim_player_id: String, killer_player_id: String, _gold_lost: int, _items_lost: Array, _loss_percent: float, _victim_was_skulled: bool) -> void:
	grant_progress(killer_player_id, "first_blood")
	grant_progress(killer_player_id, "pvp_veteran")

func _on_auction_listing_created(_listing_id: String, seller_id: String) -> void:
	grant_progress(seller_id, "first_sale")
	grant_progress(seller_id, "auctioneer")

func _on_report_submitted(entry: Dictionary) -> void:
	grant_progress(String(entry.get("reporter_player_id", "")), "community_watch")

## Round 103: vierte Trigger-Quelle. delta ist bereits das korrekte Inkrement
## (siehe StatsService.stat_changed) — grant_progress() akkumuliert selbst,
## kein zweiter Absolut-Wert-Abgleich nötig.
func _on_stat_changed(player_id: String, stat_name: String, delta: float, _new_total: float) -> void:
	for achievement_id in STAT_ACHIEVEMENT_MAP.get(stat_name, []):
		grant_progress(player_id, achievement_id, delta)

func _on_character_created(player_id: String, _appearance_preset_id: String, _traits: Array) -> void:
	grant_progress(player_id, "character_creator_complete")

func _on_character_creation_skipped(player_id: String) -> void:
	grant_progress(player_id, "character_creator_skipped")

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

## Erhöht den Fortschritt für (player_id, achievement_id) um `amount` und
## schaltet bei Erreichen von `target` automatisch frei. No-Op wenn bereits
## freigeschaltet, wenn achievement_id unbekannt ist, oder wenn player_id
## leer ist.
func grant_progress(player_id: String, achievement_id: String, amount: float = 1.0) -> void:
	if not _require_authority("grant_progress"):
		return
	if player_id.is_empty():
		return
	if not _definitions.has(achievement_id):
		AppLogger.log_error("grant_progress(): unbekannte achievement_id '%s'." % achievement_id, LOG_CAT)
		return
	if is_unlocked(player_id, achievement_id):
		return

	if not _progress.has(player_id):
		_progress[player_id] = {}
	var current: float = float((_progress[player_id] as Dictionary).get(achievement_id, 0.0)) + amount
	(_progress[player_id] as Dictionary)[achievement_id] = current

	var target: float = float((_definitions[achievement_id] as Dictionary)["target"])
	achievement_progress.emit(player_id, achievement_id, current, target)

	if current >= target:
		_unlock(player_id, achievement_id)

## Gegenstück zu NetworkBridge.send_client_observed_achievement() (siehe
## Klassenkommentar "EASTER EGGS" für das Vertrauensmodell). Läuft nur über
## den RPC-Handler bzw. den Tier-1-Fallback in NetworkBridge auf, beide
## bereits auf der Autorität — braucht deshalb kein eigenes
## _require_authority() (grant_progress() darunter hat es ohnehin schon).
## Lehnt alles außerhalb der CLIENT_REPORTABLE_ACHIEVEMENTS-Whitelist ab,
## OHNE Fehler zu loggen wie bei einer unbekannten achievement_id in
## grant_progress() — ein manipulierter Client, der wahllos IDs durchprobiert,
## soll kein Feedback über Logs bekommen, welche IDs "echt" sind.
func on_client_observed_achievement(player_id: String, achievement_id: String) -> void:
	if achievement_id not in CLIENT_REPORTABLE_ACHIEVEMENTS:
		AppLogger.log_warn(
			"on_client_observed_achievement(): '%s' ist nicht client-meldbar — abgelehnt." % achievement_id,
			LOG_CAT
		)
		return
	grant_progress(player_id, achievement_id)

func is_unlocked(player_id: String, achievement_id: String) -> bool:
	return achievement_id in (_unlocked.get(player_id, []) as Array)

func get_progress(player_id: String, achievement_id: String) -> float:
	return float((_progress.get(player_id, {}) as Dictionary).get(achievement_id, 0.0))

func get_unlocked(player_id: String) -> Array:
	return (_unlocked.get(player_id, []) as Array).duplicate()

func get_definition(achievement_id: String) -> Dictionary:
	return (_definitions.get(achievement_id, {}) as Dictionary).duplicate()

func get_all_definitions() -> Dictionary:
	return _definitions.duplicate(true)

func _unlock(player_id: String, achievement_id: String) -> void:
	if not _unlocked.has(player_id):
		_unlocked[player_id] = []
	var list: Array = _unlocked[player_id]
	if achievement_id in list:
		return
	list.append(achievement_id)

	var definition: Dictionary = _definitions[achievement_id]
	AppLogger.log_info(
		"Achievement freigeschaltet: '%s' -> '%s'." % [player_id, String(definition["name"])],
		LOG_CAT
	)
	achievement_unlocked.emit(player_id, achievement_id)

	if is_instance_valid(_telemetry):
		_telemetry.record_event("achievement_unlocked", {"player_id": player_id, "achievement_id": achievement_id})

	var reward_gold: int = int(definition.get("reward_gold", 0))
	if reward_gold > 0 and is_instance_valid(_currency):
		_currency.request_add_gold(player_id, reward_gold)

	if is_instance_valid(_network):
		_network.send_achievement_unlocked_for_player(player_id, {
			"achievement_id": achievement_id,
			"name": String(definition["name"]),
			"description": String(definition["description"]),
			"reward_gold": reward_gold,
		})

# ─────────────────────────────────────────────
# Snapshot-Sync (Round 103) — Pull-statt-Push, analog
# AuctionHouseService.request_listings_snapshot()
# ─────────────────────────────────────────────

## Client-seitiger Einstiegspunkt: eigenen Stand anfragen.
func request_snapshot(player_id: String) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.send_achievement_snapshot_request(player_id)
	else:
		on_snapshot_requested(player_id)

## Autoritätsseitig: baut den Snapshot für player_id und schickt ihn gezielt
## zurück (über denselben Kanal wie Unlock-Benachrichtigungen — dieselbe
## RPC-Rückrichtung, anderer payload["kind"]).
func on_snapshot_requested(player_id: String) -> void:
	if not _require_authority("on_snapshot_requested"):
		return
	if player_id.is_empty():
		return
	if is_instance_valid(_network):
		_network.send_achievement_snapshot_for_player(player_id, {
			"unlocked": get_unlocked(player_id),
			"progress": get_all_progress(player_id),
		})

func get_all_progress(player_id: String) -> Dictionary:
	return (_progress.get(player_id, {}) as Dictionary).duplicate()

# ─────────────────────────────────────────────
# Client-Empfang (Round 104) — Gegenstück zu _unlock()/on_snapshot_requested()
# auf einem Nicht-Autoritäts-Peer. Übernimmt Server-Payloads direkt in
# _progress/_unlocked statt über grant_progress()/_unlock() zu laufen (die
# beide _require_authority() erzwingen) — hier wird nichts neu entschieden,
# nur ein bereits von der Autorität getroffenes Ergebnis gespiegelt.
# ─────────────────────────────────────────────

func _local_player_id() -> String:
	return _session_manager.get_local_player_id() if is_instance_valid(_session_manager) else ""

## Payload enthält keine player_id (siehe NetworkBridge.
## send_achievement_unlocked_for_player() — Adressierung läuft bereits über
## rpc_id an den Ziel-Peer) — der Empfänger IST der betroffene Spieler.
func _on_remote_unlock_received(payload: Dictionary) -> void:
	var player_id := _local_player_id()
	if player_id.is_empty():
		AppLogger.log_error("_on_remote_unlock_received: lokale player_id unbekannt (SessionManager fehlt?).", LOG_CAT)
		return
	var achievement_id := String(payload.get("achievement_id", ""))
	if achievement_id.is_empty():
		return

	if not _unlocked.has(player_id):
		_unlocked[player_id] = []
	var list: Array = _unlocked[player_id]
	if achievement_id not in list:
		list.append(achievement_id)

	var target: float = float((_definitions.get(achievement_id, {}) as Dictionary).get("target", 1.0))
	if not _progress.has(player_id):
		_progress[player_id] = {}
	(_progress[player_id] as Dictionary)[achievement_id] = target

	achievement_progress.emit(player_id, achievement_id, target, target)
	achievement_unlocked.emit(player_id, achievement_id)

## Antwort auf request_snapshot() — vollständiger Zustand statt Einzel-Diff,
## deshalb eigenes Signal (achievements_synced) statt achievement_progress/
## achievement_unlocked pro Eintrag zu re-emittieren.
func _on_remote_snapshot_received(payload: Dictionary) -> void:
	var player_id := _local_player_id()
	if player_id.is_empty():
		AppLogger.log_error("_on_remote_snapshot_received: lokale player_id unbekannt (SessionManager fehlt?).", LOG_CAT)
		return
	var unlocked_ids: Array = payload.get("unlocked", [])
	var progress: Dictionary = payload.get("progress", {})
	_unlocked[player_id] = unlocked_ids.duplicate()
	_progress[player_id] = progress.duplicate()
	achievements_synced.emit(player_id)

# ─────────────────────────────────────────────
# Save-Interface (analog AuraService/ReportService)
# ─────────────────────────────────────────────

func get_save_key() -> String:
	return SAVE_KEY

func get_save_data() -> Dictionary:
	return {"progress": _progress, "unlocked": _unlocked}

func _restore_from_save(saved: Dictionary) -> void:
	if saved.get("progress") is Dictionary:
		_progress = saved["progress"]
	if saved.get("unlocked") is Dictionary:
		_unlocked = saved["unlocked"]

func _require_authority(caller: String) -> bool:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		AppLogger.log_error("%s: Aufruf auf Nicht-Autorität — verweigert." % caller, LOG_CAT)
		return false
	return true

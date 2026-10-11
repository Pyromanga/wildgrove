extends ServiceNode
# justified: enthaelt @rpc-Methoden (Godot 4 RPC nur auf Node); hostet alle Netzwerk-RPCs (ADR-010).
class_name NetworkBridge

## NetworkBridge — RPC-Empfangsstelle + Host/Join-API für alle RefCounted-Services.
##
## TIER 1 (Solo): Kein MultiplayerPeer → kein RPC nötig.
##   request_*()-Methoden in den Services rufen on_*_confirmed() direkt auf.
##
## TIER 2 (Hosted Coop): Host ruft host_game(port), Clients rufen join_game(ip, port).
##   request_*() rufen rpc_id(1, "_rpc_*", ...) auf.
##   NetworkBridge empfängt auf der Autorität (peer_id=1) und delegiert an die zuständigen Services.
##
## TIER 3 (Dedicated Server): Identisch zu Tier 2, Server ist kein spielender Client.

const LOG_CAT := "NetworkBridge"

## G-03: Snapshot-Retry-Konfiguration.
## Das RPC ist "reliable" — ENet garantiert Delivery auf Protokollebene.
## Retry schützt gegen Boot-Race-Conditions: Server antwortet lautlos wenn
## SaveSystem zur Zeit des Requests noch nicht bereit war.
const SNAPSHOT_TIMEOUT_SEC := 3.0   ## Wartezeit auf _rpc_receive_initial_state
const SNAPSHOT_MAX_RETRIES := 3     ## Max. Retry-Versuche bevor aufgegeben wird

const DEFAULT_PORT    := 7777
const MAX_CLIENTS     := 8

## Schritt 3: Rate-Limiting auf mutierenden any_peer-RPCs (Spam-/Flood-Schutz).
## Fixed-Window-Zähler pro (peer_id, rpc_name). Bewusst NICHT auf
## `_rpc_submit_movement_input` — das läuft absichtlich mit 20+ Hz über
## "unreliable_ordered" (ADR-025); ein Fenster-Limit hier würde legitimen
## Bewegungs-Input verwerfen statt Spam abzuwehren. Nur RPCs, deren legitime
## Aufrufrate klar unter "mehrfach pro Sekunde" liegt, sind gelistet.
const RATE_LIMIT_WINDOW_SEC := 1.0
const RATE_LIMITS := {
	"_rpc_start_quest":                   5,
	"_rpc_complete_quest":                5,
	"_rpc_set_state":                     10,
	"_rpc_equip_item":                    10,
	"_rpc_unequip_item":                  10,
	"_rpc_request_entity_interaction":    10,
	"_rpc_report_domain_event":           10,
	"_rpc_client_requests_initial_state": 2,
	"_rpc_shop_buy_item":                 10,
	"_rpc_shop_sell_item":                10,
	"_rpc_smithing_craft":                10,
	"_rpc_bank_deposit_item":             10,
	"_rpc_bank_withdraw_item":            10,
	"_rpc_bank_deposit_gold":             10,
	"_rpc_bank_withdraw_gold":            10,
	"_rpc_trade_respond_invite":          10,
	"_rpc_trade_update_offer":            10,
	"_rpc_trade_set_ready":               10,
	"_rpc_trade_set_confirmed":           10,
	"_rpc_trade_cancel":                  10,
	"_rpc_auction_list_item":             10,
	"_rpc_auction_buy_item":              10,
	"_rpc_auction_cancel_listing":        10,
	"_rpc_auction_request_snapshot":      5,
	"_rpc_item_protection_apply":         10,
	"_rpc_aura_thank":                    5,
	"_rpc_pickpocket_attempt":            10,
	"_rpc_chat_send_message":             5,
	"_rpc_report_submit":                 3,
	"_rpc_achievement_snapshot_request":  5,
	"_rpc_character_creation_submit_answers": 3,
	"_rpc_character_creation_skip":            3,
	"_rpc_character_set_look":                3,
	"_rpc_wiki_snapshot_request":              5,
	"_rpc_report_player_spawned":               5,
	"_rpc_report_pet_spawned":                   5,
	"_rpc_client_observed_achievement":          10,
}

var _inventory:     InventorySystem    = null
var _quest:         QuestService       = null
var _skill_system:  SkillSystem        = null
var _player_states: PlayerStateService = null
var _equipment:     EquipmentService   = null
var _shop:          ShopService        = null
var _smithing:      SmithingService    = null
var _bank:          BankService        = null
var _trade:          TradeService        = null
var _auction:        AuctionHouseService = null
var _item_protection: ItemProtectionService = null
var _aura:            AuraService          = null
var _pickpocket:      PickpocketService    = null
var _chat:            ChatService          = null
var _report:          ReportService        = null
var _achievement:     AchievementService   = null
var _character_creation: CharacterCreationService = null
var _wiki:                WikiService               = null  ## ADR-049
var _zone_service:  ZoneService        = null
var _save_system:   SaveSystem         = null
## ADR-017 / AUDIT-05 Mutation 3: SessionManager ist die einzige Quelle der
## Wahrheit für "wer bin ich" (peer_id). NetworkBridge berechnet das nicht
## mehr selbst, sondern delegiert.
var _session_manager: SessionManager   = null
## ADR-020: WorldService — für _rpc_request_entity_interaction(), delegiert dort
## an resolve_and_dispatch_interaction() (EntityOrchestrator.resolve_for_player,
## ADR-023). Einseitiger Dep (siehe BootstrapConfig.tres-Kommentar dazu) —
## WorldService bekommt NetworkBridge umgekehrt NICHT als configure()-Dep,
## sondern über Late-Inject (Phase C8), um den Zyklus zu vermeiden.
var _world:         WorldService       = null

## G-03: Snapshot-Retry-State (Client-Seite).
var _snapshot_received:  bool           = false
var _snapshot_retries:   int            = 0
var _snapshot_timer:     SceneTreeTimer = null

## Schritt 3: Rate-Limit-State (Autoritäts-Seite). Key: "<peer_id>:<rpc_name>",
## Value: {"window_start": float (Sekunden), "count": int}.
var _rate_limit_state: Dictionary = {}

## BUGFIX (2026-09-14, "zwei Welten" Teil 2): NUR auf der Autorität befüllt.
## peer_id (int) → { "player_id": String, "pos": Vector3 } für jeden Peer, der
## sein lokales Player-Entity bereits gespawnt UND gemeldet hat (siehe
## report_local_player_spawned()/_rpc_report_player_spawned()). Grundlage für
## den gegenseitigen "wer ist schon da"-Abgleich beim Join und für den
## Despawn-Broadcast beim Verlassen (_on_peer_disconnected()).
var _active_world_peers: Dictionary = {}

## BUGFIX (2026-09-15, "Spieler sehen sich immer noch nicht"): letzte per
## report_local_player_spawned() gemeldete eigene Position + ob überhaupt schon
## gemeldet — Grundlage für den Nachtrag in _rpc_request_player_report().
var _last_local_report_pos: Vector3 = Vector3.ZERO
var _has_reported_local_player: bool = false

## Signale für UI/GameManager
signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_failed()
signal server_disconnected()

## ADR-021 (R-5): generischer "Autorität-informieren"-Kanal für Domain-Events,
## die selbst keinen Wert/keine Menge tragen, die auf Client-Seite fälschbar
## wäre (siehe report_domain_event()) — nur Quest-relevante Beobachtungen wie
## "Interaktion X abgeschlossen" / "NPC Y angesprochen" / "Trigger Z betreten".
## Feuert NUR auf der Autorität, mit serverseitig ermitteltem peer_id.
## QuestService (und künftige Konsumenten) abonnieren dieses Signal statt
## einzelner lokaler EventBus-Signale, wenn sie eine Autoritäts-seitige,
## netzwerkfähige Meldung brauchen statt der rein lokalen Peer-Kopie.
signal domain_event_received(event_name: String, payload: Dictionary, peer_id: int)

## R-7 (ADR-022): generischer Autorität→Ziel-Client-Rücksync für Economy-Mutationen
## (Inventory/Skill/Equipment). Feuert NUR auf dem EMPFANGENDEN Client, nach
## Empfang von `_rpc_receive_economy_update()` — die Services (InventorySystem/
## SkillSystem/EquipmentService) abonnieren dies, um ihre eigene lokale Kopie
## des STATE für ihren eigenen player_id zu aktualisieren, wenn dieser Client
## nicht die Autorität ist. `kind` unterscheidet "inventory"/"skill"/"equipment",
## `payload` ist service-spezifisch (siehe jeweiliger send_economy_update()-Aufrufer).
signal economy_state_received(kind: String, payload: Dictionary)

## ADR-042: generischer Autorität→ALLE-Clients-Broadcast-Kanal. Feuert NUR auf
## empfangenden Clients (nie auf der Autorität selbst, siehe
## _rpc_receive_broadcast_event()-Guard), nach Empfang von
## `_rpc_receive_broadcast_event()`. `kind` unterscheidet den Broadcast-Typ
## (z.B. künftig "auction_listing_changed"), `payload` ist kind-spezifisch.
## Bewusst KEIN Ersatz für economy_state_received()/domain_event_received() —
## dort bleibt die 1:1-Ziel-Adressierung, weil dort ein einzelner betroffener
## Spieler feststeht. broadcast_event_received() ist nur für Fälle gedacht, in
## denen die Nachricht tatsächlich für ALLE aktuell verbundenen Spieler
## relevant ist (siehe ADR-042 für die Abgrenzung).
signal broadcast_event_received(kind: String, payload: Dictionary)

## ADR-043: gezielte Zustellung EINER Chat-Nachricht (nur "whisper" — der
## "global"-Kanal läuft über broadcast_event_received/ADR-042, nicht über
## dieses Signal). `payload` hat dasselbe Format wie beim Broadcast-Pfad
## (message_id, sender_player_id, channel, text, target_player_id,
## timestamp_unix) — ChatService verarbeitet beide Quellen identisch.
signal chat_message_received(payload: Dictionary)

## ADR-046: gezielte Achievement-Unlock-Benachrichtigung. Analog
## chat_message_received (whisper) — Autorität→EINEN-Ziel-Spieler, kein
## Broadcast (ein Unlock ist fachlich privat zum jeweiligen Spieler). Kein
## Gegenstück für eine Client→Autorität-Anfrage — Achievements werden
## ausschließlich durch autoritative Spiel-Logik ausgelöst
## (AchievementService.grant_progress()), nie durch einen Client-Request.
signal achievement_unlocked_received(payload: Dictionary)

## Round 103 (ADR-046): Antwort auf eine Achievement-Snapshot-Anfrage.
## payload enthält {"unlocked": Array[String], "progress": Dictionary} —
## siehe AchievementService.on_snapshot_requested().
signal achievement_snapshot_received(payload: Dictionary)

## Round 106 (ADR-048): gezielte Zustellung des Charaktererstellungs-
## Ergebnisses an den anfragenden Spieler — Gegenstück zu
## send_character_creation_completed_for_player()/
## send_character_creation_skipped_for_player(). Analog
## achievement_unlocked_received.
signal character_creation_completed_received(payload: Dictionary)
signal character_creation_skipped_received(payload: Dictionary)
## Aussehen-Editor: Rückkanal nach send_character_set_look() — payload enthält
## {"look": Dictionary}. Analog character_creation_completed_received.
signal character_look_updated_received(payload: Dictionary)

## Round 107 (ADR-049): gezielte Zustellung einer Wiki-Entdeckung an den
## betroffenen Spieler — Gegenstück zu
## send_wiki_entry_discovered_for_player(). Analog achievement_unlocked_received.
signal wiki_entry_discovered_received(payload: Dictionary)
## Round 107 (ADR-049): Antwort auf eine Wiki-Snapshot-Anfrage. payload ist
## { category: String -> Array[String] } — siehe WikiService.on_snapshot_requested().
signal wiki_snapshot_received(payload: Dictionary)

# ─────────────────────────────────────────────
# Phase 4: Configure
# ─────────────────────────────────────────────

func configure(deps: ServiceDeps) -> void:
	_inventory     = deps.get_optional(ServiceKeys.INVENTORY)      as InventorySystem
	_quest         = deps.get_optional(ServiceKeys.QUEST)          as QuestService
	_skill_system  = deps.get_optional(ServiceKeys.SKILL_SYSTEM)   as SkillSystem
	_player_states = deps.get_optional(ServiceKeys.PLAYER_STATES)  as PlayerStateService
	_equipment     = deps.get_optional(ServiceKeys.EQUIPMENT)      as EquipmentService
	_shop          = deps.get_optional(ServiceKeys.SHOP)           as ShopService
	_smithing      = deps.get_optional(ServiceKeys.SMITHING)       as SmithingService
	_bank          = deps.get_optional(ServiceKeys.BANK)           as BankService
	_trade         = deps.get_optional(ServiceKeys.TRADE)          as TradeService
	_auction       = deps.get_optional(ServiceKeys.AUCTION_HOUSE)  as AuctionHouseService
	_item_protection = deps.get_optional(ServiceKeys.ITEM_PROTECTION) as ItemProtectionService
	_aura            = deps.get_optional(ServiceKeys.AURA)            as AuraService
	_pickpocket      = deps.get_optional(ServiceKeys.PICKPOCKET)      as PickpocketService
	_chat            = deps.get_optional(ServiceKeys.CHAT)            as ChatService
	_report          = deps.get_optional(ServiceKeys.REPORT)          as ReportService
	_achievement     = deps.get_optional(ServiceKeys.ACHIEVEMENT)     as AchievementService
	_wiki            = deps.get_optional(ServiceKeys.WIKI)            as WikiService
	_character_creation = deps.get_optional(ServiceKeys.CHARACTER_CREATION) as CharacterCreationService
	## ADR-030: einseitige Kante Network -> Zone (siehe BootstrapConfig.tres-
	## Kommentar bei network_bridge/zone_service) — Umkehrung (ZoneService.
	## inject_network_bridge()) läuft über Phase C8 Late-Inject, nicht configure().
	_zone_service  = deps.get_optional(ServiceKeys.ZONE_SERVICE)   as ZoneService
	_save_system   = deps.get_optional(ServiceKeys.SAVE_SYSTEM)    as SaveSystem
	_session_manager = deps.get_optional(ServiceKeys.SESSION_MANAGER) as SessionManager
	_world           = deps.get_optional(ServiceKeys.WORLD)           as WorldService
	if not is_instance_valid(_world):
		AppLogger.log_warn(
			"WorldService fehlt in deps — _rpc_request_entity_interaction() kann nicht auflösen.",
			LOG_CAT
		)
	if not is_instance_valid(_session_manager):
		AppLogger.log_warn(
			"SessionManager fehlt in deps — get_local_peer_id() fällt auf Tier-1-Default (1) zurück.",
			LOG_CAT
		)
	AppLogger.log_info("NetworkBridge konfiguriert.", LOG_CAT)

func on_ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	var peer_set := _has_peer()
	AppLogger.log_info("NetworkBridge bereit. Peer gesetzt: %s" % str(peer_set), LOG_CAT)

func on_cleanup() -> void:
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)
	if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)
	close()
	_rate_limit_state.clear()
	AppLogger.log_info("NetworkBridge cleanup.", LOG_CAT)

# ─────────────────────────────────────────────
# Host / Join API (Phase 4)
# ─────────────────────────────────────────────

## Startet einen ENet-Host auf dem angegebenen Port.
## Gibt true zurück wenn erfolgreich.
func host_game(port: int = DEFAULT_PORT, max_clients: int = MAX_CLIENTS) -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_clients)
	if err != OK:
		AppLogger.log_error("host_game(): create_server(%d) fehlgeschlagen: %s" % [port, error_string(err)], LOG_CAT)
		return false
	multiplayer.multiplayer_peer = peer
	AppLogger.log_info("Host gestartet auf Port %d (max. %d Clients)." % [port, max_clients], LOG_CAT)
	return true

## Verbindet als Client mit einem Host.
## Gibt true zurück wenn die Verbindung eingeleitet wurde (nicht: wenn sie fertig ist).
func join_game(address: String, port: int = DEFAULT_PORT) -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		AppLogger.log_error("join_game(): create_client(%s:%d) fehlgeschlagen: %s" % [address, port, error_string(err)], LOG_CAT)
		return false
	multiplayer.multiplayer_peer = peer
	AppLogger.log_info("Verbindung zu %s:%d eingeleitet." % [address, port], LOG_CAT)
	return true

## Trennt den Peer und setzt ihn zurück auf Tier 1 (Solo).
func close() -> void:
	if _has_peer():
		multiplayer.multiplayer_peer = null
		AppLogger.log_info("Multiplayer-Peer geschlossen — zurück zu Tier 1.", LOG_CAT)

func is_server() -> bool:
	return not _has_peer() or multiplayer.is_server()

## Delegiert an SessionManager — die einzige Stelle im Projekt, die peer_id
## berechnet (ADR-017). Fällt nur auf den Tier-1-Default zurück, wenn
## SessionManager nicht injiziert wurde (z.B. in isolierten Unit-Tests, die
## NetworkBridge ohne vollen Boot-Pipeline-Lauf instanziieren).
func get_local_peer_id() -> int:
	if is_instance_valid(_session_manager):
		return _session_manager.get_local_peer_id()
	return 1

## ADR-029 Plan-Schritt 4: dieselbe Fassade wie get_local_peer_id(), nur für
## die stabile player_id statt der Routing-peer_id. Migrierte Services (bisher:
## InventorySystem) fragen das statt SessionManager selbst zu halten — genau
## das Muster, das get_local_peer_id() für ADR-015 schon etabliert hat.
func get_local_player_id() -> String:
	if is_instance_valid(_session_manager):
		return _session_manager.get_local_player_id()
	return ""

## Fassade für SessionManager.get_player_id_for_peer() — dieselbe Begründung
## wie get_local_peer_id(): Services sollen SessionManager nicht selbst als
## Dep halten müssen, wenn sie ohnehin schon NetworkBridge injiziert bekommen.
## Leerer String wenn kein SessionManager verfügbar ODER die peer_id (noch)
## keinen Slot hat — Aufrufer müssen das prüfen, kein stiller Platzhalter.
func get_player_id_for_peer(peer_id: int) -> String:
	if is_instance_valid(_session_manager):
		return _session_manager.get_player_id_for_peer(peer_id)
	return ""

## Fassade für SessionManager.get_peer_id_for_player() — Rückwärts-Auflösung,
## gebraucht von send_economy_update_for_player() für das rpc_id()-Routing.
## -1 wenn kein SessionManager verfügbar ODER player_id keinem Peer zugeordnet.
func get_peer_id_for_player(player_id: String) -> int:
	if is_instance_valid(_session_manager):
		return _session_manager.get_peer_id_for_player(player_id)
	return -1

## ADR-042: Fassade für SessionManager.get_all_slots().keys() — die Menge der
## peer_ids, die den Join-Handshake bereits abgeschlossen haben (nicht
## dasselbe wie multiplayer.get_peers(), das auch frisch verbundene, noch
## nicht eingeloggte ENet-Peers enthält — siehe _on_peer_connected()-Kommentar
## "Client hat noch keine Session gebootet"). broadcast_to_all_peers() nutzt
## das statt der rohen ENet-Peerliste, um denselben Boot-Race-Guard zu
## bekommen, den _rpc_client_requests_initial_state() bereits für den
## Einzel-Snapshot hat. Leeres Array wenn kein SessionManager verfügbar.
func get_all_joined_peer_ids() -> Array[int]:
	var result: Array[int] = []
	if is_instance_valid(_session_manager):
		for peer_id in _session_manager.get_all_slots().keys():
			result.append(peer_id as int)
	return result

# ─────────────────────────────────────────────
# RPC-Routing-Helfer (genutzt von Services)
# ─────────────────────────────────────────────

## Gibt true zurück wenn ein Peer gesetzt ist (Tier 2/3).
## Services rufen das ab um zu entscheiden ob sie rpc_id() oder direkt aufrufen.
func has_peer() -> bool:
	return _has_peer()

## Sendet einen PlayerState-Wechsel an die Autorität.
func send_set_state(state: int) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_set_state", state)
	else:
		if is_instance_valid(_player_states):
			_player_states.set_state(state as PlayerStateService.State, get_local_peer_id())

## Sendet eine Quest-Start-Anfrage an die Autorität.
## ADR-029 Round 64: QuestService.on_quest_start_confirmed() erwartet jetzt
## player_id: String — get_local_player_id() statt hartcodierter 1.
func send_start_quest(quest_id: String) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_start_quest", quest_id)
	else:
		if is_instance_valid(_quest):
			_quest.on_quest_start_confirmed(quest_id, get_local_player_id())

## Sendet eine Quest-Complete-Anfrage an die Autorität.
func send_complete_quest(quest_id: String) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_complete_quest", quest_id)
	else:
		if is_instance_valid(_quest):
			_quest.on_quest_complete_confirmed(quest_id, get_local_player_id())

## ADR-020: Meldet der Autorität eine abgeschlossene Interaktion mit einer
## konkreten Entity. Nur der Client-seitige "Absicht"-Teil — die eigentliche
## Wirkung (Loot/Despawn/Fangen/Schaden) läuft ausschließlich auf der Autorität
## über WorldService.resolve_and_dispatch_interaction(). Wird ausschließlich von
## WorldService.request_entity_interaction() aufgerufen (nie direkt von Entities —
## siehe ADR-017, Entities kennen NetworkBridge nicht).
##
## Bewusst KEINE Reichweite/Position als Parameter — die Autorität liest die
## erlaubte Reichweite aus ihrer eigenen Kopie der Entity (siehe
## WorldService._max_interaction_range_for()), nie aus einem client-gemeldeten
## Wert, sonst wäre die Plausibilitätsprüfung in resolve_for_player() (ADR-023)
## wertlos.
## [param actor_uuid] Bugfix 2026-09-26 ("Pets können Ressourcen manchmal nicht
## abbauen"): optional die UUID der Entity, ab der die Autorität die Reichweite
## messen soll, falls NICHT der Besitzer-Spieler selbst handelt (z.B. sein Pet,
## siehe PetAbilityComponent). Wahrt dasselbe Prinzip wie oben — zeigt auf eine
## bereits serverseitig registrierte, eigene Position tragende Entity, NIE eine
## roh vom Client übertragene Position. Leer (Default) = unverändertes Verhalten.
func send_entity_interaction(entity_uuid: String, action_id: String, actor_uuid: String = "") -> void:
	rpc_id(1, "_rpc_request_entity_interaction", entity_uuid, action_id, actor_uuid)

## C-03: Sendet eine Equip-Anfrage an die Autorität.
## [param item_id] Item-ID aus DataService — kein ItemDefinition über das Netz.
## ADR-029 Round 66: player_id jetzt String, Pflichtparameter ohne Default —
## EquipmentService.request_equip() übergibt jetzt die stabile player_id.
func send_equip_item(slot: String, item_id: String, player_id: String) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_equip_item", slot, item_id)
	else:
		if is_instance_valid(_equipment):
			_equipment.on_equip_confirmed(slot, item_id, player_id)

## Round 88: Sendet eine Kauf-Anfrage (Shop-NPC) an die Autorität.
func send_shop_buy_item(item_id: String, quantity: int, player_id: String) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_shop_buy_item", item_id, quantity)
	else:
		if is_instance_valid(_shop):
			_shop.on_buy_confirmed(item_id, quantity, player_id)

## Schmelzen & Schmieden: Sendet eine Herstell-Anfrage (Rezept-Id + Anzahl Durchläufe) an die
## Autorität. Die Station steht bewusst NICHT in der Anfrage — SmithingService liest sie aus dem
## Rezept und prüft serverseitig den Stations-Zugang (siehe dortiger Klassenkommentar).
func send_smithing_craft(recipe_id: String, quantity: int, player_id: String) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_smithing_craft", recipe_id, quantity)
	else:
		if is_instance_valid(_smithing):
			_smithing.on_craft_confirmed(recipe_id, quantity, player_id)

## Round 88: Sendet eine Verkauf-Anfrage (Shop-NPC) an die Autorität.
func send_shop_sell_item(item_id: String, quantity: int, player_id: String) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_shop_sell_item", item_id, quantity)
	else:
		if is_instance_valid(_shop):
			_shop.on_sell_confirmed(item_id, quantity, player_id)

## ADR-034: Sendet eine Bank-Einzahlung (Item) an die Autorität.
func send_bank_deposit_item(item_id: String, quantity: int, player_id: String) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_bank_deposit_item", item_id, quantity)
	else:
		if is_instance_valid(_bank):
			_bank.on_deposit_item_confirmed(item_id, quantity, player_id)

## ADR-034: Sendet eine Bank-Abhebung (Item) an die Autorität.
func send_bank_withdraw_item(item_id: String, quantity: int, player_id: String) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_bank_withdraw_item", item_id, quantity)
	else:
		if is_instance_valid(_bank):
			_bank.on_withdraw_item_confirmed(item_id, quantity, player_id)

## ADR-038: Sendet eine Schutz-Anwendung (Scroll auf Item) an die Autorität.
func send_item_protection_apply(scroll_item_id: String, target_item_id: String, player_id: String) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_item_protection_apply", scroll_item_id, target_item_id)
	else:
		if is_instance_valid(_item_protection):
			_item_protection.on_apply_protection_confirmed(scroll_item_id, target_item_id, player_id)

## ADR-036: Sendet eine "Danken"-Interaktion (Aura) an die Autorität.
## from_player_id wird NICHT über das Netz geschickt (siehe
## _rpc_aura_thank()-Kommentar) — nur im Solo-/Server-Tier-1-Zweig direkt
## verwendet, wo Client und Autorität derselbe Prozess sind.
func send_aura_thank(from_player_id: String, to_player_id: String) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_aura_thank", to_player_id)
	else:
		if is_instance_valid(_aura):
			_aura.on_thank_confirmed(from_player_id, to_player_id)

## ADR-039: Sendet einen Pickpocket-Versuch an die Autorität. thief_player_id
## wird — analog from_player_id bei send_aura_thank() — NICHT über das Netz
## geschickt, aus demselben Fälschungs-Grund (ein Client könnte sich sonst
## als anderer Spieler ausgeben).
func send_pickpocket_attempt(crystal_item_id: String, victim_player_id: String, thief_player_id: String) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_pickpocket_attempt", crystal_item_id, victim_player_id)
	else:
		if is_instance_valid(_pickpocket):
			_pickpocket.on_pickpocket_confirmed(thief_player_id, victim_player_id, crystal_item_id)

## ADR-039: pusht eine Pickpocket-Systemnachricht ("wurdest bestohlen"/
## "Diebstahlversuch") an genau das betroffene Opfer — Gegenstück zu
## send_zone_update_for_peer(), aber player_id-basiert wie
## send_economy_update_for_player() (PickpocketService führt player_id
## nativ, nicht peer_id).
func send_pickpocket_notification_for_player(player_id: String, text: String) -> void:
	if not _has_peer() or not multiplayer.is_server():
		return
	if player_id == get_local_player_id():
		return
	var target_peer := get_peer_id_for_player(player_id)
	if target_peer == -1:
		AppLogger.log_debug(
			"send_pickpocket_notification_for_player(): player_id '%s' aktuell keinem Peer zugeordnet — übersprungen." % player_id,
			LOG_CAT
		)
		return
	rpc_id(target_peer, "_rpc_receive_pickpocket_notification", text)

## ADR-034: Sendet eine Bank-Einzahlung (Gold) an die Autorität.
func send_bank_deposit_gold(amount: int, player_id: String) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_bank_deposit_gold", amount)
	else:
		if is_instance_valid(_bank):
			_bank.on_deposit_gold_confirmed(amount, player_id)

## ADR-034: Sendet eine Bank-Abhebung (Gold) an die Autorität.
func send_bank_withdraw_gold(amount: int, player_id: String) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_bank_withdraw_gold", amount)
	else:
		if is_instance_valid(_bank):
			_bank.on_withdraw_gold_confirmed(amount, player_id)

## ADR-035: Antwort auf eine Handelseinladung (annehmen/ablehnen) an die Autorität.
func send_trade_respond_invite(accept: bool, player_id: String) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_trade_respond_invite", accept)
	else:
		if is_instance_valid(_trade):
			_trade.on_invite_response_confirmed(player_id, accept)

## ADR-035: Angebots-Änderung in einer Handels-Session an die Autorität.
func send_trade_update_offer(session_id: String, items: Dictionary, gold: int, player_id: String) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_trade_update_offer", session_id, items, gold)
	else:
		if is_instance_valid(_trade):
			_trade.on_offer_updated_confirmed(player_id, session_id, items, gold)

## ADR-035: Ready-Markierung in einer Handels-Session an die Autorität.
func send_trade_set_ready(session_id: String, ready: bool, player_id: String) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_trade_set_ready", session_id, ready)
	else:
		if is_instance_valid(_trade):
			_trade.on_ready_confirmed(player_id, session_id, ready)

## ADR-035: Finale Bestätigung in einer Handels-Session an die Autorität.
func send_trade_set_confirmed(session_id: String, confirmed: bool, player_id: String) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_trade_set_confirmed", session_id, confirmed)
	else:
		if is_instance_valid(_trade):
			_trade.on_confirm_confirmed(player_id, session_id, confirmed)

## ADR-035: Abbruch einer Handels-Session an die Autorität.
func send_trade_cancel(session_id: String, player_id: String) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_trade_cancel", session_id)
	else:
		if is_instance_valid(_trade):
			_trade.on_cancel_confirmed(player_id, session_id)

## ADR-035: Auktionshaus-Listing erstellen, an die Autorität.
func send_auction_list_item(item_id: String, quantity: int, price: int, player_id: String) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_auction_list_item", item_id, quantity, price)
	else:
		if is_instance_valid(_auction):
			_auction.on_list_item_confirmed(player_id, item_id, quantity, price)

## ADR-035: Auktionshaus-Kauf, an die Autorität.
func send_auction_buy_item(listing_id: String, player_id: String) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_auction_buy_item", listing_id)
	else:
		if is_instance_valid(_auction):
			_auction.on_buy_confirmed(player_id, listing_id)

## ADR-035: Auktionshaus-Listing stornieren, an die Autorität.
func send_auction_cancel_listing(listing_id: String, player_id: String) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_auction_cancel_listing", listing_id)
	else:
		if is_instance_valid(_auction):
			_auction.on_cancel_listing_confirmed(player_id, listing_id)

## ADR-035: Snapshot aller aktiven Listings anfordern (Pull statt Push — siehe
## AuctionHouseService-Klassenkommentar zur bewusst fehlenden Live-Broadcast).
func send_auction_request_snapshot(player_id: String) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_auction_request_snapshot")
	else:
		if is_instance_valid(_auction):
			_auction.request_listings_snapshot(player_id)

## ADR-043: Chat-Nachricht senden, an die Autorität. player_id NUR für den
## Tier-1/lokalen-Autoritäts-Pfad relevant — über das RPC wird die Identität
## NIE vom Client übernommen, sondern serverseitig aus dem RPC-Sender
## aufgelöst (_sender_as_player_uuid() in _rpc_chat_send_message()), exakt
## dieselbe Sicherheitsanforderung wie bei allen anderen "any_peer"-RPCs
## hier (siehe ADR-021).
func send_chat_message(channel: String, text: String, target_player_id: String, player_id: String) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_chat_send_message", channel, text, target_player_id)
	else:
		if is_instance_valid(_chat):
			_chat.on_send_message_confirmed(player_id, channel, text, target_player_id)

## ADR-043: gezielte Chat-Zustellung (nur "whisper" — "global" läuft über
## broadcast_to_all_peers(), ADR-042). Dasselbe Guard-/Skip-Local-Muster wie
## send_economy_update_for_player()/send_zone_update_for_peer().
func send_chat_message_for_player(player_id: String, payload: Dictionary) -> void:
	if not _has_peer() or not multiplayer.is_server():
		return
	var peer_id := get_peer_id_for_player(player_id)
	if peer_id == -1 or peer_id == get_local_peer_id():
		return
	rpc_id(peer_id, "_rpc_receive_chat_message", payload)

## ADR-044: Meldung an die Autorität senden. Reine Client→Autorität-Richtung
## — es gibt bewusst KEIN Gegenstück für eine Zustellung an andere Spieler
## (Meldungen sind nie für andere Spieler sichtbar, nur für die Autorität
## selbst, siehe ReportService-Klassenkommentar). reporter_player_id NUR für
## den Tier-1/lokalen-Autoritäts-Pfad relevant — über RPC wird die Identität
## wie überall hier serverseitig aus dem RPC-Sender aufgelöst.
func send_report_submit(reported_player_id: String, reason: String, details: String, context: Dictionary, reporter_player_id: String) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_report_submit", reported_player_id, reason, details, context)
	else:
		if is_instance_valid(_report):
			_report.on_submit_report_confirmed(reporter_player_id, reported_player_id, reason, details, context)

## ADR-046: gezielte Achievement-Unlock-Zustellung. Reine
## Autorität→Ziel-Spieler-Richtung, KEIN Tier-1-Fallback-Zweig nötig (im
## Unterschied zu send_chat_message()/send_report_submit()) — es gibt
## keinen Client-Request, den diese Funktion stellvertretend lokal
## ausführen müsste. Die lokale Benachrichtigung des Host-Spielers passiert
## bereits direkt über AchievementService.achievement_unlocked, BEVOR diese
## Funktion überhaupt aufgerufen wird — dasselbe Guard-/Skip-Local-Muster
## wie send_chat_message_for_player()/send_economy_update_for_player().
func send_achievement_unlocked_for_player(player_id: String, payload: Dictionary) -> void:
	if not _has_peer() or not multiplayer.is_server():
		return
	var peer_id := get_peer_id_for_player(player_id)
	if peer_id == -1 or peer_id == get_local_peer_id():
		return
	rpc_id(peer_id, "_rpc_receive_achievement_unlocked", payload)

## ADR-046 (Round 103): Achievement-Snapshot anfragen (Client→Autorität),
## reine Pull-Anfrage — analog send_auction_request_snapshot(). player_id
## NUR für den Tier-1/lokalen-Autoritäts-Pfad relevant, über RPC wird die
## Identität serverseitig aus dem RPC-Sender aufgelöst.
func send_achievement_snapshot_request(player_id: String) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_achievement_snapshot_request")
	else:
		if is_instance_valid(_achievement):
			_achievement.on_snapshot_requested(player_id)

## Easter-Egg-Achievements (siehe AchievementService.gd-Klassenkommentar
## "EASTER EGGS"): Client meldet eine rein lokal beobachtbare Bedingung
## (Kamera-Blickrichtung/-Zoom, Partikel-Sichtdauer) — anders als
## movement_stats_batch gibt es hier KEINE serverseitige Ground-Truth, der
## Server muss dem Client zwangsläufig glauben. AchievementService.
## on_client_observed_achievement() begrenzt den Schaden per Whitelist
## (CLIENT_REPORTABLE_ACHIEVEMENTS) auf genau diese wenigen, bewusst niedrig
## dotierten Achievements. player_id NUR für den Tier-1/lokalen-Autoritäts-
## Pfad relevant, über RPC wird die Identität serverseitig aus dem
## RPC-Sender aufgelöst (analog send_achievement_snapshot_request()).
func send_client_observed_achievement(player_id: String, achievement_id: String) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_client_observed_achievement", achievement_id)
	else:
		if is_instance_valid(_achievement):
			_achievement.on_client_observed_achievement(player_id, achievement_id)

## ADR-046 (Round 103): gezielte Zustellung des angeforderten Snapshots
## (Autorität→Ziel-Spieler) — dasselbe Guard-/Skip-Local-Muster wie
## send_achievement_unlocked_for_player().
func send_achievement_snapshot_for_player(player_id: String, payload: Dictionary) -> void:
	if not _has_peer() or not multiplayer.is_server():
		return
	var peer_id := get_peer_id_for_player(player_id)
	if peer_id == -1 or peer_id == get_local_peer_id():
		return
	rpc_id(peer_id, "_rpc_receive_achievement_snapshot", payload)

## Round 106 (ADR-048): Charaktererstellung an die Autorität senden
## (Client→Autorität), reine Anfrage — analog send_report_submit(). player_id
## NUR für den Tier-1/lokalen-Autoritäts-Pfad relevant, über RPC wird die
## Identität serverseitig aus dem RPC-Sender aufgelöst.
func send_character_creation_submit_answers(player_id: String, answers: Dictionary) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_character_creation_submit_answers", answers)
	else:
		if is_instance_valid(_character_creation):
			_character_creation.on_submit_answers_confirmed(player_id, answers)

## Round 106 (ADR-048): analog send_character_creation_submit_answers().
func send_character_creation_skip(player_id: String) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_character_creation_skip")
	else:
		if is_instance_valid(_character_creation):
			_character_creation.on_skip_creation_confirmed(player_id)

## Aussehen-Editor (ADR-048): Look an die Autorität senden (Client→Autorität),
## reine Anfrage — analog send_character_creation_submit_answers(). Der Look
## wird serverseitig in CharacterCreationService.on_set_look_confirmed()
## sanitisiert; der Client kann nur gültige Katalog-IDs setzen.
func send_character_set_look(player_id: String, look: Dictionary) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_character_set_look", look)
	else:
		if is_instance_valid(_character_creation):
			_character_creation.on_set_look_confirmed(player_id, look)

## Aussehen-Editor (ADR-048): gezielte Zustellung des bestätigten Looks an den
## anfragenden Spieler — Guard-/Skip-Local-Muster wie
## send_character_creation_completed_for_player().
func send_character_look_updated_for_player(player_id: String, payload: Dictionary) -> void:
	if not _has_peer() or not multiplayer.is_server():
		return
	var peer_id := get_peer_id_for_player(player_id)
	if peer_id == -1 or peer_id == get_local_peer_id():
		return
	rpc_id(peer_id, "_rpc_receive_character_look_updated", payload)

## Round 106 (ADR-048): gezielte Ergebniszustellung (Autorität→anfragender
## Spieler) — dasselbe Guard-/Skip-Local-Muster wie
## send_achievement_unlocked_for_player(). Ohne dieses Gegenstück bekäme ein
## Nicht-Host-Client sein eigenes Aussehen nie zurück.
func send_character_creation_completed_for_player(player_id: String, payload: Dictionary) -> void:
	if not _has_peer() or not multiplayer.is_server():
		return
	var peer_id := get_peer_id_for_player(player_id)
	if peer_id == -1 or peer_id == get_local_peer_id():
		return
	rpc_id(peer_id, "_rpc_receive_character_creation_completed", payload)

## Round 107 (ADR-049): gezielte Wiki-Entdeckungs-Zustellung. Reine
## Autorität→Ziel-Spieler-Richtung, KEIN Tier-1-Fallback-Zweig nötig —
## dasselbe Argument wie send_achievement_unlocked_for_player(): kein
## Client-Request, den diese Funktion stellvertretend lokal ausführen
## müsste. NIE an einen anderen Spieler als player_id selbst — das ist die
## technische Umsetzung von "pro Spieler lokal" (ADR-049 "SCOPING").
func send_wiki_entry_discovered_for_player(player_id: String, payload: Dictionary) -> void:
	if not _has_peer() or not multiplayer.is_server():
		return
	var peer_id := get_peer_id_for_player(player_id)
	if peer_id == -1 or peer_id == get_local_peer_id():
		return
	rpc_id(peer_id, "_rpc_receive_wiki_entry_discovered", payload)

## Round 107 (ADR-049): Wiki-Snapshot anfragen (Client→Autorität), reine
## Pull-Anfrage — analog send_achievement_snapshot_request().
func send_wiki_snapshot_request(player_id: String) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_wiki_snapshot_request")
	else:
		if is_instance_valid(_wiki):
			_wiki.on_snapshot_requested(player_id)

## Round 107 (ADR-049): gezielte Zustellung des angeforderten Wiki-
## Snapshots — dasselbe Guard-/Skip-Local-Muster wie
## send_achievement_snapshot_for_player().
func send_wiki_snapshot_for_player(player_id: String, payload: Dictionary) -> void:
	if not _has_peer() or not multiplayer.is_server():
		return
	var peer_id := get_peer_id_for_player(player_id)
	if peer_id == -1 or peer_id == get_local_peer_id():
		return
	rpc_id(peer_id, "_rpc_receive_wiki_snapshot", payload)

## Round 106 (ADR-048): analog send_character_creation_completed_for_player().
func send_character_creation_skipped_for_player(player_id: String, payload: Dictionary) -> void:
	if not _has_peer() or not multiplayer.is_server():
		return
	var peer_id := get_peer_id_for_player(player_id)
	if peer_id == -1 or peer_id == get_local_peer_id():
		return
	rpc_id(peer_id, "_rpc_receive_character_creation_skipped", payload)

## C-03: Sendet eine Unequip-Anfrage an die Autorität.
## ADR-029 Round 66: player_id jetzt String, Pflichtparameter ohne Default.
func send_unequip_item(slot: String, player_id: String) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_unequip_item", slot)
	else:
		if is_instance_valid(_equipment):
			_equipment.on_unequip_confirmed(slot, player_id)

## ADR-021 (R-5), Option C: generischer Kanal statt eines eigenen `_rpc_*`-Paars
## pro Quest-Trigger-Signal. `event_name`/`payload` sind Nutzdaten (welches
## Ereignis, welche IDs) — unkritisch, weil `on_quest_complete_confirmed()`
## (SEC-03) den tatsächlichen Quest-Abschluss ohnehin serverseitig gegen den
## getrackten Fortschritt re-validiert, nie dem Trigger-Ereignis selbst vertraut.
## `peer_id` ist NUR für den Tier-1-Pfad relevant (kein Peer → kein anderer
## Absender möglich, der ihn fälschen könnte). Im Tier-2/3-RPC-Pfad wird er
## verworfen — `_rpc_report_domain_event()` ermittelt ihn serverseitig aus dem
## RPC-Sender, nie aus dem Client-Payload (Sicherheitsanforderung, siehe ADR-021 —
## derselbe Fehler wie beim inzwischen entfernten `_rpc_add_item`/`_rpc_add_xp`
## darf hier nicht wieder einziehen).
func report_domain_event(event_name: String, payload: Dictionary, peer_id: int = 1) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_report_domain_event", event_name, payload)
	else:
		domain_event_received.emit(event_name, payload, peer_id)

## ADR-029 Plan-Schritt 4: String-Pendant zu send_economy_update() (int) —
## letzteres ist seit Round 66 (EquipmentService migriert, letzter der drei
## ursprünglichen Aufrufer InventorySystem/SkillSystem/EquipmentService)
## entfernt, da vollständig unbenutzt. Braucht trotzdem die tatsächliche
## peer_id für rpc_id() — ENet routet ausschließlich über Verbindungs-IDs,
## keine player_uuids (ADR-015 bleibt für den Transport-Teil zuständig) —
## deshalb die Rückwärts-Auflösung über SessionManager.get_peer_id_for_player()
## statt eines eigenen Transport-Wegs.
##
## Kein Aufruf wenn: kein Peer (Tier 1), dieser Prozess nicht Autorität, das
## Ziel der lokale Spieler selbst ist (die Autorität hat ihre eigene Kopie
## bereits direkt mutiert, kein Rundweg über RPC nötig), oder das Ziel gerade
## an keinen verbundenen Peer aufgelöst werden kann (Spieler offline — nichts
## zu synchronisieren, kein Fehler).
func send_economy_update_for_player(player_id: String, kind: String, payload: Dictionary) -> void:
	if not _has_peer() or not multiplayer.is_server():
		return
	if player_id == get_local_player_id():
		return
	var target_peer := get_peer_id_for_player(player_id)
	if target_peer == -1:
		AppLogger.log_debug(
			"send_economy_update_for_player(): player_id '%s' aktuell keinem Peer zugeordnet — übersprungen." % player_id,
			LOG_CAT
		)
		return
	rpc_id(target_peer, "_rpc_receive_economy_update", kind, payload)

## ADR-030: pusht eine Zonen-Mitgliedschaftsänderung an genau den betroffenen
## Client — Gegenstück zu send_economy_update_for_player(), aber peer_id-
## direkt statt player_id→peer_id-Rückübersetzung (ZoneService führt ohnehin
## schon peer_id nativ, siehe dortiger Klassenkommentar/Abgrenzung zu ADR-029).
##
## Kein Aufruf wenn: kein Peer (Tier 1), dieser Prozess nicht Autorität, oder
## das Ziel der lokale Spieler selbst ist (die Autorität hat ihre eigene
## ZoneService-Kopie bereits direkt mutiert, kein Rundweg über RPC nötig) —
## bewusst UNBEDINGT aus ZoneService.report_enter()/report_exit() aufgerufen,
## dieser Guard hier übernimmt die Filterung.
func send_zone_update_for_peer(peer_id: int, zone_id: StringName, entered: bool) -> void:
	if not _has_peer() or not multiplayer.is_server():
		return
	if peer_id == get_local_peer_id():
		return
	rpc_id(peer_id, "_rpc_receive_zone_update", String(zone_id), entered)

## ADR-042: generischer "an alle aktuell verbundenen Spieler"-Broadcast-Kanal.
## Erster Aufrufer der seit ADR-035/ADR-041 als fehlend dokumentierten Lücke
## ("das Projekt hat aktuell keinen an-alle-Peers-Broadcast-Mechanismus").
##
## Bewusst KEIN Ersatz für send_economy_update_for_player()/
## send_zone_update_for_peer() — diese bleiben die richtige Wahl, wenn genau
## EIN Spieler das Ziel ist. broadcast_to_all_peers() ist nur für Nachrichten
## gedacht, die für jeden aktuell verbundenen Spieler gleichermaßen gelten
## (z.B. ein künftiges "auction_listing_changed" aus dem in ADR-035
## zurückgestellten Punkt).
##
## Iteriert bewusst über get_all_joined_peer_ids() statt multiplayer.get_peers()
## — letzteres würde auch Peers treffen, die zwar ENet-verbunden sind, aber
## ihren Join-Handshake (SessionManager._rpc_join_handshake) noch nicht
## abgeschlossen haben; ein RPC an so einen Peer liefe ins Leere, weil dessen
## Session noch nicht gebootet ist (derselbe Boot-Race-Grund, aus dem
## _on_peer_connected() auch keinen Snapshot direkt verschickt).
##
## Kein Aufruf wenn: kein Peer (Tier 1 — es gibt niemanden zum Broadcasten),
## oder dieser Prozess nicht Autorität ist. Die Autorität selbst NIMMT NICHT
## an ihrem eigenen Broadcast teil (sie hat ihren lokalen State bereits direkt
## mutiert, bevor sie broadcastet) — Aufrufer dürfen sich also nicht auf einen
## Rundweg über dieses RPC verlassen, um ihre eigene lokale Kopie zu
## aktualisieren.
##
## Absichtlich NICHT Teil dieser Runde: ein Sync-Pfad für Clients, die NACH
## dem Broadcast neu verbinden (die sehen den aktuellen Stand erst beim
## nächsten Broadcast) — jeder Konsument, der das braucht, muss seinen
## Zustand zusätzlich in den initialen State-Snapshot einhängen
## (_rpc_client_requests_initial_state()/SaveSystem.get_full_state()), analog
## zum bereits bestehenden Einzel-Sync-Pfad.
func broadcast_to_all_peers(kind: String, payload: Dictionary) -> void:
	if not _has_peer() or not multiplayer.is_server():
		return
	var local_peer := get_local_peer_id()
	for peer_id in get_all_joined_peer_ids():
		if peer_id == local_peer:
			continue
		rpc_id(peer_id, "_rpc_receive_broadcast_event", kind, payload)

## ADR-025: sendet einen Bewegungs-Input-Snapshot an die Autorität. Anders als
## jede andere send_*()-Methode hier KEIN reliable RPC (siehe NetworkContract.gd,
## Abschnitt UNRELIABLE) — 20+ Hz Rate, verlorene Pakete sind normal und werden
## vom nächsten Tick überholt.
##
## input_snapshot: {seq:int, move_vec:Vector2, camera_yaw:float,
##                  jump_requested:bool, delta:float}
## Enthält bewusst KEINEN move_speed/effective_speed-Wert — die Autorität löst
## das serverseitig über StatModifierService auf (s. Player.gd._apply_movement()),
## alles andere wäre eine Einladung zum Speed-Hack.
##
## Tier-1-Kollaps: ist dieser Prozess selbst die Autorität (Solo, kein Peer),
## läuft kein RPC — der Aufruf würde ohnehin nie in _loop_free_predicted()
## entstehen (dort läuft dann stattdessen _loop_free_authoritative() direkt,
## siehe Player.gd-Physics-Loop-Kommentar), diese Methode existiert nur der
## Vollständigkeit halber / gegen Fehlaufrufe defensiv.
func submit_movement_input(input_snapshot: Dictionary) -> void:
	if _has_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_submit_movement_input", input_snapshot)
	else:
		AppLogger.log_warn(
			"submit_movement_input() ohne Peer oder auf dem Server aufgerufen — sollte nie passieren (Autorität sendet sich nicht selbst Input).",
			LOG_CAT
		)

# ─────────────────────────────────────────────
# RPC-Empfangs-Methoden (laufen auf Autorität)
# ─────────────────────────────────────────────

## Bewusst KEIN `_rpc_add_item(item_id, qty)` / `_rpc_add_xp(skill_name, amount)` mehr
## (entfernt, vorher hier). Root-Cause-Analyse (TODO-offene-probleme.md, "Server
## validiert RPC-Werte nicht"): kein einziger legitimer Spielcode-Pfad sendet einen
## client-gewählten qty/amount-Wert übers Netz — Gathering/Combat-Reward läuft über
## InteractionResolver, Kill-Reward über EnemyNPC._die(), Quest-Reward über
## RewardDispatcher — alle drei ausschließlich hinter is_multiplayer_authority()-Guards
## und rufen InventorySystem.on_item_add_confirmed()/SkillSystem.on_xp_add_confirmed()
## bereits auf dem Autoritäts-Prozess selbst auf, nie per RPC. Ein `@rpc("any_peer")`
## das einen rohen Mengen-Wert entgegennimmt, ist deshalb keine validierbare
## Schnittstelle, sondern unbenutzte, aber trotzdem angreifbare Netzwerkfläche
## (Godots RPC-System prüft nicht, ob "ehrlicher" Code den Aufruf je senden würde).
## Entscheidung: Fläche entfernen statt nachträglich validieren (kein Shop/Crafting-
## Feature braucht das aktuell — siehe TODO "🟡 Trading / Item-Transfer"). Falls ein
## echtes Feature später einen client-initiierten Grant braucht, dann nach demselben
## Muster wie `send_entity_interaction()`: Client schickt nur eine Absicht/Referenz,
## Autorität löst Menge/Wert aus ihren eigenen Daten auf — nie ein roher Zahlenwert
## vom Client. Siehe ADR-020 "Umsetzungsstand (Round 45)".
@rpc("any_peer", "call_remote", "reliable")
func _rpc_start_quest(quest_id: String) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_start_quest", peer_id):
		return
	# ADR-029 Round 64: QuestService ist migriert — Aufruf braucht player_id
	# (String), Rate-Limiting bleibt aber an der peer_id (Verbindungs-Identität,
	# ADR-015), nicht an der stabilen player_id.
	var player_id := _sender_as_player_uuid()
	AppLogger.log_debug("RPC _rpc_start_quest von peer %d (player '%s'): %s" % [peer_id, player_id, quest_id], LOG_CAT)
	if is_instance_valid(_quest):
		_quest.on_quest_start_confirmed(quest_id, player_id)
	else:
		AppLogger.log_error("_rpc_start_quest: QuestService nicht verfügbar!", LOG_CAT)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_complete_quest(quest_id: String) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_complete_quest", peer_id):
		return
	var player_id := _sender_as_player_uuid()
	AppLogger.log_debug("RPC _rpc_complete_quest von peer %d (player '%s'): %s" % [peer_id, player_id, quest_id], LOG_CAT)
	if is_instance_valid(_quest):
		_quest.on_quest_complete_confirmed(quest_id, player_id)
	else:
		AppLogger.log_error("_rpc_complete_quest: QuestService nicht verfügbar!", LOG_CAT)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_state(state: int) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_set_state", peer_id):
		return
	if is_instance_valid(_player_states):
		_player_states.set_state(state as PlayerStateService.State, peer_id)
	else:
		AppLogger.log_error("_rpc_set_state: PlayerStateService nicht verfügbar!", LOG_CAT)

## C-03: RPC-Empfang für equip auf Autorität.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_equip_item(slot: String, item_id: String) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_equip_item", peer_id):
		return
	# ADR-029 Round 66: EquipmentService ist migriert — Aufruf braucht player_id
	# (String), Rate-Limiting bleibt aber an der peer_id (Verbindungs-Identität,
	# ADR-015), nicht an der stabilen player_id — identisches Muster zu
	# _rpc_start_quest()/_rpc_complete_quest() (Round 64).
	var player_id := _sender_as_player_uuid()
	AppLogger.log_debug("RPC _rpc_equip_item von peer %d (player '%s'): slot='%s' item='%s'" % [peer_id, player_id, slot, item_id], LOG_CAT)
	if is_instance_valid(_equipment):
		_equipment.on_equip_confirmed(slot, item_id, player_id)
	else:
		AppLogger.log_error("_rpc_equip_item: EquipmentService nicht verfügbar!", LOG_CAT)

## C-03: RPC-Empfang für unequip auf Autorität.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_unequip_item(slot: String) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_unequip_item", peer_id):
		return
	var player_id := _sender_as_player_uuid()
	AppLogger.log_debug("RPC _rpc_unequip_item von peer %d (player '%s'): slot='%s'" % [peer_id, player_id, slot], LOG_CAT)
	if is_instance_valid(_equipment):
		_equipment.on_unequip_confirmed(slot, player_id)
	else:
		AppLogger.log_error("_rpc_unequip_item: EquipmentService nicht verfügbar!", LOG_CAT)

## Round 88: RPC-Empfang für Shop-Kauf auf der Autorität.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_shop_buy_item(item_id: String, quantity: int) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_shop_buy_item", peer_id):
		return
	var player_id := _sender_as_player_uuid()
	AppLogger.log_debug("RPC _rpc_shop_buy_item von peer %d (player '%s'): item='%s' x%d" % [peer_id, player_id, item_id, quantity], LOG_CAT)
	if is_instance_valid(_shop):
		_shop.on_buy_confirmed(item_id, quantity, player_id)
	else:
		AppLogger.log_error("_rpc_shop_buy_item: ShopService nicht verfügbar!", LOG_CAT)

## Schmelzen & Schmieden: RPC-Empfang für eine Herstell-Anfrage auf der Autorität.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_smithing_craft(recipe_id: String, quantity: int) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_smithing_craft", peer_id):
		return
	var player_id := _sender_as_player_uuid()
	AppLogger.log_debug("RPC _rpc_smithing_craft von peer %d (player '%s'): recipe='%s' x%d" % [peer_id, player_id, recipe_id, quantity], LOG_CAT)
	if is_instance_valid(_smithing):
		_smithing.on_craft_confirmed(recipe_id, quantity, player_id)
	else:
		AppLogger.log_error("_rpc_smithing_craft: SmithingService nicht verfügbar!", LOG_CAT)

## Round 88: RPC-Empfang für Shop-Verkauf auf der Autorität.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_shop_sell_item(item_id: String, quantity: int) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_shop_sell_item", peer_id):
		return
	var player_id := _sender_as_player_uuid()
	AppLogger.log_debug("RPC _rpc_shop_sell_item von peer %d (player '%s'): item='%s' x%d" % [peer_id, player_id, item_id, quantity], LOG_CAT)
	if is_instance_valid(_shop):
		_shop.on_sell_confirmed(item_id, quantity, player_id)
	else:
		AppLogger.log_error("_rpc_shop_sell_item: ShopService nicht verfügbar!", LOG_CAT)

## ADR-034: RPC-Empfang für Bank-Einzahlung (Item) auf der Autorität.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_bank_deposit_item(item_id: String, quantity: int) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_bank_deposit_item", peer_id):
		return
	var player_id := _sender_as_player_uuid()
	if is_instance_valid(_bank):
		_bank.on_deposit_item_confirmed(item_id, quantity, player_id)
	else:
		AppLogger.log_error("_rpc_bank_deposit_item: BankService nicht verfügbar!", LOG_CAT)

## ADR-034: RPC-Empfang für Bank-Abhebung (Item) auf der Autorität.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_bank_withdraw_item(item_id: String, quantity: int) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_bank_withdraw_item", peer_id):
		return
	var player_id := _sender_as_player_uuid()
	if is_instance_valid(_bank):
		_bank.on_withdraw_item_confirmed(item_id, quantity, player_id)
	else:
		AppLogger.log_error("_rpc_bank_withdraw_item: BankService nicht verfügbar!", LOG_CAT)

## ADR-038: RPC-Empfang für Schutz-Anwendung (Scroll auf Item) auf der Autorität.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_item_protection_apply(scroll_item_id: String, target_item_id: String) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_item_protection_apply", peer_id):
		return
	var player_id := _sender_as_player_uuid()
	if is_instance_valid(_item_protection):
		_item_protection.on_apply_protection_confirmed(scroll_item_id, target_item_id, player_id)
	else:
		AppLogger.log_error("_rpc_item_protection_apply: ItemProtectionService nicht verfügbar!", LOG_CAT)

## ADR-036: RPC-Empfang für "Danken" auf der Autorität. from_player_id wird
## bewusst NICHT als Parameter entgegengenommen — analog _sender_as_player_uuid()
## bei den anderen RPCs hier: der Absender-Peer identifiziert sich selbst über
## die RPC-Verbindung, ein client-gesendeter "ich bin Spieler X"-Parameter
## wäre fälschbar (ein Spieler könnte sich für einen anderen ausgeben und so
## dessen Aura beliebig erhöhen).
@rpc("any_peer", "call_remote", "reliable")
func _rpc_aura_thank(to_player_id: String) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_aura_thank", peer_id):
		return
	var from_player_id := _sender_as_player_uuid()
	if is_instance_valid(_aura):
		_aura.on_thank_confirmed(from_player_id, to_player_id)
	else:
		AppLogger.log_error("_rpc_aura_thank: AuraService nicht verfügbar!", LOG_CAT)

## ADR-039: RPC-Empfang für einen Pickpocket-Versuch auf der Autorität.
## thief_player_id wird — analog _rpc_aura_thank() — bewusst NICHT als
## Parameter entgegengenommen, sondern über den Absender-Peer aufgelöst
## (Fälschungs-Vermeidung, siehe PickpocketService-Klassenkommentar).
@rpc("any_peer", "call_remote", "reliable")
func _rpc_pickpocket_attempt(crystal_item_id: String, victim_player_id: String) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_pickpocket_attempt", peer_id):
		return
	var thief_player_id := _sender_as_player_uuid()
	if is_instance_valid(_pickpocket):
		_pickpocket.on_pickpocket_confirmed(thief_player_id, victim_player_id, crystal_item_id)
	else:
		AppLogger.log_error("_rpc_pickpocket_attempt: PickpocketService nicht verfügbar!", LOG_CAT)

## ADR-039: Empfang einer Pickpocket-Systemnachricht auf dem Ziel-Client
## (dem Opfer). `@rpc("authority", …)` — nur die Autorität darf senden,
## analog `_rpc_receive_zone_update()`. Reicht die Nachricht nur an den
## lokalen UI-Notification-Kanal durch, kein weiterer Zustand betroffen.
@rpc("authority", "call_remote", "reliable")
func _rpc_receive_pickpocket_notification(text: String) -> void:
	if multiplayer.is_server():
		return
	if is_instance_valid(_pickpocket):
		_pickpocket.on_notification_received(text)
	else:
		AppLogger.log_error("_rpc_receive_pickpocket_notification: PickpocketService nicht verfügbar!", LOG_CAT)

## ADR-034: RPC-Empfang für Bank-Einzahlung (Gold) auf der Autorität.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_bank_deposit_gold(amount: int) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_bank_deposit_gold", peer_id):
		return
	var player_id := _sender_as_player_uuid()
	if is_instance_valid(_bank):
		_bank.on_deposit_gold_confirmed(amount, player_id)
	else:
		AppLogger.log_error("_rpc_bank_deposit_gold: BankService nicht verfügbar!", LOG_CAT)

## ADR-034: RPC-Empfang für Bank-Abhebung (Gold) auf der Autorität.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_bank_withdraw_gold(amount: int) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_bank_withdraw_gold", peer_id):
		return
	var player_id := _sender_as_player_uuid()
	if is_instance_valid(_bank):
		_bank.on_withdraw_gold_confirmed(amount, player_id)
	else:
		AppLogger.log_error("_rpc_bank_withdraw_gold: BankService nicht verfügbar!", LOG_CAT)

## ADR-035: RPC-Empfang für Handelseinladungs-Antwort auf der Autorität.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_trade_respond_invite(accept: bool) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_trade_respond_invite", peer_id):
		return
	var player_id := _sender_as_player_uuid()
	if is_instance_valid(_trade):
		_trade.on_invite_response_confirmed(player_id, accept)
	else:
		AppLogger.log_error("_rpc_trade_respond_invite: TradeService nicht verfügbar!", LOG_CAT)

## ADR-035: RPC-Empfang für Handels-Angebots-Änderung auf der Autorität.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_trade_update_offer(session_id: String, items: Dictionary, gold: int) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_trade_update_offer", peer_id):
		return
	var player_id := _sender_as_player_uuid()
	if is_instance_valid(_trade):
		_trade.on_offer_updated_confirmed(player_id, session_id, items, gold)
	else:
		AppLogger.log_error("_rpc_trade_update_offer: TradeService nicht verfügbar!", LOG_CAT)

## ADR-035: RPC-Empfang für Handels-Ready-Markierung auf der Autorität.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_trade_set_ready(session_id: String, ready: bool) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_trade_set_ready", peer_id):
		return
	var player_id := _sender_as_player_uuid()
	if is_instance_valid(_trade):
		_trade.on_ready_confirmed(player_id, session_id, ready)
	else:
		AppLogger.log_error("_rpc_trade_set_ready: TradeService nicht verfügbar!", LOG_CAT)

## ADR-035: RPC-Empfang für finale Handels-Bestätigung auf der Autorität.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_trade_set_confirmed(session_id: String, confirmed: bool) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_trade_set_confirmed", peer_id):
		return
	var player_id := _sender_as_player_uuid()
	if is_instance_valid(_trade):
		_trade.on_confirm_confirmed(player_id, session_id, confirmed)
	else:
		AppLogger.log_error("_rpc_trade_set_confirmed: TradeService nicht verfügbar!", LOG_CAT)

## ADR-035: RPC-Empfang für Handels-Abbruch auf der Autorität.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_trade_cancel(session_id: String) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_trade_cancel", peer_id):
		return
	var player_id := _sender_as_player_uuid()
	if is_instance_valid(_trade):
		_trade.on_cancel_confirmed(player_id, session_id)
	else:
		AppLogger.log_error("_rpc_trade_cancel: TradeService nicht verfügbar!", LOG_CAT)

## ADR-035: RPC-Empfang für Auktionshaus-Listing auf der Autorität.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_auction_list_item(item_id: String, quantity: int, price: int) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_auction_list_item", peer_id):
		return
	var player_id := _sender_as_player_uuid()
	if is_instance_valid(_auction):
		_auction.on_list_item_confirmed(player_id, item_id, quantity, price)
	else:
		AppLogger.log_error("_rpc_auction_list_item: AuctionHouseService nicht verfügbar!", LOG_CAT)

## ADR-035: RPC-Empfang für Auktionshaus-Kauf auf der Autorität.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_auction_buy_item(listing_id: String) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_auction_buy_item", peer_id):
		return
	var player_id := _sender_as_player_uuid()
	if is_instance_valid(_auction):
		_auction.on_buy_confirmed(player_id, listing_id)
	else:
		AppLogger.log_error("_rpc_auction_buy_item: AuctionHouseService nicht verfügbar!", LOG_CAT)

## ADR-035: RPC-Empfang für Auktionshaus-Stornierung auf der Autorität.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_auction_cancel_listing(listing_id: String) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_auction_cancel_listing", peer_id):
		return
	var player_id := _sender_as_player_uuid()
	if is_instance_valid(_auction):
		_auction.on_cancel_listing_confirmed(player_id, listing_id)
	else:
		AppLogger.log_error("_rpc_auction_cancel_listing: AuctionHouseService nicht verfügbar!", LOG_CAT)

## ADR-035: RPC-Empfang für Auktionshaus-Snapshot-Anfrage auf der Autorität.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_auction_request_snapshot() -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_auction_request_snapshot", peer_id):
		return
	var player_id := _sender_as_player_uuid()
	if is_instance_valid(_auction):
		_auction.request_listings_snapshot(player_id)
	else:
		AppLogger.log_error("_rpc_auction_request_snapshot: AuctionHouseService nicht verfügbar!", LOG_CAT)

## ADR-043: RPC-Empfang für eine Chat-Nachricht auf der Autorität.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_chat_send_message(channel: String, text: String, target_player_id: String) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_chat_send_message", peer_id):
		return
	var player_id := _sender_as_player_uuid()
	if is_instance_valid(_chat):
		_chat.on_send_message_confirmed(player_id, channel, text, target_player_id)
	else:
		AppLogger.log_error("_rpc_chat_send_message: ChatService nicht verfügbar!", LOG_CAT)

## ADR-044: RPC-Empfang für eine Meldung auf der Autorität.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_report_submit(reported_player_id: String, reason: String, details: String, context: Dictionary) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_report_submit", peer_id):
		return
	var player_id := _sender_as_player_uuid()
	if is_instance_valid(_report):
		_report.on_submit_report_confirmed(player_id, reported_player_id, reason, details, context)
	else:
		AppLogger.log_error("_rpc_report_submit: ReportService nicht verfügbar!", LOG_CAT)

## ADR-046 (Round 103): RPC-Empfang für eine Achievement-Snapshot-Anfrage.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_achievement_snapshot_request() -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_achievement_snapshot_request", peer_id):
		return
	var player_id := _sender_as_player_uuid()
	if is_instance_valid(_achievement):
		_achievement.on_snapshot_requested(player_id)
	else:
		AppLogger.log_error("_rpc_achievement_snapshot_request: AchievementService nicht verfügbar!", LOG_CAT)

## Siehe send_client_observed_achievement()-Kommentar für das Vertrauensmodell.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_observed_achievement(achievement_id: String) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_client_observed_achievement", peer_id):
		return
	var player_id := _sender_as_player_uuid()
	if is_instance_valid(_achievement):
		_achievement.on_client_observed_achievement(player_id, achievement_id)
	else:
		AppLogger.log_error("_rpc_client_observed_achievement: AchievementService nicht verfügbar!", LOG_CAT)

## Round 106 (ADR-048): RPC-Empfang für submit_answers() auf der Autorität.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_character_creation_submit_answers(answers: Dictionary) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_character_creation_submit_answers", peer_id):
		return
	var player_id := _sender_as_player_uuid()
	if is_instance_valid(_character_creation):
		_character_creation.on_submit_answers_confirmed(player_id, answers)
	else:
		AppLogger.log_error("_rpc_character_creation_submit_answers: CharacterCreationService nicht verfügbar!", LOG_CAT)

## Round 106 (ADR-048): RPC-Empfang für skip_creation() auf der Autorität.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_character_creation_skip() -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_character_creation_skip", peer_id):
		return
	var player_id := _sender_as_player_uuid()
	if is_instance_valid(_character_creation):
		_character_creation.on_skip_creation_confirmed(player_id)
	else:
		AppLogger.log_error("_rpc_character_creation_skip: CharacterCreationService nicht verfügbar!", LOG_CAT)

## Aussehen-Editor (ADR-048): RPC-Empfang für request_set_look() auf der
## Autorität. `look` ist untrusted — on_set_look_confirmed() sanitisiert.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_character_set_look(look: Dictionary) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_character_set_look", peer_id):
		return
	var player_id := _sender_as_player_uuid()
	if is_instance_valid(_character_creation):
		_character_creation.on_set_look_confirmed(player_id, look)
	else:
		AppLogger.log_error("_rpc_character_set_look: CharacterCreationService nicht verfügbar!", LOG_CAT)

## Round 107 (ADR-049): RPC-Empfang für eine Wiki-Snapshot-Anfrage.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_wiki_snapshot_request() -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_wiki_snapshot_request", peer_id):
		return
	var player_id := _sender_as_player_uuid()
	if is_instance_valid(_wiki):
		_wiki.on_snapshot_requested(player_id)
	else:
		AppLogger.log_error("_rpc_wiki_snapshot_request: WikiService nicht verfügbar!", LOG_CAT)

## ADR-021 (R-5), Option C: RPC-Empfang für generische Domain-Events auf der
## Autorität. peer_id kommt NIE vom Client — genau wie bei
## `_rpc_request_entity_interaction()` aus `multiplayer.get_remote_sender_id()`
## (_sender_as_peer_id()), fälschungssicher. `payload` bleibt Nutzdaten,
## unkritisch (siehe report_domain_event()-Kommentar).
@rpc("any_peer", "call_remote", "reliable")
func _rpc_report_domain_event(event_name: String, payload: Dictionary) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_report_domain_event", peer_id):
		return
	AppLogger.log_debug(
		"RPC _rpc_report_domain_event von peer %d: '%s' payload=%s" % [peer_id, event_name, str(payload)],
		LOG_CAT
	)
	domain_event_received.emit(event_name, payload, peer_id)

## ADR-020: RPC-Empfang für Interaktions-Ergebnisse auf der Autorität.
## peer_id kommt NIE vom Client-Parameter, sondern aus
## multiplayer.get_remote_sender_id() (_sender_as_peer_id()) — fälschungssicher,
## von Godots High-Level-Multiplayer-API selbst gesetzt, nicht vom sendenden
## Peer beeinflussbar.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_entity_interaction(entity_uuid: String, action_id: String, actor_uuid: String = "") -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if _is_rate_limited("_rpc_request_entity_interaction", peer_id):
		return
	AppLogger.log_debug(
		"RPC _rpc_request_entity_interaction von peer %d: uuid='%s' action='%s' actor_uuid='%s'"
		% [peer_id, entity_uuid, action_id, actor_uuid],
		LOG_CAT
	)
	if is_instance_valid(_world):
		_world.resolve_and_dispatch_interaction(entity_uuid, action_id, peer_id, actor_uuid)
	else:
		AppLogger.log_error("_rpc_request_entity_interaction: WorldService nicht verfügbar!", LOG_CAT)

## ADR-025: RPC-Empfang für Bewegungs-Input auf der Autorität. Bewusst
## "unreliable_ordered" statt "reliable" (einzige Ausnahme in dieser Datei,
## s. NetworkContract.gd Abschnitt UNRELIABLE) — 20+ Hz Rate, ein verlorenes
## Paket wird vom nächsten Tick überholt statt die Queue zu stauen.
## peer_id kommt NIE aus dem Payload, sondern fälschungssicher aus
## multiplayer.get_remote_sender_id() (_sender_as_peer_id()) — derselbe
## Grundsatz wie bei jedem anderen any_peer-RPC hier.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_submit_movement_input(input_snapshot: Dictionary) -> void:
	if not _is_authority():
		return
	var peer_id := _sender_as_peer_id()
	if is_instance_valid(_world):
		_world.route_movement_input(peer_id, input_snapshot)
	else:
		AppLogger.log_error("_rpc_submit_movement_input: WorldService nicht verfügbar!", LOG_CAT)

## Sprint D/E: Empfängt den initialen State-Snapshot vom Server nach eigenem Request.
## Läuft nur auf Clients — der Server sendet nie an sich selbst.
## G-03: Cancelt den Retry-Timer — Snapshot wurde empfangen.
@rpc("authority", "call_remote", "reliable")
func _rpc_receive_initial_state(state: Dictionary) -> void:
	if multiplayer.is_server():
		return
	# G-03: Snapshot empfangen — Timer und Retry-Zähler stoppen.
	_snapshot_received = true
	_cancel_snapshot_timer()
	AppLogger.log_info("Initial-Snapshot vom Server empfangen (%d Keys)." % state.size(), LOG_CAT)
	if is_instance_valid(_save_system):
		_save_system.apply_remote_state(state)
	else:
		AppLogger.log_error("_rpc_receive_initial_state: SaveSystem nicht verfügbar!", LOG_CAT)

## R-7 (ADR-022): Empfang eines Economy-State-Updates auf dem Ziel-Client.
## `@rpc("authority", …)` — nur die Autorität darf das senden, Godot verweigert
## den Aufruf sonst bereits auf Transport-Ebene (kein zusätzlicher Guard nötig,
## analog zu `_rpc_receive_initial_state()`). Läuft nie auf dem Server selbst
## (die Autorität sendet sich laut `send_economy_update()` nie an sich selbst).
## Reicht nur durch — die eigentliche Anwendung auf den lokalen State ist
## service-spezifisch (InventorySystem/SkillSystem/EquipmentService).
@rpc("authority", "call_remote", "reliable")
func _rpc_receive_economy_update(kind: String, payload: Dictionary) -> void:
	if multiplayer.is_server():
		return
	economy_state_received.emit(kind, payload)

## ADR-030: Empfang einer Zonen-Mitgliedschaftsänderung auf dem Ziel-Client.
## Ruft absichtlich dieselbe ZoneService-API auf, die auch ZoneTriggerVolume
## auf der Autorität nutzt (report_enter()/report_exit()) — kein separater
## Client-Mutationspfad nötig. Kein Endlosloop: send_zone_update_for_peer()
## broadcastet nur auf `multiplayer.is_server()`, hier läuft es nie serverseitig
## (siehe Guard unten), also mutiert der lokale report_enter()/report_exit()-
## Aufruf hier zwar erneut _network.send_zone_update_for_peer(), aber dessen
## eigener "nicht Autorität"-Guard beendet die Kette sofort.
@rpc("authority", "call_remote", "reliable")
func _rpc_receive_zone_update(zone_id: String, entered: bool) -> void:
	if multiplayer.is_server():
		return
	if not is_instance_valid(_zone_service):
		AppLogger.log_error("_rpc_receive_zone_update: kein ZoneService verfügbar!", LOG_CAT)
		return
	var local_peer := get_local_peer_id()
	if entered:
		_zone_service.report_enter(local_peer, StringName(zone_id))
	else:
		_zone_service.report_exit(local_peer, StringName(zone_id))

## ADR-042: Empfang eines Broadcast-Events auf einem Ziel-Client.
## `@rpc("authority", …)` — nur die Autorität darf senden, Godot verweigert den
## Aufruf sonst bereits auf Transport-Ebene (kein zusätzlicher Guard nötig,
## analog zu `_rpc_receive_economy_update()`). Läuft nie auf dem Server selbst
## — broadcast_to_all_peers() überspringt den lokalen Peer bewusst (siehe
## dortiger Kommentar), der `multiplayer.is_server()`-Guard hier ist also ein
## zweites, redundantes Sicherheitsnetz, kein alleiniger Schutz.
## Reicht nur durch — kind-spezifische Anwendung ist Sache der Konsumenten,
## die sich auf broadcast_event_received() abonnieren.
@rpc("authority", "call_remote", "reliable")
func _rpc_receive_broadcast_event(kind: String, payload: Dictionary) -> void:
	if multiplayer.is_server():
		return
	broadcast_event_received.emit(kind, payload)

## ADR-043: Empfang einer gezielten ("whisper") Chat-Nachricht auf einem
## Ziel-Client. Analog _rpc_receive_broadcast_event() — nur die Autorität
## darf senden, Godot verweigert den Aufruf sonst bereits auf Transport-
## Ebene. Läuft nie auf dem Server selbst (send_chat_message_for_player()
## überspringt den lokalen Peer, siehe dortiger Kommentar).
@rpc("authority", "call_remote", "reliable")
func _rpc_receive_chat_message(payload: Dictionary) -> void:
	if multiplayer.is_server():
		return
	chat_message_received.emit(payload)

## ADR-046: Empfang einer Achievement-Unlock-Benachrichtigung auf einem
## Ziel-Client. Analog _rpc_receive_chat_message() — nur die Autorität darf
## senden, läuft nie auf dem Server selbst
## (send_achievement_unlocked_for_player() überspringt den lokalen Peer).
@rpc("authority", "call_remote", "reliable")
func _rpc_receive_achievement_unlocked(payload: Dictionary) -> void:
	if multiplayer.is_server():
		return
	achievement_unlocked_received.emit(payload)

## ADR-046 (Round 103): Empfang des angeforderten Achievement-Snapshots auf
## dem anfragenden Client. Analog _rpc_receive_achievement_unlocked().
@rpc("authority", "call_remote", "reliable")
func _rpc_receive_achievement_snapshot(payload: Dictionary) -> void:
	if multiplayer.is_server():
		return
	achievement_snapshot_received.emit(payload)

## Round 106 (ADR-048): Empfang des Charaktererstellungs-Ergebnisses auf dem
## anfragenden Client. Analog _rpc_receive_achievement_unlocked().
@rpc("authority", "call_remote", "reliable")
func _rpc_receive_character_creation_completed(payload: Dictionary) -> void:
	if multiplayer.is_server():
		return
	character_creation_completed_received.emit(payload)

@rpc("authority", "call_remote", "reliable")
func _rpc_receive_character_creation_skipped(payload: Dictionary) -> void:
	if multiplayer.is_server():
		return
	character_creation_skipped_received.emit(payload)

## Aussehen-Editor (ADR-048): Empfang des bestätigten Looks auf dem anfragenden
## Client. Analog _rpc_receive_character_creation_completed().
@rpc("authority", "call_remote", "reliable")
func _rpc_receive_character_look_updated(payload: Dictionary) -> void:
	if multiplayer.is_server():
		return
	character_look_updated_received.emit(payload)

## Round 107 (ADR-049): Empfang einer Wiki-Entdeckungs-Benachrichtigung auf
## einem Ziel-Client. Analog _rpc_receive_achievement_unlocked() — läuft nie
## auf dem Server selbst (send_wiki_entry_discovered_for_player() überspringt
## den lokalen Peer).
@rpc("authority", "call_remote", "reliable")
func _rpc_receive_wiki_entry_discovered(payload: Dictionary) -> void:
	if multiplayer.is_server():
		return
	wiki_entry_discovered_received.emit(payload)

## Round 107 (ADR-049): Empfang des angeforderten Wiki-Snapshots auf dem
## anfragenden Client. Analog _rpc_receive_achievement_snapshot().
@rpc("authority", "call_remote", "reliable")
func _rpc_receive_wiki_snapshot(payload: Dictionary) -> void:
	if multiplayer.is_server():
		return
	wiki_snapshot_received.emit(payload)

## E-4: Client ruft dies nach seinem Session-Boot auf um den State-Snapshot anzufordern.
## Korrigiertes Timing: Client hat zu diesem Zeitpunkt bereits eine aktive Session
## und apply_remote_state() ist nicht mehr durch den _active_player_id-Guard blockiert.
##
## G-03: Startet einen SNAPSHOT_TIMEOUT_SEC-Timer. Bleibt _rpc_receive_initial_state
## aus (Server noch nicht bereit, Boot-Race-Condition), wird der Request wiederholt.
func send_request_initial_state() -> void:
	if not _has_peer() or multiplayer.is_server():
		return
	_snapshot_received = false
	_snapshot_retries  = 0
	_send_snapshot_request()

## BUGFIX (2026-09-14, "zwei Welten" Teil 2): von WorldService.on_world_scene_ready()
## aufgerufen, NACHDEM das eigene lokale Player-Entity gespawnt wurde (Host UND
## Client — beide spawnen laut WorldSpawner.spawn_all() ihr eigenes lokales
## Player-Entity, aber bisher erfuhr niemand sonst davon). Tier 1 (Solo): no-op,
## kein Peer vorhanden. Client: schickt die Position an die Autorität. Autorität
## (Host): trägt sich direkt lokal ein statt sich selbst per RPC anzuschreiben.
func report_local_player_spawned(pos: Vector3) -> void:
	if not _has_peer():
		return
	# BUGFIX (2026-09-15, "Spieler sehen sich immer noch nicht"): für einen
	# eventuellen Nachtrag durch _rpc_request_player_report() unten merken —
	# NetworkBridge ist pro CharacterScope, existiert also u.U. noch gar nicht,
	# wenn diese Funktion zum ersten Mal aufgerufen wird (siehe Race-Kommentar
	# im rpc_id(1, …)-Zweig unten).
	_last_local_report_pos = pos
	_has_reported_local_player = true
	if _is_authority():
		_register_and_broadcast_player_spawn(get_local_peer_id(), pos)
		# BUGFIX (2026-09-15, "Spieler sehen sich immer noch nicht"): Host und
		# Client booten ihre jeweilige Welt UNABHÄNGIG voneinander (siehe
		# "zwei Welten"-Fixes oben) — ein Client kann (und tut es laut Log
		# regelmäßig) seinen Handshake abschließen UND sein eigenes
		# Player-Entity spawnen, BEVOR der Host überhaupt einen Charakter
		# gewählt hat. Der Client schickt seinen Report dann per
		# rpc_id(1, "_rpc_report_player_spawned", …) an peer 1 — aber
		# NetworkBridge existiert zu dem Zeitpunkt auf dem Host noch gar
		# nicht (pro CharacterScope, wird erst MIT dem World-Boot erzeugt).
		# Der RPC läuft ins Leere, OHNE Fehler (kein Empfänger-Node vorhanden)
		# — beide Peers booten "erfolgreich", sehen sich aber trotzdem nicht.
		# Fix: sobald die Autorität selbst bereit ist, bittet sie alle bereits
		# per Handshake verbundenen Peers, ihren Report zu WIEDERHOLEN.
		for other_peer_id in get_all_joined_peer_ids():
			if other_peer_id == get_local_peer_id():
				continue
			rpc_id(other_peer_id, "_rpc_request_player_report")
	else:
		rpc_id(1, "_rpc_report_player_spawned", pos)

## Gegenstück zu report_local_player_spawned()'s Autoritäts-Zweig oben —
## Autorität → (verspätet gebootetem) Peer: "schick deinen Report nochmal."
@rpc("authority", "call_remote", "reliable")
func _rpc_request_player_report() -> void:
	if not _has_reported_local_player:
		return  # eigenes Player-Entity selbst noch nicht gespawnt — nichts zu melden.
	report_local_player_spawned(_last_local_report_pos)


# ─────────────────────────────────────────────
# Pet-Sichtbarkeit (FEATURE 2026-09-17, "Pets cross-peer sichtbar")
# ─────────────────────────────────────────────
## Exaktes Gegenstück zu report_local_player_spawned() oben, mit EINEM
## wichtigen Unterschied: Pets sind CLIENT-autoritativ
## (PetComponent.on_spawn() → set_multiplayer_authority(_owner_peer_id), nicht
## immer 1 wie bei Player/EnemyNPC/AnimalBase — der Besitzer simuliert sein
## Pet selbst). Andere Peers (inkl. der Server, falls der nicht der Besitzer
## ist) brauchen trotzdem eine nicht-autoritative Kopie, sonst sehen sie das
## Pet gar nicht. Läuft über denselben Server-als-Hub-Mechanismus: melden an
## peer 1, der verteilt an alle — außer an den Besitzer selbst (der hat sein
## Pet schon lokal, autoritativ).
##
## payload: {"name": String (deterministischer Node-Name, siehe
## EntityOrchestrator.spawn_entity()), "owner_peer_id": int, "pos": Vector3,
## "config": Dictionary (dieselbe config, die auch der lokale spawn_entity()-
## Aufruf bekommen hat — color/body_size/speed/name/owner_player_id)}.
var _active_pets: Dictionary = {}  # name (String) -> payload (Dictionary)

## Aufgerufen von AnimalCatcher.catch_animal() / PetRestorer, NACHDEM das
## eigene Pet lokal gespawnt wurde.
func report_pet_spawned(pet_name: String, owner_peer_id: int, pos: Vector3, config: Dictionary) -> void:
	if not _has_peer() or pet_name.is_empty():
		return
	var payload := {"name": pet_name, "owner_peer_id": owner_peer_id, "pos": pos, "config": config}
	if _is_authority():
		_register_and_broadcast_pet_spawn(payload)
	else:
		rpc_id(1, "_rpc_report_pet_spawned", payload)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_report_pet_spawned(payload: Dictionary) -> void:
	if not _is_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	if _is_rate_limited("_rpc_report_pet_spawned", sender):
		return
	_register_and_broadcast_pet_spawn(payload)

func _register_and_broadcast_pet_spawn(payload: Dictionary) -> void:
	var pet_name: String = payload.get("name", "")
	if pet_name.is_empty():
		return
	_active_pets[pet_name] = payload
	var owner_peer_id: int = payload.get("owner_peer_id", -1)
	for peer_id in get_all_joined_peer_ids():
		if peer_id == owner_peer_id:
			continue  # Besitzer hat sein eigenes Pet schon lokal — nicht doppelt schicken.
		_deliver_spawn_remote_pet(peer_id, payload)
	# Die Autorität selbst braucht auch eine Kopie, falls sie nicht der
	# Besitzer ist (get_all_joined_peer_ids() enthält den eigenen Peer nicht).
	var local_peer := get_local_peer_id()
	if local_peer != owner_peer_id:
		_deliver_spawn_remote_pet(local_peer, payload)

func _deliver_spawn_remote_pet(target_peer_id: int, payload: Dictionary) -> void:
	if target_peer_id == multiplayer.get_unique_id():
		_rpc_spawn_remote_pet(payload)
	else:
		rpc_id(target_peer_id, "_rpc_spawn_remote_pet", payload)

## Autorität → Client: "spawne eine (nicht-autoritative) Kopie dieses Pets."
@rpc("authority", "call_remote", "reliable")
func _rpc_spawn_remote_pet(payload: Dictionary) -> void:
	var owner_peer_id: int = payload.get("owner_peer_id", -1)
	if owner_peer_id == get_local_peer_id():
		return  # eigenes Pet — schon lokal vorhanden, autoritativ.
	var pet_name: String = payload.get("name", "")
	if pet_name.is_empty() or not is_instance_valid(_world):
		return
	if not _entity_orchestrator_has_entity_named(pet_name):
		var pos: Vector3 = payload.get("pos", Vector3.ZERO)
		var config: Dictionary = payload.get("config", {}).duplicate()
		config["_is_replica_spawn"] = true
		_world.spawn_entity("pet", pos, config, owner_peer_id)
		AppLogger.log_info("Pet-Kopie gespawnt: '%s' (Besitzer: peer %d)." % [pet_name, owner_peer_id], LOG_CAT)

## Idempotenz-Check analog is_instance_valid(_world.get_player_by_id(peer_id))
## bei _rpc_spawn_remote_player() — Pets haben aber kein "eine pro peer_id"-
## Lookup wie Player, daher über den deterministischen Namen.
func _entity_orchestrator_has_entity_named(entity_name: String) -> bool:
	if not is_instance_valid(_world):
		return false
	return _world.has_entity_named(entity_name)


## Client → Autorität: "mein lokales Player-Entity steht jetzt an dieser Position."
@rpc("any_peer", "call_remote", "reliable")
func _rpc_report_player_spawned(pos: Vector3) -> void:
	if not _is_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	if _is_rate_limited("_rpc_report_player_spawned", sender):
		return
	_register_and_broadcast_player_spawn(sender, pos)

## Autorität-seitige Kernlogik (siehe _rpc_report_player_spawned()-Kommentar
## analog zu _handle_join_handshake() oben: bewusst getrennt von der @rpc-Hülle,
## damit sie auch für den lokalen Host-Fall direkt aufrufbar ist, ohne einen
## "echten" RPC-Sender zu brauchen).
## 1. Trägt peer_id in _active_world_peers ein.
## 2. Informiert jeden ANDEREN bereits aktiven Peer über den Neuzugang.
## 3. Informiert peer_id im Gegenzug über jeden bereits aktiven anderen Peer —
##    sonst sieht ein spät beitretender Client niemanden, der schon vorher da war.
## Round 114 (ADR-048 Broadcast-Lücke): jeder Spawn trägt den aktuellen Look
## (CharacterCreationService.get_look() — auf der Autorität für JEDE
## player_id abfragbar) im Payload mit, damit ein frisch gespawntes
## entferntes Player-Entity von Anfang an korrekt aussieht. Deckt nur den
## Spawn-Zeitpunkt ab; Look-Änderungen an einem bereits gespawnten Spieler
## laufen separat über CharacterCreationService._broadcast_look().
func _register_and_broadcast_player_spawn(peer_id: int, pos: Vector3) -> void:
	var player_id := get_player_id_for_peer(peer_id)
	_active_world_peers[peer_id] = {"player_id": player_id, "pos": pos}
	var look := _look_for_player(player_id)
	for other_peer_id in _active_world_peers.keys():
		if other_peer_id == peer_id:
			continue
		_deliver_spawn_remote_player(other_peer_id, peer_id, player_id, pos, look)
		var other_info: Dictionary = _active_world_peers[other_peer_id]
		var other_player_id := String(other_info.get("player_id", ""))
		_deliver_spawn_remote_player(
			peer_id, other_peer_id, other_player_id, other_info.get("pos", Vector3.ZERO),
			_look_for_player(other_player_id)
		)
	# FEATURE (2026-09-17, "Pets cross-peer sichtbar"): derselbe Zeitpunkt eignet
	# sich auch für den Pet-Nachtrag — genau hier wird ohnehin schon "wer ist
	# schon da" für Spieler abgeglichen (Race-sicher, siehe report_local_player_spawned()-
	# Kommentar). Ein neu aktiv gewordener Peer (frisch gebootet ODER via
	# _rpc_request_player_report() nachgetragen) kennt sonst keine der bereits
	# existierenden Pets anderer Spieler.
	for pet_payload in _active_pets.values():
		_deliver_spawn_remote_pet(peer_id, pet_payload)
	AppLogger.log_info(
		"Mitspieler-Sichtbarkeit: peer %d ('%s') bei %d bereits aktivem/n Peer(s) gemeldet." % [
			peer_id, player_id, max(_active_world_peers.size() - 1, 0)
		],
		LOG_CAT
	)

## Round 114: kapselt den "get_look() falls verfügbar, sonst Default-Look"-
## Fallback für den Spawn-Payload (CharacterCreationService kann fehlen,
## z. B. in Unit-Tests ohne vollständige Dependency-Injection).
func _look_for_player(player_id: String) -> Dictionary:
	if is_instance_valid(_character_creation):
		return _character_creation.get_look(player_id)
	return CharacterLook.default_look()

## Schickt _rpc_spawn_remote_player entweder per RPC (entfernter Peer) oder ruft
## die Methode direkt lokal auf (target_peer_id ist die Autorität selbst — ein
## rpc_id() an sich selbst ist unnötig und würde ohne echten Multiplayer-Peer
## sogar fehlschlagen, z.B. in Unit-Tests).
func _deliver_spawn_remote_player(target_peer_id: int, peer_id: int, player_id: String, pos: Vector3, look: Dictionary) -> void:
	if target_peer_id == multiplayer.get_unique_id():
		_rpc_spawn_remote_player(peer_id, player_id, pos, look)
	else:
		rpc_id(target_peer_id, "_rpc_spawn_remote_player", peer_id, player_id, pos, look)

## Autorität → Client: "spawne ein Player-Entity für diesen (fremden) Peer."
## `@rpc("authority", …)` analog _rpc_receive_initial_state() — nur die Autorität
## darf senden. Läuft auf JEDEM Peer, auch der Autorität selbst (siehe
## _deliver_spawn_remote_player() oben) — daher kein multiplayer.is_server()-Guard,
## nur der Idempotenz-/Selbst-Check unten.
@rpc("authority", "call_remote", "reliable")
func _rpc_spawn_remote_player(peer_id: int, player_id: String, pos: Vector3, look: Dictionary) -> void:
	if peer_id == get_local_peer_id():
		return  # das eigene, bereits lokal gespawnte Player-Entity — nicht doppelt spawnen.
	if not is_instance_valid(_world):
		AppLogger.log_error("_rpc_spawn_remote_player: WorldService nicht verfügbar!", LOG_CAT)
		return
	if is_instance_valid(_world.get_player_by_id(peer_id)):
		return  # bereits gespawnt (erneuter Broadcast) — idempotent.
	_world.spawn_entity("player", pos, {spawn_position = pos, player_id = player_id, look = look}, peer_id)
	AppLogger.log_info(
		"Mitspieler-Entity gespawnt: peer %d ('%s') pos=%s" % [peer_id, player_id, pos], LOG_CAT
	)

## Autorität-seitig: peer_id verlassen — aus der Roster entfernen und alle
## verbleibenden Peers anweisen, dessen Player-Entity zu despawnen. Aufgerufen
## aus _on_peer_disconnected() unten (nur die Autorität bekommt dieses Signal).
func _report_peer_left_world(peer_id: int) -> void:
	if not _active_world_peers.has(peer_id):
		return
	_active_world_peers.erase(peer_id)
	for other_peer_id in _active_world_peers.keys():
		_deliver_despawn_remote_player(other_peer_id, peer_id)

func _deliver_despawn_remote_player(target_peer_id: int, peer_id: int) -> void:
	if target_peer_id == multiplayer.get_unique_id():
		_rpc_despawn_remote_player(peer_id)
	else:
		rpc_id(target_peer_id, "_rpc_despawn_remote_player", peer_id)

## Autorität → Client: "despawne das Player-Entity dieses Peers."
@rpc("authority", "call_remote", "reliable")
func _rpc_despawn_remote_player(peer_id: int) -> void:
	if not is_instance_valid(_world):
		return
	var node := _world.get_player_by_id(peer_id)
	if not is_instance_valid(node):
		return
	if not node.has_meta("entity_uuid"):
		return
	_world.despawn_entity(node.get_meta("entity_uuid"))
	AppLogger.log_info("Mitspieler-Entity despawnt: peer %d." % peer_id, LOG_CAT)

## E-4: Server-Seite des Snapshot-Requests — sendet den State nur an den anfragenden Client.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_requests_initial_state() -> void:
	if not _is_authority():
		return
	var requester := multiplayer.get_remote_sender_id()
	if _is_rate_limited("_rpc_client_requests_initial_state", requester if requester != 0 else 1):
		return
	if not is_instance_valid(_save_system):
		AppLogger.log_error("_rpc_client_requests_initial_state: SaveSystem nicht verfügbar!", LOG_CAT)
		return
	var state := _save_system.get_full_state()
	AppLogger.log_info(
		"Initial-Snapshot angefragt von peer %d — sende %d Keys." % [requester, state.size()],
		LOG_CAT
	)
	rpc_id(requester, "_rpc_receive_initial_state", state)

# ─────────────────────────────────────────────
# Peer-Event-Handler
# ─────────────────────────────────────────────

func _on_peer_connected(peer_id: int) -> void:
	AppLogger.log_info("Peer verbunden: %d" % peer_id, LOG_CAT)
	player_connected.emit(peer_id)
	# Snapshot wird nicht hier gesendet — zu diesem Zeitpunkt hat der Client noch
	# keine Session gebootet und apply_remote_state() würde blockiert.
	# Stattdessen fordert der Client nach seinem Session-Boot den Snapshot an
	# via _rpc_request_initial_state() (E-4).

func _on_peer_disconnected(peer_id: int) -> void:
	AppLogger.log_info("Peer getrennt: %d" % peer_id, LOG_CAT)
	# BUGFIX (2026-09-14, "zwei Welten" Teil 2): verbleibende Peers sollen das
	# Player-Entity des getrennten Peers nicht als Leiche stehen lassen.
	# multiplayer.peer_disconnected feuert nur auf der Autorität — kein
	# zusätzlicher _is_authority()-Guard nötig, aber _report_peer_left_world()
	# ist defensiv genug, um auch ohne aktiven Eintrag früh zurückzukehren.
	_report_peer_left_world(peer_id)
	player_disconnected.emit(peer_id)

func _on_connected_to_server() -> void:
	AppLogger.log_info("Mit Server verbunden. Lokale peer_id: %d" % get_local_peer_id(), LOG_CAT)

func _on_connection_failed() -> void:
	AppLogger.log_error("Verbindung zum Server fehlgeschlagen.", LOG_CAT)
	connection_failed.emit()

func _on_server_disconnected() -> void:
	AppLogger.log_warn("Server-Verbindung verloren.", LOG_CAT)
	server_disconnected.emit()

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _has_peer() -> bool:
	# has_multiplayer_peer() gibt in Godot 4 auch für den Standard-OfflineMultiplayerPeer
	# true zurück. Wir wollen nur echte Netzwerk-Peers (ENet, WebSocket …) als "gesetzt"
	# betrachten — deshalb prüfen wir zusätzlich den Klassen-Namen des Peers.
	if not is_instance_valid(multiplayer):
		return false
	if not multiplayer.has_multiplayer_peer():
		return false
	var peer := multiplayer.multiplayer_peer
	return is_instance_valid(peer) and peer.get_class() != "OfflineMultiplayerPeer"

func _is_authority() -> bool:
	return not _has_peer() or multiplayer.is_server()

func _sender_as_peer_id() -> int:
	var sender := multiplayer.get_remote_sender_id()
	return sender if sender != 0 else 1

## ADR-029 Plan-Schritt 4: String-Pendant zu _sender_as_peer_id() — löst den
## RPC-Absender über SessionManager.get_player_id_for_peer() zur stabilen
## player_id auf statt der rohen peer_id. Genutzt von _rpc_start_quest()/
## _rpc_complete_quest() (Round 64, QuestService) und _rpc_equip_item()/
## _rpc_unequip_item() (Round 66, EquipmentService) — beide adressieren
## SAVE-Daten, für die die stabile Identität der ganze Sinn der Migration ist.
##
## Round 67 (Gegenprüfung, siehe TODO-offene-probleme.md): die verbleibenden
## vier Handler (_rpc_set_state, _rpc_report_domain_event,
## _rpc_request_entity_interaction, _rpc_submit_movement_input) werden
## ABSICHTLICH NICHT migriert — nicht weil ihre Migrationsrunde noch aussteht,
## sondern weil sie etwas grundsätzlich anderes adressieren als Inventory/
## Quest/Skill/Equipment: keine per-player_id verschachtelten Save-Buckets,
## sondern entweder (a) transienten, nicht persistierten Session-State
## (PlayerStateService._current) oder (b) eine Auflösung gegen den laufenden
## Szenenbaum über EntityOrchestrator.find_player_by_id()/resolve_for_player(),
## die selbst fest an das Entity-Meta `owner_peer_id` gebunden ist (peer_id,
## nicht player_uuid — siehe EntityOrchestrator.spawn_entity()). Eine
## Player-Node existiert nur für die Dauer einer Verbindung; sie über die
## stabile player_id zu adressieren wäre eine Umbenennung ohne Unterschied,
## weil die referenzierte Instanz beim nächsten Reconnect ohnehin neu entsteht.
## `_rpc_report_domain_event()` ist ein Sonderfall: sein Signal
## (domain_event_received) hat genau einen Konsumenten (QuestService), und der
## übersetzt peer_id → player_id bereits selbst an seiner Empfangsgrenze
## (_resolve_player_uuid()) — eine zweite Übersetzung hier wäre redundant.
## Fazit: `_sender_as_peer_id()` ist damit KEIN Übergangs-Code mehr, der mit
## der letzten Migrationsrunde verschwindet, sondern der dauerhaft richtige
## Helfer für peer-/verbindungsscoped Handler. Nur bei einem künftigen,
## tatsächlich save-keyed Handler wechselt man erneut zu diesem Helfer hier.
##
## Tier-1-Solo-Fallback: multiplayer.get_remote_sender_id() liefert außerhalb
## eines echten eingehenden RPC-Aufrufs immer 0 (Tier 1, aber auch Tier 2/3
## bei einem direkten Autoritäts-Aufruf ohne RPC) — in diesem Fall ist "der
## Absender" der lokale Prozess selbst.
func _sender_as_player_uuid() -> String:
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return get_local_player_id()
	return get_player_id_for_peer(sender)

## Schritt 3: Fixed-Window-Rate-Limit-Check. Gibt true zurück wenn der Aufruf
## verworfen werden muss (Limit für dieses (peer_id, rpc_name)-Paar im
## aktuellen Fenster bereits erreicht). Kein Eintrag in RATE_LIMITS → kein
## Limit, gibt immer false zurück (siehe RATE_LIMITS-Kommentar für die
## bewusste Ausnahme _rpc_submit_movement_input).
## Jeder any_peer-RPC-Handler ruft dies als allererstes nach dem
## Authority-Guard auf — Rate-Limit gilt nur auf der Autorität, ein Client
## begrenzt sich nicht selbst.
func _is_rate_limited(rpc_name: String, peer_id: int) -> bool:
	if not RATE_LIMITS.has(rpc_name):
		return false
	var limit: int = RATE_LIMITS[rpc_name]
	var key := "%d:%s" % [peer_id, rpc_name]
	var now := Time.get_ticks_msec() / 1000.0
	var entry: Dictionary = _rate_limit_state.get(key, {})
	if entry.is_empty() or now - float(entry.get("window_start", 0.0)) >= RATE_LIMIT_WINDOW_SEC:
		_rate_limit_state[key] = {"window_start": now, "count": 1}
		return false
	var count: int = int(entry.get("count", 0)) + 1
	entry["count"] = count
	_rate_limit_state[key] = entry
	if count > limit:
		AppLogger.log_warn(
			"Rate-Limit überschritten: peer %d, '%s' (%d/%d pro %.1fs) — Aufruf verworfen."
			% [peer_id, rpc_name, count, limit, RATE_LIMIT_WINDOW_SEC],
			LOG_CAT
		)
		return true
	return false

# ─────────────────────────────────────────────
# G-03: Snapshot-Retry-Helpers
# ─────────────────────────────────────────────

## Sendet den Snapshot-Request und startet den Timeout-Timer.
## Wird von send_request_initial_state() und _on_snapshot_timeout() aufgerufen.
func _send_snapshot_request() -> void:
	rpc_id(1, "_rpc_client_requests_initial_state")
	AppLogger.log_info(
		"Snapshot angefordert (Versuch %d/%d)." % [_snapshot_retries + 1, SNAPSHOT_MAX_RETRIES + 1],
		LOG_CAT
	)
	_start_snapshot_timer()

func _start_snapshot_timer() -> void:
	_cancel_snapshot_timer()
	_snapshot_timer = get_tree().create_timer(SNAPSHOT_TIMEOUT_SEC)
	_snapshot_timer.timeout.connect(_on_snapshot_timeout, CONNECT_ONE_SHOT)

func _cancel_snapshot_timer() -> void:
	if is_instance_valid(_snapshot_timer):
		if _snapshot_timer.timeout.is_connected(_on_snapshot_timeout):
			_snapshot_timer.timeout.disconnect(_on_snapshot_timeout)
	_snapshot_timer = null

func _on_snapshot_timeout() -> void:
	_snapshot_timer = null
	if _snapshot_received:
		return  # Snapshot kam zwischenzeitlich an — kein Retry nötig.
	if _snapshot_retries >= SNAPSHOT_MAX_RETRIES:
		AppLogger.log_error(
			"Snapshot-Request nach %d Versuchen ohne Antwort aufgegeben." % (SNAPSHOT_MAX_RETRIES + 1),
			LOG_CAT
		)
		return
	_snapshot_retries += 1
	AppLogger.log_warn(
		"Snapshot-Timeout — Retry %d/%d..." % [_snapshot_retries, SNAPSHOT_MAX_RETRIES],
		LOG_CAT
	)
	_send_snapshot_request()

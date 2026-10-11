extends Service
class_name ShopService

## ShopService — Shop-NPC-Handel (Round 88, Trading-ADR-035-Vorstufe).
##
## Zwei Richtungen, beide über CurrencyService (ADR-033) + InventorySystem:
## - Kaufen: Spieler zahlt Gold, bekommt ein Item aus BUY_CATALOG.
## - Verkaufen: Spieler gibt ein Item aus seinem Inventar ab, bekommt Gold
##   (ItemDefinition.sell_price, Fallback DEFAULT_SELL_PRICE wenn 0/nicht gesetzt).
##
## Dasselbe request_/on_*_confirmed-Muster wie InventorySystem/CurrencyService
## (ADR-004): anders als deren aktuelle request_add_item()/request_add_gold()
## ist request_buy_item()/request_sell_item() hier BEWUSST client-aufrufbar
## (die UI läuft auf dem Peer des handelnden Spielers, nicht zwingend der
## Autorität) — deshalb übernimmt DIESER Service selbst das
## Tier2/3-RPC-Routing über NetworkBridge.send_shop_buy_item()/
## send_shop_sell_item(), statt sich (wie Inventory/Currency es inzwischen tun)
## darauf zu verlassen, nur von bereits-autoritätsseitigem Code aufgerufen zu
## werden. on_buy_confirmed()/on_sell_confirmed() selbst laufen ausschließlich
## auf der Autorität (Guard analog on_gold_changed_confirmed()).

signal sale_completed(player_id: String, item_id: String, quantity: int, total_price: int)

## ADR-050 Phase 2 (Round 113): `purchase_completed`/`transaction_failed` sind
## nach scripts/economy/shop/ShopEvents.gd (EventBus-Namespace `shop`)
## migriert — jetzt eindeutig `shop_transaction_purchase_completed`/
## `shop_transaction_failed`, siehe ShopEvents.gd-Klassenkommentar.
## `sale_completed` bleibt bewusst nativ (kein Namenskollisions-Fall).

const LOG_CAT := "Shop"
const DEFAULT_SELL_PRICE := 1

## Kauf-Katalog: item_id -> Preis in Gold. Nur Items hier sind beim Shop-NPC
## käuflich. Bewusst als Konstante statt Resource/Daten-Datei — Katalog ist
## für Round 88 fix (Axt + Spitzhacke), kann bei Bedarf später ausgelagert werden.
##
## Round 94 (Anschluss an ADR-038/ADR-039 "Als Nächstes: NPC-Shop-System"):
## alle sechs ADR-038-Scrolls und ADR-039-Diebstahl-Kristalle ergänzt — beide
## ADRs verweisen unter "Ablösung" explizit auf ein Folge-ADR für die
## Beschaffung, ohne eines zu fordern; da der bestehende `ShopService` (Round 88)
## exakt den benötigten Mechanismus (Gold-Kauf gegen Katalog-Item) bereits
## unverändert bereitstellt, kein neuer Service, kein neues ADR — reine
## Katalog-Erweiterung, kein Code-Pfad geändert.
## Preise sind wie die Balance-Werte in ADR-036/037/039 selbst
## (AURA_VULNERABILITY_THRESHOLD, TIER_BONUS, …) dokumentierte Platzhalter,
## keine finalen Werte: Scrolls gestaffelt nach Nutzwert (PvP-Schutz teurer
## als PvE-/Diebstahl-Schutz), Kristalle gestaffelt nach
## `PickpocketService.TIER_BONUS`/`TIER_COOLDOWN_SEC` — der "strong"-Kristall
## ist trotz nur +20% Bonus (ggü. +5%/+10%) durch seinen 24h-Cooldown pro
## Zielspieler-Paar der mit Abstand teuerste, da er nur sehr selten einsetzbar
## ist.
const BUY_CATALOG := {
	"tool_axe": 25,
	"tool_pickaxe": 30,
	"tool_shovel": 20,
	"tool_scythe": 22,
	# Kräuter + Blumen (herbalism/gardening): Samen/Zwiebeln für die Felder im Dorf, Preise: PlantCatalog
	"chamomile_seed": 4,
	"yarrow_seed": 4,
	"nettle_seed": 4,
	"dandelion_seed": 3,
	"thyme_seed": 5,
	"meadowsweet_seed": 6,
	"poppy_seed": 5,
	"cornflower_seed": 5,
	"calendula_seed": 5,
	"lavender_seed": 6,
	"sunflower_seed": 5,
	"tulip_bulb": 8,
	# Schmiede-Werkzeuge (Voraussetzung für Hochofen/Amboss-Rezepte, siehe docs/smithing-and-crafting.md)
	"tool_tongs": 40,
	"tool_hammer": 45,
	# Eimer (Wasser schöpfen am Brunnen, siehe BuildPieceDefinition.use_*)
	"bucket": 15,
	# Leiter (Klettern aus tiefen Gruben, siehe LadderPlanner)
	"ladder": 10,
	# ADR-038: Item-Schutz-Scrolls
	"scroll_pve_protection": 40,
	"scroll_theft_protection": 40,
	"scroll_pvp_protection": 80,
	# ADR-039: Diebstahl-Kristalle (gestaffelt nach Bonus/Cooldown, siehe oben)
	"theft_crystal_weak": 15,
	"theft_crystal_normal": 60,
	"theft_crystal_strong": 400,
	# Farming — Karottensamen (Wunsch "Farming: Samen pflanzen + ernten"),
	# damit tatsächlich jemand an Samen kommt statt nur per Admin-Befehl.
	# 5 Gold Einkauf gegen CarrotSeed.tres' sell_price=1 (Standard-Spread wie
	# bei tool_axe/tool_pickaxe) — eine Ernte (1-3 Karotten à 4 Gold
	# Verkaufspreis, siehe Carrot.tres) deckt den Samenpreis also locker.
	"carrot_seed": 5,
	# Försterei (Wunsch "Försterei-Skill: Setzlinge kaufen + pflanzen", für alle
	# Baumarten ausgebaut) — verkauft vom neuen ForesterNPC (öffnet denselben
	# globalen Shop wie ShopNPC/ForesterNPC, siehe ShopUIController.
	# _refresh_buy_list(), die immer den ganzen BUY_CATALOG zeigt — kein
	# pro-NPC-Katalog vorhanden, gleiche bewusste Vereinfachung wie beim
	# carrot_seed-Eintrag oben). Gepflanzt wächst daraus ein ECHTER Baum
	# (siehe FarmCropDefinition.grows_into_entity_type) — das Holz kommt erst
	# vom späteren Fällen, der Setzlingspreis ist daher niedrig angesetzt und
	# steigt mit Fäll-XP/Seltenheit der jeweiligen Baumart (siehe
	# WorldService.on_ready() Respawn-Kommentare "schnell/standard/langsam").
	"willow_sapling": 4,
	"pine_sapling":   8,
	"oak_sapling":    8,
	"maple_sapling": 16,
}

var _inventory: InventorySystem   = null
var _currency:  CurrencyService   = null
var _data:      DataService       = null
var _network:   NetworkBridge     = null
var _bus:       IEventBus         = null

# ─────────────────────────────────────────────
# Phase 4: Configure (DI)
# ─────────────────────────────────────────────

func configure(deps: ServiceDeps) -> void:
	_inventory = deps.require(ServiceKeys.INVENTORY) as InventorySystem
	_currency  = deps.require(ServiceKeys.CURRENCY)  as CurrencyService
	_data      = deps.require(ServiceKeys.DATA)       as DataService
	_network   = deps.get_optional(ServiceKeys.NETWORK_BRIDGE) as NetworkBridge
	_bus       = deps.get_optional(ServiceKeys.EVENT_BUS)      as IEventBus
	AppLogger.log_info("ShopService initialisiert (%d Katalog-Einträge)." % BUY_CATALOG.size(), LOG_CAT)

## Phase C8 Late-Inject (siehe BootPipeline.gd).
func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network

# ─────────────────────────────────────────────
# Öffentliche API — Preise
# ─────────────────────────────────────────────

func get_buy_price(item_id: String) -> int:
	return int(BUY_CATALOG.get(item_id, -1))

func is_buyable(item_id: String) -> bool:
	return BUY_CATALOG.has(item_id)

## Verkaufspreis für ein beliebiges Item (nicht nur Katalog-Items — der Shop
## kauft grundsätzlich alles ab, siehe Klassenkommentar).
func get_sell_price(item_id: String) -> int:
	var def := _data.get_item(item_id)
	if not is_instance_valid(def):
		return 0
	return def.sell_price if def.sell_price > 0 else DEFAULT_SELL_PRICE

# ─────────────────────────────────────────────
# Öffentliche API — Kaufen
# ─────────────────────────────────────────────

## Absicht: Item kaufen. Auf einem entfernten Client (Tier 2/3) geht das über
## RPC an die Autorität; Tier 1/Solo bzw. direkt auf der Autorität läuft
## sofort synchron.
func request_buy_item(player_id: String, item_id: String, quantity: int = 1) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.send_shop_buy_item(item_id, quantity, player_id)
	else:
		on_buy_confirmed(item_id, quantity, player_id)

## Autoritäts-Mutation. Erneute Vollprüfung hier (ADR-010 Tier-3-Prinzip) statt
## sich auf die UI/den Aufrufer zu verlassen.
func on_buy_confirmed(item_id: String, quantity: int, player_id: String) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		AppLogger.log_error(
			"on_buy_confirmed: Aufruf auf Nicht-Autorität — verweigert.", LOG_CAT
		)
		return

	if quantity <= 0:
		if is_instance_valid(_bus):
			_bus.shop().emit_shop_transaction_failed(player_id, "invalid_quantity")
		return

	var unit_price := get_buy_price(item_id)
	if unit_price < 0:
		AppLogger.log_warn("on_buy_confirmed: '%s' ist nicht käuflich (Spieler '%s')." % [item_id, player_id], LOG_CAT)
		if is_instance_valid(_bus):
			_bus.shop().emit_shop_transaction_failed(player_id, "not_for_sale")
		return

	var total_price := unit_price * quantity
	if not _currency.has_gold(player_id, total_price):
		AppLogger.log_info("on_buy_confirmed: zu wenig Gold (Spieler '%s', braucht %d)." % [player_id, total_price], LOG_CAT)
		if is_instance_valid(_bus):
			_bus.shop().emit_shop_transaction_failed(player_id, "insufficient_gold")
		return

	# Gold zuerst abziehen — schlägt request_add_item() (z.B. volles Inventar)
	# fehl, wird das Gold sofort zurückerstattet statt den Spieler zu bestehlen.
	if not _currency.request_remove_gold(player_id, total_price):
		if is_instance_valid(_bus):
			_bus.shop().emit_shop_transaction_failed(player_id, "insufficient_gold")
		return

	if not _inventory.request_add_item(item_id, player_id, quantity):
		_currency.request_add_gold(player_id, total_price)  # Rollback
		AppLogger.log_warn("on_buy_confirmed: Inventar voll — Gold zurückerstattet (Spieler '%s')." % player_id, LOG_CAT)
		if is_instance_valid(_bus):
			_bus.shop().emit_shop_transaction_failed(player_id, "inventory_full")
		return

	if is_instance_valid(_bus):
		_bus.shop().emit_shop_transaction_purchase_completed(player_id, item_id, quantity, total_price)
	AppLogger.log_debug("Kauf: Spieler '%s' erwirbt %dx '%s' für %d Gold." % [player_id, quantity, item_id, total_price], LOG_CAT)

# ─────────────────────────────────────────────
# Öffentliche API — Verkaufen
# ─────────────────────────────────────────────

func request_sell_item(player_id: String, item_id: String, quantity: int = 1) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.send_shop_sell_item(item_id, quantity, player_id)
	else:
		on_sell_confirmed(item_id, quantity, player_id)

func on_sell_confirmed(item_id: String, quantity: int, player_id: String) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		AppLogger.log_error(
			"on_sell_confirmed: Aufruf auf Nicht-Autorität — verweigert.", LOG_CAT
		)
		return

	if quantity <= 0:
		if is_instance_valid(_bus):
			_bus.shop().emit_shop_transaction_failed(player_id, "invalid_quantity")
		return

	if not _inventory.has_item(item_id, player_id, quantity):
		AppLogger.log_info("on_sell_confirmed: Spieler '%s' besitzt '%s' nicht (x%d)." % [player_id, item_id, quantity], LOG_CAT)
		if is_instance_valid(_bus):
			_bus.shop().emit_shop_transaction_failed(player_id, "item_not_owned")
		return

	var total_price := get_sell_price(item_id) * quantity

	if not _inventory.remove_item(item_id, player_id, quantity):
		if is_instance_valid(_bus):
			_bus.shop().emit_shop_transaction_failed(player_id, "item_not_owned")
		return

	_currency.request_add_gold(player_id, total_price)
	sale_completed.emit(player_id, item_id, quantity, total_price)
	AppLogger.log_debug("Verkauf: Spieler '%s' verkauft %dx '%s' für %d Gold." % [player_id, quantity, item_id, total_price], LOG_CAT)

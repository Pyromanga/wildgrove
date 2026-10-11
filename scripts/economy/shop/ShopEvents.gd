class_name ShopEvents extends BaseEvents

## ShopEvents — EventBus-Namespace für Shop-NPC-Signale (Round 88).
##
## ADR-050 Phase 2, Round 113: löst die `purchase_completed`/
## `transaction_failed`-Namenskollision auf ShopService auf (ADR-050 Phase 1,
## Round 111 identifiziert). Externer Konsument (ShopUIController) holt sich
## die Service-Instanz per DI (`_ctx.get_shop()`), kein lokaler
## Node-Subtree-Connect — analog BankEvents.gd/AuctionEvents.gd.
##
## Zielnamen nach dem in Round 113 vereinheitlichten Schema
## `<domain>_transaction_<verb>_completed` / `<domain>_transaction_failed`:
##   purchase_completed  -> shop_transaction_purchase_completed
##   transaction_failed  -> shop_transaction_failed
##
## `sale_completed` bleibt bewusst AUSSERHALB dieses Batches — nicht Teil der
## Namenskollision (nur ShopService deklariert diesen Namen), folgt erst in
## einem eigenen Migrations-Schritt (ADR-050 Phase 2: ein Batch pro Round).
##
## Einbinden in EventBus.gd:
##   var shop: ShopEvents
##   # in _ready(): shop = ShopEvents.new()
##
## Verwendung:
##   ctx.bus().shop().shop_transaction_purchase_completed.connect(_on_purchase)

## Emittiert nach jedem erfolgreichen Kauf beim Shop-NPC. Signatur identisch
## zur bisherigen nativen `purchase_completed`-Signal-Signatur.
signal shop_transaction_purchase_completed(player_id: String, item_id: String, quantity: int, total_price: int)

## Umbenannt aus dem ursprünglich generischen `transaction_failed` (ADR-050
## Phase 1 Namenskollisions-Auflösung, Round 111) — siehe Klassenkommentar.
signal shop_transaction_failed(player_id: String, reason: String)

func _init() -> void:
	super._init("Events/Shop")

func emit_shop_transaction_purchase_completed(player_id: String, item_id: String, quantity: int, total_price: int) -> void:
	_log("Shop-Kauf: '%s' erwirbt %dx '%s' für %d Gold." % [player_id, quantity, item_id, total_price])
	shop_transaction_purchase_completed.emit(player_id, item_id, quantity, total_price)

func emit_shop_transaction_failed(player_id: String, reason: String) -> void:
	_log_warn("Shop-Transaktion fehlgeschlagen: '%s' (%s)." % [player_id, reason])
	shop_transaction_failed.emit(player_id, reason)

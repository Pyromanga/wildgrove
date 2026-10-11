class_name AuctionEvents extends BaseEvents

## AuctionEvents — EventBus-Namespace für Auktionshaus-Signale (ADR-035).
##
## ADR-050 Phase 2, Round 113: löst die `purchase_completed`/
## `transaction_failed`-Namenskollision auf AuctionHouseService auf (ADR-050
## Phase 1, Round 111 identifiziert — vier unabhängige Fakten auf Bank/
## Auction/Trade/Shop, zufällig gleicher Name). Externe Konsumenten
## (AuctionHouseUIController) holten sich die Service-Instanz per DI
## (`_ctx.get_auction_house()`), kein lokaler Node-Subtree-Connect — analog
## BankEvents.gd, siehe dortiger Klassenkommentar für die volle Begründung.
##
## Zielnamen nach dem in Round 113 vereinheitlichten Schema
## `<domain>_transaction_<verb>_completed` / `<domain>_transaction_failed`
## (analog bank_transaction_deposit_completed/bank_transaction_failed):
##   purchase_completed  -> auction_transaction_purchase_completed
##   transaction_failed  -> auction_transaction_failed
##
## `listing_created`/`listing_cancelled`/`listings_updated` bleiben bewusst
## AUSSERHALB dieses Batches — sie sind nicht Teil der Namenskollision und
## folgen erst in einem eigenen Migrations-Schritt (ADR-050 Phase 2: ein
## Batch pro Round, kein großer Schritt).
##
## Einbinden in EventBus.gd:
##   var auction: AuctionEvents
##   # in _ready(): auction = AuctionEvents.new()
##
## Verwendung:
##   ctx.bus().auction().auction_transaction_purchase_completed.connect(_on_purchase)

## Emittiert nach jedem erfolgreichen Auktionshaus-Kauf. Signatur identisch
## zur bisherigen nativen `purchase_completed`-Signal-Signatur — keine
## Verhaltensänderung, nur der Transportweg wechselt.
signal auction_transaction_purchase_completed(listing_id: String, buyer_id: String, seller_id: String, item_id: String, quantity: int, price: int)

## Umbenannt aus dem ursprünglich generischen `transaction_failed` (ADR-050
## Phase 1 Namenskollisions-Auflösung, Round 111) — siehe Klassenkommentar.
signal auction_transaction_failed(player_id: String, reason: String)

func _init() -> void:
	super._init("Events/Auction")

func emit_auction_transaction_purchase_completed(listing_id: String, buyer_id: String, seller_id: String, item_id: String, quantity: int, price: int) -> void:
	_log("Auktionshaus-Kauf: '%s' kauft %dx '%s' von '%s' für %d Gold (Listing %s)." % [buyer_id, quantity, item_id, seller_id, price, listing_id])
	auction_transaction_purchase_completed.emit(listing_id, buyer_id, seller_id, item_id, quantity, price)

func emit_auction_transaction_failed(player_id: String, reason: String) -> void:
	_log_warn("Auktionshaus-Transaktion fehlgeschlagen: '%s' (%s)." % [player_id, reason])
	auction_transaction_failed.emit(player_id, reason)

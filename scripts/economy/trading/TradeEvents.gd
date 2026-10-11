class_name TradeEvents extends BaseEvents

## TradeEvents — EventBus-Namespace für Spieler-zu-Spieler-Handel-Signale
## (ADR-035, Handshake-Teil).
##
## ADR-050 Phase 2, Round 113: löst den `transaction_failed`-Teil der
## Namenskollision auf TradeService auf (ADR-050 Phase 1, Round 111
## identifiziert). Externer Konsument (TradeUIController) holt sich die
## Service-Instanz per DI (`_ctx.get_trade_service()`), kein lokaler
## Node-Subtree-Connect — analog BankEvents.gd/AuctionEvents.gd/ShopEvents.gd.
##
## Anders als bei Auction/Shop gibt es hier KEIN `purchase_completed`-
## Gegenstück — TradeService war nie Mitglied dieser Kollisionsgruppe (Handel
## ist kein Kauf/Verkauf, siehe TradeService-Klassenkommentar "kein Escrow").
##
## Zielname nach dem in Round 113 vereinheitlichten Schema
## `<domain>_transaction_failed`:
##   transaction_failed -> trade_transaction_failed
##
## `trade_completed`/`invite_received`/`invite_declined`/`session_*` bleiben
## bewusst AUSSERHALB dieses Batches — nicht Teil der Namenskollision, folgen
## erst in einem eigenen Migrations-Schritt (ADR-050 Phase 2: ein Batch pro
## Round).
##
## Einbinden in EventBus.gd:
##   var trade: TradeEvents
##   # in _ready(): trade = TradeEvents.new()
##
## Verwendung:
##   ctx.bus().trade().trade_transaction_failed.connect(_on_transaction_failed)

## Umbenannt aus dem ursprünglich generischen `transaction_failed` (ADR-050
## Phase 1 Namenskollisions-Auflösung, Round 111) — siehe Klassenkommentar.
## Signatur identisch zur bisherigen nativen Signal-Signatur (3 Parameter,
## abweichend von Bank/Auction/Shop — TradeService kennt `session_id`).
signal trade_transaction_failed(player_id: String, session_id: String, reason: String)

func _init() -> void:
	super._init("Events/Trade")

func emit_trade_transaction_failed(player_id: String, session_id: String, reason: String) -> void:
	_log_warn("Handel-Transaktion fehlgeschlagen: '%s' (%s, Session %s)." % [player_id, reason, session_id])
	trade_transaction_failed.emit(player_id, session_id, reason)

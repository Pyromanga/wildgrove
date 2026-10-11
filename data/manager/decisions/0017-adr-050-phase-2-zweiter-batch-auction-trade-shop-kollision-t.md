# 0017 — ADR-050 Phase 2, zweiter Batch: Auction/Trade/Shop-Kollision (transaction_failed/purchase_completed) vollstaendig auf EventBus migriert

Zeit: 2026-08-06 15:11 UTC
Rolle: manager

## Gewählt
AuctionHouseService/TradeService/ShopService: die drei verbleibenden Namenskollisions-Partner aus Round 111 (nach Bank in Round 112) auf neue Namespaces AuctionEvents/TradeEvents/ShopEvents (EventBus.auction/trade/shop) migriert -- auction_transaction_purchase_completed, auction_transaction_failed, trade_transaction_failed, shop_transaction_purchase_completed, shop_transaction_failed. listing_created/listing_cancelled/listings_updated (Auction), trade_completed/invite_*/session_* (Trade), sale_completed (Shop) bewusst ausserhalb des Batches, kein Kollisions-Fall. BootstrapConfig.tres: event_bus zu optional_deps von shop/trade/auction_house ergaenzt (bei shop gab es vorher gar keinen optional_deps-Eintrag) -- sonst Round-98/112-Bug-Klasse (still null in Produktion). Zusaetzlich auf Nutzeranfrage: BankService.deposit_completed/withdraw_completed (kein Kollisions-Fall, aber gleiche Domain) auf bank_transaction_deposit_completed/bank_transaction_withdrawal_completed migriert, plus fehlenden bank-Eintrag in EventBus.gd Boot-Log-Namespace-Liste ergaenzt.

## Verworfene Alternativen
- Alle drei Services in getrennten Rounds migrieren (analog Bank in Round 112) -- verworfen, weil die Kollision per Definition erst aufgeloest ist wenn alle vier Deklarationen umbenannt sind, ein Zwischenzustand mit nur zwei von vier waere kein sauberer Meilenstein. | Testdateien unveraendert lassen, da sie nur die Assertion-Ziele betreffen -- verworfen, drei Testdateien hatten den bereits aus Bank/PvPDeathLossService bekannten Bug (MockEventBus instanziiert aber nie in configure() durchgereicht), stiller Test-Blindflug ohne Fix.

## Begründung
Round 111 hat die Zielnamen fuer alle vier Kollisions-Partner bereits festgelegt (Signatur-/Connect-Ziel-Vergleich, kein Raten), Round 112 hat mit Bank das Muster am ersten Batch bestaetigt. Dieser Batch schliesst die Kollisionsgruppe vollstaendig ab, bevor der naechste economy-Sub-Batch (Currency/Inventory/Equipment) beginnt -- ADR-050 Phase 2 Prinzip 'ein Batch pro Round', hier auf Gruppenebene statt Einzelservice-Ebene angewendet, weil die drei Services nur gemeinsam einen abgeschlossenen Zustand ergeben. Beide gefundenen Bugs (Test-Wiring, BootstrapConfig) folgen demselben Muster wie der Round-98-Praezedenzfall: deps.get_optional(EVENT_BUS) bleibt still null ohne den jeweiligen Eintrag, kein Compile-Fehler, nur stiller Ausfall zur Laufzeit.

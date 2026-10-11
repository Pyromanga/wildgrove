class_name BankEvents extends BaseEvents

## BankEvents — EventBus-Namespace für Bank-/Lager-Signale (ADR-034).
##
## ADR-050 Phase 2, erster Migrations-Batch (Round 112): ersetzt die drei
## nativen `signal`-Deklarationen, die vorher direkt auf BankService lagen
## (CROSS_LAYER laut `analyze_native_signals.py` — externe Konsumenten in
## BankUIController.gd UND AuctionHouseUIController.gd, beide per DI-Lookup,
## keiner davon ein lokaler Node-Subtree-Connect). Gehört fachlich zu
## scripts/economy/bank/ (wo BankService lebt), nicht in den domänenlosen
## eventbus/-Ordner — analog ZoneEvents (scripts/world/zones/) und
## CombatEvents (scripts/entities/combat/).
##
## `transaction_failed` hieß auf BankService ursprünglich genauso wie auf
## AuctionHouseService/TradeService/ShopService — vier unabhängige Fakten,
## zufällig gleicher Name (ADR-050 Phase 1, Round 111 Namenskollision
## aufgelöst). Hier deshalb bewusst als `bank_transaction_failed` benannt,
## kein Sammel-Signal für alle vier — siehe ADR-050 „Phase 1 Nachtrag".
##
## Einbinden in EventBus.gd:
##   var bank: BankEvents
##   # in _ready():
##   bank = BankEvents.new()
##
## Verwendung:
##   ctx.bus().bank().bank_transaction_deposit_completed.connect(_on_bank_deposit)

## Round 113 (Nutzeranfrage nach Round 112): `deposit_completed`/
## `withdraw_completed` liefen bewusst unverändert weiter, weil sie nie Teil
## der `transaction_failed`-Namenskollision waren (siehe Klassenkommentar
## oben, Historie unten). Für ein einheitliches Namensschema über alle
## economy/-Events hinweg (`<domain>_transaction_<verb>_completed`, analog
## dem neuen Auction/Shop-Batch) jetzt trotzdem umbenannt:
##   deposit_completed  -> bank_transaction_deposit_completed
##   withdraw_completed -> bank_transaction_withdrawal_completed
## Reine Umbenennung, keine Signatur-/Verhaltensänderung.

## Emittiert nach jeder erfolgreichen Ein-/Auszahlung. `kind` ist
## BankService.KIND_ITEM oder BankService.KIND_GOLD (roher String hier
## statt Enum, identisch zur bisherigen nativen Signal-Signatur — keine
## Verhaltensänderung, nur der Transportweg wechselt).
signal bank_transaction_deposit_completed(player_id: String, kind: String, id: String, amount: int)
signal bank_transaction_withdrawal_completed(player_id: String, kind: String, id: String, amount: int)

## Umbenannt aus dem ursprünglich generischen `transaction_failed` (ADR-050
## Phase 1 Namenskollisions-Auflösung, Round 111) — siehe Klassenkommentar.
signal bank_transaction_failed(player_id: String, reason: String)

func _init() -> void:
	super._init("Events/Bank")

func emit_bank_transaction_deposit_completed(player_id: String, kind: String, id: String, amount: int) -> void:
	_log("Bank-Einzahlung: '%s' -> %s '%s' x%d." % [player_id, kind, id, amount])
	bank_transaction_deposit_completed.emit(player_id, kind, id, amount)

func emit_bank_transaction_withdrawal_completed(player_id: String, kind: String, id: String, amount: int) -> void:
	_log("Bank-Abhebung: '%s' -> %s '%s' x%d." % [player_id, kind, id, amount])
	bank_transaction_withdrawal_completed.emit(player_id, kind, id, amount)

func emit_bank_transaction_failed(player_id: String, reason: String) -> void:
	_log_warn("Bank-Transaktion fehlgeschlagen: '%s' (%s)." % [player_id, reason])
	bank_transaction_failed.emit(player_id, reason)

class_name BankUIController
extends Node

## BankUIController — öffnet/befüllt das Bank-Panel, leitet Ein-/Auszahl-
## Klicks an BankService weiter. Analog ShopUIController.

var _visuals: BankVisuals
var _ctx: IUIContext

func setup(visuals: BankVisuals, ctx: IUIContext) -> void:
	_visuals = visuals
	_ctx     = ctx
	_visuals.close_requested.connect(_on_close_requested)
	_visuals.deposit_gold_requested.connect(_on_deposit_gold)
	_visuals.withdraw_gold_requested.connect(_on_withdraw_gold)
	_visuals.deposit_all_requested.connect(_on_deposit_all)

	_ctx.bus().ui().bank_opened.connect(_on_bank_opened)
	_ctx.bus().ui().bank_closed.connect(_on_close_requested)

	var currency := _ctx.get_currency()
	if is_instance_valid(currency):
		currency.gold_changed.connect(func(pid: String, _amt: int, _d: int) -> void: _on_state_changed(pid))

	var inventory := _ctx.get_inventory()
	if is_instance_valid(inventory):
		inventory.inventory_changed.connect(func(pid: String, _items: Array) -> void: _on_state_changed(pid))

	# ADR-050 Phase 2 (Round 112): deposit_completed/withdraw_completed/
	# transaction_failed sind von nativen BankService-Signalen nach
	# EventBus.bank() (Path B, ADR-012) migriert. Round 113: deposit_completed/
	# withdraw_completed zusätzlich auf das einheitliche
	# bank_transaction_deposit_completed/bank_transaction_withdrawal_completed
	# umbenannt (reine Umbenennung, siehe BankEvents.gd).
	_ctx.bus().bank().bank_transaction_failed.connect(_on_transaction_failed)
	_ctx.bus().bank().bank_transaction_deposit_completed.connect(func(pid: String, _k: String, _id: String, _amt: int) -> void: _on_state_changed(pid))
	_ctx.bus().bank().bank_transaction_withdrawal_completed.connect(func(pid: String, _k: String, _id: String, _amt: int) -> void: _on_state_changed(pid))

func _on_bank_opened(npc_display_name: String) -> void:
	_visuals.open(npc_display_name)
	_refresh_all()

func _on_close_requested() -> void:
	_visuals.close()

func _on_state_changed(player_id: String) -> void:
	if not _visuals.panel.visible:
		return
	if player_id != _ctx.get_local_player_id():
		return
	_refresh_all()

func _on_transaction_failed(player_id: String, reason: String) -> void:
	if player_id != _ctx.get_local_player_id():
		return
	_ctx.bus().ui().emit_notification_requested(_reason_text(reason))

func _reason_text(reason: String) -> String:
	match reason:
		"insufficient_gold":
			return "Nicht genug Gold bei dir."
		"insufficient_bank_gold":
			return "Nicht genug Gold in der Bank."
		"inventory_full":
			return "Inventar voll."
		"item_not_owned":
			return "Das hast du nicht (mehr)."
		"item_not_in_bank":
			return "Das liegt nicht in der Bank."
		_:
			return "Vorgang fehlgeschlagen."

func _refresh_all() -> void:
	var currency := _ctx.get_currency()
	var bank := _ctx.get_bank()
	var player_id := _ctx.get_local_player_id()
	if is_instance_valid(currency) and is_instance_valid(bank):
		_visuals.update_gold(currency.get_gold(player_id), bank.get_bank_gold(player_id))
	_refresh_inventory_list()
	_refresh_bank_list()
	var unlocked := QolUnlocks.is_unlocked(QolUnlocks.BANK_DEPOSIT_ALL, _ctx, player_id)
	_visuals.set_deposit_all_enabled(unlocked, QolUnlocks.locked_hint(QolUnlocks.BANK_DEPOSIT_ALL))

## QoL-Sammel-Button (Wunsch "so was wie alles einlagern") — legt für JEDEN
## aktuellen Inventar-Stack einen Einlagern-Request mit der VOLLEN Stückzahl
## an, statt wie der Einzel-Button immer nur 1 Stück. Nutzt bewusst denselben
## request_deposit_item()-Pfad wie ein einzelner Klick (kein neuer,
## ungeprüfter "Bulk"-Request auf BankService-Seite nötig) — Reihenfolge/
## Menge sind identisch zu "jede Zeile einzeln anklicken", nur automatisiert.
func _on_deposit_all() -> void:
	var player_id := _ctx.get_local_player_id()
	if not QolUnlocks.is_unlocked(QolUnlocks.BANK_DEPOSIT_ALL, _ctx, player_id):
		return
	var inventory := _ctx.get_inventory()
	var bank := _ctx.get_bank()
	if not is_instance_valid(inventory) or not is_instance_valid(bank):
		return
	for stack in inventory.get_all_items(player_id):
		bank.request_deposit_item(player_id, stack["id"], int(stack["quantity"]))

func _refresh_inventory_list() -> void:
	var inventory := _ctx.get_inventory()
	if not is_instance_valid(inventory):
		return
	var entries: Array[Dictionary] = []
	for stack in inventory.get_all_items(_ctx.get_local_player_id()):
		entries.append({"item_id": stack["id"], "display_name": stack["name"], "quantity": stack["quantity"]})
	_visuals.set_inventory_entries(entries, _on_deposit_item)

func _refresh_bank_list() -> void:
	var bank := _ctx.get_bank()
	if not is_instance_valid(bank):
		return
	var entries: Array[Dictionary] = []
	for stack in bank.get_bank_items(_ctx.get_local_player_id()):
		entries.append({"item_id": stack["id"], "display_name": stack["name"], "quantity": stack["quantity"]})
	_visuals.set_bank_entries(entries, _on_withdraw_item)

func _on_deposit_item(item_id: String) -> void:
	var bank := _ctx.get_bank()
	if is_instance_valid(bank):
		bank.request_deposit_item(_ctx.get_local_player_id(), item_id, 1)

func _on_withdraw_item(item_id: String) -> void:
	var bank := _ctx.get_bank()
	if is_instance_valid(bank):
		bank.request_withdraw_item(_ctx.get_local_player_id(), item_id, 1)

func _on_deposit_gold(amount: int) -> void:
	var bank := _ctx.get_bank()
	if is_instance_valid(bank) and amount > 0:
		bank.request_deposit_gold(_ctx.get_local_player_id(), amount)

func _on_withdraw_gold(amount: int) -> void:
	var bank := _ctx.get_bank()
	if is_instance_valid(bank) and amount > 0:
		bank.request_withdraw_gold(_ctx.get_local_player_id(), amount)

class_name ShopUIController
extends Node

## ShopUIController — öffnet/befüllt das Shop-Panel und leitet Kauf-/
## Verkauf-Klicks an ShopService weiter. Analog QuestPanelController.

var _visuals: ShopVisuals
var _ctx: IUIContext

func setup(visuals: ShopVisuals, ctx: IUIContext) -> void:
	_visuals = visuals
	_ctx     = ctx
	_visuals.close_requested.connect(_on_close_requested)
	_visuals.sell_all_requested.connect(_on_sell_all)

	_ctx.bus().ui().shop_opened.connect(_on_shop_opened)
	_ctx.bus().ui().shop_closed.connect(_on_close_requested)

	var currency := _ctx.get_currency()
	if is_instance_valid(currency):
		currency.gold_changed.connect(_on_gold_changed)

	var inventory := _ctx.get_inventory()
	if is_instance_valid(inventory):
		inventory.inventory_changed.connect(_on_inventory_changed)

	var shop := _ctx.get_shop()
	if is_instance_valid(shop):
		shop.sale_completed.connect(_on_transaction_completed)
	_ctx.bus().shop().shop_transaction_failed.connect(_on_transaction_failed)
	_ctx.bus().shop().shop_transaction_purchase_completed.connect(_on_transaction_completed)

func _on_shop_opened(npc_display_name: String) -> void:
	_visuals.open(npc_display_name)
	_refresh_gold()
	_refresh_buy_list()
	_refresh_sell_list()

func _on_close_requested() -> void:
	_visuals.close()

func _on_gold_changed(player_id: String, new_amount: int, _delta: int) -> void:
	if player_id != _ctx.get_local_player_id():
		return
	_visuals.update_gold(new_amount)

func _on_inventory_changed(player_id: String, _items: Array) -> void:
	if not _visuals.panel.visible:
		return
	if player_id != _ctx.get_local_player_id():
		return
	_refresh_sell_list()

func _on_transaction_failed(player_id: String, reason: String) -> void:
	if player_id != _ctx.get_local_player_id():
		return
	_ctx.bus().ui().emit_notification_requested(_reason_text(reason))

func _on_transaction_completed(player_id: String, _item_id: String, _quantity: int, _total_price: int) -> void:
	if player_id != _ctx.get_local_player_id():
		return
	_refresh_gold()
	_refresh_buy_list()
	_refresh_sell_list()

func _reason_text(reason: String) -> String:
	match reason:
		"insufficient_gold":
			return "Nicht genug Gold."
		"inventory_full":
			return "Inventar voll."
		"item_not_owned":
			return "Das hast du nicht (mehr)."
		"not_for_sale":
			return "Nicht käuflich."
		_:
			return "Handel fehlgeschlagen."

# ─────────────────────────────────────────────
# Listen-Aufbau
# ─────────────────────────────────────────────

func _refresh_gold() -> void:
	var currency := _ctx.get_currency()
	if is_instance_valid(currency):
		_visuals.update_gold(currency.get_gold(_ctx.get_local_player_id()))

func _refresh_buy_list() -> void:
	var shop := _ctx.get_shop()
	var data := _ctx.get_data()
	if not is_instance_valid(shop) or not is_instance_valid(data):
		return
	var entries: Array[Dictionary] = []
	for item_id in ShopService.BUY_CATALOG:
		var def := data.get_item(item_id)
		entries.append({
			"item_id": item_id,
			"display_name": def.display_name if is_instance_valid(def) else item_id,
			"price": shop.get_buy_price(item_id),
		})
	_visuals.set_buy_entries(entries, _on_buy_pressed)

func _refresh_sell_list() -> void:
	var shop := _ctx.get_shop()
	var inventory := _ctx.get_inventory()
	if not is_instance_valid(shop) or not is_instance_valid(inventory):
		return
	var player_id := _ctx.get_local_player_id()
	var entries: Array[Dictionary] = []
	for stack in inventory.get_all_items(player_id):
		var item_id: String = stack["id"]
		var qty: int = stack["quantity"]
		entries.append({
			"item_id": item_id,
			"display_name": stack["name"],
			"quantity": qty,
			"price": shop.get_sell_price(item_id),
		})
	_visuals.set_sell_entries(entries, _on_sell_pressed)
	var unlocked := QolUnlocks.is_unlocked(QolUnlocks.SHOP_SELL_ALL, _ctx, player_id)
	_visuals.set_sell_all_enabled(unlocked, QolUnlocks.locked_hint(QolUnlocks.SHOP_SELL_ALL))

## QoL-Sammel-Button (Wunsch "so was wie alles verkaufen") — verkauft JEDEN
## aktuellen Inventar-Stack in voller Stückzahl, über denselben
## request_sell_item()-Pfad wie ein einzelner Klick (kein neuer "Bulk"-Request
## auf ShopService-Seite). ShopVisuals fragt vorher zweimal nach (siehe
## _on_sell_all_pressed()), diese Methode löst also erst NACH Bestätigung aus.
func _on_sell_all() -> void:
	var player_id := _ctx.get_local_player_id()
	if not QolUnlocks.is_unlocked(QolUnlocks.SHOP_SELL_ALL, _ctx, player_id):
		return
	var shop := _ctx.get_shop()
	var inventory := _ctx.get_inventory()
	if not is_instance_valid(shop) or not is_instance_valid(inventory):
		return
	for stack in inventory.get_all_items(player_id):
		shop.request_sell_item(player_id, stack["id"], int(stack["quantity"]))

func _on_buy_pressed(item_id: String) -> void:
	var shop := _ctx.get_shop()
	if is_instance_valid(shop):
		shop.request_buy_item(_ctx.get_local_player_id(), item_id, 1)

func _on_sell_pressed(item_id: String) -> void:
	var shop := _ctx.get_shop()
	if is_instance_valid(shop):
		shop.request_sell_item(_ctx.get_local_player_id(), item_id, 1)

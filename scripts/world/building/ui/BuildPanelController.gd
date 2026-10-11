class_name BuildPanelController
extends Node

## BuildPanelController — füllt das Bau-Menü mit den Bauteilen aus DataService.get_all_build_pieces()
## UND den Hausvorlagen aus DataService.get_all_house_templates(), markiert jeweils, was sich der
## Spieler gerade leisten kann (aus Inventar UND Bank — siehe can_afford()/Wunsch "Bauitems können
## auch aus der Bank gezogen werden"; WorldService._can_afford_build() zieht serverseitig genauso
## beides zusammen, siehe dortiger Kommentar, sonst würde das Menü ein Bauteil grau anzeigen, das
## sich tatsächlich bauen ließe).
##
## Wahl eines Bauteils → Fenster schließt, piece_selected(piece_id). Wahl eines Hauses → Fenster
## schließt, house_selected(template_id). HUDBuilder verbindet beide mit dem BuildModeController
## (start()/start_house()).

signal piece_selected(piece_id: String)
## Wahl einer kompletten Hausvorlage — HUDBuilder verbindet das mit
## BuildModeController.start_house(), analog piece_selected/start().
signal house_selected(template_id: String)

const LOG_CAT := "BuildPanel"

var _visuals: BuildPanelVisuals
var _ctx: IUIContext

func setup(visuals: BuildPanelVisuals, ctx: IUIContext) -> void:
	_visuals = visuals
	_ctx = ctx
	_visuals.piece_chosen.connect(_on_piece_chosen)
	_visuals.house_chosen.connect(_on_house_chosen)
	_visuals.panel.visibility_changed.connect(_on_visibility_changed)
	refresh()

func _ready() -> void:
	var inv: InventorySystem = _ctx.get_inventory() if is_instance_valid(_ctx) else null
	if is_instance_valid(inv) and not inv.inventory_changed.is_connected(_on_inventory_changed):
		inv.inventory_changed.connect(_on_inventory_changed)
	# Bank-Bestand zählt jetzt auch mit (siehe can_afford()) — ohne diesen Hook
	# würde das Menü nach einer Einzahlung/Abhebung in der Bank erst beim
	# nächsten Öffnen/Schließen aktualisieren, nicht sofort.
	var bank: BankService = _ctx.get_bank() if is_instance_valid(_ctx) else null
	if is_instance_valid(bank) and is_instance_valid(_ctx.bus()):
		var bank_events := _ctx.bus().bank()
		if not bank_events.bank_transaction_deposit_completed.is_connected(_on_bank_changed):
			bank_events.bank_transaction_deposit_completed.connect(_on_bank_changed)
		if not bank_events.bank_transaction_withdrawal_completed.is_connected(_on_bank_changed):
			bank_events.bank_transaction_withdrawal_completed.connect(_on_bank_changed)

func _exit_tree() -> void:
	var inv: InventorySystem = _ctx.get_inventory() if is_instance_valid(_ctx) else null
	if is_instance_valid(inv) and inv.inventory_changed.is_connected(_on_inventory_changed):
		inv.inventory_changed.disconnect(_on_inventory_changed)
	if is_instance_valid(_ctx) and is_instance_valid(_ctx.bus()):
		var bank_events := _ctx.bus().bank()
		if bank_events.bank_transaction_deposit_completed.is_connected(_on_bank_changed):
			bank_events.bank_transaction_deposit_completed.disconnect(_on_bank_changed)
		if bank_events.bank_transaction_withdrawal_completed.is_connected(_on_bank_changed):
			bank_events.bank_transaction_withdrawal_completed.disconnect(_on_bank_changed)

func refresh() -> void:
	if not is_instance_valid(_visuals):
		return
	_visuals.set_entries(build_entries(_ctx))
	_visuals.set_house_entries(build_house_entries(_ctx))

## Bauteil-Einträge fürs Menü. Statisch, damit ohne UI testbar.
static func build_entries(ctx: IUIContext) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var data: DataService = ctx.get_data() if is_instance_valid(ctx) else null
	if not is_instance_valid(data):
		return entries
	var inv: InventorySystem = ctx.get_inventory()
	var bank: BankService = ctx.get_bank() if is_instance_valid(ctx) else null
	var player_id: String = ctx.get_local_player_id()
	var quests: QuestService = ctx.get_quest() if is_instance_valid(ctx) else null
	for piece in data.get_all_build_pieces():
		# Wunsch "Quest schaltet Spawner-Grabstein per Toggle im Baumenü frei"
		# — siehe BuildPieceDefinition.requires_quest_id Klassenkommentar:
		# der Eintrag erscheint schlicht erst NACH Quest-Abschluss in der
		# Liste, das ist der "Toggle". Ohne QuestService (z.B. Tests ohne
		# vollen Kontext) bleibt ein quest-gated Bauteil sicherheitshalber
		# ausgeblendet statt versehentlich immer sichtbar zu sein.
		if not piece.requires_quest_id.is_empty():
			if not is_instance_valid(quests) or not quests.is_quest_completed(piece.requires_quest_id, player_id):
				continue
		entries.append({
			"id": piece.id,
			"name": piece.display_name,
			"cost_text": format_cost(piece.cost, inv),
			"affordable": can_afford(piece.cost, inv, player_id, bank),
			"kind": int(piece.kind),
		})
	return entries

## Hausvorlagen-Einträge fürs Menü. Statisch, damit ohne UI testbar (wie build_entries()).
## Die Materialkosten kommen aus HouseTemplateDefinition.total_cost() — braucht dieselben
## BuildPieceDefinition-Objekte wie die Einzelteile-Liste, deshalb data.get_build_piece als
## Callable (siehe HouseTemplateDefinition-Klassenkommentar, "kein DataService dort").
static func build_house_entries(ctx: IUIContext) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var data: DataService = ctx.get_data() if is_instance_valid(ctx) else null
	if not is_instance_valid(data):
		return entries
	var inv: InventorySystem = ctx.get_inventory()
	var bank: BankService = ctx.get_bank() if is_instance_valid(ctx) else null
	var player_id: String = ctx.get_local_player_id()
	for house: HouseTemplateDefinition in data.get_all_house_templates():
		var cost: Dictionary = house.total_cost(data.get_build_piece)
		entries.append({
			"id": house.id,
			"name": house.display_name,
			"description": house.description,
			"cost_text": format_cost(cost, inv),
			"affordable": can_afford(cost, inv, player_id, bank),
		})
	return entries

## "3× Holz, 5× Stein" — Item-Namen aus dem Inventar-Register (Fallback: die ID).
static func format_cost(cost: Dictionary, inv: InventorySystem) -> String:
	var parts: PackedStringArray = []
	for item_id: String in cost.keys():
		var item_name: String = item_id
		if is_instance_valid(inv):
			var def: ItemDefinition = inv.get_item_info(item_id)
			if is_instance_valid(def) and not def.display_name.is_empty():
				item_name = def.display_name
		parts.append("%d× %s" % [int(cost[item_id]), item_name])
	return ", ".join(parts)

## bank: optional (Wunsch "Bauitems können auch aus der Bank gezogen werden") —
## Bestand aus Inventar UND Bank zusammen, gleiche Logik wie
## WorldService._available_build_material() (dort die serverseitig
## maßgebliche Version, hier nur fürs Anzeigen im Menü dupliziert, weil
## BuildPanelController rein clientseitig läuft und keinen WorldService-Zugriff
## hat). null (kein BankService verfügbar) verhält sich wie vorher: rein
## inventarbasiert.
static func can_afford(cost: Dictionary, inv: InventorySystem, player_id: String, bank: BankService = null) -> bool:
	if not is_instance_valid(inv):
		return false
	for item_id: String in cost.keys():
		var have: int = 0
		var inv_inst: ItemInstance = inv.get_item_instance(player_id, item_id)
		if is_instance_valid(inv_inst):
			have += inv_inst.quantity
		if is_instance_valid(bank):
			var bank_inst: ItemInstance = bank.get_bank_item_instance(player_id, item_id)
			if is_instance_valid(bank_inst):
				have += bank_inst.quantity
		if have < int(cost[item_id]):
			return false
	return true

func _on_piece_chosen(piece_id: String) -> void:
	_visuals.close()
	piece_selected.emit(piece_id)

func _on_house_chosen(template_id: String) -> void:
	_visuals.close()
	house_selected.emit(template_id)

func _on_visibility_changed() -> void:
	if is_instance_valid(_visuals):
		BuildModeState.set_source(BuildModeState.SOURCE_PANEL, _visuals.panel.visible, _bus())
		if _visuals.panel.visible:
			refresh()

func _bus() -> IEventBus:
	return _ctx.bus() if is_instance_valid(_ctx) else null

func _on_inventory_changed(player_id: String, _items: Array[Dictionary]) -> void:
	if is_instance_valid(_ctx) and player_id == _ctx.get_local_player_id() and is_instance_valid(_visuals) and _visuals.panel.visible:
		refresh()

func _on_bank_changed(player_id: String, _kind: String, _id: String, _amount: int) -> void:
	if is_instance_valid(_ctx) and player_id == _ctx.get_local_player_id() and is_instance_valid(_visuals) and _visuals.panel.visible:
		refresh()

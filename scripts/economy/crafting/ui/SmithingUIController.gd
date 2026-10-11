class_name SmithingUIController
extends Node

## SmithingUIController — öffnet/befüllt das Schmiede-Panel einer Station (Hochofen/Amboss) und
## leitet "Herstellen"-Klicks an SmithingService weiter. Analog ShopUIController.
##
## Geöffnet wird das Panel über UIEvents.smithing_opened(station_kind, station_name), das
## BuildPiece beim "Benutzen" der Station auf dem Peer des Spielers emittiert. Welche Rezepte
## erscheinen, entscheidet allein station_kind (SmithingRecipe.station).
##
## Rückmeldung: Erfolg/Fehlschlag emittiert SmithingService nur auf der AUTORITÄT. Auf einem
## entfernten Client kommt das Ergebnis deshalb über den Inventar-Sync an (Panel aktualisiert sich
## über inventory_changed); eine Fehlermeldung ("zu weit weg", "Inventar voll") sieht dort nur der
## Host — gleiche bekannte Lücke wie beim Shop (shop_transaction_failed).

var _visuals: SmithingVisuals
var _ctx: IUIContext
var _station_kind: String = ""

func setup(visuals: SmithingVisuals, ctx: IUIContext) -> void:
	_visuals = visuals
	_ctx = ctx
	_visuals.close_requested.connect(_on_close_requested)

	_ctx.bus().ui().smithing_opened.connect(_on_smithing_opened)
	_ctx.bus().ui().smithing_closed.connect(_on_close_requested)

	var inventory := _ctx.get_inventory()
	if is_instance_valid(inventory):
		inventory.inventory_changed.connect(_on_inventory_changed)
	var skills := _ctx.get_skill_system()
	if is_instance_valid(skills):
		skills.skill_changed.connect(_on_skill_changed)

	var events := _ctx.bus().smithing()
	if is_instance_valid(events):
		events.smithing_craft_completed.connect(_on_craft_completed)
		events.smithing_craft_failed.connect(_on_craft_failed)

func _on_smithing_opened(station_kind: String, station_name: String) -> void:
	_station_kind = station_kind
	_visuals.open(station_name)
	_refresh()

## Skill der Rezepte dieser Station (alle Rezepte einer Station teilen sich einen Skill) —
## Fallback "smithing". So zeigt das Panel auch für spätere Verarbeitungs-Skills das richtige Level.
func _station_skill_id() -> String:
	var smithing := _ctx.get_smithing()
	if is_instance_valid(smithing) and not _station_kind.is_empty():
		var recipes := smithing.get_recipes_for_station(_station_kind)
		if not recipes.is_empty():
			return recipes[0].skill_id
	return SmithingService.SKILL_ID

func _on_close_requested() -> void:
	_visuals.close()
	_station_kind = ""

func _on_inventory_changed(player_id: String, _items: Array) -> void:
	if _visuals.panel.visible and player_id == _ctx.get_local_player_id():
		_refresh()

func _on_skill_changed(skill_id: String, player_id: String) -> void:
	if _visuals.panel.visible and skill_id == _station_skill_id() and player_id == _ctx.get_local_player_id():
		_refresh()

func _on_craft_completed(player_id: String, _recipe_id: String, output_item_id: String, quantity: int, xp: int) -> void:
	if player_id != _ctx.get_local_player_id():
		return
	var data := _ctx.get_data()
	var def: ItemDefinition = data.get_item(output_item_id) if is_instance_valid(data) else null
	var item_name: String = def.display_name if is_instance_valid(def) else output_item_id
	_ctx.bus().ui().emit_notification_requested("%dx %s hergestellt (+%d XP)" % [quantity, item_name, xp])

func _on_craft_failed(player_id: String, _recipe_id: String, reason: String) -> void:
	if player_id != _ctx.get_local_player_id():
		return
	_ctx.bus().ui().emit_notification_requested(reason_text(reason))

static func reason_text(reason: String) -> String:
	match reason:
		SmithingService.FAIL_LEVEL_TOO_LOW:
			return "Dein Schmiede-Können reicht dafür noch nicht."
		SmithingService.FAIL_MISSING_TOOL:
			return "Dir fehlt das passende Werkzeug."
		SmithingService.FAIL_MISSING_INGREDIENTS:
			return "Dir fehlen Zutaten."
		SmithingService.FAIL_INVENTORY_FULL:
			return "Inventar voll."
		SmithingService.FAIL_NO_STATION:
			return "Benutze die Station erneut, um hier zu arbeiten."
		SmithingService.FAIL_INVALID_QUANTITY, SmithingService.FAIL_UNKNOWN_RECIPE, SmithingService.FAIL_INVALID_PLAYER:
			return "Das lässt sich nicht herstellen."
		_:
			return "Herstellen fehlgeschlagen."

# ─────────────────────────────────────────────
# Listen-Aufbau
# ─────────────────────────────────────────────

func _refresh() -> void:
	var smithing := _ctx.get_smithing()
	var data := _ctx.get_data()
	if not is_instance_valid(smithing) or not is_instance_valid(data) or _station_kind.is_empty():
		return
	var player_id := _ctx.get_local_player_id()
	var skills := _ctx.get_skill_system()
	if is_instance_valid(skills):
		_visuals.update_skill(skills.get_level(_station_skill_id(), player_id))
	var entries: Array[Dictionary] = []
	for recipe in smithing.get_recipes_for_station(_station_kind):
		entries.append(build_entry(recipe, smithing, data, _ctx.get_inventory(), player_id))
	_visuals.set_entries(entries, _on_craft_pressed)

## Eine Panel-Zeile für `recipe`. Statisch/rein (keine Szene nötig), damit Tests die Texte direkt prüfen.
static func build_entry(recipe: SmithingRecipe, smithing: SmithingService, data: DataService, inventory: InventorySystem, player_id: String) -> Dictionary:
	var parts: PackedStringArray = []
	for item_id in recipe.inputs:
		var need: int = int(recipe.inputs[item_id])
		var have: int = _count_owned(inventory, player_id, String(item_id), need)
		parts.append("%s %d/%d" % [_item_name(data, String(item_id)), have, need])
	var block := smithing.get_block_reason(player_id, recipe.id)
	var detail := "Benötigt: %s" % ", ".join(parts)
	if recipe.min_level > 1:
		detail += " · Stufe %d" % recipe.min_level
	if block == SmithingService.FAIL_MISSING_TOOL:
		var tool_names: PackedStringArray = []
		for tool_id in recipe.required_tools:
			tool_names.append(_item_name(data, tool_id))
		detail += "\nWerkzeug: %s" % ", ".join(tool_names)
	elif block == SmithingService.FAIL_LEVEL_TOO_LOW:
		detail += "\nSchmiede-Stufe zu niedrig"
	return {
		"recipe_id": recipe.id,
		"display_name": "%s → %dx %s" % [recipe.display_name, recipe.output_quantity, _item_name(data, recipe.output_item_id)],
		"detail": detail,
		"enabled": block.is_empty(),
	}

static func _count_owned(inventory: InventorySystem, player_id: String, item_id: String, cap: int) -> int:
	if not is_instance_valid(inventory):
		return 0
	# has_item() ist die einzige garantierte Abfrage — zählen bis `need` reicht für die Anzeige.
	var have := 0
	for n in range(cap, 0, -1):
		if inventory.has_item(item_id, player_id, n):
			have = n
			break
	return have

static func _item_name(data: DataService, item_id: String) -> String:
	var def: ItemDefinition = data.get_item(item_id) if is_instance_valid(data) else null
	return def.display_name if is_instance_valid(def) else item_id

func _on_craft_pressed(recipe_id: String) -> void:
	var smithing := _ctx.get_smithing()
	if is_instance_valid(smithing):
		smithing.request_craft(_ctx.get_local_player_id(), recipe_id, 1)

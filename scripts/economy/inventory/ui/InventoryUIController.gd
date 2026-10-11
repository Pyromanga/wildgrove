# res://scripts/economy/inventory/ui/InventoryUIController.gd
class_name InventoryUIController

## InventoryUIController — Steuert das 🎒-Inventar-Panel.
##
## BUG-FIX: Baute vorher nur eine reine Text-Anzeige ("Name ×Menge" als
## Label-Zeilen) ohne jede Interaktion — Ausrüstung war aus diesem Panel
## heraus nicht möglich, obwohl das separate ⚔-Panel (EquipmentUIController)
## bereits einen funktionierenden "Anlegen"-Button für Waffen hat. Jetzt
## bekommt jede ausrüstbare Zeile denselben Button/dieselbe equip()-Logik,
## damit beide Panels konsistent nutzbar sind.

const LOG_CAT := "InventoryUI"

var _visuals:   InventoryVisuals
var _service:   InventorySystem
var _equipment: EquipmentService = null
var _currency:  CurrencyService  = null
var _data:      DataService      = null
var _ctx:       IUIContext       = null
var _item_protection: ItemProtectionService = null

## ADR-038: item_id des gerade zur Anwendung ausgewählten Schutz-Scrolls.
## "" = keine Scroll-Anwendung im Gang (Normalzustand). Gesetzt durch
## _on_scroll_selected(), zurückgesetzt durch _on_cancel_scroll_selection()
## oder nach Empfang von protection_applied()/application_failed().
var _pending_scroll_item_id: String = ""

## BUGFIX (2026-09-20, "Inventar-UI hängt sich nach mehreren Sessions/Reloads
## auf, Zombie-Popups"): InventoryUIController hat kein `extends Node` — ist
## also ein reines RefCounted-Objekt, KEIN Scene-Tree-Node. Wenn HUDManager
## das HUD neu baut (world_scene_ready), wird zwar `_visuals` (ein echter
## Control-Node, Kind von `hud`) über `child.free()` zerstört — der
## Controller selbst aber NICHT, weil die unten verbundenen Lambdas implizit
## `self` festhalten und die Signalverbindung (auf dem langlebigen
## InventorySystem/EquipmentService/etc.) dadurch eine harte Referenz auf
## diesen Controller hält. Ohne explizites disconnect() bleibt der alte
## Controller für immer am Leben ("Zombie") und crasht beim nächsten Event
## gegen sein bereits freigegebenes `_visuals` ("Cannot call method
## 'add_child' on a previously freed instance"). Jeder weitere HUD-Rebuild
## (z.B. Welt-Reload) fügt einen weiteren Zombie hinzu — kumulativ, daher der
## wachsende Lag über eine längere Session. Fix: alle Verbindungen als
## gebundene Callables merken + teardown() zum Trennen; HUDManager ruft
## teardown() jetzt vor dem Verwerfen des alten Controllers auf (siehe dort).
var _is_setup: bool = false
var _inventory_changed_cb:  Callable = Callable()
var _equipment_changed_cb:  Callable = Callable()
var _gold_changed_cb:       Callable = Callable()
var _protection_applied_cb: Callable = Callable()
var _protection_failed_cb:  Callable = Callable()

func setup(
	visuals: InventoryVisuals,
	inv_service: InventorySystem,
	equipment: EquipmentService = null,
	data: DataService = null,
	ctx: IUIContext = null,
	currency: CurrencyService = null,
	item_protection: ItemProtectionService = null
) -> void:
	if _is_setup:
		AppLogger.log_warn(
			"setup() erneut aufgerufen — vorherige Verbindungen werden zuerst getrennt (teardown()).",
			LOG_CAT
		)
		teardown()

	_visuals   = visuals
	_service   = inv_service
	_equipment = equipment
	_data      = data
	_ctx       = ctx
	_currency  = currency
	_item_protection = item_protection
	# R-7 (ADR-022): war hartcodiert auf Spieler 1 — zeigte auf jedem Client
	# ausschließlich Spieler 1s Inventar, unabhängig vom lokalen Spieler dieses
	# Clients. inventory_changed(player_id, items) jetzt gegen die stabile
	# player_id geprüft (ctx.get_local_player_id() — ADR-029 Plan-Schritt 4,
	# Round 63: InventorySystem ist migriert, Key ist jetzt String/player_uuid
	# statt int/peer_id).
	_inventory_changed_cb = func(player_id: String, items: Array[Dictionary]) -> void:
		if player_id == _local_player_id():
			_on_inventory_changed(items)
	_service.inventory_changed.connect(_inventory_changed_cb)

	if is_instance_valid(_equipment):
		# ADR-029 Round 66: equipment_changed liefert jetzt player_id (String).
		_equipment_changed_cb = func(_slot: String, _item: ItemDefinition, player_id: String) -> void:
			if player_id == _local_player_id():
				refresh()
		_equipment.equipment_changed.connect(_equipment_changed_cb)

	if is_instance_valid(_currency):
		_gold_changed_cb = func(player_id: String, new_amount: int, _delta: int) -> void:
			if player_id == _local_player_id():
				_visuals.update_gold(new_amount)
		_currency.gold_changed.connect(_gold_changed_cb)
		_visuals.update_gold(_currency.get_gold(_local_player_id()))

	if is_instance_valid(_item_protection):
		_protection_applied_cb = func(player_id: String, _item_id: String, _protection_type: String) -> void:
			if player_id == _local_player_id():
				_on_protection_applied()
		_item_protection.protection_applied.connect(_protection_applied_cb)

		_protection_failed_cb = func(player_id: String, reason: String) -> void:
			if player_id == _local_player_id():
				_on_protection_failed(reason)
		_item_protection.application_failed.connect(_protection_failed_cb)

	_is_setup = true
	_update_display(_service.get_all_items(_local_player_id()))

## Trennt alle in setup() aufgebauten Signalverbindungen. MUSS von HUDManager
## vor dem Verwerfen dieses Controllers aufgerufen werden (siehe HUDManager.
## _on_world_scene_ready()) — sonst bleibt dieser Controller als Zombie am
## Leben (siehe Klassenkommentar zu _is_setup oben).
func teardown() -> void:
	if is_instance_valid(_service) and _inventory_changed_cb.is_valid():
		if _service.inventory_changed.is_connected(_inventory_changed_cb):
			_service.inventory_changed.disconnect(_inventory_changed_cb)
	if is_instance_valid(_equipment) and _equipment_changed_cb.is_valid():
		if _equipment.equipment_changed.is_connected(_equipment_changed_cb):
			_equipment.equipment_changed.disconnect(_equipment_changed_cb)
	if is_instance_valid(_currency) and _gold_changed_cb.is_valid():
		if _currency.gold_changed.is_connected(_gold_changed_cb):
			_currency.gold_changed.disconnect(_gold_changed_cb)
	if is_instance_valid(_item_protection):
		if _protection_applied_cb.is_valid() and _item_protection.protection_applied.is_connected(_protection_applied_cb):
			_item_protection.protection_applied.disconnect(_protection_applied_cb)
		if _protection_failed_cb.is_valid() and _item_protection.application_failed.is_connected(_protection_failed_cb):
			_item_protection.application_failed.disconnect(_protection_failed_cb)
	_is_setup = false

## R-7 (ADR-022): zentraler Zugriffspunkt für "wer ist der lokale Spieler
## dieses Clients" — Default 1 nur wenn kein IUIContext injiziert wurde
## (isolierte Unit-Tests), sonst IMMER ctx.get_local_peer_id().
func _local_peer_id() -> int:
	return _ctx.get_local_peer_id() if is_instance_valid(_ctx) else 1

## ADR-029 Plan-Schritt 4 (Round 63): String-Pendant zu _local_peer_id(), für
## Aufrufe in InventorySystem (migriert, player_id: String). Kein Default "1"
## möglich (keine sinnvolle String-Entsprechung) — ohne ctx bewusst "" (isolierte
## Unit-Tests müssen ihren eigenen ctx-Double mit get_local_player_id() stellen,
## falls sie diesen Pfad testen wollen).
func _local_player_id() -> String:
	return _ctx.get_local_player_id() if is_instance_valid(_ctx) else ""

## Manuelles Refresh — von HUDBuilder nach dem Build aufgerufen damit der
## initiale Inventar-Stand korrekt angezeigt wird (wird nach on_ready() gebaut).
func refresh() -> void:
	if is_instance_valid(_service):
		_update_display(_service.get_all_items(_local_player_id()))

func _on_inventory_changed(items: Array[Dictionary]) -> void:
	_update_display(items)

func _update_display(items: Array[Dictionary]) -> void:
	_visuals.clear()
	if items.is_empty():
		_visuals.add_empty_label()
		_update_status_text()
		return

	for item in items:
		var item_id: String   = item.get("id", item.get("item_id", ""))
		var item_name: String = item.get("name", item.get("display_name", item_id))
		var qty: int           = item.get("quantity", 1)
		var text := "%s ×%d" % [item_name, qty]

		var equip_cb := Callable()
		var equip_label := "⚔ Anlegen"
		var item_def: ItemDefinition = _data.get_item(item_id) if is_instance_valid(_data) else null
		if is_instance_valid(_equipment) and item_def:
			if item_def is WeaponDefinition:
				var captured_def: WeaponDefinition = item_def as WeaponDefinition
				equip_cb = func() -> void: _on_equip_weapon(captured_def)
			elif item_def is ToolDefinition:
				var captured_tool: ToolDefinition = item_def as ToolDefinition
				equip_cb = func() -> void: _on_equip_tool(captured_tool)
				equip_label = "🪓 Anlegen"
			elif item_def is ArmorDefinition:
				var captured_armor: ArmorDefinition = item_def as ArmorDefinition
				equip_cb = func() -> void: _on_equip_armor(captured_armor)
				equip_label = "🛡 Anlegen"
			elif item_def is WearableDefinition:
				var captured_wear: WearableDefinition = item_def as WearableDefinition
				equip_cb = func() -> void: _on_equip_wearable(captured_wear)
				equip_label = "👕 Anziehen"

		# ADR-038: zweiter Button — "📜 Anwenden" auf einem Schutz-Scroll
		# selbst (startet die Zielauswahl), "🎯 Ziel" auf jedem ANDEREN Item
		# während eine Zielauswahl läuft, "✖ Abbrechen" wieder auf dem Scroll
		# selbst solange die Auswahl noch aktiv ist.
		var secondary_cb := Callable()
		var secondary_label := ""
		var is_scroll := is_instance_valid(_item_protection) and item_def and not item_def.grants_protection_type.is_empty()
		if is_scroll and _pending_scroll_item_id.is_empty():
			var captured_scroll_id := item_id
			secondary_cb = func() -> void: _on_scroll_selected(captured_scroll_id)
			secondary_label = "📜 Anwenden"
		elif is_scroll and _pending_scroll_item_id == item_id:
			secondary_cb = func() -> void: _on_cancel_scroll_selection()
			secondary_label = "✖ Abbrechen"
		elif not _pending_scroll_item_id.is_empty() and item_id != _pending_scroll_item_id:
			var captured_target_id := item_id
			secondary_cb = func() -> void: _on_target_selected(captured_target_id)
			secondary_label = "🎯 Ziel"

		_visuals.add_row(text, equip_cb, equip_label, secondary_cb, secondary_label)

	_update_status_text()

## ADR-038: Statuszeile für die Zielauswahl — leer/ausgeblendet außerhalb
## einer laufenden Scroll-Anwendung.
func _update_status_text() -> void:
	if _pending_scroll_item_id.is_empty():
		_visuals.clear_status()
		return
	var scroll_name := _pending_scroll_item_id
	if is_instance_valid(_data):
		var def: ItemDefinition = _data.get_item(_pending_scroll_item_id)
		if def:
			scroll_name = def.display_name
	_visuals.set_status("Ziel wählen für '%s' — 🎯 auf dem gewünschten Item, oder ✖ Abbrechen." % scroll_name)

## ADR-027: request_equip() statt equip() direkt — die Autorität löst
## PlayerVisuals jetzt selbst über WorldService.get_player_visuals(peer_id)
## auf (siehe EquipmentService.on_equip_confirmed()), deshalb entfällt die
## bisherige _find_local_player_visuals()-Kopie hier komplett. Nebeneffekt:
## dieser Pfad läuft jetzt netzwerk-sicher UND durch die has_item()-Prüfung.
func _on_equip_weapon(weapon_def: WeaponDefinition) -> void:
	if not is_instance_valid(_equipment):
		return

	# ADR-029 Round 66: request_equip() erwartet jetzt player_id (String).
	var player_id := _local_player_id()
	_equipment.request_equip("weapon", weapon_def.id, player_id)
	AppLogger.log_info("Equip angefordert über Inventar-Panel: '%s'." % weapon_def.display_name, LOG_CAT)

## Round 88: Analog _on_equip_weapon(), Slot "tool" statt "weapon".
## Rüstung: Slot kommt aus der Definition (ArmorDefinition.get_slot_id()); EquipmentService prüft
## ihn serverseitig erneut (on_equip_confirmed()).
func _on_equip_armor(armor_def: ArmorDefinition) -> void:
	if not is_instance_valid(_equipment):
		return
	_equipment.request_equip(armor_def.get_slot_id(), armor_def.id, _local_player_id())
	AppLogger.log_info("Equip angefordert über Inventar-Panel: '%s'." % armor_def.display_name, LOG_CAT)

## Kleidung: Slot kommt aus der Definition (WearableDefinition.wear_slot); EquipmentService prüft
## Besitz und Slot serverseitig erneut und bucht das bisher getragene Teil zurück ins Inventar.
func _on_equip_wearable(wear_def: WearableDefinition) -> void:
	if not is_instance_valid(_equipment):
		return
	_equipment.request_equip(wear_def.wear_slot, wear_def.id, _local_player_id())
	AppLogger.log_info("Anziehen angefordert über Inventar-Panel: '%s'." % wear_def.display_name, LOG_CAT)

func _on_equip_tool(tool_def: ToolDefinition) -> void:
	if not is_instance_valid(_equipment):
		return
	var player_id := _local_player_id()
	_equipment.request_equip(EquipmentService.SLOT_TOOL, tool_def.id, player_id)
	AppLogger.log_info("Equip angefordert über Inventar-Panel: '%s'." % tool_def.display_name, LOG_CAT)

func toggle() -> void:
	_visuals.toggle()

# ─────────────────────────────────────────────
# ADR-038: Schutz-Scroll auf Item anwenden
# ─────────────────────────────────────────────

## Startet die Zielauswahl für ein Schutz-Scroll — kein Netzwerk-Call hier,
## nur lokaler UI-Zustand (analog "Angebot bearbeiten" in TradeUIController).
func _on_scroll_selected(scroll_item_id: String) -> void:
	_pending_scroll_item_id = scroll_item_id
	_update_display(_service.get_all_items(_local_player_id()))

func _on_cancel_scroll_selection() -> void:
	_pending_scroll_item_id = ""
	_update_display(_service.get_all_items(_local_player_id()))

## Zielauswahl abgeschlossen — schickt die eigentliche Anfrage an die
## Autorität. Zustand wird erst bei Empfang von protection_applied()/
## application_failed() zurückgesetzt (nicht schon hier optimistisch), damit
## ein fehlgeschlagener Versuch nicht so aussieht als sei nichts passiert.
func _on_target_selected(target_item_id: String) -> void:
	if not is_instance_valid(_item_protection) or _pending_scroll_item_id.is_empty():
		return
	_item_protection.request_apply_protection(_pending_scroll_item_id, target_item_id, _local_player_id())
	AppLogger.log_info(
		"Schutz-Anwendung angefordert über Inventar-Panel: Scroll '%s' auf '%s'."
		% [_pending_scroll_item_id, target_item_id],
		LOG_CAT
	)

func _on_protection_applied() -> void:
	_pending_scroll_item_id = ""
	_update_display(_service.get_all_items(_local_player_id()))
	_visuals.set_status("Schutz angewendet.")

func _on_protection_failed(reason: String) -> void:
	_pending_scroll_item_id = ""
	_update_display(_service.get_all_items(_local_player_id()))
	_visuals.set_status("Schutz-Anwendung fehlgeschlagen: %s" % reason)

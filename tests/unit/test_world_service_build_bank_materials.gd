# res://tests/unit/test_world_service_build_bank_materials.gd
extends GutTest

## Unit-Tests für FEATURE "Bauitems können auch aus der Bank gezogen werden" —
## WorldService._can_afford_build()/_pay_build()/_refund_build() zählen und
## verbrauchen jetzt Inventar UND Bank zusammen, nicht mehr nur Inventar.
##
## Strategie: echte InventorySystem-/BankService-/CurrencyService-Instanzen
## (gleiches Muster wie test_bank_service.gd), direkt auf die entsprechenden
## Felder eines mit leeren Deps konfigurierten WorldService gesteckt (siehe
## test_world_service.gd — configure() mit ServiceDeps.from_dict({}) ist laut
## dortiger Doku ausdrücklich der null-sichere Standardpfad für genau so
## einen minimalen Test-Aufbau).

class MockItemDef extends ItemDefinition:
	func _init(p_name: String, p_max_stack: int = 999) -> void:
		display_name = p_name
		max_stack     = p_max_stack

class MockDataService extends DataService:
	func get_all_items() -> Dictionary:
		return _items

const WOOD := "log_oak"
const P1 := "p1"

var _svc: WorldService
var _inventory: InventorySystem
var _bank: BankService
var _currency: CurrencyService
var _ds: MockDataService
var _bus: MockEventBus
var _save: SaveSystem

func before_each() -> void:
	_ds = MockDataService.new()
	_ds._items[WOOD] = MockItemDef.new("Holzstamm")
	_bus = MockEventBus.new()
	_save = SaveSystem.new()
	_save.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: _bus}))

	_inventory = InventorySystem.new()
	_inventory.configure(ServiceDeps.from_dict({
		ServiceKeys.DATA:        _ds,
		ServiceKeys.SAVE_SYSTEM: _save,
		ServiceKeys.EVENT_BUS:   _bus,
	}))

	_currency = CurrencyService.new()
	_currency.configure(ServiceDeps.from_dict({
		ServiceKeys.SAVE_SYSTEM: _save,
		ServiceKeys.EVENT_BUS:   _bus,
	}))

	_bank = BankService.new()
	_bank.configure(ServiceDeps.from_dict({
		ServiceKeys.INVENTORY:   _inventory,
		ServiceKeys.CURRENCY:    _currency,
		ServiceKeys.DATA:        _ds,
		ServiceKeys.SAVE_SYSTEM: _save,
		ServiceKeys.EVENT_BUS:   _bus,
	}))

	_svc = WorldService.new()
	add_child_autofree(_svc)
	_svc.configure(ServiceDeps.from_dict({}))
	_svc._ent_inventory = _inventory
	_svc._ent_bank = _bank

func after_each() -> void:
	_svc.on_cleanup()
	_inventory.on_cleanup()
	_svc = null
	_inventory = null
	_currency = null
	_bank = null

# ─────────────────────────────────────────────
# _can_afford_build() — kombinierter Bestand
# ─────────────────────────────────────────────

func test_afford_true_when_inventory_alone_covers_cost() -> void:
	_inventory.on_item_add_confirmed(WOOD, 100, P1)
	assert_true(_svc._can_afford_build(P1, {WOOD: 100}))

func test_afford_false_when_neither_covers_cost() -> void:
	_inventory.on_item_add_confirmed(WOOD, 10, P1)
	assert_false(_svc._can_afford_build(P1, {WOOD: 100}))

func test_afford_true_when_inventory_and_bank_combined_cover_cost() -> void:
	_inventory.on_item_add_confirmed(WOOD, 40, P1)
	_bank.on_deposit_item_confirmed(WOOD, 60, P1)
	# 40 im Rucksack allein würden NICHT reichen — erst zusammen mit der Bank.
	assert_true(_svc._can_afford_build(P1, {WOOD: 100}))

func test_afford_false_when_combined_still_not_enough() -> void:
	_inventory.on_item_add_confirmed(WOOD, 40, P1)
	_bank.on_deposit_item_confirmed(WOOD, 30, P1)
	assert_false(_svc._can_afford_build(P1, {WOOD: 100}))

# ─────────────────────────────────────────────
# _pay_build() — Reihenfolge Inventar zuerst, dann Bank
# ─────────────────────────────────────────────

func test_pay_takes_from_inventory_first_then_bank() -> void:
	_inventory.on_item_add_confirmed(WOOD, 40, P1)
	_bank.on_deposit_item_confirmed(WOOD, 60, P1)

	assert_true(_svc._pay_build(P1, {WOOD: 100}))

	assert_false(_inventory.has_item(WOOD, P1, 1), "Inventar-Anteil muss vollständig verbraucht sein")
	var bank_inst := _bank.get_bank_item_instance(P1, WOOD)
	assert_eq(bank_inst.quantity, 20, "Bank muss nur um den FEHLENDEN Rest (60) verringert werden")

func test_pay_does_not_touch_bank_when_inventory_alone_suffices() -> void:
	_inventory.on_item_add_confirmed(WOOD, 100, P1)
	_bank.on_deposit_item_confirmed(WOOD, 50, P1)

	assert_true(_svc._pay_build(P1, {WOOD: 80}))

	assert_true(_inventory.has_item(WOOD, P1, 20), "20 müssen im Inventar übrig bleiben (100-80)")
	assert_eq(_bank.get_bank_item_instance(P1, WOOD).quantity, 50, "Bank darf unangetastet bleiben")

func test_pay_fails_and_rolls_back_when_still_not_enough() -> void:
	_inventory.on_item_add_confirmed(WOOD, 40, P1)
	_bank.on_deposit_item_confirmed(WOOD, 30, P1)

	assert_false(_svc._pay_build(P1, {WOOD: 100}))

	assert_true(_inventory.has_item(WOOD, P1, 40), "Fehlgeschlagene Zahlung darf das Inventar nicht anfassen")
	assert_eq(_bank.get_bank_item_instance(P1, WOOD).quantity, 30, "Fehlgeschlagene Zahlung darf die Bank nicht anfassen")

func test_pay_rolls_back_multi_item_cost_if_one_item_insufficient() -> void:
	_ds._items["stone"] = MockItemDef.new("Stein")
	_inventory.on_item_add_confirmed(WOOD, 100, P1)
	_inventory.on_item_add_confirmed("stone", 5, P1)  # zu wenig, keine Bank-Deckung

	assert_false(_svc._pay_build(P1, {WOOD: 100, "stone": 50}))

	assert_true(_inventory.has_item(WOOD, P1, 100), "Bereits abgezogenes Holz muss bei Fehlschlag zurückgebucht werden")

# ─────────────────────────────────────────────
# _refund_build() — geht zurück ins Inventar
# ─────────────────────────────────────────────

func test_refund_returns_items_to_inventory() -> void:
	_svc._refund_build(P1, {WOOD: 25})
	assert_true(_inventory.has_item(WOOD, P1, 25))

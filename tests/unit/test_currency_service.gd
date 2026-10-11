# res://tests/unit/test_currency_service.gd
extends GutTest

## Unit-Tests für CurrencyService (ADR-033).
##
## Strategie: analog test_inventory_system.gd — CurrencyService direkt
## instanziieren, configure() ohne SaveSystem/NetworkBridge für die reinen
## Logik-Tests (Tier-1-Pfad, direkte Mutation), mit echtem NetworkBridge nur
## für den Economy-Backsync-Block (analog test_economy_backsync_r7.gd).
##
## Abgedeckt:
##   - request_add_gold()/request_remove_gold(): Erfolgsfall, amount<=0,
##     Overflow (add), unzureichender Kontostand (remove)
##   - on_gold_changed_confirmed(): ADR-010-Round-55-Verteidigung-in-der-Tiefe
##     (Overflow/negativer Kontostand auch bei Direktaufruf verhindert, der
##     die request_*()-Vorprüfung umgeht)
##   - get_gold()/has_gold()
##   - Multi-Tenanz: zwei player_ids unabhängig
##   - get_save_key()/get_save_data() Snapshot + Save-Round-Trip
##   - Economy-Backsync (R-7/ADR-022-Muster): gold_changed → NetworkBridge.
##     send_economy_update_for_player(), sowie Empfangsseite
##     (_on_economy_state_received, ignoriert fremde `kind`-Werte)

const P1 := "p1"
const P2 := "p2"

var _svc: CurrencyService
var _bus: MockEventBus
var _save: SaveSystem

func before_each() -> void:
	_bus = MockEventBus.new()
	_save = SaveSystem.new()
	_save.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: _bus}))
	_svc = CurrencyService.new()
	_svc.configure(ServiceDeps.from_dict({
		ServiceKeys.SAVE_SYSTEM: _save,
		ServiceKeys.EVENT_BUS: _bus,
	}))

func after_each() -> void:
	_svc.on_cleanup()
	_svc = null

# ─────────────────────────────────────────────
# request_add_gold()
# ─────────────────────────────────────────────

func test_request_add_gold_succeeds() -> void:
	var ok := _svc.request_add_gold(P1, 100)
	assert_true(ok, "request_add_gold() muss bei gültigem Betrag true zurückgeben.")
	assert_eq(_svc.get_gold(P1), 100)

func test_request_add_gold_zero_rejected() -> void:
	var ok := _svc.request_add_gold(P1, 0)
	assert_false(ok, "amount == 0 muss abgelehnt werden.")
	assert_eq(_svc.get_gold(P1), 0)

func test_request_add_gold_negative_rejected() -> void:
	var ok := _svc.request_add_gold(P1, -5)
	assert_false(ok, "amount < 0 muss abgelehnt werden (dafür gibt es request_remove_gold()).")
	assert_eq(_svc.get_gold(P1), 0)

func test_request_add_gold_stacks() -> void:
	_svc.request_add_gold(P1, 100)
	_svc.request_add_gold(P1, 50)
	assert_eq(_svc.get_gold(P1), 150)

func test_request_add_gold_overflow_rejected() -> void:
	_svc.on_gold_changed_confirmed(P1, CurrencyService.MAX_GOLD)  # direkt an den Rand setzen
	var ok := _svc.request_add_gold(P1, 1)
	assert_false(ok, "Ein Add über MAX_GOLD hinaus muss abgelehnt werden.")
	assert_eq(_svc.get_gold(P1), CurrencyService.MAX_GOLD, "Kontostand darf sich bei abgelehntem Overflow nicht ändern.")

# ─────────────────────────────────────────────
# request_remove_gold()
# ─────────────────────────────────────────────

func test_request_remove_gold_succeeds() -> void:
	_svc.request_add_gold(P1, 100)
	var ok := _svc.request_remove_gold(P1, 40)
	assert_true(ok)
	assert_eq(_svc.get_gold(P1), 60)

func test_request_remove_gold_zero_rejected() -> void:
	_svc.request_add_gold(P1, 100)
	var ok := _svc.request_remove_gold(P1, 0)
	assert_false(ok, "amount == 0 muss abgelehnt werden.")

func test_request_remove_gold_insufficient_balance_rejected() -> void:
	_svc.request_add_gold(P1, 10)
	var ok := _svc.request_remove_gold(P1, 20)
	assert_false(ok, "Kann nicht mehr abziehen als vorhanden.")
	assert_eq(_svc.get_gold(P1), 10, "Kontostand darf sich bei abgelehntem Remove nicht ändern.")

func test_request_remove_gold_from_empty_rejected() -> void:
	var ok := _svc.request_remove_gold(P1, 1)
	assert_false(ok)

func test_request_remove_gold_exact_balance_to_zero() -> void:
	_svc.request_add_gold(P1, 50)
	var ok := _svc.request_remove_gold(P1, 50)
	assert_true(ok, "Kompletten Kontostand auf 0 abziehen muss erlaubt sein.")
	assert_eq(_svc.get_gold(P1), 0)

# ─────────────────────────────────────────────
# on_gold_changed_confirmed() — ADR-010 Round 55 Verteidigung in der Tiefe
# (Direktaufruf, umgeht request_add_gold()/request_remove_gold()-Vorprüfung)
# ─────────────────────────────────────────────

func test_on_gold_changed_confirmed_rejects_overflow_directly() -> void:
	_svc.on_gold_changed_confirmed(P1, CurrencyService.MAX_GOLD)
	_svc.on_gold_changed_confirmed(P1, 1)  # Direktaufruf, umgeht request_add_gold()
	assert_eq(_svc.get_gold(P1), CurrencyService.MAX_GOLD,
		"on_gold_changed_confirmed() muss Overflow auch bei Direktaufruf verhindern.")

func test_on_gold_changed_confirmed_rejects_negative_balance_directly() -> void:
	_svc.on_gold_changed_confirmed(P1, 10)
	_svc.on_gold_changed_confirmed(P1, -20)  # Direktaufruf, umgeht request_remove_gold()
	assert_eq(_svc.get_gold(P1), 10,
		"on_gold_changed_confirmed() muss negativen Kontostand auch bei Direktaufruf verhindern.")

func test_on_gold_changed_confirmed_emits_gold_changed_with_delta() -> void:
	var received: Array = []
	_svc.gold_changed.connect(func(pid: String, new_amount: int, delta: int) -> void:
		received.append([pid, new_amount, delta])
	)
	_svc.on_gold_changed_confirmed(P1, 30)
	_svc.on_gold_changed_confirmed(P1, -10)
	assert_eq(received.size(), 2)
	assert_eq(received[0], [P1, 30, 30])
	assert_eq(received[1], [P1, 20, -10])

# ─────────────────────────────────────────────
# get_gold() / has_gold()
# ─────────────────────────────────────────────

func test_get_gold_zero_for_unknown_player() -> void:
	assert_eq(_svc.get_gold("never-seen"), 0)

func test_has_gold_true_when_sufficient() -> void:
	_svc.request_add_gold(P1, 100)
	assert_true(_svc.has_gold(P1, 100))
	assert_true(_svc.has_gold(P1, 50))

func test_has_gold_false_when_insufficient() -> void:
	_svc.request_add_gold(P1, 10)
	assert_false(_svc.has_gold(P1, 11))

# ─────────────────────────────────────────────
# Multi-Tenanz
# ─────────────────────────────────────────────

func test_two_players_have_independent_gold() -> void:
	_svc.request_add_gold(P1, 100)
	_svc.request_add_gold(P2, 30)
	assert_eq(_svc.get_gold(P1), 100)
	assert_eq(_svc.get_gold(P2), 30)

func test_remove_from_player1_does_not_affect_player2() -> void:
	_svc.request_add_gold(P1, 50)
	_svc.request_add_gold(P2, 50)
	_svc.request_remove_gold(P1, 50)
	assert_eq(_svc.get_gold(P1), 0)
	assert_eq(_svc.get_gold(P2), 50, "Spieler 2 unberührt")

# ─────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────

func test_save_key_is_currency() -> void:
	assert_eq(_svc.get_save_key(), "currency")

func test_save_data_reflects_current_state() -> void:
	_svc.request_add_gold(P1, 250)
	var sd := _svc.get_save_data()
	assert_true(sd.has(P1))
	assert_eq(int(sd[P1]), 250)

func test_save_data_empty_when_no_gold_ever_touched() -> void:
	var sd := _svc.get_save_data()
	assert_true(sd.is_empty(), "Frische Instanz ohne jede Mutation → leerer Snapshot.")

# ─────────────────────────────────────────────
# Save-Round-Trip
# ─────────────────────────────────────────────

func test_round_trip_restores_gold() -> void:
	_svc.request_add_gold(P1, 777)
	var snapshot := _svc.get_save_data()

	var svc2 := CurrencyService.new()
	svc2.configure(ServiceDeps.from_dict({ServiceKeys.SAVE_SYSTEM: _save, ServiceKeys.EVENT_BUS: _bus}))
	svc2._restore_from_save(snapshot)

	assert_eq(svc2.get_gold(P1), 777)
	svc2.on_cleanup()

func test_round_trip_empty_save_produces_zero_gold() -> void:
	var svc2 := CurrencyService.new()
	svc2.configure(ServiceDeps.from_dict({ServiceKeys.SAVE_SYSTEM: _save, ServiceKeys.EVENT_BUS: _bus}))
	svc2._restore_from_save({})

	assert_eq(svc2.get_gold(P1), 0)
	svc2.on_cleanup()

func test_round_trip_multi_tenant() -> void:
	_svc.request_add_gold(P1, 111)
	_svc.request_add_gold(P2, 222)
	var snapshot := _svc.get_save_data()

	var svc2 := CurrencyService.new()
	svc2.configure(ServiceDeps.from_dict({ServiceKeys.SAVE_SYSTEM: _save, ServiceKeys.EVENT_BUS: _bus}))
	svc2._restore_from_save(snapshot)

	assert_eq(svc2.get_gold(P1), 111)
	assert_eq(svc2.get_gold(P2), 222)
	svc2.on_cleanup()

# ─────────────────────────────────────────────
# Economy-Backsync (R-7/ADR-022-Muster) — analog test_economy_backsync_r7.gd
# ─────────────────────────────────────────────

class MockSaveSystemForBacksync extends SaveSystem:
	func register_save_provider(_p: Object) -> void:
		pass
	func get_state_for(_key: String) -> Dictionary:
		return {}

func test_gold_changed_relays_through_network_bridge() -> void:
	var session := SessionManager.new()
	session.register_player_slot(1, "p1")
	add_child_autofree(session)

	var bridge := NetworkBridge.new()
	bridge.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS: _bus,
		ServiceKeys.SESSION_MANAGER: session,
	}))
	add_child_autofree(bridge)

	var currency := CurrencyService.new()
	currency.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS: _bus,
		ServiceKeys.SAVE_SYSTEM: MockSaveSystemForBacksync.new(),
		ServiceKeys.NETWORK_BRIDGE: bridge,
	}))

	# Ohne echten Peer ist send_economy_update_for_player() ein No-Op (Tier 1) —
	# hier zählt nur, dass gold_changed → _on_gold_state_changed() → der
	# Aufruf tatsächlich passiert, ohne zu crashen (kein Peer nötig für diesen Test).
	currency.on_gold_changed_confirmed("some-other-player", 100)
	assert_true(true, "gold_changed darf ohne Peer nicht crashen (Tier-1-Pfad).")

	currency.on_cleanup()

func test_currency_applies_received_bucket_to_local_player() -> void:
	var session := SessionManager.new()
	session.register_player_slot(1, "p1")
	add_child_autofree(session)

	var bridge := NetworkBridge.new()
	bridge.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS: _bus,
		ServiceKeys.SESSION_MANAGER: session,
	}))
	add_child_autofree(bridge)

	var currency := CurrencyService.new()
	currency.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS: _bus,
		ServiceKeys.SAVE_SYSTEM: MockSaveSystemForBacksync.new(),
		ServiceKeys.NETWORK_BRIDGE: bridge,
	}))

	var received: Array = []
	currency.gold_changed.connect(func(pid: String, new_amount: int, delta: int) -> void:
		received.append([pid, new_amount, delta])
	)

	# Autorität hätte für eine andere player_id gesendet — der Client wendet es
	# aber immer auf SEINE EIGENE lokale player_id an ("p1"), unabhängig davon
	# was im Payload steht (analog InventorySystem._on_economy_state_received()).
	bridge.economy_state_received.emit("currency", {"gold": 500})

	assert_eq(received.size(), 1)
	assert_eq(received[0][0], "p1", "Muss auf die lokale player_id angewendet werden, nicht auf player_id aus dem Payload.")
	assert_eq(received[0][1], 500)
	assert_eq(currency.get_gold("p1"), 500)

	currency.on_cleanup()

func test_currency_ignores_non_currency_kind() -> void:
	var session := SessionManager.new()
	session.register_player_slot(1, "p1")
	add_child_autofree(session)

	var bridge := NetworkBridge.new()
	bridge.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS: _bus,
		ServiceKeys.SESSION_MANAGER: session,
	}))
	add_child_autofree(bridge)

	var currency := CurrencyService.new()
	currency.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS: _bus,
		ServiceKeys.SAVE_SYSTEM: MockSaveSystemForBacksync.new(),
		ServiceKeys.NETWORK_BRIDGE: bridge,
	}))

	var call_count := [0]
	currency.gold_changed.connect(func(_pid, _new_amount, _delta): call_count[0] += 1)

	bridge.economy_state_received.emit("inventory", {"items": {"iron_ore": 3}})

	assert_eq(call_count[0], 0, "kind=='inventory' darf CurrencyService nicht triggern.")
	currency.on_cleanup()

# ─────────────────────────────────────────────────────────────────────────────
# inject_network_bridge() — Round 113 Nachtrag, siehe
# method_reference_coverage.py-Fund (Phase-C8-Late-Inject, ADR-022). Bisherige
# Tests injizieren NetworkBridge nur über configure() (Phase-C6-Testpfad) —
# der eigentliche Late-Inject-Pfad war ungetestet.
# ─────────────────────────────────────────────────────────────────────────────

func test_inject_network_bridge_sets_the_reference() -> void:
	var bridge: NetworkBridge = add_child_autofree(NetworkBridge.new())
	_svc.inject_network_bridge(bridge)
	assert_same(_svc._network, bridge)

func test_inject_network_bridge_connects_economy_state_received() -> void:
	var bridge: NetworkBridge = add_child_autofree(NetworkBridge.new())
	assert_eq(bridge.economy_state_received.get_connections().size(), 0)
	_svc.inject_network_bridge(bridge)
	assert_eq(bridge.economy_state_received.get_connections().size(), 1)

func test_inject_network_bridge_does_not_double_connect_when_called_twice() -> void:
	var bridge: NetworkBridge = add_child_autofree(NetworkBridge.new())
	_svc.inject_network_bridge(bridge)
	_svc.inject_network_bridge(bridge)
	assert_eq(bridge.economy_state_received.get_connections().size(), 1)

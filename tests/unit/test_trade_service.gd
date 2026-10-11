# res://tests/unit/test_trade_service.gd
extends GutTest

## Unit-Tests für TradeService (ADR-035, Handshake-Teil).
##
## Strategie: TradeService extends Service (RefCounted) — kein add_child
## nötig. InventorySystem und CurrencyService werden ECHT instanziiert (genau
## wie in test_bank_service.gd) — der atomare Swap in _execute_trade() ist
## das eigentliche Verhalten unter Test, und der soll gegen den echten
## Gold-/Item-Bestand laufen, nicht gegen einen Stub der das Rollback
## wegabstrahiert. Kein NetworkBridge konfiguriert -> _network bleibt null ->
## alle request_*() nehmen den synchronen else-Zweig direkt zu
## on_*_confirmed() (Tier-1-Pfad, analog test_shop_service.gd). Den
## Nicht-Autorität-Guard (_require_authority mit echtem MultiplayerPeer)
## testet dieses File bewusst nicht.
##
## Abgedeckt:
##   - Einladung: on_invite_confirmed (Erfolg, Selbst-Einladung, bereits in
##     Session), Annehmen/Ablehnen der Einladung
##   - Angebot ändern: Erfolg + Reset von ready/confirmed, ungültiges Gold/
##     Item-Menge
##   - Ready/Confirm: Zwei-Stufen-Gate ("not_ready" ohne beidseitiges ready),
##     Un-Ready setzt confirmed zurück
##   - Atomarer Swap: Erfolgsfall (Gold + Items auf beiden Seiten getauscht),
##     Neuvalidierung schlägt fehl -> session_cancelled("offer_no_longer_valid")
##   - Abbrechen: on_cancel_confirmed entfernt Session und benachrichtigt
##     beide Seiten
##   - get_session_for()/get_pending_invite_for() Abfrage-API

class MockItemDef extends ItemDefinition:
	func _init(p_name: String, p_max_stack: int = 99) -> void:
		display_name = p_name
		max_stack     = p_max_stack

class MockDataService extends DataService:
	func get_all_items() -> Dictionary:
		return _items

const ITEM_A := "iron_ore"
const ITEM_B := "silver_ring"
const A := "player-a"
const B := "player-b"

var _svc: TradeService
var _inventory: InventorySystem
var _currency: CurrencyService
var _ds: MockDataService
var _bus: MockEventBus


func before_each() -> void:
	_ds = MockDataService.new()
	_ds._items[ITEM_A] = MockItemDef.new("Iron Ore", 50)
	_ds._items[ITEM_B] = MockItemDef.new("Silver Ring", 1)
	_bus = MockEventBus.new()

	_inventory = InventorySystem.new()
	_inventory.configure(ServiceDeps.from_dict({
		ServiceKeys.DATA:      _ds,
		ServiceKeys.EVENT_BUS: _bus,
	}))

	_currency = CurrencyService.new()
	_currency.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS: _bus,
	}))

	_svc = TradeService.new()
	_svc.configure(ServiceDeps.from_dict({
		ServiceKeys.INVENTORY: _inventory,
		ServiceKeys.CURRENCY:  _currency,
		ServiceKeys.EVENT_BUS: _bus,
	}))


func after_each() -> void:
	_inventory.on_cleanup()
	_currency.on_cleanup()
	_svc = null
	_inventory = null
	_currency = null
	_ds = null
	_bus = null


func _start_session() -> String:
	_svc.on_invite_confirmed(A, B)
	_svc.request_respond_invite(B, true)
	return _svc.get_session_for(A).get("session_id", "")


# ─────────────────────────────────────────────
# Einladung
# ─────────────────────────────────────────────

func test_invite_confirmed_emits_invite_received_and_registers_pending() -> void:
	var received: Array = []
	_svc.invite_received.connect(func(to_id, from_id): received.append([to_id, from_id]))
	_svc.on_invite_confirmed(A, B)
	assert_eq(received, [[B, A]])
	assert_eq(_svc.get_pending_invite_for(B), A)

func test_invite_confirmed_ignores_self_invite() -> void:
	var received: Array = []
	_svc.invite_received.connect(func(to_id, from_id): received.append([to_id, from_id]))
	_svc.on_invite_confirmed(A, A)
	assert_true(received.is_empty())
	assert_eq(_svc.get_pending_invite_for(A), "")

func test_invite_confirmed_ignored_when_a_side_already_in_session() -> void:
	_start_session()  # A und B jetzt in aktiver Session
	var received: Array = []
	_svc.invite_received.connect(func(to_id, from_id): received.append([to_id, from_id]))
	_svc.on_invite_confirmed(A, "player-c")
	assert_true(received.is_empty(), "A ist bereits in einer Session, darf keine neue Einladung aussprechen können.")

func test_respond_invite_accept_starts_session() -> void:
	_svc.on_invite_confirmed(A, B)
	var started: Array = []
	_svc.session_started.connect(func(sid, pa, pb): started.append([pa, pb]))
	_svc.request_respond_invite(B, true)
	assert_eq(started, [[A, B]])
	assert_eq(_svc.get_pending_invite_for(B), "", "Einladung muss nach Annahme konsumiert sein.")
	assert_false(_svc.get_session_for(A).is_empty())
	assert_false(_svc.get_session_for(B).is_empty())

func test_respond_invite_decline_emits_invite_declined_without_session() -> void:
	_svc.on_invite_confirmed(A, B)
	var declined: Array = []
	_svc.invite_declined.connect(func(pid): declined.append(pid))
	_svc.request_respond_invite(B, false)
	assert_eq(declined, [B])
	assert_true(_svc.get_session_for(A).is_empty())
	assert_true(_svc.get_session_for(B).is_empty())

func test_respond_invite_accept_declines_cleanly_if_inviter_meanwhile_busy() -> void:
	_svc.on_invite_confirmed(A, B)
	# A nimmt zwischenzeitlich an einer anderen Session teil.
	_svc.on_invite_confirmed(A, "player-c")
	_svc.request_respond_invite("player-c", true)

	var declined: Array = []
	_svc.invite_declined.connect(func(pid): declined.append(pid))
	_svc.request_respond_invite(B, true)
	assert_eq(declined, [B], "A ist inzwischen anderweitig in einer Session -> sauberer Abbruch statt Doppel-Session.")


# ─────────────────────────────────────────────
# Angebot ändern
# ─────────────────────────────────────────────

func test_update_offer_sets_offer_and_resets_ready_confirmed() -> void:
	var sid := _start_session()
	_svc.request_set_ready(A, sid, true)
	_svc.request_update_offer(A, sid, {ITEM_A: 2}, 10)
	var session := _svc.get_session_for(A)
	assert_eq(session["offer_a"], {"items": {ITEM_A: 2}, "gold": 10})
	assert_false(session["ready_a"], "Angebotsänderung muss ready_a zurücksetzen (Scam-Schutz).")

func test_update_offer_rejects_negative_gold() -> void:
	var sid := _start_session()
	var failed: Array = []
	_bus.trade().trade_transaction_failed.connect(func(pid, s, reason): failed.append(reason))
	_svc.request_update_offer(A, sid, {}, -5)
	assert_eq(failed, ["invalid_gold_amount"])

func test_update_offer_rejects_zero_or_negative_item_quantity() -> void:
	var sid := _start_session()
	var failed: Array = []
	_bus.trade().trade_transaction_failed.connect(func(pid, s, reason): failed.append(reason))
	_svc.request_update_offer(A, sid, {ITEM_A: 0}, 0)
	assert_eq(failed, ["invalid_item_quantity"])

func test_update_offer_ignored_for_non_participant() -> void:
	var sid := _start_session()
	_svc.request_update_offer("player-c", sid, {ITEM_A: 1}, 0)
	var session := _svc.get_session_for(A)
	assert_eq(session["offer_a"], {"items": {}, "gold": 0})
	assert_eq(session["offer_b"], {"items": {}, "gold": 0})


# ─────────────────────────────────────────────
# Ready / Bestätigen — Zwei-Stufen-Gate
# ─────────────────────────────────────────────

func test_set_ready_updates_session_for_correct_side() -> void:
	var sid := _start_session()
	_svc.request_set_ready(B, sid, true)
	var session := _svc.get_session_for(A)
	assert_true(session["ready_b"])
	assert_false(session["ready_a"])

func test_unready_resets_confirmed_for_that_side() -> void:
	var sid := _start_session()
	_svc.request_set_ready(A, sid, true)
	_svc.request_set_ready(B, sid, true)
	_svc.request_set_confirmed(A, sid, true)
	_svc.request_set_ready(A, sid, false)
	var session := _svc.get_session_for(A)
	assert_false(session["confirmed_a"], "Un-Ready muss die eigene Bestätigung zurücksetzen.")

func test_confirm_fails_with_not_ready_when_not_both_ready() -> void:
	var sid := _start_session()
	_svc.request_set_ready(A, sid, true)  # nur A ist ready
	var failed: Array = []
	_bus.trade().trade_transaction_failed.connect(func(pid, s, reason): failed.append(reason))
	_svc.request_set_confirmed(A, sid, true)
	assert_eq(failed, ["not_ready"])

func test_confirm_from_both_sides_executes_trade() -> void:
	_inventory.on_item_add_confirmed(ITEM_A, 5, A)
	_currency.request_add_gold(B, 100)

	var sid := _start_session()
	_svc.request_update_offer(A, sid, {ITEM_A: 5}, 0)
	_svc.request_update_offer(B, sid, {}, 40)
	_svc.request_set_ready(A, sid, true)
	_svc.request_set_ready(B, sid, true)

	var completed: Array = []
	_svc.trade_completed.connect(func(s, pa, pb): completed.append([pa, pb]))
	_svc.request_set_confirmed(A, sid, true)
	_svc.request_set_confirmed(B, sid, true)

	assert_eq(completed, [[A, B]])
	assert_true(_svc.get_session_for(A).is_empty(), "Session muss nach Abschluss aufgeräumt sein.")
	assert_true(_inventory.has_item(ITEM_A, B, 5), "B muss die 5x iron_ore erhalten haben.")
	assert_false(_inventory.has_item(ITEM_A, A, 1), "A muss die iron_ore abgegeben haben.")
	assert_eq(_currency.get_gold(A), 40, "A muss die 40 Gold erhalten haben.")
	assert_eq(_currency.get_gold(B), 60, "B: 100 - 40 = 60.")

func test_execute_trade_revalidates_and_cancels_on_stale_offer() -> void:
	# A bietet 5x iron_ore an, besitzt aber inzwischen (z.B. anderweitig
	# verbraucht) nur noch 2 -> Neuvalidierung bei _execute_trade() muss
	# greifen statt mit falschem Zustand fortzufahren.
	_inventory.on_item_add_confirmed(ITEM_A, 5, A)
	_currency.request_add_gold(B, 100)

	var sid := _start_session()
	_svc.request_update_offer(A, sid, {ITEM_A: 5}, 0)
	_svc.request_update_offer(B, sid, {}, 40)

	# Bestand von A schmilzt zwischen Angebot und Bestätigung.
	_inventory.remove_item(ITEM_A, A, 3)

	_svc.request_set_ready(A, sid, true)
	_svc.request_set_ready(B, sid, true)

	var cancelled: Array = []
	_svc.session_cancelled.connect(func(s, reason): cancelled.append(reason))
	_svc.request_set_confirmed(A, sid, true)
	_svc.request_set_confirmed(B, sid, true)

	assert_eq(cancelled, ["offer_no_longer_valid"])
	assert_eq(_currency.get_gold(B), 100, "B darf beim Abbruch kein Gold verloren haben.")
	assert_true(_inventory.has_item(ITEM_A, A, 2), "A behält die verbliebenen 2x iron_ore.")


# ─────────────────────────────────────────────
# Abbrechen
# ─────────────────────────────────────────────

func test_cancel_removes_session_and_notifies_both_sides() -> void:
	var sid := _start_session()
	var cancelled: Array = []
	_svc.session_cancelled.connect(func(s, reason): cancelled.append([s, reason]))
	_svc.request_cancel(A, sid)
	assert_eq(cancelled, [[sid, "cancelled_by_player"]])
	assert_true(_svc.get_session_for(A).is_empty())
	assert_true(_svc.get_session_for(B).is_empty())

func test_cancel_ignored_for_non_participant() -> void:
	var sid := _start_session()
	_svc.request_cancel("player-c", sid)
	assert_false(_svc.get_session_for(A).is_empty(), "Session darf durch Nicht-Teilnehmer nicht storniert werden.")


# ─────────────────────────────────────────────
# Abfrage-API
# ─────────────────────────────────────────────

func test_get_session_for_unknown_player_is_empty() -> void:
	assert_true(_svc.get_session_for("nobody").is_empty())

func test_get_pending_invite_for_unknown_player_is_empty_string() -> void:
	assert_eq(_svc.get_pending_invite_for("nobody"), "")

# ─────────────────────────────────────────────
# Netzwerk-Routing — inject_network_bridge() + request_*() als Client
# (Round 113 Nachtrag, siehe method_reference_coverage.py-Fund: die
# on_*_confirmed()-Handler wurden bisher nur INDIREKT über request_*() im
# No-Network-Pfad geprüft, inject_network_bridge()/der Client-Routing-Zweig
# selbst nie direkt)
# ─────────────────────────────────────────────

class MockBridgeAsClient extends NetworkBridge:
	var respond_invite_calls: Array = []
	var update_offer_calls: Array = []
	var set_ready_calls: Array = []
	var set_confirmed_calls: Array = []
	var cancel_calls: Array = []
	func has_peer() -> bool:
		return true
	func is_server() -> bool:
		return false
	func send_trade_respond_invite(accept: bool, player_id: String) -> void:
		respond_invite_calls.append([accept, player_id])
	func send_trade_update_offer(session_id: String, items: Dictionary, gold: int, player_id: String) -> void:
		update_offer_calls.append([session_id, items, gold, player_id])
	func send_trade_set_ready(session_id: String, ready: bool, player_id: String) -> void:
		set_ready_calls.append([session_id, ready, player_id])
	func send_trade_set_confirmed(session_id: String, confirmed: bool, player_id: String) -> void:
		set_confirmed_calls.append([session_id, confirmed, player_id])
	func send_trade_cancel(session_id: String, player_id: String) -> void:
		cancel_calls.append([session_id, player_id])

func test_inject_network_bridge_sets_the_reference() -> void:
	var bridge: NetworkBridge = add_child_autofree(NetworkBridge.new())
	_svc.inject_network_bridge(bridge)
	assert_same(_svc._network, bridge)

func test_inject_network_bridge_connects_economy_state_received() -> void:
	var bridge: NetworkBridge = add_child_autofree(NetworkBridge.new())
	assert_eq(bridge.economy_state_received.get_connections().size(), 0)
	_svc.inject_network_bridge(bridge)
	assert_eq(bridge.economy_state_received.get_connections().size(), 1,
		"inject_network_bridge() muss _connect_economy_sync() erneut anstoßen (Late-Inject-Fall, siehe BootPipeline)")

func test_inject_network_bridge_does_not_double_connect_when_called_twice() -> void:
	var bridge: NetworkBridge = add_child_autofree(NetworkBridge.new())
	_svc.inject_network_bridge(bridge)
	_svc.inject_network_bridge(bridge)
	assert_eq(bridge.economy_state_received.get_connections().size(), 1,
		"_connect_economy_sync() prüft is_connected() — zweimaliges Inject darf nicht doppelt verbinden")

func test_request_respond_invite_as_client_routes_via_network_not_local() -> void:
	var bridge: MockBridgeAsClient = add_child_autofree(MockBridgeAsClient.new())
	_svc.on_invite_confirmed(A, B)
	_svc.inject_network_bridge(bridge)

	_svc.request_respond_invite(B, true)

	assert_eq(bridge.respond_invite_calls, [[true, B]])
	assert_true(_svc.get_session_for(B).is_empty(), "Auf dem Client darf keine Session direkt gestartet werden")

func test_request_update_offer_as_client_routes_via_network_not_local() -> void:
	var bridge: MockBridgeAsClient = add_child_autofree(MockBridgeAsClient.new())
	var sid := _start_session()
	_svc.inject_network_bridge(bridge)

	_svc.request_update_offer(A, sid, {ITEM_A: 2}, 10)

	assert_eq(bridge.update_offer_calls, [[sid, {ITEM_A: 2}, 10, A]])
	assert_eq(_svc.get_session_for(A)["offer_a"]["gold"], 0, "Auf dem Client darf sich das Angebot nicht direkt ändern")

func test_request_set_ready_as_client_routes_via_network_not_local() -> void:
	var bridge: MockBridgeAsClient = add_child_autofree(MockBridgeAsClient.new())
	var sid := _start_session()
	_svc.inject_network_bridge(bridge)

	_svc.request_set_ready(A, sid, true)

	assert_eq(bridge.set_ready_calls, [[sid, true, A]])
	assert_false(_svc.get_session_for(A)["ready_a"], "Auf dem Client darf ready nicht direkt gesetzt werden")

func test_request_set_confirmed_as_client_routes_via_network_not_local() -> void:
	var bridge: MockBridgeAsClient = add_child_autofree(MockBridgeAsClient.new())
	var sid := _start_session()
	_svc.on_ready_confirmed(A, sid, true)
	_svc.on_ready_confirmed(B, sid, true)
	_svc.inject_network_bridge(bridge)

	_svc.request_set_confirmed(A, sid, true)

	assert_eq(bridge.set_confirmed_calls, [[sid, true, A]])
	assert_false(_svc.get_session_for(A)["confirmed_a"], "Auf dem Client darf confirmed nicht direkt gesetzt werden")

func test_request_cancel_as_client_routes_via_network_not_local() -> void:
	var bridge: MockBridgeAsClient = add_child_autofree(MockBridgeAsClient.new())
	var sid := _start_session()
	_svc.inject_network_bridge(bridge)

	_svc.request_cancel(A, sid)

	assert_eq(bridge.cancel_calls, [[sid, A]])
	assert_false(_svc.get_session_for(A).is_empty(), "Auf dem Client darf die Session nicht direkt storniert werden")

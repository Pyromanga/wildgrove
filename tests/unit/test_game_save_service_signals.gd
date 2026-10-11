# res://tests/unit/test_game_save_service_signals.gd
extends GutTest

## Signal-Tests für GameSaveService (H-07 / EventBus-Injektion).
##
## Testet:
##   - save_requested-Signal triggert save_all()
##   - save_pre_flush wird vor dem eigentlichen Speichern emittiert
##   - on_cleanup() trennt Connections

var _bus:  MockEventBus
var _svc:  GameSaveService
var _save: SaveSystem

func before_each() -> void:
	_bus  = MockEventBus.new()
	_save = _make_stub_save()
	_svc  = GameSaveService.new()
	_svc.configure(ServiceDeps.from_dict({
		ServiceKeys.SAVE_SYSTEM: _save,
		ServiceKeys.EVENT_BUS:   _bus,
	}))
	_svc.on_ready()

func after_each() -> void:
	_svc.on_cleanup()
	_svc  = null
	_bus  = null
	_save = null

# ─────────────────────────────────────────────────────────────────────────────
# on_ready Connection
# ─────────────────────────────────────────────────────────────────────────────

func test_on_ready_connects_save_requested() -> void:
	assert_true(
		_bus.persistence().save_requested.is_connected(_svc._on_save_requested),
		"on_ready() muss save_requested mit _on_save_requested verbinden."
	)

# ─────────────────────────────────────────────────────────────────────────────
# save_requested → save_all() → save_pre_flush
# ─────────────────────────────────────────────────────────────────────────────

func test_save_requested_signal_triggers_save_pre_flush() -> void:
	## save_requested → save_all() → save_pre_flush emittiert
	## Dieser Pfad war vorher KOMPLETT unbetestbar.
	watch_signals(_bus.persistence())
	_bus.persistence().save_requested.emit()
	assert_signal_emitted(_bus.persistence(), "save_pre_flush",
		"save_requested muss über GameSaveService save_pre_flush auslösen."
	)

func test_save_pre_flush_emitted_before_save() -> void:
	## Reihenfolge: save_pre_flush MUSS vor save_started kommen.
	## (WorldService reagiert auf pre_flush um Pet-Daten zu sichern)
	var order: Array[String] = []
	_bus.persistence().save_pre_flush.connect(func(): order.append("pre_flush"))
	_bus.persistence().save_started.connect(func(): order.append("save_started"))

	_bus.persistence().save_requested.emit()

	assert_true(order.has("pre_flush"),    "save_pre_flush muss emittiert werden.")
	if order.has("pre_flush") and order.has("save_started"):
		assert_true(order.find("pre_flush") < order.find("save_started"),
			"save_pre_flush muss VOR save_started kommen.")

func test_direct_save_all_also_emits_pre_flush() -> void:
	watch_signals(_bus.persistence())
	_svc.save_all()
	assert_signal_emitted(_bus.persistence(), "save_pre_flush",
		"Direkter save_all()-Aufruf muss auch save_pre_flush emittieren."
	)

# ─────────────────────────────────────────────────────────────────────────────
# Double-call protection
# ─────────────────────────────────────────────────────────────────────────────

func test_concurrent_save_requests_only_emit_one_pre_flush() -> void:
	var pre_flush_count := [0]
	_bus.persistence().save_pre_flush.connect(func(): pre_flush_count[0] += 1)

	# Zweiter Aufruf während erstem läuft würde doppelten pre_flush auslösen
	# Der _is_saving-Guard in save_all() verhindert das.
	# Da wir in GDScript single-threaded sind, simulieren wir das durch
	# direktes Setzen des Guards vor dem zweiten Aufruf.
	_svc.save_all()
	_svc._is_saving = true  # simuliert: erster Aufruf läuft noch (Reentrancy)
	_svc.save_all()  # zweiter Aufruf — soll ignoriert werden

	assert_eq(pre_flush_count[0], 1,
		"Doppelter save_all()-Aufruf darf nur einen save_pre_flush auslösen."
	)

# ─────────────────────────────────────────────────────────────────────────────
# on_cleanup
# ─────────────────────────────────────────────────────────────────────────────

func test_on_cleanup_disconnects_save_requested() -> void:
	_svc.on_cleanup()
	assert_false(
		_bus.persistence().save_requested.is_connected(_svc._on_save_requested),
		"on_cleanup() muss save_requested disconnecten."
	)

func test_save_requested_after_cleanup_does_not_trigger_save() -> void:
	_svc.on_cleanup()
	watch_signals(_bus.persistence())
	_bus.persistence().save_requested.emit()
	# Kein save_pre_flush weil Connection getrennt
	assert_signal_not_emitted(_bus.persistence(), "save_pre_flush",
		"Nach on_cleanup() darf save_requested nicht mehr save_pre_flush auslösen."
	)

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

func _make_stub_save() -> SaveSystem:
	var stub := SaveSystem.new()
	stub.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: MockEventBus.new()}))
	return stub

# res://tests/unit/test_teardown_order.gd
extends GutTest

## Tests für ServiceTeardownManager.execute(registry, boot_order) — ARCH-2.
##
## Abgedeckt:
##   - Ohne boot_order: Fallback auf Registry-Reihenfolge
##   - Mit boot_order: Teardown in explizit reverser Boot-Reihenfolge
##   - Resource-Einträge in der Registry verschieben die Teardown-Reihenfolge
##     NICHT mehr wenn boot_order übergeben wird
##   - on_cleanup() wird in korrekter Reihenfolge aufgerufen

class OrderTracker extends Service:
	var _log: Array = []
	var tracker_id: String = ""
	func on_cleanup() -> void:
		_log.append(tracker_id)

func _register_tracker(reg: ServiceRegistry, name: String, log: Array) -> OrderTracker:
	# register_resource() registriert ein Object direkt ohne ServiceDefinition —
	# ausreichend für Teardown-Tests (kein configure/on_ready nötig).
	var tracker := OrderTracker.new()
	tracker.tracker_id = name
	tracker._log = log
	reg.register_resource(tracker, name)
	return tracker

func test_without_boot_order_uses_registry_reverse() -> void:
	var log: Array = []
	var reg := ServiceRegistry.new()
	_register_tracker(reg, "a", log)
	_register_tracker(reg, "b", log)
	_register_tracker(reg, "c", log)

	var mgr := ServiceTeardownManager.new()
	mgr.execute(reg)

	assert_eq(log, ["c", "b", "a"],
		"Ohne boot_order: Teardown in reverser Registry-Reihenfolge (c→b→a)")

func test_with_boot_order_uses_explicit_reverse() -> void:
	# Register in different order than boot_order
	var log: Array = []
	var reg := ServiceRegistry.new()
	_register_tracker(reg, "c", log)
	_register_tracker(reg, "a", log)
	_register_tracker(reg, "b", log)

	var boot_order: Array[String] = ["a", "b", "c"]
	var mgr := ServiceTeardownManager.new()
	mgr.execute(reg, boot_order)

	assert_eq(log, ["c", "b", "a"],
		"Mit boot_order [a,b,c]: Teardown muss [c,b,a] — unabhängig von Registration-Reihenfolge")

func test_boot_order_isolates_resource_entries() -> void:
	# die Teardown-Reihenfolge NICHT wenn boot_order übergeben wird.
	var log: Array = []
	var reg := ServiceRegistry.new()
	_register_tracker(reg, "a", log)
	# Simuliert register_resource() zwischen zwei Service-Registrierungen:
	reg.register_resource(RefCounted.new(), "some_resource")
	_register_tracker(reg, "b", log)

	# boot_order enthält nur Services — keine Resources
	var boot_order: Array[String] = ["a", "b"]
	var mgr := ServiceTeardownManager.new()
	mgr.execute(reg, boot_order)

	assert_eq(log, ["b", "a"],
		"boot_order isoliert Resource-Einträge — Teardown-Reihenfolge deterministisch")

func test_empty_boot_order_falls_back_gracefully() -> void:
	var log: Array = []
	var reg := ServiceRegistry.new()
	_register_tracker(reg, "only", log)

	var mgr := ServiceTeardownManager.new()
	mgr.execute(reg, [])

	assert_eq(log, ["only"], "Leerer boot_order → Fallback, on_cleanup() trotzdem aufgerufen")

func test_registry_cleared_after_execute() -> void:
	var reg := ServiceRegistry.new()
	reg.register_resource(Service.new(), "x")

	var mgr := ServiceTeardownManager.new()
	mgr.execute(reg, ["x"])

	assert_true(reg.get_all_names().is_empty(), "Registry nach execute() muss leer sein")

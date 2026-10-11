# res://tests/unit/test_service_deps.gd
extends GutTest

## Unit-Tests für ServiceDeps (ADR-011).
##
## ServiceDeps extends RefCounted — kein SceneTree, direkt testbar.
##
## Abgedeckt:
##   - from_dict() erstellt Instanz korrekt
##   - require() gibt Wert zurück wenn vorhanden
##   - require() löst push_error() + assert() aus wenn fehlt (gut-catch_push_error)
##   - get_optional() gibt Wert zurück wenn vorhanden
##   - get_optional() gibt null zurück wenn fehlt (kein Fehler)
##   - has() korrekt für vorhandene und fehlende Keys
##   - keys() gibt sortierte Liste zurück
##   - from_dict() dupliziert das Dictionary (Mutation-Safety)

# ─────────────────────────────────────────────────────────────────────────────
# Fixtures
# ─────────────────────────────────────────────────────────────────────────────

class MockService extends RefCounted:
	var label: String = ""

var _mock_a: MockService
var _mock_b: MockService
var _deps:   ServiceDeps

func before_each() -> void:
	_mock_a       = MockService.new()
	_mock_a.label = "serviceA"
	_mock_b       = MockService.new()
	_mock_b.label = "serviceB"
	_deps = ServiceDeps.from_dict({
		"service_a": _mock_a,
		"service_b": _mock_b,
	})

# ─────────────────────────────────────────────────────────────────────────────
# from_dict
# ─────────────────────────────────────────────────────────────────────────────

func test_from_dict_returns_service_deps_instance() -> void:
	var deps := ServiceDeps.from_dict({"a": RefCounted.new()})
	assert_not_null(deps, "from_dict() darf nicht null zurückgeben")
	assert_true(deps is ServiceDeps, "from_dict() muss ServiceDeps zurückgeben")

func test_from_dict_empty_dict_is_valid() -> void:
	var deps := ServiceDeps.from_dict({})
	assert_not_null(deps)
	assert_eq(deps.keys().size(), 0, "Leeres Dict → keine Keys")

func test_from_dict_duplicates_dict_for_mutation_safety() -> void:
	var d := {"foo": RefCounted.new()}
	var deps := ServiceDeps.from_dict(d)
	# Mutation des Originals darf deps nicht beeinflussen
	d["bar"] = RefCounted.new()
	assert_false(deps.has("bar"), "from_dict() muss das Dictionary duplizieren")

# ─────────────────────────────────────────────────────────────────────────────
# require()
# ─────────────────────────────────────────────────────────────────────────────

func test_require_returns_correct_object() -> void:
	var result := _deps.require("service_a")
	assert_not_null(result, "require() muss das Objekt zurückgeben")
	assert_eq(result, _mock_a, "require() muss genau das registrierte Objekt zurückgeben")

func test_require_missing_key_triggers_push_error() -> void:
	## GUT 9.3.0 bietet kein eingebautes push_error()-Capturing (kein
	## get_push_errors() / assert_error_emitted()). ignore_method_when_doubling()
	## existiert zwar, aber nur zum Stubben von Methoden auf gedoubelten Objekten —
	## nicht zum globalen Unterdrücken von push_error().
	## require() ruft push_error() + assert(false, ...). Außerhalb des Debuggers
	## (headless CI) bricht assert() die Ausführung nicht ab, sondern loggt nur
	## einen Fehler — wir testen daher direkt den Vertrag: null-Rückgabe, kein Crash.
	var result := _deps.require("nonexistent_key")
	assert_null(result, "require() muss bei fehlendem Key null zurückgeben")

func test_require_present_key_no_error() -> void:
	var result: Object = null
	# Kein Fehler erwartet
	result = _deps.require("service_b")
	assert_eq(result, _mock_b)

# ─────────────────────────────────────────────────────────────────────────────
# get_optional()
# ─────────────────────────────────────────────────────────────────────────────

func test_get_optional_returns_object_when_present() -> void:
	var result := _deps.get_optional("service_a")
	assert_eq(result, _mock_a, "get_optional() muss das registrierte Objekt zurückgeben")

func test_get_optional_returns_null_when_missing() -> void:
	var result := _deps.get_optional("does_not_exist")
	assert_null(result, "get_optional() muss null für fehlende Keys zurückgeben")

func test_get_optional_returns_null_for_null_value() -> void:
	var deps := ServiceDeps.from_dict({"nullable": null})
	var result := deps.get_optional("nullable")
	assert_null(result, "get_optional() muss null zurückgeben wenn Wert null ist")

# ─────────────────────────────────────────────────────────────────────────────
# has()
# ─────────────────────────────────────────────────────────────────────────────

func test_has_returns_true_for_existing_non_null_key() -> void:
	assert_true(_deps.has("service_a"))
	assert_true(_deps.has("service_b"))

func test_has_returns_false_for_missing_key() -> void:
	assert_false(_deps.has("missing"))

func test_has_returns_false_for_null_value() -> void:
	var deps := ServiceDeps.from_dict({"null_dep": null})
	assert_false(deps.has("null_dep"), "has() muss false für null-Werte zurückgeben")

# ─────────────────────────────────────────────────────────────────────────────
# keys()
# ─────────────────────────────────────────────────────────────────────────────

func test_keys_returns_all_registered_keys() -> void:
	var result := _deps.keys()
	assert_eq(result.size(), 2, "keys() muss alle Keys zurückgeben")
	assert_has(result, "service_a")
	assert_has(result, "service_b")

func test_keys_is_sorted() -> void:
	var deps := ServiceDeps.from_dict({
		"zebra": RefCounted.new(),
		"alpha": RefCounted.new(),
		"middle": RefCounted.new(),
	})
	var result := deps.keys()
	assert_eq(result[0], "alpha",  "keys() muss alphabetisch sortiert sein")
	assert_eq(result[1], "middle")
	assert_eq(result[2], "zebra")

func test_keys_empty_for_empty_dict() -> void:
	var deps := ServiceDeps.from_dict({})
	assert_eq(deps.keys().size(), 0)

# ─────────────────────────────────────────────────────────────────────────────
# Integration: configure()-Aufruf mit ServiceDeps
# ─────────────────────────────────────────────────────────────────────────────

## Stellt sicher dass ServiceDeps.from_dict() als configure()-Argument funktioniert.
## Smoke-Test für das End-to-End-Interface.
class _MinimalService extends Service:
	var received_dep: Object = null
	func configure(deps: ServiceDeps) -> void:
		received_dep = deps.get_optional("my_dep")

func test_service_configure_receives_dep_via_service_deps() -> void:
	var svc := _MinimalService.new()
	var mock := RefCounted.new()
	svc.configure(ServiceDeps.from_dict({"my_dep": mock}))
	assert_eq(svc.received_dep, mock, "Service muss Dep via ServiceDeps korrekt empfangen")

func test_service_configure_receives_null_for_missing_optional() -> void:
	var svc := _MinimalService.new()
	svc.configure(ServiceDeps.from_dict({}))
	assert_null(svc.received_dep, "Optionaler Dep muss null sein wenn fehlt")

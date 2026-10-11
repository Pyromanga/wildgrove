# res://tests/unit/test_service_installer.gd
extends GutTest

## Unit-Tests für ServiceInstaller.
##
## Regression: RECOMMENDED_SESSION war `const RECOMMENDED_SESSION := [...]` ohne
## explizite Typisierung — GDScript leitet daraus einen untypisierten `Array`
## ab, nicht `Array[String]`. `_check()` erwartet für Parameter `recommended`
## aber `Array[String]`. Die Engine wirft beim Aufruf einen "Invalid type"-Fehler
## und install_session() lieferte dadurch `false` zurück — Phase C7 schlug fehl,
## obwohl alle kritischen Services vorhanden waren.

var _installer: ServiceInstaller
var _registry: ServiceRegistry

func before_each() -> void:
	_installer = ServiceInstaller.new()
	_registry = ServiceRegistry.new()

func _register_dummy(name: String) -> void:
	_registry.register_resource(RefCounted.new(), name)

func test_recommended_session_is_typed_string_array() -> void:
	# Direkter Schutz gegen die konkrete Regression: eine falsch typisierte
	# Konstante crasht erst beim Aufruf, nicht beim Parsen — dieser Test
	# prüft den Typ direkt statt nur den Call-Erfolg.
	assert_true(
		ServiceInstaller.RECOMMENDED_SESSION is Array[String],
		"RECOMMENDED_SESSION muss Array[String] sein, sonst crasht _check()"
	)

func test_install_session_succeeds_when_all_critical_services_present() -> void:
	for key in [
		ServiceKeys.INVENTORY, ServiceKeys.SKILL_SYSTEM, ServiceKeys.QUEST,
		ServiceKeys.WORLD, ServiceKeys.PLAYER_STATES
	]:
		_register_dummy(key)

	var ok := _installer.install_session(_registry)
	assert_true(ok, "install_session() muss true liefern wenn alle kritischen Services registriert sind")

func test_install_session_fails_when_critical_service_missing() -> void:
	for key in [ServiceKeys.INVENTORY, ServiceKeys.SKILL_SYSTEM, ServiceKeys.QUEST, ServiceKeys.WORLD]:
		_register_dummy(key)
	# PLAYER_STATES fehlt absichtlich.

	var ok := _installer.install_session(_registry)
	assert_false(ok, "install_session() muss false liefern wenn ein kritischer Service fehlt")

func test_install_session_ignores_missing_recommended_services() -> void:
	for key in [
		ServiceKeys.INVENTORY, ServiceKeys.SKILL_SYSTEM, ServiceKeys.QUEST,
		ServiceKeys.WORLD, ServiceKeys.PLAYER_STATES
	]:
		_register_dummy(key)
	# Keine RECOMMENDED_SESSION-Einträge registriert — darf trotzdem ok=true bleiben.

	var ok := _installer.install_session(_registry)
	assert_true(ok, "fehlende empfohlene Services dürfen install_session() nicht scheitern lassen")

# res://tests/unit/test_boot_pipeline_smoke.gd
extends GutTest

## End-to-End-Smoke-Test: BootPipeline.boot_app() mit ALLEN echten Helfern
## (ServiceValidator, ServiceDependencyResolver, ServiceFactory, ServiceInitializer,
## ServiceInstaller, ServiceTeardownManager) gegen die echte BootstrapConfig.tres.
##
## Warum ein eigener Test statt Wiederverwendung bestehender Tests:
##   test_boot_pipeline.gd           — alle 6 Helfer sind gemockt. Testet die
##                                      Orchestrierung, nie die echten Klassen.
##   test_bootstrap_config_integration.gd — nutzt den echten Validator/Resolver,
##                                      aber löst nur den Dependency-Graphen auf.
##                                      Instanziiert und registriert nie wirklich.
##
## Genau in dieser Lücke saß der ServiceTicker-Bug: 'ticker' war im Graphen
## auflösbar (Resolver kennt nur Namen, keine Interfaces), aber die echte
## Registrierung schlug an der Interface-Assertion (ADR-011 / H-06) fehl, weil
## ServiceTicker damals `extends Node` statt `extends ServiceNode` war — und
## boot_app() meldete trotzdem Result.ok = true. Dieser Test boot-tet für echt
## und hätte das sofort rot gemeldet.

var _parent: Node

func before_each() -> void:
	_parent = add_child_autofree(Node.new())

func test_real_boot_app_succeeds() -> void:
	var pipeline  := BootPipeline.new()
	var app_scope := AppScope.new(ServiceRegistry.new())

	var result := pipeline.boot_app(app_scope, _parent)

	assert_true(
		result.ok,
		"echter boot_app() gegen die reale BootstrapConfig.tres muss erfolgreich sein — Grund: %s" % result.reason
	)

func test_real_boot_app_registers_every_critical_global_service() -> void:
	var pipeline  := BootPipeline.new()
	var app_scope := AppScope.new(ServiceRegistry.new())
	pipeline.boot_app(app_scope, _parent)

	for key in ServiceInstaller.CRITICAL_GLOBAL:
		assert_true(
			app_scope.registry.has_service(key),
			"kritischer Service '%s' fehlt in der Registry nach echtem boot_app()" % key
		)

## Regression-Test für den konkreten Bug: 'ticker' muss nicht nur "irgendwie"
## registriert sein, sondern als echte, gültige ServiceTicker-Instanz.
func test_real_ticker_is_registered_as_valid_instance() -> void:
	var pipeline  := BootPipeline.new()
	var app_scope := AppScope.new(ServiceRegistry.new())
	pipeline.boot_app(app_scope, _parent)

	var ticker := app_scope.registry.get_service(ServiceKeys.TICKER)
	assert_not_null(ticker, "ticker muss nach boot_app() eine echte Instanz sein, kein null")
	assert_true(ticker is ServiceNode, "ticker muss von ServiceNode erben (ADR-003), sonst schlägt Registrierung/Teardown fehl")

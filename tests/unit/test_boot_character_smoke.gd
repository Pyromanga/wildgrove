# res://tests/unit/test_boot_character_smoke.gd
extends GutTest

## End-to-End-Smoke-Test: boot_app() → boot_character() mit ALLEN echten Helfern
## gegen die reale BootstrapConfig.tres.
##
## Warum ein eigener Test (analog test_boot_pipeline_smoke.gd für boot_app()):
## test_boot_pipeline.gd und test_service_orchestrator_lifecycle.gd mocken
## ServiceInitializer/Factory/etc. komplett — sie hätten eine vergessene
## Cross-Scope-Bridge (ADR-017) nie bemerkt, weil der echte Dependency-Lookup
## nie läuft. Genau das ist die Lücke, in der eine vergessene Zeile in
## BootPipeline._bridge_app_services_into_session() heute nur eine
## AppLogger.log_warn() wäre, statt beim Boot rot zu werden.

var _parent: Node

func before_each() -> void:
	_parent = add_child_autofree(Node.new())

func _boot_real_app_and_character(player_id: String) -> Dictionary:
	var pipeline  := BootPipeline.new()
	var app_scope := AppScope.new(ServiceRegistry.new())
	var app_result := pipeline.boot_app(app_scope, _parent)
	assert_true(app_result.ok, "boot_app() muss für den Character-Smoke-Test erfolgreich sein — Grund: %s" % app_result.reason)

	var char_registry := ServiceRegistry.new()
	var char_scope := CharacterScope.new(char_registry, app_scope.registry, player_id, _parent)
	var char_result := pipeline.boot_character(char_scope, _parent)

	return {pipeline = pipeline, app_scope = app_scope, char_scope = char_scope, result = char_result}

func test_real_boot_character_succeeds() -> void:
	var ctx := _boot_real_app_and_character("smoke_player")
	assert_true(
		ctx.result.ok,
		"echter boot_character() gegen die reale BootstrapConfig.tres muss erfolgreich sein — Grund: %s" % ctx.result.reason
	)

## ADR-017: jede Cross-Scope-Dep, die BootPipeline._bridge_app_services_into_session()
## verspricht, muss nach echtem boot_character() tatsächlich in der Session-Registry
## stehen — nicht nur im Boot-Log als "gebridged" behauptet werden.
func test_bridged_global_services_are_visible_in_session_registry() -> void:
	var ctx := _boot_real_app_and_character("smoke_player")
	var session_registry: ServiceRegistry = ctx.char_scope.registry

	for key in [
		ServiceKeys.EVENT_BUS,
		ServiceKeys.SAVE_SYSTEM,
		ServiceKeys.DATA,
		ServiceKeys.GAME_MANAGER,
		ServiceKeys.SESSION_MANAGER,
		ServiceKeys.TICKER,
	]:
		assert_true(
			session_registry.has_service(key),
			"'%s' muss laut ADR-017 in die Session-Registry gebridged sein, ist es aber nicht" % key
		)

## Regression-Test für AUDIT-05 Mutation 1/2/3: NetworkBridge muss dieselbe
## peer_id liefern wie SessionManager — keine zweite, unabhängige Berechnung.
func test_network_bridge_peer_id_matches_session_manager() -> void:
	var ctx := _boot_real_app_and_character("smoke_player")
	var session_registry: ServiceRegistry = ctx.char_scope.registry
	var app_registry: ServiceRegistry     = ctx.app_scope.registry

	var sm := app_registry.get_service(ServiceKeys.SESSION_MANAGER) as SessionManager
	var nb := session_registry.get_service(ServiceKeys.NETWORK_BRIDGE) as NetworkBridge

	assert_not_null(sm, "SessionManager muss nach boot_app() existieren")
	if nb == null:
		pending("kein NetworkBridge in dieser BootstrapConfig-Variante — Test übersprungen")
		return

	assert_eq(
		nb.get_local_peer_id(), sm.get_local_peer_id(),
		"NetworkBridge.get_local_peer_id() muss an SessionManager delegieren (ADR-017) statt selbst zu rechnen"
	)

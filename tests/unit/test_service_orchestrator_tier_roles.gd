# res://tests/unit/test_service_orchestrator_tier_roles.gd
extends GutTest

## Tests für ADR-031 "Rollenzuweisung nach Tier" — die Verdrahtung von
## PermissionService.ensure_default_role() an ServiceOrchestrator._on_session_requested()
## (Round 81, Teil 2 von ADR-031; Teil 1 war Round 80, siehe test_permission_service.gd).
##
## STRATEGIE (zwei Ebenen, analog test_service_orchestrator_lifecycle.gd):
##
##   Ebene 1 (rein/statisch): _should_get_default_admin(is_server, is_dedicated_server)
##   ist die reine Tier-Entscheidungslogik, getrennt von den AppScope-Lookups
##   (analog SessionManager._handle_join_handshake() vs. dessen @rpc-Hülle).
##   Alle vier Kombinationen werden direkt getestet, ohne SceneTree/Boot nötig.
##
##   Ebene 2 (Service-Verdrahtung): ServiceOrchestrator wird instanziiert, _app_scope
##   direkt gesetzt (GDScript kennt keine echte Privatheit für Skript-Member — der
##   Unterstrich ist Konvention, kein Zugriffsschutz) und _ensure_default_role_for_tier()
##   isoliert aufgerufen, mit einer echten PermissionService- und SessionManager-Instanz
##   in einer minimalen AppScope-Registry. Kein create_server()/Peer nötig: Tier-1-Solo
##   (kein Peer) und Tier-3-Dedicated (Flag ohne echten Peer, siehe SessionManager
##   .enable_dedicated_server_mode()) sind beide ohne ENet-Stack auslösbar — echtes
##   Tier-2-Hosting scheitert in headless-CI an create_server() (siehe SM-04 in
##   test_session_manager.gd) und wird deshalb nur auf Ebene 1 abgedeckt.
##
## Abgedeckt:
##   T-01…T-04  _should_get_default_admin() — alle vier is_server/is_dedicated-Kombinationen
##   T-05       Tier 1 (Solo, kein Peer): player_id bekommt automatisch 'admin'
##   T-06       Tier 3 (Dedicated-Flag): KEIN automatischer Admin-Eintrag
##   T-07       ensure_default_role() überschreibt keine bereits gesetzte Rolle (Idempotenz)
##   T-08       Fehlende PermissionService in der Registry: kein Crash, kein Zuweisungsversuch
##   T-09       Fehlender SessionManager in der Registry: kein Crash, kein Zuweisungsversuch

const ROLES_TEST_PATH := "user://unit_test_orchestrator_roles.json"

var _orchestrator: ServiceOrchestrator
var _permission_service: PermissionService
var _session_manager: SessionManager

func before_each() -> void:
	_delete_test_file()

	_permission_service = PermissionService.new()
	_permission_service.set_path_override(ROLES_TEST_PATH)
	_permission_service.configure(ServiceDeps.from_dict({}))

	_session_manager = SessionManager.new()
	_session_manager.configure(ServiceDeps.from_dict({}))
	add_child_autofree(_session_manager)  # on_ready() braucht SceneTree (multiplayer-Signale)

	_orchestrator = ServiceOrchestrator.new()
	# Kein add_child_autofree(_orchestrator): _ready() würde den vollen boot_app()-Pfad
	# anstoßen (echte BootstrapConfig, EventBus-Connects etc.) — für diese Tests unnötig
	# und ungewollt. Wir testen _ensure_default_role_for_tier() isoliert, siehe Klassenkommentar.
	autofree(_orchestrator)

	var global_registry := ServiceRegistry.new()
	global_registry.register_resource(_permission_service, ServiceKeys.PERMISSION_SERVICE)
	global_registry.register_resource(_session_manager, ServiceKeys.SESSION_MANAGER)
	_orchestrator._app_scope = AppScope.new(global_registry)

func after_each() -> void:
	_session_manager.on_cleanup()
	_orchestrator = null
	_permission_service = null
	_session_manager = null
	_delete_test_file()

func _delete_test_file() -> void:
	if FileAccess.file_exists(ROLES_TEST_PATH):
		DirAccess.remove_absolute(ROLES_TEST_PATH)
	if FileAccess.file_exists(ROLES_TEST_PATH + ".tmp"):
		DirAccess.remove_absolute(ROLES_TEST_PATH + ".tmp")

# ═════════════════════════════════════════════════════════════════════════════
# T-01…T-04 — _should_get_default_admin(): reine Tier-Entscheidungslogik
# ═════════════════════════════════════════════════════════════════════════════

func test_t01_solo_or_host_without_dedicated_flag_gets_admin() -> void:
	assert_true(
		ServiceOrchestrator._should_get_default_admin(true, false),
		"T-01: is_server=true, is_dedicated_server=false (Tier 1 Solo oder Tier 2 Host) → admin"
	)

func test_t02_dedicated_server_never_gets_auto_admin() -> void:
	assert_false(
		ServiceOrchestrator._should_get_default_admin(true, true),
		"T-02: Tier 3 (Dedicated-Flag gesetzt) → kein Auto-Admin, egal ob is_server true ist"
	)

func test_t03_client_never_gets_auto_admin() -> void:
	assert_false(
		ServiceOrchestrator._should_get_default_admin(false, false),
		"T-03: is_server=false (Tier 2 Client) → kein Auto-Admin"
	)

func test_t04_non_server_dedicated_combo_never_gets_auto_admin() -> void:
	## Theoretisch unmöglicher State (dedicated impliziert immer is_server=true in der
	## echten SessionManager-Logik), aber die reine Funktion muss auch hier fail-safe sein.
	assert_false(
		ServiceOrchestrator._should_get_default_admin(false, true),
		"T-04: is_server=false, is_dedicated_server=true → fail-safe kein Auto-Admin"
	)

# ═════════════════════════════════════════════════════════════════════════════
# T-05…T-09 — _ensure_default_role_for_tier(): Service-Verdrahtung
# ═════════════════════════════════════════════════════════════════════════════

func test_t05_tier1_solo_gets_admin_assigned() -> void:
	assert_true(_session_manager.is_solo(), "T-05 Setup: frischer SessionManager ohne Peer muss Tier 1 (Solo) sein")

	_orchestrator._ensure_default_role_for_tier("player_solo")

	assert_eq(
		_permission_service.get_role_id("player_solo"), "admin",
		"T-05: Tier 1 (Solo) muss automatisch 'admin' zugewiesen bekommen"
	)

func test_t06_dedicated_server_flag_gets_no_auto_admin() -> void:
	_session_manager.enable_dedicated_server_mode()

	_orchestrator._ensure_default_role_for_tier("__dedicated_server_world__")

	assert_eq(
		_permission_service.get_role_id("__dedicated_server_world__"), "player",
		"T-06: Tier 3 (Dedicated-Flag) darf KEINEN automatischen Admin-Eintrag bekommen"
	)

func test_t07_does_not_overwrite_existing_manual_role() -> void:
	## Manuelle Vorab-Beförderung zu 'moderator' — ensure_default_role() (über
	## _ensure_default_role_for_tier()) darf das nicht überschreiben, auch wenn
	## der Tier-Default eigentlich 'admin' wäre (Idempotenz, siehe ADR-031).
	_permission_service.assign_role("player_promoted", "moderator")

	_orchestrator._ensure_default_role_for_tier("player_promoted")

	assert_eq(
		_permission_service.get_role_id("player_promoted"), "moderator",
		"T-07: bereits gesetzte Rolle darf durch den Tier-Default nicht überschrieben werden"
	)

func test_t08_missing_permission_service_does_not_crash() -> void:
	var registry_without_permissions := ServiceRegistry.new()
	registry_without_permissions.register_resource(_session_manager, ServiceKeys.SESSION_MANAGER)
	_orchestrator._app_scope = AppScope.new(registry_without_permissions)

	_orchestrator._ensure_default_role_for_tier("player_x")  # darf nicht crashen

	pass_test("T-08: fehlende PermissionService in der Registry darf nicht crashen")

func test_t09_missing_session_manager_does_not_crash() -> void:
	var registry_without_session := ServiceRegistry.new()
	registry_without_session.register_resource(_permission_service, ServiceKeys.PERMISSION_SERVICE)
	_orchestrator._app_scope = AppScope.new(registry_without_session)

	_orchestrator._ensure_default_role_for_tier("player_x")  # darf nicht crashen

	assert_eq(
		_permission_service.get_role_id("player_x"), "player",
		"T-09: ohne SessionManager darf keine Zuweisung passieren (Fallback bleibt Default-Rolle)"
	)

class_name BootPipeline extends RefCounted

const LOG_CAT := "BootPipeline"

class Result:
	var ok: bool = true
	var failed_phase: String = ""
	var reason: String = ""

	static func success() -> Result:
		return Result.new()

	static func failure(phase: String, why: String) -> Result:
		var r := Result.new()
		r.ok = false
		r.failed_phase = phase
		r.reason = why
		return r

	func _to_string() -> String:
		if ok:
			return "BootPipeline.Result(ok)"
		return "BootPipeline.Result(FAIL phase='%s' reason='%s')" % [failed_phase, reason]

var validator: ServiceValidator
var resolver: ServiceDependencyResolver
var factory: ServiceFactory
var initializer: ServiceInitializer
var installer: ServiceInstaller
var teardown: ServiceTeardownManager

var _app_boot_order: Array[String] = []
var _character_boot_order: Array[String] = []
var _world_boot_order: Array[String] = []

func _init() -> void:
	validator = ServiceValidator.new()
	resolver = ServiceDependencyResolver.new()
	factory = ServiceFactory.new()
	initializer = ServiceInitializer.new()
	installer = ServiceInstaller.new()
	teardown = ServiceTeardownManager.new()

func boot_app(app_scope: AppScope, parent: Node) -> Result:
	AppLogger.log_info("╔══ APP BOOT START ══╗", LOG_CAT)
	var started := Time.get_ticks_msec()
	var registry := app_scope.registry

	registry.register_resource(EventBusAdapter.new(), ServiceKeys.EVENT_BUS)

	var defs := validator.validate()
	if defs.is_empty():
		AppLogger.log_error("Phase 1 FAIL — global_services leer oder defekt.", LOG_CAT)
		return Result.failure("validate_app", "BootstrapConfig.global_services ungültig")
	AppLogger.log_info("Phase 1 OK — %d App-Definitionen." % defs.size(), LOG_CAT)

	var cfg := validator.get_loaded_config()
	var resource_names: Array[String] = []
	if cfg != null and not cfg.global_resources.is_empty():
		resource_names = _load_resources(cfg.global_resources, registry)
		AppLogger.log_info("Phase 1.5 OK — %d Resources geladen." % resource_names.size(), LOG_CAT)

	var ordered := resolver.resolve(defs, registry.get_all_names())
	if ordered.is_empty():
		AppLogger.log_error("Phase 2 FAIL — Dependency-Fehler.", LOG_CAT)
		return Result.failure("resolve_app", "Dependency-Fehler")
	AppLogger.log_info("Phase 2 OK — Reihenfolge: [%s]" % ", ".join(ordered), LOG_CAT)
	_app_boot_order = ordered

	var ordered_defs := _sort_defs(defs, ordered)
	if not factory.instantiate_all(ordered_defs, registry, parent):
		return Result.failure("factory_app", "Instanziierung fehlgeschlagen")
	AppLogger.log_info("Phase 3 OK — Alle App-Services instanziiert.", LOG_CAT)

	initializer.run(ordered, registry)
	AppLogger.log_info("Phase 4 OK — configure() abgeschlossen.", LOG_CAT)

	initializer.run_on_ready(ordered, registry)
	AppLogger.log_info("Phase 5 OK — on_ready() abgeschlossen.", LOG_CAT)

	var ticker := registry.get_service(ServiceKeys.TICKER) as ServiceTicker
	if ticker:
		ticker.start_ticking()
		AppLogger.log_info("Phase 6 OK — Ticker gestartet.", LOG_CAT)
	else:
		AppLogger.log_warn("Phase 6 — Kein Ticker.", LOG_CAT)

	if not installer.install(registry):
		AppLogger.log_error("Phase 7 FAIL — kritischer Global-Service fehlt.", LOG_CAT)
		return Result.failure("install_app", "Kritischer Service fehlt in globaler Registry")
	AppLogger.log_info("Phase 7 OK — App-Services registriert.", LOG_CAT)

	var gm := registry.get_service(ServiceKeys.GAME_MANAGER)
	if gm is GameManager:
		gm.start_game()
		AppLogger.log_info("Phase 8 OK — GameManager.start_game().", LOG_CAT)
	else:
		AppLogger.log_warn("Phase 8 — GameManager nicht gefunden.", LOG_CAT)

	var elapsed := Time.get_ticks_msec() - started
	AppLogger.log_info("╚══ APP BOOT FERTIG (%d ms) ══╝" % elapsed, LOG_CAT)
	return Result.success()

func boot_character(char_scope: CharacterScope, parent: Node) -> Result:
	var player_id := char_scope.player_id
	AppLogger.log_info("╔══ CHARACTER BOOT START ('%s') ══╗" % player_id, LOG_CAT)
	var started := Time.get_ticks_msec()
	var registry := char_scope.registry
	var app_reg := char_scope.app_registry

	var save_sys: Object = app_reg.get_service(ServiceKeys.SAVE_SYSTEM)
	if is_instance_valid(save_sys) and save_sys.has_method("begin_session"):
		save_sys.begin_session(player_id)
		AppLogger.log_info("Phase C1 OK — Save für '%s' geladen." % player_id, LOG_CAT)
	else:
		AppLogger.log_error("Phase C1 FAIL — SaveSystem fehlt!", LOG_CAT)
		return Result.failure("character_save", "SaveSystem fehlt")

	# ADR-017: Cross-Scope-Zugriff läuft ausschließlich über diese explizite
	# Bridge-Liste — nicht über einen impliziten Fallback in ServiceInitializer.
	# Jeder Global-Service, den irgendein Session-Service in BootstrapConfig.tres
	# als Dep deklariert, MUSS hier stehen, sonst bleibt configure() für diese
	# Dep null (mit Warnung), statt sie "zufällig" über eine zweite Registry
	# nachzuschlagen. Diese Liste ist die einzige Quelle der Wahrheit dafür,
	# was Session-Scope aus App-Scope sehen darf.
	_bridge_app_services_into_session(app_reg, registry, [
		ServiceKeys.EVENT_BUS,
		ServiceKeys.SAVE_SYSTEM,
		ServiceKeys.DATA,
		ServiceKeys.GAME_MANAGER,
		ServiceKeys.SESSION_MANAGER,
		ServiceKeys.TICKER,
		ServiceKeys.SETTINGS_SERVICE,
		ServiceKeys.PERMISSION_SERVICE,
	])

	var app_names := app_reg.get_all_names()
	var defs := validator.validate_session(app_names)
	if defs.is_empty():
		return Result.failure("validate_character", "BootstrapConfig.session_services ungültig")
	AppLogger.log_info("Phase C2 OK — %d Character-Definitionen." % defs.size(), LOG_CAT)

	var external_names := app_names.duplicate()
	external_names.append_array(registry.get_all_names())
	var ordered := resolver.resolve(defs, external_names)
	if ordered.is_empty():
		return Result.failure("resolve_character", "Dependency-Fehler")
	AppLogger.log_info("Phase C3 OK — Reihenfolge: [%s]" % ", ".join(ordered), LOG_CAT)
	_character_boot_order = ordered

	var ordered_defs := _sort_defs(defs, ordered)
	if not factory.instantiate_all(ordered_defs, registry, parent):
		return Result.failure("factory_character", "Instanziierung fehlgeschlagen")
	AppLogger.log_info("Phase C4 OK — Alle Character-Services instanziiert.", LOG_CAT)

	initializer.run(ordered, registry)
	AppLogger.log_info("Phase C5 OK — configure() abgeschlossen.", LOG_CAT)

	initializer.run_on_ready(ordered, registry)
	AppLogger.log_info("Phase C6 OK — on_ready() abgeschlossen.", LOG_CAT)

	if not installer.install_session(registry):
		AppLogger.log_error("Phase C7 FAIL — kritischer Session-Service fehlt.", LOG_CAT)
		return Result.failure("install_character", "Kritischer Service fehlt in Session-Registry")
	AppLogger.log_info("Phase C7 OK — Character-Services registriert.", LOG_CAT)

	# ADR-027: WorldService → EquipmentService Late-Inject, unabhängig vom
	# NetworkBridge-Zweig unten (auch Tier 1/Solo braucht die Visual-Auflösung).
	# Beide Services sind seit Phase C7 in der Session-Registry instanziiert.
	# configure()-Dep wäre hier ein zirkulärer Fehler im Resolver, da WorldService
	# selbst "equipment" bereits als Dep deklariert (siehe EquipmentService.gd).
	var world_for_equipment := registry.get_service(ServiceKeys.WORLD) as WorldService
	var equipment_svc := registry.get_service(ServiceKeys.EQUIPMENT) as EquipmentService
	if is_instance_valid(world_for_equipment) and is_instance_valid(equipment_svc):
		equipment_svc.inject_world_service(world_for_equipment)
		AppLogger.log_info("Phase C7.5 OK — WorldService in EquipmentService injiziert.", LOG_CAT)
	else:
		AppLogger.log_debug("Phase C7.5 — WorldService oder EquipmentService fehlt (Tests).", LOG_CAT)

	# Round 114 (ADR-048 Broadcast-Lücke): dieselbe Late-Inject-Begründung wie
	# oben bei EquipmentService — CharacterCreationService braucht WorldService,
	# um PlayerVisuals für BELIEBIGE player_ids aufzulösen (siehe
	# CharacterCreationService._apply_look_to_visuals()).
	var character_creation_svc := registry.get_service(ServiceKeys.CHARACTER_CREATION) as CharacterCreationService
	if is_instance_valid(world_for_equipment) and is_instance_valid(character_creation_svc):
		character_creation_svc.inject_world_service(world_for_equipment)
		AppLogger.log_info("Phase C7.5 OK — WorldService in CharacterCreationService injiziert.", LOG_CAT)
	else:
		AppLogger.log_debug("Phase C7.5 — WorldService oder CharacterCreationService fehlt (Tests).", LOG_CAT)

	# Kleidung/Rüstung: EquipmentService schreibt getragene Teile in den Look des
	# CharacterCreationService (Late-Inject aus demselben Zyklus-Grund wie oben).
	if is_instance_valid(equipment_svc) and is_instance_valid(character_creation_svc):
		equipment_svc.inject_wearables(character_creation_svc)
		AppLogger.log_info("Phase C7.5 OK — CharacterCreationService in EquipmentService injiziert (Kleidung).", LOG_CAT)

	var net := registry.get_service(ServiceKeys.NETWORK_BRIDGE) as NetworkBridge
	if is_instance_valid(net):
		for key in [ServiceKeys.INVENTORY, ServiceKeys.QUEST, ServiceKeys.SKILL_SYSTEM, ServiceKeys.EQUIPMENT, ServiceKeys.WORLD, ServiceKeys.REWARD_DISPATCHER, ServiceKeys.COMBAT, ServiceKeys.ZONE_SERVICE, ServiceKeys.CURRENCY, ServiceKeys.INTERACTION, ServiceKeys.SHOP, ServiceKeys.SMITHING, ServiceKeys.PVP, ServiceKeys.BANK, ServiceKeys.TRADE, ServiceKeys.AUCTION_HOUSE, ServiceKeys.ITEM_PROTECTION, ServiceKeys.PVP_DEATH_LOSS, ServiceKeys.AURA, ServiceKeys.DEATH_LOOT, ServiceKeys.PICKPOCKET, ServiceKeys.CHAT, ServiceKeys.REPORT, ServiceKeys.ACHIEVEMENT, ServiceKeys.STATS, ServiceKeys.CHARACTER_CREATION, ServiceKeys.WIKI]:
			var svc := registry.get_service(key)
			if is_instance_valid(svc) and svc.has_method("inject_network_bridge"):
				svc.inject_network_bridge(net)
		AppLogger.log_info("Phase C8 OK — NetworkBridge injiziert.", LOG_CAT)
	else:
		AppLogger.log_debug("Phase C8 — kein NetworkBridge (Solo/Tests).", LOG_CAT)

	var sm := registry.get_service(ServiceKeys.SESSION_MANAGER) as SessionManager
	if is_instance_valid(sm):
		var local_peer := sm.get_local_peer_id()
		sm.register_player_slot(local_peer, player_id)
		AppLogger.log_info("Phase C9 OK — '%s' als peer %d eingetragen." % [player_id, local_peer], LOG_CAT)
	else:
		AppLogger.log_debug("Phase C9 — kein SessionManager (Tests).", LOG_CAT)

	# ADR-029 Round 64: Hook für Services, deren EIGENE lokale player_id erst
	# NACH dem SessionManager-Slot-Eintrag (Phase C9) auflösbar ist — weder
	# configure() (C5) noch on_ready() (C6) noch inject_network_bridge() (C8)
	# reichen dafür aus, weil C9 selbst der Slot-Eintrag ist, den
	# NetworkBridge.get_local_player_id() braucht. Duck-typed wie der C8-Loop
	# oben, damit nicht jeder Service diese Methode implementieren muss.
	# Bislang einziger Konsument: QuestService (Auto-Start-Quests).
	for key2 in [ServiceKeys.QUEST]:
		var svc3 := registry.get_service(key2)
		if is_instance_valid(svc3) and svc3.has_method("on_local_identity_ready"):
			svc3.on_local_identity_ready()
	AppLogger.log_info("Phase C9.5 OK — lokale Identität an abhängige Services verteilt.", LOG_CAT)

	var net_svc := registry.get_service(ServiceKeys.NETWORK_BRIDGE) as NetworkBridge
	if is_instance_valid(net_svc):
		net_svc.send_request_initial_state()
		AppLogger.log_info("Phase C10 OK — Initial-Snapshot angefordert.", LOG_CAT)
	else:
		AppLogger.log_debug("Phase C10 — kein NetworkBridge (Solo/Tests).", LOG_CAT)

	var elapsed := Time.get_ticks_msec() - started
	AppLogger.log_info("╚══ CHARACTER BOOT FERTIG (%d ms) ══╝" % elapsed, LOG_CAT)
	return Result.success()

func boot_world(world_scope: WorldScope, parent: Node) -> Result:
	AppLogger.log_info("╔══ WORLD BOOT START ══╗", LOG_CAT)
	var started := Time.get_ticks_msec()
	var registry := world_scope.registry
	var char_reg := world_scope.char_registry
	var app_reg := world_scope.app_registry
	var world_root := world_scope.world_root

	var world_svc := char_reg.get_service(ServiceKeys.WORLD) as WorldService
	if not is_instance_valid(world_svc):
		AppLogger.log_error("Phase W1 FAIL — WorldService nicht in Character-Registry!", LOG_CAT)
		return Result.failure("world_service", "WorldService fehlt in CharacterScope")

	world_svc.warmup_mesh_cache()
	AppLogger.log_info("Phase W1 OK — MeshCache gebaut.", LOG_CAT)

	# await: on_world_scene_ready() generiert Entity-Positionen ggf. asynchron
	# (WorldGenerationService-Thread) und kehrt erst zurück wenn die Welt
	# vollständig gespawnt ist. boot_world() ist dadurch selbst eine Coroutine —
	# Aufrufer (ServiceOrchestrator._on_world_initializer_ready) müssen awaiten.
	await world_svc.on_world_scene_ready(world_root)
	AppLogger.log_info("Phase W2 OK — WorldService mit Root '%s' verdrahtet." % world_root.name, LOG_CAT)

	_world_boot_order = []

	var elapsed := Time.get_ticks_msec() - started
	AppLogger.log_info("╚══ WORLD BOOT FERTIG (%d ms) ══╝" % elapsed, LOG_CAT)
	return Result.success()

func teardown_world(world_scope: WorldScope) -> void:
	AppLogger.log_info("── World-Teardown gestartet.", LOG_CAT)
	teardown.execute(world_scope.registry, _world_boot_order)
	_world_boot_order = []
	AppLogger.log_info("── World-Teardown fertig.", LOG_CAT)

func teardown_character(char_scope: CharacterScope) -> void:
	AppLogger.log_info("── Character-Teardown gestartet.", LOG_CAT)
	teardown.execute(char_scope.registry, _character_boot_order)
	_character_boot_order = []
	var save_sys: Object = char_scope.app_registry.get_service(ServiceKeys.SAVE_SYSTEM)
	if is_instance_valid(save_sys) and save_sys.has_method("end_session"):
		save_sys.end_session()
	AppLogger.log_info("── Character-Teardown fertig.", LOG_CAT)

func teardown_app(app_scope: AppScope) -> void:
	AppLogger.log_info("── App-Teardown gestartet.", LOG_CAT)
	teardown.execute(app_scope.registry, _app_boot_order)
	_app_boot_order = []
	AppLogger.log_info("── App-Teardown fertig.", LOG_CAT)

func teardown_all(app_scope: AppScope) -> void:
	AppLogger.log_info("── Full-Teardown gestartet.", LOG_CAT)
	if app_scope.has_character_scope():
		var cs := app_scope.get_character_scope()
		if cs.has_world_scope():
			teardown_world(cs.get_world_scope())
		teardown_character(cs)
	teardown_app(app_scope)
	AppLogger.log_info("── Full-Teardown fertig.", LOG_CAT)

## ADR-017: Einziger Weg, wie ein Service aus einem Kind-Scope (z.B. Session)
## einen Service aus dem Eltern-Scope (z.B. App) sehen darf. Kopiert die
## Referenz explizit in die Ziel-Registry, bevor configure() läuft — danach
## ist jede Dep für ServiceInitializer eine ganz normale lokale Dep, kein
## Sonderfall, kein zweiter Nachschlage-Pfad.
func _bridge_app_services_into_session(
	app_reg: ServiceRegistry,
	session_reg: ServiceRegistry,
	keys: Array
) -> void:
	for key in keys:
		var svc := app_reg.get_service(key)
		if svc != null:
			session_reg.register_resource(svc, key)
		else:
			AppLogger.log_warn(
				"Cross-Scope-Bridge: '%s' nicht in App-Registry gefunden — Session-Services mit dieser Dep bekommen null." % key,
				LOG_CAT
			)

func _load_resources(defs: Array[ResourceDefinition], registry: ServiceRegistry) -> Array[String]:
	var names: Array[String] = []
	for def in defs:
		if def == null or def.registry_key.is_empty() or def.path.is_empty():
			AppLogger.log_error("ResourceDefinition ungültig.", LOG_CAT)
			continue
		if not ResourceLoader.exists(def.path):
			AppLogger.log_error("Resource nicht gefunden: '%s'" % def.path, LOG_CAT)
			continue
		var res := load(def.path)
		if res == null:
			AppLogger.log_error("Resource konnte nicht geladen werden: '%s'" % def.path, LOG_CAT)
			continue
		registry.register_resource(res, def.registry_key)
		names.append(def.registry_key.to_lower())
	return names

func _sort_defs(defs: Array[ServiceDefinition], ordered: Array[String]) -> Array[ServiceDefinition]:
	var def_map: Dictionary = {}
	for d in defs:
		def_map[d.service_name.to_lower()] = d
	var result: Array[ServiceDefinition] = []
	for name in ordered:
		if def_map.has(name):
			result.append(def_map[name])
	return result

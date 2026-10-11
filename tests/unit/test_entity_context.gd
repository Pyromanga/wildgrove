# res://tests/unit/test_entity_context.gd
extends GutTest

## Tests für EntityContext.for_test() — kein AutoLoad, kein SceneTree nötig.
##
## Abgedeckte Pfade:
##   - for_test() liefert gültige EntityContext-Instanz
##   - Alle Getter geben null zurück (kein Mock injiziert)
##   - Nach Injektion liefern Getter die injizierten Mock-Objekte
##   - IEntityContext-Interface korrekt implementiert (alle Methoden vorhanden)
##   - get_event_bus() → IEventBus: null by default, injizierbarer MockEventBus (I-02b)

# ─────────────────────────────────────────────
# Minimale Mock-Klassen (inline, kein extra File)
# ─────────────────────────────────────────────

class MockSkillSystem extends SkillSystem:
	func get_level(_skill: String, _player_id: String = "1") -> int: return 42

class MockInventorySystem extends InventorySystem:
	func has_item(_item_id: String, _player_id: String, _quantity: int = 1) -> bool: return true

class MockFactory3D extends Factory3D:
	pass

class MockRespawnService extends RespawnService:
	pass

# ─────────────────────────────────────────────
# Basis-Verhalten
# ─────────────────────────────────────────────

func test_for_test_returns_valid_instance() -> void:
	var ctx := EntityContext.for_test()
	assert_not_null(ctx, "for_test() muss eine EntityContext-Instanz liefern")
	assert_true(ctx is IEntityContext, "EntityContext muss IEntityContext implementieren")

func test_for_test_all_services_null_by_default() -> void:
	var ctx := EntityContext.for_test()
	assert_null(ctx.get_skill_system(), "SkillSystem ohne Injektion → null")
	assert_null(ctx.get_inventory(),    "InventorySystem ohne Injektion → null")
	assert_null(ctx.get_factory(),      "Factory3D ohne Injektion → null")
	assert_null(ctx.get_respawn(),      "RespawnService ohne Injektion → null")

func test_for_test_independent_instances() -> void:
	# Zwei for_test()-Aufrufe → unabhängige Instanzen (kein Singleton-Leak)
	var ctx_a := EntityContext.for_test()
	var ctx_b := EntityContext.for_test()
	ctx_a._skill_system = MockSkillSystem.new()
	assert_null(ctx_b.get_skill_system(), "ctx_b darf ctx_a-Injection nicht sehen")

# ─────────────────────────────────────────────
# Mock-Injection
# ─────────────────────────────────────────────

func test_injected_skill_system_returned() -> void:
	var ctx  := EntityContext.for_test()
	var mock := MockSkillSystem.new()
	ctx._skill_system = mock
	assert_eq(ctx.get_skill_system(), mock, "Injiziertes SkillSystem wird zurückgegeben")

func test_injected_inventory_returned() -> void:
	var ctx  := EntityContext.for_test()
	var mock := MockInventorySystem.new()
	ctx._inventory = mock
	assert_eq(ctx.get_inventory(), mock, "Injiziertes Inventory wird zurückgegeben")

func test_injected_factory_returned() -> void:
	var ctx  := EntityContext.for_test()
	var mock := MockFactory3D.new()
	ctx._factory = mock
	assert_eq(ctx.get_factory(), mock, "Injizierte Factory wird zurückgegeben")

func test_injected_respawn_returned() -> void:
	var ctx  := EntityContext.for_test()
	var mock := MockRespawnService.new()
	ctx._respawn = mock
	assert_eq(ctx.get_respawn(), mock, "Injizierter RespawnService wird zurückgegeben")

func test_mock_skill_system_method_callable() -> void:
	var ctx  := EntityContext.for_test()
	var mock := MockSkillSystem.new()
	ctx._skill_system = mock

	# Verhalten des Mocks prüfen (nicht nur Identität)
	assert_eq(ctx.get_skill_system().get_level("woodcutting", "p1"), 42,
		"Mock-SkillSystem.get_level() muss 42 zurückgeben")

# ─────────────────────────────────────────────
# IEntityContext-Vertrag
# ─────────────────────────────────────────────

func test_ientitycontext_base_methods_return_null() -> void:
	# IEntityContext selbst (Basisklasse) gibt auf allen Gettern null zurück
	var base := IEntityContext.new()
	assert_null(base.get_skill_system())
	assert_null(base.get_inventory())
	assert_null(base.get_factory())
	assert_null(base.get_respawn())

func test_get_event_bus_returns_null_by_default() -> void:
	# I-02b fix: IEntityContext.get_event_bus() → IEventBus (war Node → AutoLoad-Hardcode)
	# for_test() injiziert keinen Bus → null ist korrekt
	var ctx := EntityContext.for_test()
	assert_null(ctx.get_event_bus(),
		"for_test() ohne injizierten Bus muss null liefern — kein AutoLoad-Hardcode")

func test_get_event_bus_returns_injected_mock() -> void:
	# from_deps() mit MockEventBus → get_event_bus() gibt den Mock zurück
	var mock_bus := MockEventBus.new()
	var ctx := EntityContext.from_deps(
		null, null, null, null, null, null, null, null, null, null, 1, mock_bus
	)
	var result := ctx.get_event_bus()
	assert_eq(result, mock_bus, "get_event_bus() muss den injizierten MockEventBus zurückgeben")

func test_iEntityContext_base_returns_null_not_autoload() -> void:
	# Basis-Implementierung (IEntityContext direkt) darf EventBus-AutoLoad NICHT zurückgeben
	var base := IEntityContext.new()
	assert_null(base.get_event_bus(),
		"IEntityContext-Basis darf keinen AutoLoad zurückgeben — nur null als Vertrag")

func test_get_network_bridge_returns_null_by_default() -> void:
	# ADR-021 (R-5): for_test() injiziert keine NetworkBridge → null ist korrekt
	var ctx := EntityContext.for_test()
	assert_null(ctx.get_network_bridge(),
		"for_test() ohne injizierte NetworkBridge muss null liefern")

func test_get_network_bridge_returns_injected_instance() -> void:
	# ADR-021 (R-5): from_deps() mit NetworkBridge als letztem Positions-Arg →
	# get_network_bridge() gibt sie zurück. QuestNPC/QuestCustomTrigger brauchen
	# das für report_domain_event().
	var network := NetworkBridge.new()
	var ctx := EntityContext.from_deps(
		null, null, null, null, null, null, null, null, null, null, 1, null, 1, network
	)
	assert_eq(ctx.get_network_bridge(), network,
		"get_network_bridge() muss die injizierte NetworkBridge zurückgeben")
	network.free()

func test_iEntityContext_base_get_network_bridge_returns_null() -> void:
	var base := IEntityContext.new()
	assert_null(base.get_network_bridge(),
		"IEntityContext-Basis muss null liefern — kein impliziter Autoload-Zugriff")

# ─────────────────────────────────────────────
# ─────────────────────────────────────────────

class MockDataService extends DataService:
	pass

class MockStatModifierService extends StatModifierService:
	pass

func test_from_deps_returns_valid_instance() -> void:
	# from_deps() braucht keine Services-Autoloads
	var skill    := MockSkillSystem.new()
	var inv      := MockInventorySystem.new()
	var factory  := MockFactory3D.new()
	var respawn  := MockRespawnService.new()
	var data     := MockDataService.new()
	var stat_mod := MockStatModifierService.new()

	var ctx := EntityContext.from_deps(
		skill, inv, factory, respawn, data, stat_mod,
		null, null, null, null, 42
	)
	assert_not_null(ctx, "from_deps() muss EntityContext liefern")
	assert_true(ctx is IEntityContext, "EntityContext implements IEntityContext")

func test_from_deps_peer_id_correctly_set() -> void:
	var ctx := EntityContext.from_deps(
		null, null, null, null, null, null,
		null, null, null, null, 7
	)
	assert_eq(ctx.owner_peer_id, 7, "peer_id 7 muss in owner_peer_id landen")

func test_from_deps_default_peer_id_is_1() -> void:
	# Default peer_id = 1 (Solo/Tier-1)
	var ctx := EntityContext.from_deps(
		null, null, null, null, null, null,
		null, null, null, null
	)
	assert_eq(ctx.owner_peer_id, 1, "Default peer_id muss 1 sein")

func test_from_deps_skill_system_injected() -> void:
	var skill := MockSkillSystem.new()
	var ctx   := EntityContext.from_deps(
		skill, null, null, null, null, null,
		null, null, null, null
	)
	assert_eq(ctx.get_skill_system(), skill, "SkillSystem aus from_deps() korrekt")

func test_from_deps_independent_of_services_container() -> void:
	# Der Test braucht keinen befüllten Services-Singleton — das ist der Kernpunkt
	var ctx := EntityContext.from_deps(
		MockSkillSystem.new(), MockInventorySystem.new(), MockFactory3D.new(),
		MockRespawnService.new(), MockDataService.new(), MockStatModifierService.new(),
		null, null, null, null, 1
	)
	# Dieser Test läuft ohne Autoload-Zugriff — EntityContext.from_deps() ist der einzige Pfad.
	assert_not_null(ctx.get_skill_system(), "SkillSystem aus from_deps() — kein Services-Locator nötig")
	assert_not_null(ctx.get_inventory(),    "Inventory aus from_deps() — kein Services-Locator nötig")


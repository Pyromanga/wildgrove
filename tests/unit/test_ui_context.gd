# res://tests/unit/test_ui_context.gd
extends GutTest

## Tests für UIContext.bus() — I-02 (AUDIT-03).
##
## I-02 schließt die UI-Hälfte von H-07/ADR-011: Services injizieren IEventBus bereits
## korrekt via deps.require(EVENT_BUS); UI-Controller griffen bisher direkt auf den
## EventBus-AutoLoad zu. Diese Tests decken den neuen Injektionspfad ab, analog zu
## test_entity_context.gd für IEntityContext.
##
## Abgedeckte Pfade:
##   - for_test() liefert gültige UIContext-Instanz, bus() ist null ohne Injektion
##   - Nach Injektion (ctx._bus = MockEventBus.new()) liefert bus() den Mock
##   - from_registry() löst IEventBus aus ServiceKeys.EVENT_BUS auf — identischer
##     Registry-Key wie bei Services (kein zweiter Adapter, keine zweite Quelle)
##   - from_registry() liefert weiterhin alle bestehenden Getter korrekt (Regression)
##   - IUIContext-Basisklasse: bus() ohne Override gibt null zurück (Interface-Vertrag)

# ─────────────────────────────────────────────
# IUIContext — Basisklassen-Vertrag
# ─────────────────────────────────────────────

func test_iuicontext_base_bus_returns_null() -> void:
	# Die abstrakte Basisklasse selbst (kein Override) muss null liefern —
	# exakt wie alle anderen IUIContext-Getter (get_quest(), get_data(), …).
	var base := IUIContext.new()
	assert_null(base.bus(), "IUIContext.bus() ohne Override muss null liefern")

# ─────────────────────────────────────────────
# UIContext.for_test() — kein AutoLoad, kein SceneTree nötig
# ─────────────────────────────────────────────

func test_for_test_returns_valid_instance() -> void:
	var ctx := UIContext.for_test()
	assert_not_null(ctx, "for_test() muss eine UIContext-Instanz liefern")
	assert_true(ctx is IUIContext, "UIContext muss IUIContext implementieren")

func test_for_test_bus_null_by_default() -> void:
	# Wie bei allen anderen Services in UIContext.for_test(): kein Mock injiziert → null.
	var ctx := UIContext.for_test()
	assert_null(ctx.bus(), "bus() ohne Injektion muss null liefern")

func test_for_test_bus_returns_injected_mock() -> void:
	var ctx := UIContext.for_test()
	var mock := MockEventBus.new()
	ctx._bus = mock
	assert_eq(ctx.bus(), mock, "bus() muss den injizierten MockEventBus liefern")

func test_for_test_independent_instances() -> void:
	# Zwei for_test()-Aufrufe → unabhängige Instanzen, kein Bus-Leak zwischen Tests.
	var ctx_a := UIContext.for_test()
	var ctx_b := UIContext.for_test()
	ctx_a._bus = MockEventBus.new()
	assert_null(ctx_b.bus(), "ctx_b darf ctx_a's injizierten Bus nicht sehen")

# ─────────────────────────────────────────────
# UIContext.from_registry() — Produktionspfad
# ─────────────────────────────────────────────

func test_from_registry_resolves_bus_from_event_bus_key() -> void:
	# from_registry() muss IEventBus aus genau demselben Registry-Key lesen,
	# den auch Services für deps.require(ServiceKeys.EVENT_BUS) nutzen —
	# kein zweiter, paralleler Adapter-Pfad für UI.
	var registry := ServiceRegistry.new()
	var mock := MockEventBus.new()
	registry.register_resource(mock, ServiceKeys.EVENT_BUS)

	var ctx := UIContext.from_registry(registry)
	assert_eq(ctx.bus(), mock, "from_registry() muss IEventBus aus ServiceKeys.EVENT_BUS lesen")

func test_from_registry_bus_null_when_not_registered() -> void:
	# Kein Crash wenn der Key fehlt (z.B. in einer unvollständigen Test-Registry) —
	# get_service() liefert null, bus() reicht das null durch statt zu werfen.
	var registry := ServiceRegistry.new()
	var ctx := UIContext.from_registry(registry)
	assert_null(ctx.bus(), "from_registry() ohne registrierten event_bus → bus() ist null")

func test_from_registry_real_adapter_matches_service_pattern() -> void:
	# Produktionspfad: BootPipeline registriert EventBusAdapter.new() unter EVENT_BUS,
	# identisch für Services UND UIContext (kein zweiter Adapter-Typ für UI).
	var registry := ServiceRegistry.new()
	var adapter := EventBusAdapter.new()
	registry.register_resource(adapter, ServiceKeys.EVENT_BUS)

	var ctx := UIContext.from_registry(registry)
	assert_eq(ctx.bus(), adapter, "from_registry() muss denselben EventBusAdapter liefern wie Services")
	assert_true(ctx.bus() is IEventBus, "Resultat muss IEventBus sein")

func test_from_registry_still_resolves_existing_getters() -> void:
	# Regression: from_registry() darf durch die bus()-Erweiterung die bestehenden
	# Service-Getter nicht brechen.
	var registry := ServiceRegistry.new()

	var quest := QuestService.new()
	var def := ServiceDefinition.new()
	def.service_name = ServiceKeys.QUEST
	def.path = "res://scripts/progression/quests/QuestService.gd"
	def.required_deps = []
	registry.register(quest, def)

	var ctx := UIContext.from_registry(registry)
	assert_eq(ctx.get_quest(), quest, "from_registry() muss weiterhin QuestService auflösen")
	assert_null(ctx.bus(), "event_bus nicht registriert → bus() bleibt null, kein Crash")

# ─────────────────────────────────────────────
# get_settings() — SettingsService-Fassade (Settings.gd-Persistenz-Fix)
# ─────────────────────────────────────────────

func test_iuicontext_base_get_settings_returns_null() -> void:
	var base := IUIContext.new()
	assert_null(base.get_settings(), "IUIContext.get_settings() ohne Override muss null liefern")

func test_for_test_get_settings_null_by_default() -> void:
	var ctx := UIContext.for_test()
	assert_null(ctx.get_settings(), "get_settings() ohne Injektion muss null liefern")

func test_from_registry_resolves_settings_from_bridged_key() -> void:
	# Produktionspfad: SettingsService ist ein Global-Service, wird per
	# BootPipeline._bridge_app_services_into_session() als Resource unter
	# ServiceKeys.SETTINGS_SERVICE in die Session-Registry gespiegelt — exakt
	# derselbe Mechanismus wie für DATA/SAVE_SYSTEM/EVENT_BUS.
	var registry := ServiceRegistry.new()
	var settings := SettingsService.new()
	registry.register_resource(settings, ServiceKeys.SETTINGS_SERVICE)

	var ctx := UIContext.from_registry(registry)
	assert_eq(ctx.get_settings(), settings, "from_registry() muss SettingsService aus SETTINGS_SERVICE lesen")

func test_from_registry_get_settings_null_when_not_registered() -> void:
	var registry := ServiceRegistry.new()
	var ctx := UIContext.from_registry(registry)
	assert_null(ctx.get_settings(), "from_registry() ohne registrierten settings_service → get_settings() ist null")

# ─────────────────────────────────────────────
# get_local_player_id() — ADR-029 Plan-Schritt 4 (Round 63)
# ─────────────────────────────────────────────

func test_iuicontext_base_get_local_player_id_returns_empty() -> void:
	# Basisklasse ohne Override: leerer String, kein geratener Platzhalter
	# (analog zu get_settings()/bus() — siehe IUIContext-Kommentar).
	var base := IUIContext.new()
	assert_eq(base.get_local_player_id(), "", "IUIContext.get_local_player_id() ohne Override muss '' liefern")

func test_for_test_get_local_player_id_empty_by_default() -> void:
	var ctx := UIContext.for_test()
	assert_eq(ctx.get_local_player_id(), "", "get_local_player_id() ohne Injektion muss '' liefern")

func test_from_registry_resolves_local_player_id_from_session_manager() -> void:
	# Produktionspfad: from_registry() fragt SessionManager.get_local_player_id(),
	# genau wie es bereits für get_local_peer_id() tut (kein zweiter Auflösungsweg).
	var registry := ServiceRegistry.new()
	var session := SessionManager.new()
	session.register_player_slot(1, "player-uuid-abc")
	registry.register_resource(session, ServiceKeys.SESSION_MANAGER)

	var ctx := UIContext.from_registry(registry)
	assert_eq(ctx.get_local_player_id(), "player-uuid-abc",
		"from_registry() muss get_local_player_id() über SessionManager auflösen")

	session.free()

func test_from_registry_local_player_id_empty_when_session_manager_not_registered() -> void:
	var registry := ServiceRegistry.new()
	var ctx := UIContext.from_registry(registry)
	assert_eq(ctx.get_local_player_id(), "",
		"from_registry() ohne registrierten session_manager → get_local_player_id() bleibt ''")

# ─────────────────────────────────────────────
# get_world() — nur Lese-Zugriff der UI (Bau-Vorschau)
# ─────────────────────────────────────────────

func test_iuicontext_base_get_world_returns_null() -> void:
	assert_null(IUIContext.new().get_world())

func test_for_test_get_world_null_by_default() -> void:
	assert_null(UIContext.for_test().get_world())

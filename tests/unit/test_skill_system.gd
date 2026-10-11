# res://tests/unit/test_skill_system.gd
## Unit-Tests für SkillSystem.
##
## ADR-029 Plan-Schritt 4 (Round 65): player_id ist jetzt String (Pflicht-
## parameter, kein Default mehr) statt peer_id (int, Default 1). P1/P2 sind
## hier reine opake Test-Bucket-Keys, keine echten UUIDs — genügt, SkillSystem
## behandelt player_id ohnehin nur als Dictionary-Key. Kein Parameter-
## Reordering nötig, player_id stand überall bereits als letzter Parameter
## (siehe SkillSystem.gd Klassenkommentar).
##
## Zweite Änderung dieser Runde: configure() ruft kein _ensure_player(1) mehr
## automatisch auf (lokale player_id ist zum Zeitpunkt von configure() noch
## nicht auflösbar, siehe SkillSystem.configure()-Kommentar) — Spieler-Buckets
## entstehen ausschließlich lazy über _ensure_player(). Tests, die einen
## Bucket ohne Xp-Mutation brauchen, rufen jetzt explizit _svc._ensure_player()
## auf, analog zum direkten _svc._definitions-Zugriff in test_quest_service.gd.
##
## Dritte Änderung: SkillSystem lädt seine Definitionen jetzt zwingend aus
## DataService (ServiceDeps.require) statt aus einem hardkodierten Fallback —
## ein leerer DataService führt zu AppLogger.fatal() (siehe
## SkillSystem._init_definitions()). Ein MockDataService mit vier
## SkillDefinitions (analog zu MockDataService in test_inventory_system.gd)
## ersetzt die früheren Fallback-Skills. Die XP-Kurve der Mock-Definitionen
## ist bewusst level * 100 nachgebaut, damit die bereits vorhandenen
## Level-Up-Testwerte (100 / 150 / 300 XP) unverändert gültig bleiben.
##
## Abdeckung:
##   - Spieler-State wird bei Bedarf angelegt (_ensure_player Fix 3)
##   - request_add_xp() / on_xp_add_confirmed() mutieren State korrekt
##   - get_xp() / get_level() lesen den mutierten State zurück
##   - Level-Up bei Erreichen der XP-Schwelle (Mock-Kurve: level * 100)
##   - XP-Verbrauch beim Level-Up (kein Überlauf)
##   - Zwei player_ids erhalten unabhängigen State (Multi-Tenanz, MIGRATION-010 Phase 1)
##   - Unbekannter Skill-Name → kein Crash, kein State-Leak
##   - get_skill_ids() gibt alle konfigurierten Skills zurück
##   - get_save_key() liefert "skills"
##   - get_save_data() liefert serialisierbaren Snapshot
##
## Teardown: kein SceneTree nötig, keine AutoLoads außer AppLogger/EventBus.

extends GutTest

# ─────────────────────────────────────────────────────────────────────────────
# Minimal-Mocks
# ─────────────────────────────────────────────────────────────────────────────

## XP-Kurve level * 100 (level 1→2: 100, 2→3: 200, 3→4: 300, ...) — reproduziert
## die frühere hardkodierte Fallback-Kurve, damit die bestehenden Level-Up-
## Testwerte unverändert gelten.
class MockSkillDef extends SkillDefinition:
	func _init(p_id: String) -> void:
		id = p_id

	func get_xp_required(level: int) -> int:
		return level * 100

class MockDataService extends DataService:
	func get_all_skills() -> Dictionary:
		return _skills

# ─────────────────────────────────────────────────────────────────────────────
# Test-Setup
# ─────────────────────────────────────────────────────────────────────────────

var _svc: SkillSystem
var _ds:  MockDataService
var _bus: MockEventBus

const WOOD    := "woodcutting"
const MINE    := "mining"
const FARM    := "farming"
const COMBAT  := "combat"
const P1      := "p1"
const P2      := "p2"

func before_each() -> void:
	_ds = MockDataService.new()
	_ds._skills[WOOD]   = MockSkillDef.new(WOOD)
	_ds._skills[MINE]   = MockSkillDef.new(MINE)
	_ds._skills[FARM]   = MockSkillDef.new(FARM)
	_ds._skills[COMBAT] = MockSkillDef.new(COMBAT)

	_bus = MockEventBus.new()
	var save := SaveSystem.new()
	save.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: _bus}))

	_svc = SkillSystem.new()
	_svc.configure(ServiceDeps.from_dict({
		ServiceKeys.DATA:        _ds,
		ServiceKeys.SAVE_SYSTEM: save,
		ServiceKeys.EVENT_BUS:   _bus,
	}))

func after_each() -> void:
	_svc.on_cleanup()
	_svc = null

# ─────────────────────────────────────────────
# Grundzustand
# ─────────────────────────────────────────────

func test_ensure_player_creates_all_configured_skills() -> void:
	# configure() legt keinen Bucket mehr automatisch an (siehe Klassenkommentar
	# oben) — _ensure_player() direkt aufgerufen, analog zum direkten
	# _svc._definitions-Zugriff in test_quest_service.gd.
	_svc._ensure_player(P1)
	var ids := _svc.get_skill_ids(P1)
	assert_true(ids.has(WOOD),   "'woodcutting' muss vorhanden sein.")
	assert_true(ids.has(MINE),   "'mining' muss vorhanden sein.")
	assert_true(ids.has(FARM),   "'farming' muss vorhanden sein.")
	assert_true(ids.has(COMBAT), "'combat' muss vorhanden sein.")

func test_initial_level_is_1() -> void:
	_svc._ensure_player(P1)
	assert_eq(_svc.get_level(WOOD, P1), 1, "Startlevel muss 1 sein.")

func test_initial_xp_is_0() -> void:
	_svc._ensure_player(P1)
	assert_eq(_svc.get_xp(WOOD, P1), 0, "Start-XP muss 0 sein.")

# ─────────────────────────────────────────────
# Fix 3 — _ensure_player-Regression
# ─────────────────────────────────────────────

func test_request_add_xp_does_not_crash() -> void:
	# Kerntest für Fix 3: skills war undeclared → jeder XP-Gain crashte
	_svc.request_add_xp(WOOD, 10, P1)
	assert_eq(_svc.get_xp(WOOD, P1), 10,
		"Nach request_add_xp(10) muss XP = 10 sein (Fix 3).")

func test_request_add_xp_accumulates() -> void:
	_svc.request_add_xp(WOOD, 30, P1)
	_svc.request_add_xp(WOOD, 20, P1)
	assert_eq(_svc.get_xp(WOOD, P1), 50, "XP muss akkumulieren.")

func test_add_xp_to_unknown_skill_is_silent() -> void:
	# Kein Crash, kein State-Leak bei unbekanntem Skill-Namen
	_svc.request_add_xp("nonexistent_skill", 999, P1)
	assert_false(_svc.has_skill("nonexistent_skill", P1), "Unbekannter Skill darf nicht angelegt werden.")

# ─────────────────────────────────────────────
# Level-Up-Logik (Mock-Kurve: xp_needed = level * 100)
# ─────────────────────────────────────────────

func test_no_level_up_before_threshold() -> void:
	_svc.request_add_xp(MINE, 99, P1)
	assert_eq(_svc.get_level(MINE, P1), 1, "99 XP < 100 → kein Level-Up.")
	assert_eq(_svc.get_xp(MINE, P1),   99, "XP muss erhalten bleiben.")

func test_level_up_at_exact_threshold() -> void:
	_svc.request_add_xp(MINE, 100, P1)
	assert_eq(_svc.get_level(MINE, P1), 2, "100 XP → Level 2.")
	assert_eq(_svc.get_xp(MINE, P1),    0, "XP wird beim Level-Up verbraucht.")

func test_level_up_with_overflow_xp() -> void:
	_svc.request_add_xp(MINE, 150, P1)
	assert_eq(_svc.get_level(MINE, P1), 2, "150 XP → Level 2.")
	assert_eq(_svc.get_xp(MINE, P1),   50, "Überschuss-XP 50 muss übertragen werden.")

func test_double_level_up_in_one_call() -> void:
	# Level 1→2 braucht 100 XP, Level 2→3 braucht 200 XP — insgesamt 300 XP
	_svc.request_add_xp(MINE, 300, P1)
	assert_eq(_svc.get_level(MINE, P1), 3, "300 XP → Level 3 (zwei Level-Ups).")
	assert_eq(_svc.get_xp(MINE, P1),    0, "Kein überschüssiges XP nach genau 300.")

# ─────────────────────────────────────────────
# Multi-Tenanz (MIGRATION-010 Phase 1)
# ─────────────────────────────────────────────

func test_two_player_ids_have_independent_state() -> void:
	_svc.request_add_xp(WOOD, 50, P1)
	_svc.request_add_xp(WOOD, 99, P2)

	assert_eq(_svc.get_xp(WOOD, P1), 50,
		"Spieler 1 darf Spieler-2-XP nicht sehen.")
	assert_eq(_svc.get_xp(WOOD, P2), 99,
		"Spieler 2 darf Spieler-1-XP nicht sehen.")

func test_level_up_for_player2_does_not_affect_player1() -> void:
	_svc.request_add_xp(COMBAT, 100, P2)

	assert_eq(_svc.get_level(COMBAT, P1), 1, "Level-Up für Spieler 2 darf Spieler 1 nicht verändern.")
	assert_eq(_svc.get_level(COMBAT, P2), 2, "Spieler 2 muss Level 2 haben.")

# ─────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────

func test_get_save_key_returns_skills() -> void:
	assert_eq(_svc.get_save_key(), "skills", "SAVE_KEY muss 'skills' sein.")

func test_get_save_data_contains_player() -> void:
	# Kein automatischer Bucket mehr (siehe Klassenkommentar) — request_add_xp()
	# legt P1 als Nebeneffekt an.
	_svc.request_add_xp(WOOD, 1, P1)
	var data := _svc.get_save_data()
	assert_true(data.has(P1), "get_save_data() muss Spieler '%s' enthalten." % P1)

func test_get_save_data_reflects_xp_changes() -> void:
	_svc.request_add_xp(FARM, 42, P1)
	var data := _svc.get_save_data()
	var p1: Dictionary = data.get(P1, {}) as Dictionary
	var farming: Dictionary = p1.get(FARM, {}) as Dictionary
	assert_eq(farming.get("xp", -1), 42, "get_save_data() muss aktuellen XP-Stand serialisieren.")

# ─────────────────────────────────────────────────────────────────────────────
# inject_network_bridge() / get_xp_to_next_level() (Round 113 Nachtrag, siehe
# method_reference_coverage.py-Fund)
# ─────────────────────────────────────────────────────────────────────────────

func test_inject_network_bridge_sets_the_reference() -> void:
	var bridge: NetworkBridge = add_child_autofree(NetworkBridge.new())
	_svc.inject_network_bridge(bridge)
	assert_same(_svc._network, bridge)

func test_inject_network_bridge_connects_economy_state_received() -> void:
	var bridge: NetworkBridge = add_child_autofree(NetworkBridge.new())
	assert_eq(bridge.economy_state_received.get_connections().size(), 0)
	_svc.inject_network_bridge(bridge)
	assert_eq(bridge.economy_state_received.get_connections().size(), 1)

func test_get_xp_to_next_level_unknown_skill_returns_default_100() -> void:
	assert_eq(_svc.get_xp_to_next_level("nonexistent_skill", P1), 100)

func test_get_xp_to_next_level_reflects_current_level_requirement() -> void:
	var before := _svc.get_xp_to_next_level(WOOD, P1)
	_svc.request_add_xp(WOOD, 100, P1)
	var after := _svc.get_xp_to_next_level(WOOD, P1)
	assert_ne(before, after, "Nach einem Level-Up muss sich die benötigte XP-Schwelle ändern")

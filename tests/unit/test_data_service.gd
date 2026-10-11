# res://tests/unit/test_data_service.gd
extends GutTest

## Unit-Tests für DataService (scripts/persistence/DataService.gd) — bisher
## ungetestet (siehe architecture_overview.py-Fund, Round 113), obwohl
## DataService.new() bereits in mehreren anderen Testdateien als echte
## (nicht gemockte) Dependency verwendet wird (test_achievement_service.gd,
## test_bank_service.gd, u.a.) — DataService lädt bewusst die echten
## Projekt-.tres-Dateien über DataManifest, kein Mock nötig/möglich (siehe
## Klassenkommentar: "einziger Ladeort für alle statischen .tres-Ressourcen").
##
## Bewusst KEINE hartcodierten Item-/Quest-/Achievement-IDs als Erwartungswert
## (außer wo DataManifest sie namentlich fest verdrahtet, z.B. LootTable-IDs
## aus dem Dateinamen) — Tests bleiben robust gegen künftig hinzugefügte/
## entfernte Daten, indem sie Invarianten prüfen (Konsistenz zwischen
## get_all_X()/get_X()) statt exakte Inhalte.
##
## Abgedeckt:
##   configure() — lädt player_data, Items, Quests, CombatProfiles, LootTables
##   get_player_stat() — bekannter Stat exakt, unbekannter Stat = Default statt Crash
##   get_item()/get_all_items() — Konsistenz, unbekannte ID = null
##   get_quest()/get_all_quests()/get_auto_start_quests() — Konsistenz, auto_start-Filter korrekt
##   get_combat_profile() — unbekannte ID liefert NIEMALS null, sondern Default-Profil
##   get_achievement()/get_all_achievements() — Konsistenz, unbekannte ID = null
##   get_loot_table()/get_all_loot_tables() — Konsistenz, ID aus Dateinamen abgeleitet

var _svc: DataService

func before_each() -> void:
	_svc = DataService.new()
	_svc.configure(ServiceDeps.from_dict({}))

# ─────────────────────────────────────────────
# configure() — PlayerData
# ─────────────────────────────────────────────

func test_configure_loads_player_data() -> void:
	assert_not_null(_svc.player_data, "configure() muss res://config/PlayerData.tres laden")

func test_get_player_stat_returns_real_value() -> void:
	assert_eq(_svc.get_player_stat("speed"), _svc.player_data.speed)

func test_get_player_stat_unknown_stat_returns_default_without_crash() -> void:
	assert_eq(_svc.get_player_stat("does_not_exist_xyz", 42.0), 42.0)

func test_get_player_stat_unknown_stat_default_value_is_zero_by_default() -> void:
	assert_eq(_svc.get_player_stat("does_not_exist_xyz"), 0.0)

# ─────────────────────────────────────────────
# Items
# ─────────────────────────────────────────────

func test_configure_loads_at_least_one_item() -> void:
	assert_false(_svc.get_all_items().is_empty(), "DataManifest.ITEMS ist nicht leer, configure() muss sie laden")

func test_get_item_matches_get_all_items_entry() -> void:
	var all_items := _svc.get_all_items()
	var any_id: String = all_items.keys()[0]
	assert_eq(_svc.get_item(any_id), all_items[any_id])

func test_get_item_unknown_id_returns_null() -> void:
	assert_null(_svc.get_item("does_not_exist_xyz"))

# ─────────────────────────────────────────────
# Quests
# ─────────────────────────────────────────────

func test_configure_loads_at_least_one_quest() -> void:
	assert_false(_svc.get_all_quests().is_empty(), "DataManifest.QUESTS ist nicht leer, configure() muss sie laden")

func test_get_quest_matches_get_all_quests_entry() -> void:
	var all_quests := _svc.get_all_quests()
	var any_id: String = all_quests.keys()[0]
	assert_eq(_svc.get_quest(any_id), all_quests[any_id])

func test_get_quest_unknown_id_returns_null() -> void:
	assert_null(_svc.get_quest("does_not_exist_xyz"))

func test_auto_start_quests_only_contains_flagged_quests() -> void:
	var all_quests := _svc.get_all_quests()
	for id in _svc.get_auto_start_quests():
		var q: QuestDefinition = all_quests[id]
		assert_true(q.auto_start, "get_auto_start_quests() darf nur auto_start=true-Quests liefern (id=%s)" % id)

# ─────────────────────────────────────────────
# CombatProfiles (TD-10) — get_combat_profile() darf NIE null zurückgeben
# ─────────────────────────────────────────────

func test_get_combat_profile_unknown_id_returns_default_not_null() -> void:
	var profile := _svc.get_combat_profile("does_not_exist_xyz")
	assert_not_null(profile, "get_combat_profile() darf laut Klassenkommentar NIEMALS null zurückgeben")
	assert_true(profile is CombatProfile)

# ─────────────────────────────────────────────
# Achievements (Round 103, ADR-046)
# ─────────────────────────────────────────────

func test_get_achievement_unknown_id_returns_null() -> void:
	assert_null(_svc.get_achievement("does_not_exist_xyz"))

func test_get_achievement_matches_get_all_achievements_entry() -> void:
	var all_achievements := _svc.get_all_achievements()
	if all_achievements.is_empty():
		pass_test("Keine Achievements in DataManifest — Konsistenz-Check entfällt")
		return
	var any_id: String = all_achievements.keys()[0]
	assert_eq(_svc.get_achievement(any_id), all_achievements[any_id])

# ─────────────────────────────────────────────
# LootTables (Round 108, ADR-049)
# ─────────────────────────────────────────────

func test_configure_loads_loot_tables_from_manifest() -> void:
	assert_eq(_svc.get_all_loot_tables().size(), DataManifest.LOOT_TABLES.size())

func test_get_loot_table_id_derived_from_filename() -> void:
	# DataManifest listet u.a. "res://data/loot_tables/goblin_loot.tres" —
	# _load_loot_tables() leitet die ID aus dem Dateinamen ab (ohne .tres).
	assert_not_null(_svc.get_loot_table("goblin_loot"))

func test_get_loot_table_unknown_id_returns_null() -> void:
	assert_null(_svc.get_loot_table("does_not_exist_xyz"))

# res://tests/unit/test_permission_service.gd
extends GutTest

## Tests für PermissionService (ADR-031 — Rollenbasiertes Permission-System).
##
## WICHTIG: _path_override zeigt auf eine Test-Datei, NIEMALS auf die echte
## user://roles.json — sonst überschreiben Testläufe echte Rollen-Zuweisungen
## (analog test_settings_service.gd).
##
## Abgedeckte Pfade:
##   configure()          — lädt die drei Basis-Rollen, keine Zuweisungen ohne Datei
##   get_role_id()         — Default "player" ohne Zuweisung
##   has_capability()      — pro Rolle korrekt, unbekannte player_id = Default-Rolle
##   assign_role()          — persistiert sofort, lehnt unbekannte role_id ab
##   revoke_role()          — fällt zurück auf Default
##   ensure_default_role()  — idempotent, überschreibt nie eine bestehende Zuweisung
##   Persistenz-Roundtrip   — Zuweisung überlebt eine neue Service-Instanz
##   Fehlertoleranz          — korrupte Datei, unbekannte Rolle in Datei

const TEST_PATH := "user://unit_test_roles.json"

var _svc: PermissionService

func before_each() -> void:
	_delete_test_file()
	_svc = PermissionService.new()
	_svc.set_path_override(TEST_PATH)
	_svc.configure(ServiceDeps.from_dict({}))

func after_each() -> void:
	_delete_test_file()
	_svc = null

func _delete_test_file() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)
	if FileAccess.file_exists(TEST_PATH + ".tmp"):
		DirAccess.remove_absolute(TEST_PATH + ".tmp")

func _new_service_same_file() -> PermissionService:
	var s := PermissionService.new()
	s.set_path_override(TEST_PATH)
	s.configure(ServiceDeps.from_dict({}))
	return s

# ─────────────────────────────────────────────
# configure() — Rollen laden
# ─────────────────────────────────────────────

func test_configure_loads_all_three_base_roles() -> void:
	for role_id in ["player", "moderator", "admin"]:
		assert_true(_svc.is_known_role(role_id), "Basis-Rolle '%s' muss geladen sein" % role_id)

func test_configure_does_not_create_file_by_itself() -> void:
	assert_false(FileAccess.file_exists(TEST_PATH), "configure() darf keine Datei anlegen")

func test_unassigned_player_gets_default_role() -> void:
	assert_eq(_svc.get_role_id("some-uuid"), "player")

# ─────────────────────────────────────────────
# has_capability() / get_capabilities()
# ─────────────────────────────────────────────

func test_player_role_has_no_special_capabilities() -> void:
	assert_false(_svc.has_capability("uuid-1", &"kick_player"))
	assert_false(_svc.has_capability("uuid-1", &"full_access"))
	assert_eq(_svc.get_capabilities("uuid-1"), [])

func test_moderator_has_moderation_capabilities_but_not_admin_ones() -> void:
	_svc.assign_role("uuid-mod", "moderator")
	for cap in [&"kick_player", &"mute_player", &"teleport_self", &"teleport_player", &"spectate_player", &"view_reports"]:
		assert_true(_svc.has_capability("uuid-mod", cap), "moderator muss '%s' haben" % cap)
	assert_false(_svc.has_capability("uuid-mod", &"pvp_immune"))
	assert_false(_svc.has_capability("uuid-mod", &"full_access"))

func test_admin_has_all_moderator_capabilities_plus_admin_ones() -> void:
	_svc.assign_role("uuid-admin", "admin")
	for cap in [&"kick_player", &"mute_player", &"teleport_self", &"teleport_player", &"spectate_player", &"view_reports", &"pvp_immune", &"full_access"]:
		assert_true(_svc.has_capability("uuid-admin", cap), "admin muss '%s' haben" % cap)

func test_is_admin_convenience_matches_full_access_capability() -> void:
	_svc.assign_role("uuid-admin", "admin")
	assert_true(_svc.is_admin("uuid-admin"))
	assert_false(_svc.is_admin("uuid-mod-or-player"))

func test_has_capability_is_false_for_unknown_capability_string() -> void:
	_svc.assign_role("uuid-admin", "admin")
	assert_false(_svc.has_capability("uuid-admin", &"does_not_exist_as_a_capability"))

# ─────────────────────────────────────────────
# assign_role()
# ─────────────────────────────────────────────

func test_assign_role_updates_role_id() -> void:
	_svc.assign_role("uuid-1", "moderator")
	assert_eq(_svc.get_role_id("uuid-1"), "moderator")

func test_assign_role_rejects_unknown_role_id() -> void:
	var ok := _svc.assign_role("uuid-1", "super_admin_typo")
	assert_false(ok, "Unbekannte role_id darf nicht akzeptiert werden")
	assert_eq(_svc.get_role_id("uuid-1"), "player", "Zuweisung darf bei Ablehnung nicht greifen")

func test_assign_role_rejects_empty_player_id() -> void:
	var ok := _svc.assign_role("", "admin")
	assert_false(ok)

func test_assign_role_persists_immediately() -> void:
	_svc.assign_role("uuid-1", "admin")
	assert_true(FileAccess.file_exists(TEST_PATH), "assign_role() muss sofort persistieren")

func test_assign_role_leaves_no_tmp_file_behind() -> void:
	_svc.assign_role("uuid-1", "admin")
	assert_false(FileAccess.file_exists(TEST_PATH + ".tmp"))

# ─────────────────────────────────────────────
# revoke_role()
# ─────────────────────────────────────────────

func test_revoke_role_falls_back_to_default() -> void:
	_svc.assign_role("uuid-1", "admin")
	_svc.revoke_role("uuid-1")
	assert_eq(_svc.get_role_id("uuid-1"), "player")

func test_revoke_role_on_unassigned_player_is_a_safe_noop() -> void:
	assert_true(_svc.revoke_role("never-assigned"), "revoke_role() ohne bestehende Zuweisung darf nicht scheitern")

# ─────────────────────────────────────────────
# ensure_default_role() — idempotente Erstzuweisung (ADR-031 Tier-Rollout)
# ─────────────────────────────────────────────

func test_ensure_default_role_assigns_on_first_call() -> void:
	var assigned := _svc.ensure_default_role("uuid-1", "admin")
	assert_true(assigned)
	assert_eq(_svc.get_role_id("uuid-1"), "admin")

func test_ensure_default_role_never_overwrites_existing_assignment() -> void:
	_svc.assign_role("uuid-1", "moderator")
	var assigned := _svc.ensure_default_role("uuid-1", "admin")
	assert_false(assigned, "ensure_default_role() darf eine bestehende Zuweisung nicht überschreiben")
	assert_eq(_svc.get_role_id("uuid-1"), "moderator", "Moderator-Beförderung darf nicht durch Tier-Default verloren gehen")

func test_ensure_default_role_is_idempotent_across_repeated_calls() -> void:
	_svc.ensure_default_role("uuid-1", "admin")
	_svc.ensure_default_role("uuid-1", "player")
	assert_eq(_svc.get_role_id("uuid-1"), "admin", "zweiter Aufruf darf den ersten Default nicht überschreiben")

# ─────────────────────────────────────────────
# Persistenz-Roundtrip
# ─────────────────────────────────────────────

func test_roundtrip_assignment_survives_reload() -> void:
	_svc.assign_role("uuid-1", "admin")
	var reloaded := _new_service_same_file()
	assert_eq(reloaded.get_role_id("uuid-1"), "admin", "Zuweisung muss Neustart überleben")

func test_roundtrip_multiple_assignments_keep_previous_entries() -> void:
	_svc.assign_role("uuid-1", "admin")
	_svc.assign_role("uuid-2", "moderator")
	var reloaded := _new_service_same_file()
	assert_eq(reloaded.get_role_id("uuid-1"), "admin", "erste Zuweisung darf beim zweiten Write nicht verloren gehen")
	assert_eq(reloaded.get_role_id("uuid-2"), "moderator")

# ─────────────────────────────────────────────
# Fehlertoleranz
# ─────────────────────────────────────────────

func test_configure_with_corrupt_file_falls_back_to_no_assignments() -> void:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("{ das ist kein gueltiges JSON")
	file.close()

	var recovered := PermissionService.new()
	recovered.set_path_override(TEST_PATH)
	recovered.configure(ServiceDeps.from_dict({}))

	assert_eq(
		recovered.get_role_id("uuid-1"), "player",
		"Korrupte Datei darf configure() nicht crashen — Fallback auf Default-Rolle"
	)

func test_configure_ignores_assignment_to_unknown_role_in_file() -> void:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"uuid-1": "totally_unknown_role", "uuid-2": "admin"}))
	file.close()

	var reloaded := _new_service_same_file()
	assert_eq(reloaded.get_role_id("uuid-1"), "player", "Zuweisung auf unbekannte Rolle wird verworfen")
	assert_eq(reloaded.get_role_id("uuid-2"), "admin", "gültige Zuweisung bleibt erhalten")

# ─────────────────────────────────────────────
# list_role_ids() / is_known_role()
# ─────────────────────────────────────────────

func test_list_role_ids_contains_all_three_base_roles() -> void:
	var ids := _svc.list_role_ids()
	for role_id in ["player", "moderator", "admin"]:
		assert_true(role_id in ids)

func test_is_known_role_false_for_made_up_role() -> void:
	assert_false(_svc.is_known_role("super_admin_typo"))

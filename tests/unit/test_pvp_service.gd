# res://tests/unit/test_pvp_service.gd
extends GutTest

## Unit-Tests für PvPService (ADR-032 — PvP-Angreifbarkeit + Skull-System).
##
## Strategie: PvPService extends Service (RefCounted) — kein add_child nötig
## für den Service selbst (analog test_zone_service.gd/test_currency_service.gd).
## required_deps (permission_service, zone_service) werden als echte Instanzen
## konfiguriert statt gemockt — für beide existiert kein Mock in tests/mocks/,
## und beide sind selbst simpel genug (kein Netzwerk/Dateisystem im kritischen
## Pfad) um direkt zu instanziieren. optional_deps (network_bridge, savesystem,
## ticker) nur dort konfiguriert, wo der jeweilige Test sie braucht.
##
## _path_override bei PermissionService zeigt auf eine Test-Datei, NIEMALS auf
## die echte user://roles.json (analog test_permission_service.gd).
##
## Abgedeckt:
##   - is_pvp_active(): alle drei ADR-032-Bedingungen (global-Schalter,
##     pvp_immune-Capability, Zonen-Tag), plus unbekannter Peer
##   - report_pvp_damage(): Skull-Trigger, Selbst-Hit/leere IDs als No-Op,
##     Gegenwehr-Fenster (kein erneuter Trigger sobald beide Richtungen
##     getroffen haben — auch der ursprüngliche Angreifer nicht mehr)
##   - set_voluntary_skull(): setzen/aufheben
##   - report_safe_zone_entered() / is_vulnerable_in_safe_zone(): No-Op wenn
##     nicht geskullt, Grace-Fenster wenn geskullt
##   - set_global_pvp_enabled()/is_global_pvp_enabled()
##   - Save-Interface: get_save_key(), get_save_data() (abgelaufene Skulls
##     ausgeschlossen), Round-Trip über _restore_from_save()
##   - _on_zone_entered()-Verdrahtung über EventBus (Safe-Zone-Integration)
##
## NICHT abgedeckt (bewusst): tatsächlicher Ablauf der 20-Minuten-Skull-Dauer
## in Echtzeit — nicht sinnvoll ohne Zeit-Mocking, das dieses Repo für
## PvPService nicht bereitstellt. Stattdessen wird die Größenordnung über
## get_skull_remaining_seconds() mit Tolerenz geprüft.

const P_ATTACKER := "attacker-uuid"
const P_VICTIM := "victim-uuid"
const TEST_ROLES_PATH := "user://unit_test_pvp_roles.json"

var _svc: PvPService
var _bus: MockEventBus
var _perms: PermissionService
var _zones: ZoneService
var _session: SessionManager
var _bridge: NetworkBridge


class StubSaveSystem extends SaveSystem:
	## Analog MockSaveSystemForBacksync in test_currency_service.gd — echte
	## SaveSystem-API-Form ohne Festplattenzugriff, damit PvPService.configure()
	## den register_save_provider()/get_state_for()-Pfad nimmt (statt den
	## "Abhängigkeit fehlt"-Log-Zweig), ohne dass ein Test je etwas restored.
	func register_save_provider(_p: Object) -> void:
		pass
	func get_state_for(_key: String) -> Dictionary:
		return {}


func before_each() -> void:
	_delete_test_roles_file()
	_bus = MockEventBus.new()

	_perms = PermissionService.new()
	_perms.set_path_override(TEST_ROLES_PATH)
	_perms.configure(ServiceDeps.from_dict({}))

	_zones = ZoneService.new()
	_zones.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: _bus}))
	_zones.on_ready()

	_session = SessionManager.new()
	add_child_autofree(_session)

	_bridge = NetworkBridge.new()
	_bridge.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS: _bus,
		ServiceKeys.SESSION_MANAGER: _session,
	}))
	add_child_autofree(_bridge)

	_svc = PvPService.new()
	_svc.configure(ServiceDeps.from_dict({
		ServiceKeys.PERMISSION_SERVICE: _perms,
		ServiceKeys.ZONE_SERVICE: _zones,
		ServiceKeys.NETWORK_BRIDGE: _bridge,
		ServiceKeys.SAVE_SYSTEM: StubSaveSystem.new(),
		ServiceKeys.EVENT_BUS: _bus,
	}))
	_svc.on_ready()


func after_each() -> void:
	_svc.on_cleanup()
	_zones.on_cleanup()
	_svc = null
	_bus = null
	_perms = null
	_zones = null
	_session = null
	_bridge = null
	_delete_test_roles_file()


func _delete_test_roles_file() -> void:
	if FileAccess.file_exists(TEST_ROLES_PATH):
		DirAccess.remove_absolute(TEST_ROLES_PATH)
	if FileAccess.file_exists(TEST_ROLES_PATH + ".tmp"):
		DirAccess.remove_absolute(TEST_ROLES_PATH + ".tmp")


## Registriert player_id<->peer_id (SessionManager) und steckt den Peer in
## eine Zone mit den gegebenen Tags (ZoneService) — die zwei Zutaten, die
## is_pvp_active() über _peer_for()/_zones.has_tag() braucht.
func _place_player(player_id: String, peer_id: int, zone_id: StringName, tags: Array[StringName]) -> void:
	_session.register_player_slot(peer_id, player_id)
	var config := ZoneConfig.new()
	config.zone_id = zone_id
	config.tags = tags
	_zones.register_zone_config(config)
	_zones.report_enter(peer_id, zone_id)


# ─────────────────────────────────────────────
# is_pvp_active() — ADR-032, alle drei Bedingungen
# ─────────────────────────────────────────────

func test_is_pvp_active_true_in_pvp_zone() -> void:
	_place_player(P_ATTACKER, 1, &"desert_pvp", [&"pvp"])
	assert_true(_svc.is_pvp_active(P_ATTACKER))

func test_is_pvp_active_false_when_global_pvp_disabled() -> void:
	_place_player(P_ATTACKER, 1, &"desert_pvp", [&"pvp"])
	_svc.set_global_pvp_enabled(false)
	assert_false(_svc.is_pvp_active(P_ATTACKER))

func test_is_pvp_active_false_when_immune_capability() -> void:
	_place_player(P_ATTACKER, 1, &"desert_pvp", [&"pvp"])
	_perms.assign_role(P_ATTACKER, "admin")  # "admin"-Rolle hat pvp_immune (data/roles/admin.tres)
	assert_false(_svc.is_pvp_active(P_ATTACKER))

func test_is_pvp_active_false_outside_pvp_zone() -> void:
	_place_player(P_ATTACKER, 1, &"spawn", [&"safe"])
	assert_false(_svc.is_pvp_active(P_ATTACKER))

func test_is_pvp_active_false_for_unknown_player() -> void:
	# Nie via _place_player() registriert -> kein Peer -> _peer_for() == -1.
	assert_false(_svc.is_pvp_active("ghost-uuid"))


# ─────────────────────────────────────────────
# report_pvp_damage() — Skull-Trigger + Gegenwehr-Fenster
# ─────────────────────────────────────────────

func test_report_pvp_damage_skulls_attacker_only() -> void:
	_svc.report_pvp_damage(P_ATTACKER, P_VICTIM)
	assert_true(_svc.is_skulled(P_ATTACKER), "Angreifer muss nach erstem Treffer geskullt sein.")
	assert_false(_svc.is_skulled(P_VICTIM), "Opfer darf durch reines Erleiden von Schaden nicht geskullt werden.")

func test_report_pvp_damage_skull_is_not_voluntary() -> void:
	_svc.report_pvp_damage(P_ATTACKER, P_VICTIM)
	assert_false(_svc.is_skull_voluntary(P_ATTACKER))

func test_report_pvp_damage_self_hit_is_noop() -> void:
	_svc.report_pvp_damage(P_ATTACKER, P_ATTACKER)
	assert_false(_svc.is_skulled(P_ATTACKER), "Ein Spieler kann sich nicht selbst skullen.")

func test_report_pvp_damage_empty_attacker_id_is_noop() -> void:
	_svc.report_pvp_damage("", P_VICTIM)
	assert_false(_svc.is_skulled(P_VICTIM))

func test_report_pvp_damage_empty_victim_id_is_noop() -> void:
	_svc.report_pvp_damage(P_ATTACKER, "")
	assert_false(_svc.is_skulled(P_ATTACKER))

func test_report_pvp_damage_emits_skulled_signal() -> void:
	var received: Array = []
	_svc.skulled.connect(func(pid: String, voluntary: bool) -> void:
		received.append([pid, voluntary])
	)
	_svc.report_pvp_damage(P_ATTACKER, P_VICTIM)
	assert_eq(received.size(), 1)
	assert_eq(received[0], [P_ATTACKER, false])

func test_report_pvp_damage_return_hit_does_not_skull_victim() -> void:
	# A trifft B (A geskullt) -> B trifft zurück: das ist der Moment, in dem
	# beide Richtungen erstmals getroffen haben, also öffnet SICH DIESER
	# Treffer bereits das Gegenwehr-Fenster -> B wird dadurch NICHT geskullt.
	_svc.report_pvp_damage(P_ATTACKER, P_VICTIM)
	_svc.report_pvp_damage(P_VICTIM, P_ATTACKER)
	assert_false(_svc.is_skulled(P_VICTIM), "Der Gegenwehr-Treffer selbst darf keinen neuen Skull auslösen.")
	assert_true(_svc.is_skulled(P_ATTACKER), "Ursprünglicher Skull des Angreifers bleibt bestehen.")

func test_report_pvp_damage_further_hits_after_window_open_trigger_no_new_skull_signal() -> void:
	_svc.report_pvp_damage(P_ATTACKER, P_VICTIM)  # 1: A->B, Fenster noch zu, A geskullt
	_svc.report_pvp_damage(P_VICTIM, P_ATTACKER)  # 2: B->A, Fenster öffnet sich, kein neuer Skull
	var received: Array = []
	_svc.skulled.connect(func(pid: String, voluntary: bool) -> void:
		received.append([pid, voluntary])
	)
	_svc.report_pvp_damage(P_ATTACKER, P_VICTIM)  # 3: Fenster bereits offen -> kein Trigger mehr
	assert_eq(received.size(), 0, "Nach geöffnetem Gegenwehr-Fenster darf kein weiterer Skull-Trigger mehr feuern.")

func test_report_pvp_damage_repeated_hits_before_retaliation_reskull_each_time() -> void:
	# "jeder weitere Treffer setzt den Skull-Timer des Angreifers neu" —
	# solange B sich noch nicht gewehrt hat, feuert JEDER weitere Treffer
	# von A erneut den Trigger (beobachtbar über das Signal, da die reale
	# 20-Minuten-Differenz ohne Zeit-Mocking nicht separat messbar ist).
	var fire_count := 0
	_svc.skulled.connect(func(_pid, _voluntary): fire_count += 1)
	_svc.report_pvp_damage(P_ATTACKER, P_VICTIM)
	_svc.report_pvp_damage(P_ATTACKER, P_VICTIM)
	_svc.report_pvp_damage(P_ATTACKER, P_VICTIM)
	assert_eq(fire_count, 3, "Ohne Gegenwehr muss jeder Treffer erneut triggern.")


# ─────────────────────────────────────────────
# is_skulled() / get_skull_remaining_seconds()
# ─────────────────────────────────────────────

func test_default_not_skulled() -> void:
	assert_false(_svc.is_skulled(P_ATTACKER))
	assert_eq(_svc.get_skull_remaining_seconds(P_ATTACKER), 0.0)

func test_skull_remaining_seconds_close_to_full_duration_right_after_trigger() -> void:
	_svc.report_pvp_damage(P_ATTACKER, P_VICTIM)
	# 20 Minuten = 1200s; unmittelbar danach muss der Rest sehr nah an 1200s sein.
	assert_almost_eq(_svc.get_skull_remaining_seconds(P_ATTACKER), PvPService.SKULL_DURATION_SEC, 2.0)


# ─────────────────────────────────────────────
# set_voluntary_skull()
# ─────────────────────────────────────────────

func test_set_voluntary_skull_true_marks_skulled_and_voluntary() -> void:
	_svc.set_voluntary_skull(P_ATTACKER, true)
	assert_true(_svc.is_skulled(P_ATTACKER))
	assert_true(_svc.is_skull_voluntary(P_ATTACKER))

func test_set_voluntary_skull_false_removes_flag_entirely() -> void:
	_svc.set_voluntary_skull(P_ATTACKER, true)
	_svc.set_voluntary_skull(P_ATTACKER, false)
	assert_false(_svc.is_skulled(P_ATTACKER))
	assert_false(_svc.is_skull_voluntary(P_ATTACKER))

func test_set_voluntary_skull_empty_id_is_noop() -> void:
	_svc.set_voluntary_skull("", true)
	assert_false(_svc.is_skulled(""))

func test_set_voluntary_skull_emits_skulled_signal_with_voluntary_true() -> void:
	var received: Array = []
	_svc.skulled.connect(func(pid: String, voluntary: bool) -> void:
		received.append([pid, voluntary])
	)
	_svc.set_voluntary_skull(P_ATTACKER, true)
	assert_eq(received.size(), 1)
	assert_eq(received[0], [P_ATTACKER, true])


# ─────────────────────────────────────────────
# report_safe_zone_entered() / is_vulnerable_in_safe_zone()
# ─────────────────────────────────────────────

func test_report_safe_zone_entered_noop_when_not_skulled() -> void:
	_svc.report_safe_zone_entered(P_ATTACKER)
	assert_false(_svc.is_vulnerable_in_safe_zone(P_ATTACKER))

func test_report_safe_zone_entered_sets_grace_window_when_skulled() -> void:
	_svc.report_pvp_damage(P_ATTACKER, P_VICTIM)
	_svc.report_safe_zone_entered(P_ATTACKER)
	assert_true(_svc.is_vulnerable_in_safe_zone(P_ATTACKER))

func test_default_not_vulnerable_in_safe_zone() -> void:
	assert_false(_svc.is_vulnerable_in_safe_zone(P_ATTACKER))

# ─────────────────────────────────────────────
# ADR-036: Aura-Teil des Safe-Zone-Vulnerabilitäts-Fensters
# ─────────────────────────────────────────────

func test_report_safe_zone_entered_triggers_grace_window_on_low_aura_even_without_skull() -> void:
	# Kernaussage ADR-036: "is_skulled ODER Aura unterhalb der Schwelle" —
	# hier explizit OHNE Skull, nur über niedrige Aura.
	var aura := AuraService.new()
	aura.configure(ServiceDeps.from_dict({}))
	aura._aura[P_ATTACKER] = AuraService.AURA_VULNERABILITY_THRESHOLD - 1

	var svc2 := PvPService.new()
	svc2.configure(ServiceDeps.from_dict({
		ServiceKeys.PERMISSION_SERVICE: _perms,
		ServiceKeys.ZONE_SERVICE: _zones,
		ServiceKeys.AURA: aura,
		ServiceKeys.SAVE_SYSTEM: StubSaveSystem.new(),
	}))

	assert_false(svc2.is_skulled(P_ATTACKER), "Sanity: Spieler ist nicht geskullt")
	svc2.report_safe_zone_entered(P_ATTACKER)
	assert_true(svc2.is_vulnerable_in_safe_zone(P_ATTACKER))
	svc2.on_cleanup()

func test_report_safe_zone_entered_noop_when_aura_above_threshold_and_not_skulled() -> void:
	var aura := AuraService.new()
	aura.configure(ServiceDeps.from_dict({}))
	aura._aura[P_ATTACKER] = AuraService.AURA_VULNERABILITY_THRESHOLD + 1

	var svc2 := PvPService.new()
	svc2.configure(ServiceDeps.from_dict({
		ServiceKeys.PERMISSION_SERVICE: _perms,
		ServiceKeys.ZONE_SERVICE: _zones,
		ServiceKeys.AURA: aura,
		ServiceKeys.SAVE_SYSTEM: StubSaveSystem.new(),
	}))

	svc2.report_safe_zone_entered(P_ATTACKER)
	assert_false(svc2.is_vulnerable_in_safe_zone(P_ATTACKER))
	svc2.on_cleanup()


# ─────────────────────────────────────────────
# _on_zone_entered() — Safe-Zone-Integration über den EventBus (on_ready())
# ─────────────────────────────────────────────

func test_zone_entered_event_triggers_safe_zone_grace_when_skulled() -> void:
	_svc.report_pvp_damage(P_ATTACKER, P_VICTIM)
	_place_player(P_ATTACKER, 5, &"town_safe", [&"safe"])
	_bus.zones().emit_zone_entered(5, &"town_safe")
	assert_true(_svc.is_vulnerable_in_safe_zone(P_ATTACKER))

func test_zone_entered_event_for_non_safe_zone_is_noop() -> void:
	_svc.report_pvp_damage(P_ATTACKER, P_VICTIM)
	_place_player(P_ATTACKER, 5, &"desert_pvp", [&"pvp"])
	_bus.zones().emit_zone_entered(5, &"desert_pvp")
	assert_false(_svc.is_vulnerable_in_safe_zone(P_ATTACKER))


# ─────────────────────────────────────────────
# set_global_pvp_enabled() / is_global_pvp_enabled()
# ─────────────────────────────────────────────

func test_global_pvp_enabled_by_default() -> void:
	assert_true(_svc.is_global_pvp_enabled(), "Default an (siehe Klassenkommentar: bereits eine PvP-Zone in der Welt).")

func test_set_global_pvp_enabled_toggle() -> void:
	_svc.set_global_pvp_enabled(false)
	assert_false(_svc.is_global_pvp_enabled())
	_svc.set_global_pvp_enabled(true)
	assert_true(_svc.is_global_pvp_enabled())


# ─────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────

func test_save_key_is_pvp_flags() -> void:
	assert_eq(_svc.get_save_key(), "pvp_flags")

func test_save_data_empty_when_never_skulled() -> void:
	var sd := _svc.get_save_data()
	assert_true(sd.is_empty())

func test_save_data_includes_active_skull() -> void:
	_svc.report_pvp_damage(P_ATTACKER, P_VICTIM)
	var sd := _svc.get_save_data()
	assert_true(sd.has(P_ATTACKER))

func test_save_data_excludes_expired_skull() -> void:
	# Direktzugriff auf _flags (GDScript kennt keine echte Privatheit; gleiches
	# Muster wie _restore_from_save()-Direktaufrufe in test_currency_service.gd) —
	# einzige Möglichkeit, "abgelaufen" zu testen, ohne 20 Minuten Echtzeit
	# verstreichen zu lassen.
	_svc._flags[P_ATTACKER] = {
		"skull_until": Time.get_unix_time_from_system() - 10.0,  # in der Vergangenheit
		"skull_is_voluntary": false,
		"safe_zone_grace_until": 0.0,
	}
	var sd := _svc.get_save_data()
	assert_false(sd.has(P_ATTACKER), "Abgelaufene Skulls dürfen nicht mit gespeichert werden.")

func test_save_round_trip_restores_skull() -> void:
	_svc.report_pvp_damage(P_ATTACKER, P_VICTIM)
	var snapshot := _svc.get_save_data()

	var svc2 := PvPService.new()
	svc2.configure(ServiceDeps.from_dict({
		ServiceKeys.PERMISSION_SERVICE: _perms,
		ServiceKeys.ZONE_SERVICE: _zones,
		ServiceKeys.SAVE_SYSTEM: StubSaveSystem.new(),
	}))
	svc2._restore_from_save(snapshot)

	assert_true(svc2.is_skulled(P_ATTACKER))
	svc2.on_cleanup()

func test_save_round_trip_empty_save_produces_no_skulls() -> void:
	var svc2 := PvPService.new()
	svc2.configure(ServiceDeps.from_dict({
		ServiceKeys.PERMISSION_SERVICE: _perms,
		ServiceKeys.ZONE_SERVICE: _zones,
		ServiceKeys.SAVE_SYSTEM: StubSaveSystem.new(),
	}))
	svc2._restore_from_save({})

	assert_false(svc2.is_skulled(P_ATTACKER))
	svc2.on_cleanup()

# ─────────────────────────────────────────────
# inject_network_bridge() — Round 113 Nachtrag
# ─────────────────────────────────────────────

func test_inject_network_bridge_sets_the_reference() -> void:
	var bridge: NetworkBridge = add_child_autofree(NetworkBridge.new())
	_svc.inject_network_bridge(bridge)
	assert_same(_svc._network, bridge)

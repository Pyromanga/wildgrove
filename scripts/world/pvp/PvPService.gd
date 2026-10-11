extends Service
class_name PvPService

## PvPService — ADR-032: PvP-Angreifbarkeit + Skull-Reputationssystem.
##
## Serverautoritativ, exakt wie in der ADR-Entscheidung beschrieben:
##
##   is_pvp_active(player_id) :=
##       global_pvp_enabled
##       AND NOT PermissionService.has_capability(player_id, "pvp_immune")
##       AND current_zone.has_tag("pvp")
##
## SKULL-TRIGGER: report_pvp_damage() ist der zentrale Einstiegspunkt, den
## CombatSystem bei JEDEM Schaden zwischen zwei Spielern aufrufen muss (auch
## AoE/Fernkampf-Streuschaden zählt als Treffer, nicht nur der Todesstoß).
## Solange das Opfer sich noch nicht gewehrt hat, setzt jeder weitere Treffer
## den Skull-Timer des Angreifers neu auf +20 Minuten — sobald beide
## Richtungen mindestens einmal getroffen haben, gilt das Gegenwehr-Fenster
## als eröffnet und weitere Treffer lösen keinen neuen Trigger mehr aus (der
## zuletzt gesetzte Timer läuft einfach weiter runter, auch mitten im Kampf).
##
## PERSISTENZ: `PlayerFlags` (skull_until/skull_is_voluntary/
## safe_zone_grace_until) ist player_uuid-gekeyt und überlebt Reconnects
## (ADR-029-Muster) — persistiert über SaveSystem, exakt wie CurrencyService
## (ADR-033). `CombatConsent` (wer hat wen schon getroffen) ist dagegen
## bewusst NICHT persistiert — reiner transienter World-Scope-State, der bei
## Server-Neustart ohnehin wertlos wäre (die Kämpfe sind vorbei).
##
## AURA-TEIL (ADR-036): laut ADR bleiben Spieler mit `is_skulled == true`
## **oder** Aura unterhalb der Schwelle nach Betreten einer Safe-Zone noch
## 10s angreifbar — beide Bedingungen sind jetzt verdrahtet, in
## report_safe_zone_entered() (dort wird die OR-Bedingung geprüft, BEVOR das
## 10s-Fenster startet; is_vulnerable_in_safe_zone() selbst bleibt ein reiner
## Timer-Check, unverändert). `_aura` ist bewusst OPTIONAL (nicht
## required_dep): PvPService selbst ist die Grundlage für AuraService (über
## PvPDeathLossService/Skull-Status), ein required_dep hier würde einen
## Bootstrap-Zyklus erzeugen. Fehlt AuraService (z.B. reiner PvE-Test-
## Kontext), greift nur noch der Skull-Teil — kein Crash, kein stiller
## Ausfall der Kernfunktion.

const LOG_CAT := "PvP"
const SAVE_KEY := "pvp_flags"

const SKULL_DURATION_SEC: float          = 20.0 * 60.0  ## 20 Minuten (ADR-032)
const SAFE_ZONE_GRACE_SEC: float         = 10.0         ## Anti-Escape-Fenster (ADR-032)
## Cleanup-Schwelle für CombatConsent (ADR-032 "Mitigationen"): ein Paar ist
## aufräumbar, sobald der letzte Treffer länger als die Skull-Dauer zurückliegt
## — zu diesem Zeitpunkt ist jeder mögliche Skull aus diesem Paar ohnehin
## bereits abgelaufen.
const CONSENT_STALE_AFTER_SEC: float     = SKULL_DURATION_SEC
const CONSENT_CLEANUP_INTERVAL_SEC: float = 5.0 * 60.0  ## Aufräum-Tick alle 5 Minuten

const PVP_ZONE_TAG: StringName        = &"pvp"
const SAFE_ZONE_TAG: StringName       = &"safe"
const PVP_IMMUNE_CAPABILITY: StringName = &"pvp_immune"

## Emittiert bei jedem neuen/erneuerten Skull (freiwillig oder Trigger).
signal skulled(player_id: String, voluntary: bool)

var _permissions:  PermissionService = null
var _zones:        ZoneService       = null
var _network:      NetworkBridge     = null
var _save_system:  SaveSystem        = null
var _ticker:       ServiceTicker     = null
var _bus:          IEventBus         = null
var _aura:         AuraService       = null

## Weltweiter PvP-Schalter — bewusst NICHT persistiert (Admin-Runtime-Toggle,
## Default an, da bereits eine PvP-Zone in der Welt existiert (Wüste, ADR-030
## Round 74) und ohne aktives PvP nutzlos wäre).
var _global_pvp_enabled: bool = true

## player_id (String) -> {skull_until: float, skull_is_voluntary: bool, safe_zone_grace_until: float}
var _flags: Dictionary = {}

## Paar-Schlüssel (sortiert, "idA|idB") -> {a_hit_b: bool, b_hit_a: bool, last_damage_timestamp: float}.
## "a"/"b" beziehen sich auf die sortierte Paar-Reihenfolge (_pair_a()/_pair_b()),
## NICHT auf Angreifer/Opfer einer einzelnen Interaktion — die Zuordnung
## wird bei jedem Aufruf neu über einen String-Vergleich aufgelöst.
var _consent: Dictionary = {}

var _cleanup_accum: float = 0.0

# ─────────────────────────────────────────────
# Phase 4/5: Configure / Ready
# ─────────────────────────────────────────────

func configure(deps: ServiceDeps) -> void:
	_permissions = deps.require(ServiceKeys.PERMISSION_SERVICE) as PermissionService
	_zones       = deps.require(ServiceKeys.ZONE_SERVICE)        as ZoneService
	_network     = deps.get_optional(ServiceKeys.NETWORK_BRIDGE) as NetworkBridge
	_save_system = deps.get_optional(ServiceKeys.SAVE_SYSTEM)    as SaveSystem
	_ticker      = deps.get_optional(ServiceKeys.TICKER)         as ServiceTicker
	_bus         = deps.get_optional(ServiceKeys.EVENT_BUS)      as IEventBus
	_aura        = deps.get_optional(ServiceKeys.AURA)           as AuraService

	if _save_system:
		_save_system.register_save_provider(self)
		var saved: Variant = _save_system.get_state_for(SAVE_KEY)
		if saved is Dictionary and not (saved as Dictionary).is_empty():
			_restore_from_save(saved)
	else:
		AppLogger.log_error("Abhängigkeit 'savesystem' fehlt!", LOG_CAT)

	AppLogger.log_info("PvPService initialisiert (%d gespeicherte Flags)." % _flags.size(), LOG_CAT)

## Phase C8 Late-Inject (siehe BootPipeline.gd), analog ZoneService/CurrencyService.
func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network

func on_ready() -> void:
	# duck-typed Registrierung, gleiches Muster wie CombatSystem/RespawnService.
	if is_instance_valid(_ticker):
		_ticker.register_service(self)
	# Event-Bus statt direktem ZoneService-Dep (würde einen Zyklus erzeugen,
	# da is_pvp_active() bereits _zones als Dep braucht — ZoneService selbst
	# kennt PvPService also nicht, meldet Zonen-Wechsel nur per Broadcast,
	# genau wie WorldService/andere Konsumenten von zone_entered/zone_exited).
	if is_instance_valid(_bus):
		_bus.zones().zone_entered.connect(_on_zone_entered)
	else:
		AppLogger.log_warn("EventBus fehlt — Safe-Zone-Vulnerabilitäts-Fenster nicht verdrahtet.", LOG_CAT)
	AppLogger.log_info("PvPService aktiv.", LOG_CAT)

func on_cleanup() -> void:
	if is_instance_valid(_bus) and _bus.zones().zone_entered.is_connected(_on_zone_entered):
		_bus.zones().zone_entered.disconnect(_on_zone_entered)
	AppLogger.log_info("PvPService cleanup.", LOG_CAT)

## ADR-032 "Safe-Zone-Vulnerabilitäts-Fenster": jeder Zonen-Enter wird geprüft,
## No-op-Kosten für alle nicht-"safe"-getaggten Zonen sind vernachlässigbar
## (ein Dictionary-Lookup + has_tag()-Scan über typischerweise 1-2 Tags).
func _on_zone_entered(peer_id: int, zone_id: StringName) -> void:
	if not is_instance_valid(_zones):
		return
	var config := _zones.get_zone_config(zone_id)
	if not is_instance_valid(config) or not config.has_tag(SAFE_ZONE_TAG):
		return
	var player_id := _network.get_player_id_for_peer(peer_id) if is_instance_valid(_network) else ""
	if not player_id.is_empty():
		report_safe_zone_entered(player_id)

## CombatConsent-Aufräumen (ADR-032 "Mitigationen") — läuft alle 5 Minuten,
## entfernt Paare deren letzter Treffer länger als die Skull-Dauer zurückliegt.
func on_tick(delta: float) -> void:
	_cleanup_accum += delta
	if _cleanup_accum < CONSENT_CLEANUP_INTERVAL_SEC:
		return
	_cleanup_accum = 0.0
	_cleanup_expired_consent()

# ─────────────────────────────────────────────
# Öffentliche API — Abfrage
# ─────────────────────────────────────────────

## ADR-032 "PvP-Aktivierung" — alle drei Bedingungen serverseitig geprüft.
func is_pvp_active(player_id: String) -> bool:
	if not _global_pvp_enabled:
		return false
	if is_instance_valid(_permissions) and _permissions.has_capability(player_id, PVP_IMMUNE_CAPABILITY):
		return false
	if not is_instance_valid(_zones):
		return false
	var peer_id := _peer_for(player_id)
	if peer_id == -1:
		return false
	return _zones.has_tag(peer_id, PVP_ZONE_TAG)

func is_skulled(player_id: String) -> bool:
	var until: float = (_flags.get(player_id, {}) as Dictionary).get("skull_until", 0.0)
	return until > 0.0 and until > _now()

func get_skull_remaining_seconds(player_id: String) -> float:
	var until: float = (_flags.get(player_id, {}) as Dictionary).get("skull_until", 0.0)
	return maxf(0.0, until - _now())

func is_skull_voluntary(player_id: String) -> bool:
	return bool((_flags.get(player_id, {}) as Dictionary).get("skull_is_voluntary", false))

## ADR-032 "Safe-Zone-Vulnerabilitäts-Fenster" (Anti-Escape) — Aura-Teil aus
## ADR-036 noch nicht enthalten, siehe Klassenkommentar.
func is_vulnerable_in_safe_zone(player_id: String) -> bool:
	var until: float = (_flags.get(player_id, {}) as Dictionary).get("safe_zone_grace_until", 0.0)
	return until > 0.0 and until > _now()

func is_global_pvp_enabled() -> bool:
	return _global_pvp_enabled

# ─────────────────────────────────────────────
# Öffentliche API — Mutation (nur Autorität — dieser Service prüft das nicht
# selbst, sondern vertraut seinen Aufrufern, exakt wie ZoneService seinem
# einzigen Aufrufer vertraut, siehe dortiger Klassenkommentar)
# ─────────────────────────────────────────────

## Admin-Runtime-Toggle. Aufrufer (z.B. AdminConsole) muss selbst
## PermissionService.is_admin() prüfen — dieser Service kennt keine
## Aufrufer-Identität (gleiche Abgrenzung wie ZoneService.report_enter()).
func set_global_pvp_enabled(enabled: bool) -> void:
	_global_pvp_enabled = enabled
	AppLogger.log_info("Globales PvP: %s" % ("aktiviert" if enabled else "deaktiviert"), LOG_CAT)

## Zentraler Skull-Trigger-Einstiegspunkt (ADR-032 "Skull-Trigger"). Von
## CombatSystem bei JEDEM Schaden zwischen zwei Spielern aufzurufen — auch
## Streuschaden, nicht nur der Todesstoß.
func report_pvp_damage(attacker_player_id: String, victim_player_id: String) -> void:
	if attacker_player_id.is_empty() or victim_player_id.is_empty():
		return
	if attacker_player_id == victim_player_id:
		return

	var key := _pair_key(attacker_player_id, victim_player_id)
	var entry: Dictionary = _consent.get(key, {"a_hit_b": false, "b_hit_a": false, "last_damage_timestamp": 0.0})
	if attacker_player_id == _pair_a(key):
		entry["a_hit_b"] = true
	else:
		entry["b_hit_a"] = true
	entry["last_damage_timestamp"] = _now()
	_consent[key] = entry

	# Gegenwehr-Fenster ist eröffnet, sobald BEIDE Richtungen mindestens
	# einmal getroffen haben — ab dann kein neuer Skull-Trigger mehr
	# zwischen genau diesen beiden Spielern (ADR-032 "Skull-Trigger").
	if bool(entry["a_hit_b"]) and bool(entry["b_hit_a"]):
		return

	_apply_skull(attacker_player_id, false)

## Freiwilliges Skullen (ADR-032, Grundlage für ADR-036s erhöhte
## Loot-Chance bei eigenem PvP-Tod) — gleicher Flag, andere Ursache, kein
## Gegenwehr-Fenster-Check nötig (kein Angriff, keine Opfer-Seite).
func set_voluntary_skull(player_id: String, enabled: bool) -> void:
	if player_id.is_empty():
		return
	if not enabled:
		_flags.erase(player_id)
		return
	_apply_skull(player_id, true)

## ADR-032 "Safe-Zone-Vulnerabilitäts-Fenster": von der Zonen-Integration
## (ZoneTriggerVolume/WorldService) beim Betreten einer "safe"-getaggten Zone
## aufzurufen. No-op wenn der Spieler ohnehin nicht verwundbar ist — kein
## Grace-Fenster ohne etwas, wovor es schützen müsste.
##
## ADR-036: OR-Bedingung "is_skulled ODER Aura unterhalb der Schwelle" —
## siehe Klassenkommentar "AURA-TEIL".
func report_safe_zone_entered(player_id: String) -> void:
	var low_aura := is_instance_valid(_aura) and _aura.is_below_vulnerability_threshold(player_id)
	if not is_skulled(player_id) and not low_aura:
		return
	var f: Dictionary = _flags.get(player_id, {})
	f["safe_zone_grace_until"] = _now() + SAFE_ZONE_GRACE_SEC
	_flags[player_id] = f
	AppLogger.log_debug(
		"'%s' betritt Safe-Zone verwundbar (geskullt=%s, niedrige Aura=%s) — %ds Vulnerabilitäts-Fenster."
		% [player_id, is_skulled(player_id), low_aura, int(SAFE_ZONE_GRACE_SEC)],
		LOG_CAT
	)

func _apply_skull(player_id: String, voluntary: bool) -> void:
	var f: Dictionary = _flags.get(player_id, {})
	f["skull_until"]        = _now() + SKULL_DURATION_SEC
	f["skull_is_voluntary"] = voluntary
	if not f.has("safe_zone_grace_until"):
		f["safe_zone_grace_until"] = 0.0
	_flags[player_id] = f
	skulled.emit(player_id, voluntary)
	AppLogger.log_info("'%s' geskullt (freiwillig=%s)." % [player_id, voluntary], LOG_CAT)

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _now() -> float:
	return Time.get_unix_time_from_system()

## Sortierter, kanonischer Paar-Schlüssel — unabhängig davon, wer Angreifer
## oder Opfer der aktuellen Interaktion ist.
func _pair_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]

func _pair_a(key: String) -> String:
	return key.split("|")[0]

func _peer_for(player_id: String) -> int:
	if not is_instance_valid(_network):
		return -1
	return _network.get_peer_id_for_player(player_id)

func _cleanup_expired_consent() -> void:
	var now := _now()
	var stale: Array[String] = []
	for key in _consent:
		var entry: Dictionary = _consent[key]
		if now - float(entry.get("last_damage_timestamp", 0.0)) > CONSENT_STALE_AFTER_SEC:
			stale.append(key)
	for key in stale:
		_consent.erase(key)
	if not stale.is_empty():
		AppLogger.log_debug("CombatConsent-Cleanup: %d abgelaufene Paare entfernt." % stale.size(), LOG_CAT)

# ─────────────────────────────────────────────
# Save-Interface (analog CurrencyService/ADR-033)
# ─────────────────────────────────────────────

func get_save_key() -> String:
	return SAVE_KEY

## Abgelaufene Skulls werden nicht mit gespeichert — kein Erkenntniswert,
## hält den Save schlank (analog CurrencyService-Muster, hier zusätzlich
## zeitbasiert statt wertbasiert gefiltert).
func get_save_data() -> Dictionary:
	var out: Dictionary = {}
	var now := _now()
	for pid in _flags:
		var f: Dictionary = _flags[pid]
		if float(f.get("skull_until", 0.0)) > now:
			out[pid] = f
	return out

func _restore_from_save(saved: Dictionary) -> void:
	for pid in saved:
		if saved[pid] is Dictionary:
			_flags[pid] = saved[pid]

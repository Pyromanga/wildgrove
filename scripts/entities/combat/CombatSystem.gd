extends ServiceNode
# justified: on_ready() verbindet CombatEvents; ServiceTicker-Registrierung braucht Node-Parent.
class_name CombatSystem

## CombatSystem — Zentrales Fundament für alle Kampf-Berechnungen.
##
## Abhängigkeiten (deps): ["stat_modifiers" (optional)]
##
## VERANTWORTUNG:
##   calculate_damage()              → Nimmt raw_amount + DamageType, wendet
##                                      Resistenzen (als rohe Floats) an, füllt
##                                      final_amount, gibt DamageRecord zurück.
##   calculate_damage_with_profile() → Wie calculate_damage(), nimmt aber ein
##                                      CombatProfile statt zweier loser Floats (TD-10).
##   apply_damage()                  → Wendet einen fertigen Record auf ein
##                                      HealthComponent an und emittiert
##                                      EventBus.world.damage_dealt.
##   roll_critical()                 → Zufalls-Check ob ein Treffer kritisch ist (TD-13).
##   player_melee_damage()           → Zentralisiert die Spieler-Angriffs-Formel.
##   enemy_melee_damage()            → Zentralisiert die Gegner-Angriffs-Formel (TD-11).
##   apply_poison() / apply_burn()   → Registriert einen rekurrierenden Status-Effekt
##                                      (TD-12). Tickt via on_tick() — siehe unten.
##
## NICHT VERANTWORTLICH für:
##   - KI-Entscheidungen (EnemyAI)
##   - Animations-Timing (EnemyVisuals / EnemyAttack)
##   - XP-Vergabe (bleibt in EnemyNPC._die() → EventBus.player)
##   - Loot-Drop (bleibt in EnemyNPC._die() → EventBus.world)
##
## STATUS-EFFEKTE (TD-12): `_active_effects: { effect_key: StatusEffect }`.
## Verdrahtet über apply_weapon_on_hit() (EnemyNPC._on_interacted() → CombatSystem)
## und direkte apply_poison()/apply_burn()-Aufrufe. on_hit_effect-Dispatch per match
## auf StatusEffect.Kind (POISON=0, BURN=1). Kein Stacking — Überschreiben per effect_key.

## Ticker wird via DI injiziert (ADR-011 / H-03) und in configure() gespeichert.
## StatModifierService.cleanup_all_expired()). Kein eigener Timer-Node nötig.
##
## ERWEITERBARKEIT (noch offen, siehe ADR-008 "Bekannter Tech Debt"):
##   - Reflect/Thorns: apply_damage() gibt optionalen Rückschlag-Record zurück
##
## ADR-008: Diese Klasse begründet ADR-008 (CombatSystem mit DamageRecord + DamageType).

const LOG_CAT := "Combat"

## Basis-Krit-Chance (5 %). Wird später durch StatModifier "crit_chance" erhöht.
const BASE_CRIT_CHANCE: float  = 0.05

## Krit-Multiplikator (1.5× Schaden).
const CRIT_MULTIPLIER: float   = 1.5

## Minimaler Schaden (verhindert 0-Damage durch hohe Rüstung).
const MIN_DAMAGE: float = 1.0

var _stat_modifiers: StatModifierService = null
var _ticker: ServiceTicker = null
var _equipment: EquipmentService = null
var _skill_system: SkillSystem = null
## ADR-029 Round 65: NEU — CombatSystem hatte bisher keine NetworkBridge-
## Referenz. Nötig geworden, weil SkillSystem.get_level() (player_melee_damage())
## seit dieser Runde peer_id: String verlangt, CombatSystem selbst aber
## weiterhin mit peer_id (int) arbeitet (ADR-019) — Übersetzung über
## _resolve_player_uuid() unten. Kein configure()-Dep (Zyklusgefahr wie bei
## RewardDispatcher/EquipmentService, siehe deren Kommentare) — kommt über
## denselben Phase-C8-Late-Inject-Mechanismus (BootPipeline.gd,
## ServiceKeys.COMBAT in der Liste ergänzt).
var _network: NetworkBridge = null

## ADR-032: optional — CombatSystem kennt (noch) keinen Angriffsweg für
## Spieler-gegen-Spieler-Schaden (der existiert in diesem Projekt bisher
## nicht, siehe resolve_pvp_hit()-Kommentar unten). Normaler configure()-Dep
## (kein Late-Inject nötig — PvPService hat keine Rückabhängigkeit auf
## CombatSystem, also kein Zyklusrisiko wie bei _network oben).
var _pvp: PvPService = null

## Instanz (Produktionsverhalten bleibt nicht-deterministisch wie zuvor).
## Tests können via configure({"rng": seeded_rng}) einen geseedeten RandomNumberGenerator
## injizieren — dann ist calculate_damage()/roll_critical() exakt reproduzierbar,
## ohne das Krit-Toleranzband aus test_combat_system.gd zu brauchen.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _bus: IEventBus

## Siehe on_tick() für die Tick-Verarbeitung, apply_poison()/apply_burn() für die API.
var _active_effects: Dictionary = {}

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func configure(deps: ServiceDeps) -> void:
	_stat_modifiers = deps.get_optional(ServiceKeys.STAT_MODIFIERS) as StatModifierService
	if not is_instance_valid(_stat_modifiers):
		AppLogger.log_debug("StatModifierService nicht in deps — Boni nicht verfügbar.", LOG_CAT)
	_ticker = deps.get_optional(ServiceKeys.TICKER) as ServiceTicker
	_equipment    = deps.get_optional(ServiceKeys.EQUIPMENT)    as EquipmentService
	# II-02: SkillSystem als optionale Dep statt Funktions-Parameter in player_melee_damage()
	_skill_system = deps.get_optional(ServiceKeys.SKILL_SYSTEM) as SkillSystem
	_bus        = deps.require(ServiceKeys.EVENT_BUS)       as IEventBus
	_pvp        = deps.get_optional(ServiceKeys.PVP)        as PvPService

	# Production-BootstrapConfig deklariert "rng" nicht als Service-Dependency —
	# dieser Pfad wird nur von Tests genutzt (configure({"rng": seeded_rng})).
	var injected_rng: Variant = deps.get_optional("rng")
	if injected_rng is RandomNumberGenerator:
		_rng = injected_rng
	else:
		_rng.randomize()

	AppLogger.log_info("CombatSystem konfiguriert.", LOG_CAT)

## Phase C8 Late-Inject (BootPipeline.gd) — identischer Mechanismus/Grund wie
## InventorySystem/RewardDispatcher/EquipmentService.inject_network_bridge().
func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network

## Übersetzt eine peer_id in die stabile peer_id über NetworkBridge — für
## den SkillSystem.get_level()-Aufruf in player_melee_damage()/
## apply_weapon_on_hit(). Identisches Muster zu
## RewardDispatcher/EquipmentService._resolve_player_uuid().
func _resolve_player_uuid(peer_id: int) -> String:
	if not is_instance_valid(_network):
		AppLogger.log_warn(
			"_resolve_player_uuid(%d): kein NetworkBridge injiziert — Übersetzung nicht möglich." % peer_id,
			LOG_CAT
		)
		return ""
	return _network.get_player_id_for_peer(peer_id)

func on_ready() -> void:
	# duck-typed, gleiches Muster wie RespawnService.on_ready().
	if is_instance_valid(_ticker):
		_ticker.register_service(self)
	AppLogger.log_info("CombatSystem aktiv.", LOG_CAT)

func on_cleanup() -> void:
	_active_effects.clear()
	AppLogger.log_info("CombatSystem cleanup.", LOG_CAT)

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

## Berechnet den finalen Schaden für einen DamageRecord.
##
## Verarbeitung:
##   1. Krit-Check (PHYSICAL + MAGIC, nicht TRUE)
##   2. Type-spezifische Resistenz via target_armor / target_magic_resist
##   3. StatModifier "damage_bonus" des Angreifers addiert auf raw
##   4. Clamp auf MIN_DAMAGE
##   5. record.final_amount gesetzt — Record danach als fertig betrachten
##
## [param record]         Vorbereiteter DamageRecord (source, target, raw, type gesetzt).
## [param target_armor]   Rüstungswert des Ziels (0.0 = keine Rüstung, 1.0 = immun — kein sinnvoller Wert, Clamp auf 0.85 max).
## [param target_magic]   Magische Resistenz des Ziels (selbes Schema).
## [return] denselben Record (gefüllt, zur Weitergabe).
func calculate_damage(
		record: DamageRecord,
		target_armor: float = 0.0,
		target_magic_resist: float = 0.0
) -> DamageRecord:
	var raw := record.raw_amount

	# Damage-Bonus aus StatModifiers des Angreifers — TRUE-Schaden (Gift-/Brand-Ticks,
	# Umweltschaden) bleibt bewusst unverändert, siehe StatusEffect.gd Kommentar.
	#
	# Bug A (gefunden Round 69, siehe TODO-offene-probleme.md): dieser Aufruf las
	# vorher get_effective_stat("damage_bonus", raw) OHNE jedes Id-Argument — der
	# Guard prüfte nur record.source_id (Entity-Typ-Label "player", keine
	# Identität), record.attacker_peer_id (die echte Angreifer-Id seit ADR-019)
	# wurde komplett ignoriert. Strukturell wurde dadurch immer der Default-
	# Bucket gelesen, unabhängig vom tatsächlichen Angreifer — gleiche Bug-
	# Familie wie R-8 (Round 49). Fix: Gate auf attacker_peer_id != -1, über
	# dieselbe _resolve_player_uuid()-Stelle wie player_melee_damage(); Bonus
	# nur anwenden wenn ein echter Spieler-Angreifer bekannt ist.
	if record.damage_type != DamageRecord.DamageType.TRUE \
			and is_instance_valid(_stat_modifiers) and record.attacker_peer_id != -1:
		var attacker_uuid := _resolve_player_uuid(record.attacker_peer_id)
		if not attacker_uuid.is_empty():
			raw = _stat_modifiers.get_effective_stat("damage_bonus", raw, attacker_uuid)

	# Krit-Check (TRUE-Schaden ignoriert Krits — kein Würfelglück bei Gift/Sturz)
	if record.damage_type != DamageRecord.DamageType.TRUE:
		if roll_critical(record.attacker_peer_id):
			raw *= CRIT_MULTIPLIER
			record.is_critical = true

	# Resistenz anwenden
	var final := raw
	match record.damage_type:
		DamageRecord.DamageType.PHYSICAL:
			var mitigation := clampf(target_armor, 0.0, 0.85)
			final = raw * (1.0 - mitigation)
		DamageRecord.DamageType.MAGIC:
			var mitigation := clampf(target_magic_resist, 0.0, 0.85)
			final = raw * (1.0 - mitigation)
		DamageRecord.DamageType.TRUE:
			final = raw  # Unverändert

	record.final_amount = maxf(final, MIN_DAMAGE)

	AppLogger.log_debug(record.to_debug_string(), LOG_CAT)
	return record

## Wie calculate_damage(), nimmt aber ein CombatProfile statt zweier loser
## Floats entgegen (TD-10). Bevorzugter Einstiegspunkt für Entity-Code —
## calculate_damage() bleibt als reine Funktion über zwei Floats bestehen,
## weil sie ohne DataService/CombatProfile-Setup testbar sein soll (ADR-008).
##
## [param profile] Resistenz-Profil des Ziels. null → CombatProfile.default_profile()
## (keine Resistenz) statt eines Crashs — z.B. wenn DataService nicht verfügbar ist.
func calculate_damage_with_profile(record: DamageRecord, profile: CombatProfile, target_player_id: String = "") -> DamageRecord:
	var p := profile if is_instance_valid(profile) else CombatProfile.default_profile()
	return calculate_damage(record, p.armor + equipped_armor_bonus(target_player_id), p.magic_resist)

## Summe der Rüstungswerte, die ein Spieler über ausgerüstete ArmorDefinition-Teile trägt
## (StatModifier auf EquipmentService.STAT_ARMOR, siehe EquipmentService._apply_stat_bonus()).
## 0.0 für leere player_id (Monster-Ziele) oder ohne StatModifierService. Die Obergrenze (0.85)
## setzt calculate_damage() für Profil-Rüstung und Ausrüstung zusammen.
func equipped_armor_bonus(player_id: String) -> float:
	if player_id.is_empty() or not is_instance_valid(_stat_modifiers):
		return 0.0
	return _stat_modifiers.get_effective_stat(EquipmentService.STAT_ARMOR, 0.0, player_id)

## Wendet einen fertigen DamageRecord auf ein HealthComponent an.
##
## Emittiert EventBus.world.damage_dealt(record) nach dem Schaden.
## Gibt false zurück wenn hc ungültig ist oder bereits tot.
func apply_damage(record: DamageRecord, hc: HealthComponent) -> bool:
	if not is_instance_valid(hc) or hc.is_dead:
		return false
	# take_damage_record() statt take_damage(int(...)) — gibt den Record bei
	# Tod an HealthComponent.died weiter, damit die Angreifer-Identität
	# (record.attacker_peer_id) am todesursächlichen Ereignis hängt (ADR-019).
	hc.take_damage_record(record)
	_bus.world().emit_damage_dealt(record)
	return true

## ADR-032: Gate + Skull-Trigger für Spieler-gegen-Spieler-Schaden.
##
## WICHTIGER SCOPE-HINWEIS: Dieses Projekt hat aktuell KEINEN Weg, mit dem ein
## Spieler überhaupt einen anderen Spieler angreifen kann — es gibt weder ein
## Targeting noch eine Interaktion, die Player.health (statt EnemyNPC.health)
## als Ziel nimmt. Diese Methode ist deshalb die vorbereitete Ziel-Schnittstelle
## für genau den Moment, in dem echtes PvP-Combat gebaut wird (eigene
## Folge-Runde) — sie ist unit-testbar und korrekt, hat aber aktuell noch
## KEINEN Aufrufer im Spiel selbst.
##
## Gate: is_pvp_active(victim) ODER is_vulnerable_in_safe_zone(victim) — die
## zweite Bedingung deckt exakt das ADR-032-Anti-Escape-Fenster ab (Opfer ist
## physisch schon in der Safe-Zone, aber noch für 10s verwundbar).
## Gibt false zurück wenn der Treffer verweigert wird (kein apply_damage()-Aufruf).
func resolve_pvp_hit(
	record: DamageRecord,
	victim_hc: HealthComponent,
	attacker_player_id: String,
	victim_player_id: String
) -> bool:
	if not is_instance_valid(_pvp):
		AppLogger.log_warn("resolve_pvp_hit(): kein PvPService injiziert — Treffer verweigert.", LOG_CAT)
		return false
	var vulnerable := _pvp.is_pvp_active(victim_player_id) or _pvp.is_vulnerable_in_safe_zone(victim_player_id)
	if not vulnerable:
		return false
	if not apply_damage(record, victim_hc):
		return false
	_pvp.report_pvp_damage(attacker_player_id, victim_player_id)
	return true

## Würfelt ob ein Treffer kritisch ist.
## attacker_peer_id kann genutzt werden um Krit-Chance per Angreifer zu variieren.
## configure({"rng": seeded_rng}) ist das Ergebnis deterministisch (siehe Tests).
##
## Bug B (gefunden Round 69, siehe TODO-offene-probleme.md): vorher nahm diese
## Funktion source_id: String entgegen und rief source_id.to_int() als "peer_id"
## für den crit_chance-Lookup auf — aber source_id ist nur das Entity-Typ-Label
## ("player", "goblin_1"), kein Identifier. "player".to_int() == 0 in GDScript;
## Peer 0 ist nie eine echte Verbindung, der Lookup las also strukturell IMMER
## einen leeren Bucket. Bisher maskiert, weil (a) noch kein Content einen
## "crit_chance"-Modifier registriert und (b) der bisherige Test nur das
## aggregierte Krit-Band prüfte, nie die Attribution. Fix: echte
## attacker_peer_id entgegennehmen, über dieselbe _resolve_player_uuid()-Stelle
## wie calculate_damage()/player_melee_damage() auflösen.
func roll_critical(attacker_peer_id: int = -1) -> bool:
	# Authority-Guard — Krit-Würfe sind server-autoritativ (ADR-010 Tier 2/3).
	# Tier 1 (kein Peer gesetzt): Guard überspringen.
	# Tier 2/3: nur die Autorität darf Krit-Würfe durchführen (verhindert Client-Manipulation).
	# Guard ist ein hard return false, NICHT assert() — assert() ist in Release-Builds ein No-Op.
	if is_instance_valid(multiplayer) and multiplayer.has_multiplayer_peer():
		if not multiplayer.is_server():
			AppLogger.log_error(
				"roll_critical() auf Nicht-Autorität aufgerufen — verweigert.",
				LOG_CAT
			)
			return false
	var chance := BASE_CRIT_CHANCE
	if is_instance_valid(_stat_modifiers) and attacker_peer_id != -1:
		var attacker_uuid := _resolve_player_uuid(attacker_peer_id)
		if not attacker_uuid.is_empty():
			chance += _stat_modifiers.get_effective_stat("crit_chance", 0.0, attacker_uuid)
	return _rng.randf() < chance

## Berechnet Spieler-Angriffs-Schaden basierend auf Skill-Level + ausgerüsteter Waffe.
## Liest SkillSystem via _skill_system-Dep (injiziert via configure(), II-02-Fix).
## Liest Equipment via _equipment-Dep (injiziert via configure(), ADR-011 H-04).
##
## [param peer_id] Echte peer_id des angreifenden Spielers (ADR-019 — vorher
## ein hartcodierter String "player", der weder Skill-Level-Lookup noch
## Killer-Attribution korrekt bedienen konnte). source_id bleibt das feste
## Entity-Typ-Label "player" für Logging; peer_id reist separat als
## record.attacker_peer_id mit.
func player_melee_damage(peer_id: int) -> DamageRecord:
	var base_dmg := 10.0
	# ADR-029 Round 66: attacker_uuid wird jetzt EINMAL aufgelöst und für BEIDE
	# Lookups unten wiederverwendet (Skill-Level UND Equipment) — vorher saß die
	# Übersetzung nur innerhalb des _skill_system-Guards und wäre für den
	# Waffen-Lookup separat dupliziert worden. Leere player_uuid (kein
	# NetworkBridge/SessionManager-Slot) heißt hier bewusst "kein Skill-Bonus,
	# keine Waffe gefunden" statt Crash — derselbe Grad an Fehlertoleranz wie
	# die vorherigen einzelnen Guards.
	var attacker_uuid := _resolve_player_uuid(peer_id)

	if is_instance_valid(_skill_system) and not attacker_uuid.is_empty():
		# ADR-029 Round 65: SkillSystem.get_level() verlangt peer_id: String.
		base_dmg += _skill_system.get_level("combat", attacker_uuid) * 2.0

	# Waffen-Bonus aus Equipment
	# R-8 (gefunden während R-7): war `get_equipped_weapon()` ohne peer_id —
	# las strukturell immer Spieler 1s Waffe, unabhängig vom tatsächlichen
	# Angreifer. ADR-029 Round 66: EquipmentService.get_equipped_weapon()
	# verlangt jetzt ebenfalls peer_id: String — dieselbe attacker_uuid von
	# oben, keine zweite parallele Übersetzungsstelle.
	var weapon: WeaponDefinition = null
	if is_instance_valid(_equipment) and not attacker_uuid.is_empty():
		weapon = _equipment.get_equipped_weapon(attacker_uuid, EquipmentService.SLOT_WEAPON)
		if is_instance_valid(weapon):
			base_dmg += weapon.damage_bonus

	var dmg_type := DamageRecord.DamageType.PHYSICAL
	if is_instance_valid(weapon):
		dmg_type = weapon.damage_type

	return DamageRecord.make_player_attack("player", "", base_dmg, dmg_type, peer_id)

## Wendet on_hit_effects der ausgerüsteten Waffe auf das Ziel an (Gift, Brand, …).
## Aufgerufen von EnemyNPC._on_interacted() nach erfolgreichem Treffer.
## on_hit_effect entspricht StatusEffect.Kind (POISON = 0, BURN = 1, -1 = kein Effekt).
##
## [param attacker_peer_id] ADR-019: reist mit dem Status-Effekt, damit ein
## Gift-/Brand-Tick, der ein Ziel tötet, denselben Killer bekommt wie der
## ursprüngliche Treffer — sonst bliebe genau hier eine zweite, kleinere
## Version der Attributions-Lücke offen (siehe ADR-019 "Noch offen").
func apply_weapon_on_hit(
		target_hc: HealthComponent, attacker_id: String, target_id: String,
		attacker_peer_id: int = -1
) -> void:
	if not is_instance_valid(target_hc):
		return
	if not is_instance_valid(_equipment):
		return
	# R-8 (gefunden während R-7): dieselbe Lücke wie in player_melee_damage() —
	# `get_equipped_weapon()` ohne peer_id las immer Spieler 1s Waffe.
	# attacker_peer_id ist hier optional (Default -1, siehe Signatur) für
	# bestehende Aufrufer/Tests ohne Angreifer-Kontext — -1 fällt bewusst auf
	# Spieler 1 zurück (identisch zum bisherigen, impliziten Verhalten), ein
	# echter attacker_peer_id >= 0 (wie von EnemyNPC._on_interacted() immer
	# übergeben) nutzt stattdessen dessen eigene Ausrüstung.
	var lookup_peer_id := attacker_peer_id if attacker_peer_id >= 0 else 1
	# ADR-029 Round 66: EquipmentService.get_equipped_weapon() verlangt jetzt
	# peer_id: String — dieselbe _resolve_player_uuid()-Stelle wie
	# player_melee_damage(), nicht dupliziert (siehe TODO-offene-probleme.md).
	# Leere attacker_uuid heißt hier bewusst "keine Waffe gefunden" statt Crash.
	var attacker_uuid := _resolve_player_uuid(lookup_peer_id)
	var weapon: WeaponDefinition = null
	if not attacker_uuid.is_empty():
		weapon = _equipment.get_equipped_weapon(attacker_uuid, EquipmentService.SLOT_WEAPON)
	if not is_instance_valid(weapon) or weapon.on_hit_effect < 0:
		return
	match weapon.on_hit_effect:
		StatusEffect.Kind.POISON:
			apply_poison(
				attacker_id, target_id, target_hc,
				weapon.on_hit_damage_per_tick,
				weapon.on_hit_ticks,
				weapon.on_hit_tick_interval,
				attacker_peer_id
			)
			_bus.ui().emit_floating_loot_text_requested("☠ Vergiftet!")
		StatusEffect.Kind.BURN:
			apply_burn(
				attacker_id, target_id, target_hc,
				weapon.on_hit_damage_per_tick,
				weapon.on_hit_ticks,
				weapon.on_hit_tick_interval,
				attacker_peer_id
			)
			_bus.ui().emit_floating_loot_text_requested("🔥 Brennt!")
		_:
			AppLogger.log_warn(
				"apply_weapon_on_hit: unbekannter on_hit_effect-Wert %d — ignoriert." % weapon.on_hit_effect,
				LOG_CAT
			)

## Berechnet Gegner-Angriffs-Schaden (Enemy → Spieler). Spiegelt player_melee_damage().
## CombatSystem vorbei — kein Krit-Check, keine Resistenz, kein damage_dealt-Event.
##
## [param raw_damage] Basis-Schaden aus der EnemyNPC-Konfiguration (on_spawn cfg "damage").
## Bewusst kein Skill-Level-Einfluss wie bei player_melee_damage() — Gegner haben
## (noch) keine Skills. Variation kommt aktuell ausschließlich aus dem Ziel-Profil
## (Resistenz) und dem Krit-Würfel in calculate_damage().
func enemy_melee_damage(source_id: String, target_id: String, raw_damage: float) -> DamageRecord:
	return DamageRecord.make_enemy_attack(
		source_id, target_id, raw_damage, DamageRecord.DamageType.PHYSICAL
	)

# ─────────────────────────────────────────────
# Status-Effekte (TD-12)
# ─────────────────────────────────────────────

## Registriert einen Gift-Tick-Status-Effekt auf hc. Erneuter Aufruf mit derselben
## source_id/target_id-Kombination überschreibt den bestehenden Effekt (kein Stacking,
## Dauer + Schaden werden zurückgesetzt) — siehe StatusEffect.gd Kommentar.
##
## [param hc]              Ziel-HealthComponent (direkte Referenz, wie bei apply_damage()).
## [param damage_per_tick] Roh-Schaden pro Tick. Läuft über DamageType.TRUE — ignoriert
##                          Rüstung/Magieresistenz des Ziels (siehe StatusEffect.gd).
## [param total_ticks]     Anzahl Ticks bis der Effekt endet.
## [param tick_interval]   Sekunden zwischen zwei Ticks. Muss > 0 sein.
## [return] Den registrierten StatusEffect, oder null bei ungültigen Parametern.
func apply_poison(
		source_id: String, target_id: String, hc: HealthComponent,
		damage_per_tick: float, total_ticks: int, tick_interval: float = 1.0,
		attacker_peer_id: int = -1
) -> StatusEffect:
	return _apply_status_effect(
		StatusEffect.Kind.POISON, source_id, target_id, hc,
		damage_per_tick, tick_interval, total_ticks, attacker_peer_id
	)

## Registriert einen Brand-Tick-Status-Effekt. Spiegelt apply_poison() — siehe dort.
func apply_burn(
		source_id: String, target_id: String, hc: HealthComponent,
		damage_per_tick: float, total_ticks: int, tick_interval: float = 1.0,
		attacker_peer_id: int = -1
) -> StatusEffect:
	return _apply_status_effect(
		StatusEffect.Kind.BURN, source_id, target_id, hc,
		damage_per_tick, tick_interval, total_ticks, attacker_peer_id
	)

func _apply_status_effect(
		kind: StatusEffect.Kind, source_id: String, target_id: String, hc: HealthComponent,
		damage_per_tick: float, tick_interval: float, total_ticks: int,
		attacker_peer_id: int = -1
) -> StatusEffect:
	if not is_instance_valid(hc) or hc.is_dead:
		AppLogger.log_warn("apply_status_effect: HealthComponent ungültig oder Ziel bereits tot — ignoriert.", LOG_CAT)
		return null
	if tick_interval <= 0.0:
		AppLogger.log_error("apply_status_effect: tick_interval muss > 0 sein (war %.2f)." % tick_interval, LOG_CAT)
		return null
	if total_ticks <= 0:
		AppLogger.log_warn("apply_status_effect: total_ticks <= 0 — Effekt wird ignoriert.", LOG_CAT)
		return null

	var effect := StatusEffect.make(
		kind, source_id, target_id, hc, damage_per_tick, tick_interval, total_ticks, attacker_peer_id
	)
	var was_overwrite := _active_effects.has(effect.effect_key)
	_active_effects[effect.effect_key] = effect

	AppLogger.log_debug(
		"%s %s" % ["Überschrieben:" if was_overwrite else "Aktiviert:", effect.to_debug_string()],
		LOG_CAT
	)
	return effect

## Entfernt einen aktiven Status-Effekt vorzeitig (z.B. Heiltrank/Gegengift).
## Gibt false zurück wenn kein Effekt mit diesem Key aktiv ist.
func remove_status_effect(effect_key: String) -> bool:
	if not _active_effects.has(effect_key):
		return false
	_active_effects.erase(effect_key)
	AppLogger.log_debug("Status-Effekt entfernt: %s" % effect_key, LOG_CAT)
	return true

func has_status_effect(effect_key: String) -> bool:
	return _active_effects.has(effect_key)

## Debug/Tests: Anzahl aktuell aktiver Status-Effekte.
func get_active_status_effect_count() -> int:
	return _active_effects.size()

## Tick-Einstiegspunkt für ServiceTicker (TD-12). Verarbeitet alle aktiven
## Status-Effekte: akkumuliert delta, wendet bei Überschreiten von tick_interval
## eine TRUE-Damage-Tick via apply_damage() an, entfernt abgelaufene/ungültige
## Effekte. Mehrere fällige Ticks in einem einzigen on_tick() (z.B. nach Lag-Spike)
## werden alle nachgeholt — siehe while-Schleife.
func on_tick(delta: float) -> void:
	# StatModifier-Cleanup für ALLE Player-IDs — verhindert Modifier-Leak in Multiplayer.
	# StatModifierService hat kein eigenes on_tick(); diese Klasse ist der einzige Ticker-Aufrufer.
	# cleanup_all_expired() iteriert _players.keys() intern → korrekt für Spieler 1-N.
	if is_instance_valid(_stat_modifiers):
		_stat_modifiers.cleanup_all_expired()

	if _active_effects.is_empty():
		return

	var expired: Array[String] = []
	for key in _active_effects:
		var effect: StatusEffect = _active_effects[key]

		if not is_instance_valid(effect.health_component) or effect.health_component.is_dead:
			expired.append(key)
			continue

		effect._elapsed += delta
		while effect._elapsed >= effect.tick_interval and effect.ticks_remaining > 0:
			effect._elapsed -= effect.tick_interval

			var record := DamageRecord.make_environmental(
				effect.target_id, effect.damage_per_tick, effect.context_tag(),
				effect.attacker_peer_id
			)
			record.source_id = effect.source_id
			calculate_damage(record)  # TRUE-Type: kein Krit, keine Resistenz — final_amount = raw
			apply_damage(record, effect.health_component)

			effect.ticks_remaining -= 1
			if effect.ticks_remaining <= 0:
				break

		if effect.ticks_remaining <= 0:
			expired.append(key)

	for key in expired:
		_active_effects.erase(key)

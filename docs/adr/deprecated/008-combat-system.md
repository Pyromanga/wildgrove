> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-008: CombatSystem mit DamageRecord + DamageType

**Status:** Akzeptiert  
**Datum:** 2026-06  
**Kontext:** EnemyNPC, zukünftige Skill-Effekte, Equipment-Boni, Status-Effekte

---

## Problem

`HealthComponent` existiert und nimmt `take_damage(amount: int)` entgegen — aber wer berechnet den Schaden? Aktuell liegt die Formel verstreut in `EnemyAttack.calculate_player_damage()` (statische Methode, nur für Spieler-Angriffe). `_do_melee()` in `EnemyNPC` ruft direkt `hc.take_damage(_damage)` auf ohne Typ oder Krit. Es gibt keine `DamageType`-Unterscheidung, kein Resistenz-System, und keine Möglichkeit, Schadens-Events zu beobachten.

**Konsequenz für zukünftige Features:**
- Equipment-Boni (ADR-007 × StatModifierService) haben keinen zentralen Anwendungspunkt.
- Krit-Treffer, Gift, Magie — jede neue Mechanik müsste ihre eigene Schadens-Pipeline aufbauen.
- `EventBus.world.damage_dealt` existiert nicht → Floating-Text-UI, Analytics, Achievements sind blind.

---

## Optionen

### Option A: Schaden bleibt verteilt, Erweiterungen ad-hoc
Jede neue Mechanik fügt ihre eigene Berechnung ein.
- ✅ Kein Overhead jetzt
- ❌ Kein zentraler Punkt für Resistenzen, Krit-Chance, StatModifier
- ❌ Logging, UI, Analytics müssen N verschiedene Stellen beobachten
- ❌ Teuer zu migrieren wenn ein zentrales System nötig wird

### Option B: Schaden komplett in HealthComponent
`take_damage(source, type, raw_amount)` — HealthComponent berechnet alles selbst.
- ✅ Kein neuer Service
- ❌ HealthComponent ist kein Service — kein Zugriff auf StatModifierService oder Krit-Zufall
- ❌ Vermischt Datenhaltung (HP) mit Berechnung (Resistenzen)

### Option C: CombatSystem als Service + DamageRecord als Datenbehälter (gewählt)
`DamageRecord` — unveränderliches Datenobjekt mit `source_id`, `target_id`, `raw_amount`, `damage_type`, `final_amount`, `is_critical`.  
`CombatSystem extends ServiceNode` — berechnet `final_amount` via `calculate_damage()`, wendet via `apply_damage()` an, emittiert `EventBus.world.damage_dealt`.

- ✅ Zentraler Ort für alle Schadens-Transformationen
- ✅ DamageRecord ist beobachtbar (Event) und loggbar
- ✅ StatModifierService-Integration ohne Änderung an HealthComponent
- ✅ Testbar: `CombatSystem.calculate_damage()` ist pure function über `DamageRecord`
- ⚠️ Ein weiterer Service im Boot-Stack

---

## Entscheidung

**Option C.** `DamageRecord` in `scripts/resources/`, `CombatSystem` in `scripts/services/`.

**DamageType-Enum:**
```gdscript
enum DamageType {
    PHYSICAL,  # Durch Rüstung reduziert
    MAGIC,     # Durch magische Resistenz reduziert
    TRUE,      # Ignoriert alle Resistenzen (Gift, Sturz, Reflect)
}
```

**Verarbeitungs-Pipeline in `calculate_damage()`:**
1. `damage_bonus`-StatModifier des Angreifers auf `raw_amount` addieren
2. Krit-Check (nur PHYSICAL + MAGIC, nicht TRUE)
3. Resistenz-Mitigation: `final = raw * (1.0 - mitigation)` — Mitigation max 0.85 (nie Immunität)
4. Clamp auf `MIN_DAMAGE = 1.0`
5. `record.final_amount` setzen

**IEntityContext:** `get_combat_system() -> CombatSystem` hinzugefügt — EnemyNPC nutzt `_ctx.get_combat_system()`.

---

## Konsequenzen

### Positiv
- `EventBus.world.damage_dealt(record)` — ein Signal, alle Beobachter (Floating-Text, Logger, Analytics)
- `CombatSystem.player_melee_damage()` / `enemy_melee_damage()` zentralisieren die Angriffs-Formeln für beide Richtungen (TD-11)
- Resistenz-Profile pro Entity-Klasse (`CombatProfile`-Resource) wurden ohne Breaking Change ergänzt (TD-10) — `calculate_damage()` selbst blieb unverändert
- `DamageRecord.make_environmental()` für Sturz/Gift/Reflect ohne Angreifer-Quelle

### Negativ / Risiken
- `EnemyNPC._on_interacted()` braucht `IEntityContext` für CombatSystem-Zugriff — Fallback für Testumgebungen ohne ctx nötig
- ~~Resistenz-Werte werden aktuell als Parameter übergeben (`target_armor: float = 0.0`) — kein Resistenz-Profil pro Entity-Typ.~~ Behoben in Session 5 (TD-10). `calculate_damage(record, target_armor, target_magic_resist)` bleibt als reine Zwei-Floats-Funktion bestehen (Testbarkeit ohne DataService), `calculate_damage_with_profile()` ist der neue bevorzugte Einstiegspunkt für Entity-Code.
- ~~`roll_critical()` würfelt über das globale `randf()` ohne injizierbare RNG-Quelle — `calculate_damage()` ist dadurch nicht vollständig deterministisch testbar.~~ Behoben in Session 6 (TD-13) — siehe unten.

### Bekannter Tech Debt
- **TD-10 ✅ Behoben (Session 5):** Resistenz-Profile per Entity-Klasse — `CombatProfile`-Resource (`armor` + `magic_resist`, zwei benannte Floats statt `Dictionary[DamageType, float]`, siehe CombatProfile.gd für die Begründung) plus `DataService.get_combat_profile()` / `res://data/combat_profiles/*.tres`.
- **TD-11 ✅ Behoben (Session 5):** `EnemyNPC._do_melee()` läuft jetzt über `CombatSystem.enemy_melee_damage()` + `calculate_damage_with_profile()` + `apply_damage()` — kein direktes `hc.take_damage()` mehr. Krit-Check, Resistenz und `EventBus.world.damage_dealt` greifen jetzt auch für Enemy→Spieler-Schaden.
- **TD-12 ✅ Behoben (Session 6):** Status-Effekte (Gift-Tick, Burn) — `StatusEffect.gd` (Datencontainer, gleiches Muster wie `StatModifier.gd`) + `CombatSystem.apply_poison()`/`apply_burn()`/`remove_status_effect()`/`on_tick()`. Tickt via `_ticker.register_service(self)` (Ticker per `ServiceDeps.get_optional(ServiceKeys.TICKER)` injiziert, gleiches Muster wie `RespawnService`), kein eigener Timer-Node. Schaden läuft über `DamageType.TRUE` (ignoriert Resistenz, konsistent mit dem bestehenden DamageType-Kommentar "Gift, Sturz, Reflect"). Kein Stacking — gleiche source_id/target_id/Kind-Kombination überschreibt und setzt die Restdauer zurück (Konvention aus `StatModifierService.add_modifier()` übernommen). **Bewusst NICHT verdrahtet** mit `EnemyAttack`/Player-Waffen — reines Fundament wie TD-10/TD-11 in Session 5, Integration in konkrete Angriffe ist eine künftige Feature-Session.
- **TD-13 ✅ Behoben (Session 6):** `roll_critical()` nutzt jetzt einen injizierbaren `RandomNumberGenerator` (`_rng`, Default: randomisierte Eigeninstanz). `configure({"rng": seeded_rng})` macht `calculate_damage()`/`roll_critical()` vollständig deterministisch testbar — siehe `test_roll_critical_is_deterministic_with_same_seed()`. Bestehende Tests, die produktionsnahes (nicht-deterministisches) Verhalten prüfen wollen, nutzen weiterhin `configure({})` und das Krit-Toleranzband (`_assert_damage_matches_expected_or_crit()`) — der Determinismus ist jetzt optional, nicht erzwungen.

---

## Ablösung

Dieser ADR wird durch einen Combat-V2-ADR abgelöst wenn PvP-Schaden implementiert wird oder Status-Effekte (TD-12) tatsächlich in konkrete Angriffe (Gift-Waffen, Feuer-Fallen, Skill-Effekte) integriert werden — das reine Fundament aus Session 6 zählt nicht als dieser Trigger, da es noch keine echte Spielmechanik anstößt. Resistenz-Profile (TD-10) sind seit Session 5 Teil dieses ADRs, kein separater Trigger mehr.

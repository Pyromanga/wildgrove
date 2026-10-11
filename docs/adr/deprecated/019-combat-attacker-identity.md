> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-019: Angreifer-Identität im CombatSystem (Killer-Attribution)

**Status:** Akzeptiert — Option B, umgesetzt.
**Datum:** 2026-07
**Kontext:** Betrifft `CombatSystem`, `DamageRecord`, `HealthComponent`, `EnemyNPC._on_interacted()`/`_die()`.
Direkte Folge aus Schritt 2 (`loot_collected`/`xp_gained`/`level_up` um `player_id`
erweitert, siehe [ADR-015](015-local-player-identity.md)): dort wurde bewusst
**nicht** versucht, `EnemyNPC._die()` einen echten `player_id` mitzugeben, weil die
Information an der Wurzel nicht existiert — dieses ADR schließt genau diese Lücke.

---

## Problem

**1. `HealthComponent.died` ist ein parameterloses Signal.**

`scripts/entities/combat/HealthComponent.gd:8`:
```gdscript
signal died
```
Es transportiert keinerlei Information darüber, wodurch der Tod verursacht wurde.
`EnemyNPC._die()` (verbunden über `_health.died.connect(_die)`,
`EnemyNPC.gd:236`) hat dadurch strukturell keine Möglichkeit, den Killer zu
kennen — selbst wenn `CombatSystem` ihn irgendwo hätte.

**2. `CombatSystem.player_melee_damage(player_id: String)` bekommt nie eine echte peer_id.**

`scripts/entities/combat/CombatSystem.gd:201`. Der Parameter heißt `player_id`,
ist aber ein `String`, und `EnemyNPC._on_interacted()` — das seit ADR-015 Phase 4
den echten (int) `player_id` des angreifenden Spielers als Parameter bekommt —
übergibt ihn nicht, sondern den hartcodierten String-Literal `"player"`:

```gdscript
# EnemyNPC.gd:104, 128
func _on_interacted(action_id: String, _player_id: int) -> void:
    ...
    var record: DamageRecord = combat.player_melee_damage("player")
```

Der reale `player_id` liegt buchstäblich einen Parameter-Unterstrich entfernt
ungenutzt daneben — dasselbe Muster wie bei `RewardDispatcher.dispatch()` in
Schritt 2, nur eine Ebene tiefer.

**3. `DamageRecord.source_id` (String) ist bereits doppelt belegt.**

`source_id` dient heute gleichzeitig als (a) Entity-Typ-Label für Logging
(`"enemy_melee"`, `"player"`) und (b) das einzige Feld, über das man theoretisch
eine Angreifer-Identität transportieren könnte. Diese Vermischung ist der
eigentliche Grund, warum Punkt 2 nicht einfach "der String wird halt zur
peer_id" gelöst werden kann — `source_id` müsste dann für zwei unvereinbare
Zwecke gleichzeitig geradebiegen werden.

**4. Neuer Fund (beim Nachverfolgen von Punkt 2): Schadensberechnung selbst liest den falschen Skill-Level.**

`CombatSystem.player_melee_damage()`, Zeile 203–204:
```gdscript
if is_instance_valid(_skill_system):
    base_dmg += _skill_system.get_level("combat") * 2.0
```
Ohne `player_id`-Argument liest das immer Spieler 1's `combat`-Level. Das ist
kein Xp/Loot-Attributionsproblem mehr, sondern ein Balance-Bug: Spieler B's
Waffenschaden basiert auf Spieler A's Skill-Fortschritt, sobald A Host ist.
Gehört in denselben Fix, weil die Wurzel identisch ist (fehlender `player_id`
an derselben Call-Site).

**Konkreter Effekt heute:** `EnemyNPC._die()` muss `player_id` für
`emit_xp`/`emit_loot_collected` auf dem Default 1 belassen (siehe Kommentar dort,
Schritt 2) — nicht weil das jemand vergessen hat, sondern weil es keinen Wert
gibt, den man dort ehrlich eintragen könnte. Jeder Kill in Coop wird aktuell
Spieler 1 gutgeschrieben, unabhängig davon, wer den Todesschlag geführt hat.

---

## Optionen

### Option A: Mutable "letzter Angreifer"-Feld auf EnemyNPC

`EnemyNPC._on_interacted()` speichert den `player_id` aus seinem bereits
korrekten Parameter in einem neuen Feld (`_last_attacker_player_id: int`).
`_die()` liest dieses Feld statt eines Default-Werts.

- ✅ Kleinster Diff — kein Signal, kein `DamageRecord`-Feld, `HealthComponent`
  bleibt unangetastet.
- ❌ Modelliert Kill-Attribution als Nebenzustand am Entity statt als Teil des
  Ereignisses, das den Tod tatsächlich verursacht hat. Funktioniert nur solange
  "letzter Interaktions-Treffer" und "todesursächlicher Treffer" identisch sind
  — bricht sobald ein zweiter Schadenskanal existiert (z.B. Gift-Tick von
  Spieler A tötet, nachdem Spieler B zuletzt zugeschlagen hat: `_die()` würde
  fälschlich B zuschreiben).
- ❌ Löst Punkt 3 (Wurzel: `source_id` ist überladen) nicht — nur ein weiterer
  Ort, der um dasselbe Konzept herumbaut statt es sauber zu benennen.

### Option B: `DamageRecord` bekommt echtes Attribution-Feld, `HealthComponent.died` trägt den finalen Record

- `DamageRecord.attacker_player_id: int = -1` (neues Feld, getrennt von
  `source_id` — `source_id` behält seine bestehende Logging-Rolle unverändert).
- `CombatSystem.player_melee_damage(player_id: int)` neu typisiert, echte
  `player_id` von `EnemyNPC._on_interacted()` durchgereicht — inkl. an
  `_skill_system.get_level("combat", player_id)` (behebt Punkt 4 im selben Zug).
- Neue Methode `HealthComponent.take_damage_record(record: DamageRecord)` —
  **bereits als Zielzustand dokumentiert** in `DamageRecord.gd:8`
  (`"HealthComponent.take_damage_record(record) → wendet final_amount an"`),
  nur nie gebaut. `CombatSystem.apply_damage()` ruft diese statt
  `hc.take_damage(int(record.final_amount))` auf.
- `died`-Signal wird zu `died(record: DamageRecord)`. Für Tode ohne Record
  (direkte `take_damage(amount)`-Aufrufe, z. B. in bestehenden Tests) wird
  `null` emittiert — Consumer müssen das behandeln.
- `EnemyNPC._die(record: DamageRecord)` liest `record.attacker_player_id`
  direkt aus dem todesursächlichen Treffer.

**Geprüfte Blast-Radius-Frage — wer hängt an `died`?**
Nur zwei Consumer im gesamten Code: `EnemyNPC._die()` (`EnemyNPC.gd:236`) und
`Player._on_player_died()` (`Player.gd:60`). Da Godot einem verbundenen
Callable mit weniger Parametern als das Signal emittiert einfach die
überzähligen Argumente vorenthält (kein Fehler), bleibt `Player._on_player_died()`
unverändert lauffähig — nur `EnemyNPC._die()` muss die neue Signatur annehmen,
weil es die Information tatsächlich braucht.
`take_damage(amount: int)` (die einfache, direkte API) bleibt unverändert
bestehen — sie wird von vielen Tests direkt aufgerufen
(`test_enemy_npc_pool_reuse.gd`, `test_combat_system.gd`, `test_player_gd.gd`)
und von `Player.gd`s eigenem Fallback-Schadenspfad. Sie emittiert bei Tod
weiterhin `died(null)`, kein Test-Bruch.

- ✅ Killer-Info reist mit dem Ereignis, das den Tod tatsächlich verursacht hat
  — kein Rennen zwischen "letzter Treffer" und "tödlicher Treffer".
- ✅ Behebt Punkt 4 (Skill-Level-Bug) im selben, thematisch identischen Schnitt.
- ✅ Verifizierter kleiner Blast-Radius (nur 1 von 2 `died`-Consumern muss sich ändern).
- ⚠️ Größerer Diff als Option A: neues `DamageRecord`-Feld, neue
  `HealthComponent`-Methode, `CombatSystem.player_melee_damage()`-Retyping.
- ⚠️ `null`-Record-Fall (direkter `take_damage()`-Aufruf) muss von `EnemyNPC._die()`
  sauber behandelt werden (Fallback auf Default 1 + Log-Warnung, nicht crashen).

### Option C: Wie B, aber ohne Signal-Signaturänderung — `get_last_damage_record()`-Getter statt Signal-Parameter

Statt `died(record)` zu emittieren, speichert `HealthComponent` den finalen
Record intern (`_last_damage_record`) und stellt ihn per Getter bereit.
`died` bleibt parameterlos; `EnemyNPC._die()` ruft `_health.get_last_damage_record()`
ab, statt ihn als Signal-Argument zu bekommen.

- ✅ Keinerlei Signal-Signaturänderung — noch kleinerer Blast-Radius als B.
- ❌ Implizite "lies-nach-dem-Signal"-State-Kopplung statt expliziter
  Datenweitergabe — Reihenfolge-Abhängigkeit (Getter muss VOR dem nächsten
  `take_damage_record()`-Aufruf gelesen werden), obwohl in der Praxis durch
  synchrones `_die()` innerhalb desselben Frames unkritisch.
- Kein klarer Vorteil gegenüber B, seit die Blast-Radius-Prüfung oben zeigt,
  dass B ohnehin nur einen Consumer betrifft. C spart eine Signalsignatur, kauft
  sich dafür eine weniger explizite API ein.

---

## Entscheidung

**Option B**, wie empfohlen. Der Blast-Radius war geprüft und klein (ein
einziger Consumer musste angepasst werden), das Modell ist korrekt (Killer-Info
hängt am Todes-Ereignis, nicht an einem separaten mutierbaren Feld), und Punkt 4
(Skill-Level-Bug) wurde im selben, ursächlich identischen Schnitt mitbehoben
statt als eigener Fund liegen zu bleiben.

**Die drei vor Umsetzung offenen Fragen wurden wie folgt entschieden:**

1. **Soll `attacker_player_id` auch für `enemy_melee_damage()` gesetzt werden?**
   Nein — bleibt `-1`. Ein Gegner ist kein Spieler; `-1` ("kein Spieler-Angreifer")
   ist hier keine offene Lücke, sondern der korrekte Wert. Der Parameter existiert
   trotzdem an `make_enemy_attack()`, damit ein künftiger PvP-Pfad (ein Spieler
   steuert die angreifende Entity) dieselbe Factory nutzen kann.

2. **Wie soll `EnemyNPC._die()` auf `record == null` reagieren?**
   Default 1 mit `AppLogger.log_warn()` — dokumentiert als erwarteter Fall bei
   direktem `take_damage()`-Testaufruf ohne CombatSystem-Pfad, nicht als stiller
   Fallback. Derselbe Code-Pfad behandelt zusätzlich `record.attacker_player_id
   == -1` (Record vorhanden, aber kein Spieler-Angreifer bekannt) identisch.

3. **Betrifft dieselbe Lücke `apply_poison()`/`apply_burn()`?**
   Ja. `attacker_player_id` wurde bis in `StatusEffect` und von dort in jeden
   Tick-`DamageRecord` (`CombatSystem.on_tick()`) durchgereicht. Ein Gift-/
   Brand-Tick, der ein Ziel tötet, bekommt jetzt denselben Killer wie der
   ursprüngliche Waffentreffer, der den Status-Effekt ausgelöst hat.

**Umsetzung (Kurzüberblick):**
- `DamageRecord.attacker_player_id: int = -1`, gesetzt über neue optionale
  Parameter an `make_player_attack()`/`make_enemy_attack()`/`make_environmental()`.
- `HealthComponent.died(record: DamageRecord)` + neue `take_damage_record(record)`;
  `take_damage(amount)` bleibt unverändert und emittiert weiterhin `died(null)`.
- `CombatSystem.apply_damage()` ruft `take_damage_record()` statt `take_damage(int(...))`.
- `CombatSystem.player_melee_damage(player_id: int)` — retypt von `String` auf
  `int`, liest `_skill_system.get_level("combat", player_id)` (behebt Punkt 4).
- `apply_weapon_on_hit()`/`apply_poison()`/`apply_burn()`/`StatusEffect.make()`
  bekommen einen optionalen `attacker_player_id: int = -1`-Parameter.
- `EnemyNPC._on_interacted(action_id, player_id)` gibt `player_id` jetzt echt
  weiter statt `"player"` zu hardcoden; `_die(record: DamageRecord = null)`
  liest die Killer-Identität aus dem Record.

## Konsequenzen

### Positiv
- Schließt die von ADR-015/Schritt 2 bewusst offen gelassene Lücke bei
  `EnemyNPC._die()` — Coop-Kills werden dem tatsächlichen Killer gutgeschrieben.
- Behebt nebenbei einen bisher unbenannten Fairness-Bug (Schadensberechnung
  las fremden Skill-Level).
- `DamageRecord.gd`s eigener Kommentar zu `take_damage_record()` ist eingelöst
  statt als toter Verweis auf eine nie gebaute Methode stehen zu bleiben.
- Punkt 3 aus der Problem-Sektion (Status-Effekte als zweite, kleinere Version
  derselben Lücke) ist im selben Zug mitbehoben, nicht separat offen geblieben.

### Negativ / Risiken
- Signatur-Änderung an `HealthComponent.died` — geprüfter Blast-Radius war klein
  (nur `EnemyNPC._die()` musste sich anpassen, `Player._on_player_died()` läuft
  dank Godots Signal-Callable-Arity unverändert), aber jeder künftige neue
  Consumer muss die `record`-Möglichkeit kennen (Dokumentation am Signal).
- **Noch offen (unverändert seit Entwurf):** Kein laufendes Multiplayer-Setup
  hier zum Verifizieren von Tier 2/3 — sollte, wie ADR-015, vor "vollständig
  abgeschlossen" mit zwei echten Clients getestet werden (siehe
  `TODO-offene-probleme.md`, Punkt "Kein echter Zwei-Peer-Integrationstest").
  Die hier umgesetzte Logik ist Tier-1-verifiziert (Unit-Tests), nicht gegen
  echte Peer-zu-Peer-RPCs.

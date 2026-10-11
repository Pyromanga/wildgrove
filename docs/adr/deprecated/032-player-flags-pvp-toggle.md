> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-032: Player-Flags & PvP-Toggle (Skull-System)

**Status:** Umgesetzt (Round 88) — siehe Umsetzungsstand unten
**Datum:** 2026-07
**Kontext:** Baut auf ADR-030 (Zonen) und ADR-031 (Permissions) auf.
Fundament für ADR-036 (PvP-Tod-Verlust). Neu: `PvPService`, `PlayerFlags`
(State pro Spieler).

## Problem

Es gibt keinerlei PvP-Zustand im Spiel. Gebraucht wird eine
serverautoritative Entscheidung "ist Spieler X gerade PvP-angreifbar" plus
ein Reputationsmechanismus (Skull), der unfaires/unprovoziertes Verhalten
sanktioniert, ohne Gegenwehr in laufenden Kämpfen zu bestrafen.

## Optionen

### Option A: Reines binäres Flag, keine Skull-Mechanik
Global an/aus, keine Verhaltens-Konsequenz.
- ✅ Trivial
- ❌ Kein Schutz gegen Griefing, keine Basis für ADR-036s
  Verlust-Differenzierung

### Option B: Skull-System mit unprovoziertem-Angriff-Trigger (gewählt)
Wie beschrieben unten.
- ✅ Deckt Griefing-Schutz + Verlust-Differenzierung aus einer Datenquelle ab
- ❌ Mehr State (Combat-Consent-Paare) als eine reine bool-Lösung

## Entscheidung

### PvP-Aktivierung
`PvPService.is_pvp_active(player_id) := global_pvp_enabled
AND NOT PermissionService.has_capability(player_id, "pvp_immune")
AND current_zone.has_tag("pvp")`

Alle drei Bedingungen serverseitig geprüft (ADR-030/031 liefern die Bausteine).

### Skull-Trigger
- Jeder ankommende Schaden (auch AoE/Fernkampf-Streuschaden) von Spieler A
  gegen Spieler B zählt als Angriff.
- Skull-Dauer: fest **20 Minuten**. Die entscheidende Bedingung fürs
  Zurücksetzen ist nicht "neuer Trigger" allgemein, sondern **ob das Opfer
  sich bereits gewehrt hat**:
  - Solange Opfer B **noch keinen** Schaden gegen Angreifer A ausgeteilt hat,
    gilt jeder weitere Treffer von A gegen B als frischer, unprovozierter
    Angriff — `skull_until` von A wird bei **jedem** Treffer auf
    `jetzt + 20 min` zurückgesetzt. Ein reiner Einbahnstraßen-Angriff
    (B wehrt sich nie) hält A also dauerhaft neu geskullt.
  - Sobald B **zum ersten Mal** zurückschlägt (Schaden in beide Richtungen
    ist geflossen), gilt das Gegenwehr-Fenster als eröffnet: von da an lösen
    weitere Treffer zwischen A und B **keinen** neuen Skull-Trigger mehr aus.
    Der zuletzt gesetzte `skull_until`-Wert läuft ab diesem Moment einfach
    weiter herunter — unabhängig davon, ob der Kampf weitergeht.
  - Läuft die Zeit ab, während beide immer noch kämpfen, verliert A den
    Skull-Status **mitten im laufenden Kampf** — kein Sonderfall, keine
    Verlängerung durch fortgesetztes Fighting.
- Wiederholtes Skullen (ein neuer, unprovozierter Angriff auf ein anderes
  Opfer, oder erneut auf dasselbe Opfer nach Ablauf des Gegenwehr-Fensters)
  ist jederzeit möglich.
- **Freiwilliges Skullen:** Spieler können sich selbst skullen (für erhöhte
  Loot-Chance bei eigenem PvP-Tod, siehe ADR-036) — gleicher Flag, andere
  Ursache.

### Safe-Zone-Vulnerabilitäts-Fenster (Anti-Escape)
Spieler mit `is_skulled == true` **oder** Aura unterhalb der Schwelle
(ADR-036) bleiben nach Betreten einer Safe-Zone (Zonen-Tag `"safe"`) noch
**10 Sekunden** angreifbar, bevor der normale Safe-Zone-Schutz greift. Das
verhindert reines Reinrennen in Sicherheit als Fluchtstrategie.

### Datenmodell
`PlayerFlags` (pro `player_uuid`, nicht `peer_id` — überlebt Reconnects wie
ADR-029):
- `skull_until: float` (Unix-Timestamp, 0 = kein Skull)
- `skull_is_voluntary: bool`
- `safe_zone_grace_until: float` (0 = kein aktives Vulnerabilitäts-Fenster)

`CombatConsent` (transienter World-Scope-State, kein Save-Daten):
- `Dictionary[PackedStringArray, ConsentEntry]` — Paar-Schlüssel →
  `{ a_has_hit_b: bool, b_has_hit_a: bool, last_damage_timestamp: float }`.
  Das Fenster gilt erst als "eröffnet" (keine neuen Skull-Trigger mehr),
  sobald **beide** Richtungen mindestens einmal Schaden verzeichnet haben —
  reiner einseitiger Dauerbeschuss löst also weiterhin bei jedem Treffer neu
  aus (siehe Entscheidung oben).

## Konsequenzen

### Positiv
- Einheitliche Quelle für PvP-Angreifbarkeit, wiederverwendbar in ADR-036
- Gegenwehr-Schutz verhindert, dass Verteidiger für ihre eigene
  Selbstverteidigung bestraft werden

### Negativ / Risiken
- `CombatConsent`-Dictionary kann bei vielen gleichzeitigen Kämpfen wachsen —
  braucht periodisches Aufräumen abgelaufener Einträge (TTL-Cleanup)
- Formel/Bedingungen für "schlechte Aura" sind hier nur referenziert, nicht
  definiert — Details in ADR-036

### Mitigationen
- `CombatConsent`-Cleanup über denselben periodischen Tick, der ohnehin für
  andere transiente World-State-Aufräumarbeiten existiert (o. ä. Muster wie
  Rate-Limiter-Fenster in `NetworkBridge`, Round 48). Konkret: ein Eintrag
  gilt als aufräumbar, sobald `last_damage_timestamp` länger als die
  Skull-Dauer (20 Minuten) zurückliegt — zu diesem Zeitpunkt ist ohnehin
  jeder mögliche Skull aus diesem Paar bereits abgelaufen, der Eintrag hat
  also keinen Erkenntniswert mehr. Aufräum-Tick-Intervall: z. B. alle 5
  Minuten über alle Einträge iterieren und abgelaufene entfernen.

## Umsetzungsstand (Round 88)

- `PvPService` (`scripts/world/pvp/PvPService.gd`): `is_pvp_active()`,
  Skull-Trigger (`report_pvp_damage()`) mit Gegenwehr-Fenster-Logik exakt wie
  oben spezifiziert, freiwilliges Skullen, Safe-Zone-Vulnerabilitäts-Fenster
  (per `zone_entered`-Event, kein direkter ZoneService→PvPService-Dep, um
  keinen Zyklus zu erzeugen), `CombatConsent`-Cleanup alle 5 Minuten.
- Persistenz über `SaveSystem` (`PlayerFlags`, player_uuid-gekeyt), abgelaufene
  Skulls werden nicht mit gespeichert.
- `SpawnSafeZonePlacer` (neu) platziert eine `"safe"`-getaggte Zone um den
  Weltspawn — ohne die wäre das Vulnerabilitäts-Fenster inert gewesen, da
  vorher keine einzige `"safe"`-Zone in der Welt existierte.
- **Round 88 Nachtrag:** `resolve_pvp_hit()` hat jetzt einen echten Aufrufer —
  `Player.gd` bekommt über `PlayerAttack.setup_interactable()` dieselbe
  `InteractableComponent`/`InteractionSensor`-Andockstelle wie `EnemyNPC`
  (Gruppe `"interactable"`, Interaktion `"attack_player"`). Ein Spieler kann
  jetzt einen anderen Spieler anvisieren und angreifen; Schaden läuft über
  denselben `player_melee_damage()`-Pfad wie PvE, nur das Ziel-Resistenzprofil
  und das Gate (`resolve_pvp_hit()` statt `apply_damage()`) unterscheiden sich.
  Kein Client-Prediction-Zweig für PvP-Treffer (bewusst, siehe Kommentar in
  `Player._on_interacted()`) — Treffer fühlen sich für Angreifer auf Tier 2/3
  minimal verzögert an, dafür lügt kein optimistisches Hit-Feedback über einen
  serverseitig verweigerten Treffer.
- `pvp_immune`-Capability existierte bereits auf der Admin-Rolle (ADR-031),
  kein Rollen-Update nötig.

## Ablösung

—

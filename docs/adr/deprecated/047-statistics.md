> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-047: Statistiken (Vorstufe für stat-basierte Achievements)

**Status:** Angenommen — umgesetzt (Round 103)
**Datum:** 2026-07
**Kontext:** Explizite Anforderung — "Achievements für Statistiken: Meter
gelaufen, Meter gesprungen, Meter gefallen, Anzahl NPCs getötet", mit der
korrekten Vorab-Einschätzung, dass dafür zuerst ein Statistik-System nötig
ist. Dieses ADR liefert genau das.

## Entscheidung

`StatsService` (`scripts/progression/stats/StatsService.gd`) — kumulative,
pro Spieler geführte Zähler, kein festes Schema (`add_stat(player_id,
stat_name, delta)` akzeptiert jeden `stat_name`-String). Vier Konstanten
für die aktuellen Größen: `STAT_METERS_WALKED`, `STAT_METERS_JUMPED`,
`STAT_METERS_FALLEN`, `STAT_NPCS_KILLED`.

### Zwei autoritative Quell-Signale

1. **NPC-Kills** — `EventBus.world().enemy_killed` (bereits bestehend,
   bereits von `QuestService` für Kill-Objectives genutzt). Derselbe
   Vertrauens-Präzedenzfall: `EnemyNPC._die()` läuft nur dort, wo
   tatsächlich Schaden autoritativ appliziert wurde.

2. **Bewegung** (Meter gelaufen/gesprungen/gefallen) — neues Signal
   `PlayerEvents.movement_stats_batch(peer_id, walked_m, jumped_m,
   fallen_m)`, emittiert aus `Player.gd._track_movement_stats()`.

### Bewegungs-Tracking — wo und warum genau dort

Das Projekt nutzt server-autoritative Bewegung mit Client-Prediction/
Reconciliation (ADR-025/026): der Client sendet Input, die Autorität
repliziert densel­ben `PlayerMover.calculate_velocity()`-Aufruf und hat
damit eine echte, vertrauenswürdige Position — kein Client-Trust-Problem.
`_track_movement_stats()` wird deshalb **ausschließlich** in
`_loop_free_authoritative()` aufgerufen (nie in `_loop_free_predicted()`/
`_resimulate_from()`, die Client-Prediction-Zweige) — sonst würde bei
jedem Reconciliation-Replay doppelt/falsch gezählt, oder ein Client könnte
über manipulierte lokale Prediction Fortschritt fälschen.

Berechnung pro Tick (reine Zusatz-Buchführung, `pos_before`/`was_on_floor`
werden vom Aufrufer übergeben, keine Änderung an bestehendem
Physik-/Reconciliation-Code):
- **Gelaufen:** horizontale Distanz, wenn der Spieler zu Beginn des Ticks
  auf dem Boden war.
- **Gesprungen:** vertikaler Aufstieg, während der Spieler in der Luft ist.
- **Gefallen:** vertikaler Abstieg, während der Spieler in der Luft ist.

**Bewusste Approximation:** kein Unterschied zwischen einem kurzen Hüpfer
und einem echten Fallschaden-Sturz — beides zählt als "gefallen". Eine
präzisere Unterscheidung (z. B. nur ab einer Mindesthöhe) wäre ein
sinnvoller Folge-Schritt, aber kein Blocker für einen ersten Wurf.

**Gebündelt statt pro Tick:** die drei Werte werden lokal in `Player.gd`
akkumuliert und nur alle `STAT_FLUSH_INTERVAL_SEC` (5 Sekunden) als EIN
Signal geflusht — bei ~60 Ticks/Sekunde sonst 60 Signale/Sekunde pro
Spieler, unnötiger Overhead für einen reinen Statistik-Zweck.

### Risikobewertung dieses spezifischen Eingriffs

`Player.gd` ist die reconciliation-kritischste Datei im Projekt (Movement-
Prediction, läuft auf jedem Tick für jeden Spieler). Der Eingriff wurde
deshalb bewusst MINIMAL und rein additiv gehalten: neue Felder
(`_stat_*_accum`), ein neuer Funktionsaufruf am Ende von
`_apply_movement()`, keine Änderung an `velocity`, `move_and_slide()`,
Input-Verarbeitung, Reconciliation-Puffer oder Zeitstempel-Logik. Ohne
Godot-Editor/Headless-Runner in dieser Entwicklungsumgebung ließ sich das
nicht gegen echte Physik verifizieren — siehe "Ehrlich offen" unten.

### peer_id → player_id

Beide Quell-Signale liefern `peer_id: int`, keine `player_id: String` —
Übersetzung via `NetworkBridge.get_player_id_for_peer()`, identisches
5-Zeilen-Muster wie `QuestService._resolve_player_uuid()`/
`RewardDispatcher._resolve_player_uuid()` (bewusst keine gemeinsame
Utility für eine weitere Call-Site, siehe dortige Diskussion aus Round 63).

### Verbindung zu Achievements

`stat_changed(player_id, stat_name, delta, new_total)` ist die vierte
Trigger-Quelle für `AchievementService` (siehe
[ADR-046 „Umsetzungsstand (Round 103)"](046-achievement-system.md)).

## Optionen (verworfen)

- **Client-seitig gemeldete Bewegungsdistanz** (Client rechnet selbst,
  meldet nur das Ergebnis) — verworfen: unnötig, da die Autorität die
  Position bereits selbst berechnet (siehe oben) — ein Client-Report wäre
  hier redundant UND eine unnötige Vertrauens-Schwächung gegenüber dem
  bereits etablierten Modell.
- **Stat-Tracking pro Tick statt gebündelt** — verworfen wegen
  Signal-/Log-Spam bei ~60 Ticks/Sekunde/Spieler.
- **Generische Utility-Funktion für `peer_id → player_id`** (statt
  Duplizierung des 5-Zeilen-Musters) — bereits in Round 63 diskutiert und
  verworfen (siehe dortige Notiz), hier konsistent fortgeführt.

## Konsequenzen

### Positiv
- Erste konkrete Nutzung von `enemy_killed` außerhalb von `QuestService` —
  bestätigt, dass das Signal generisch genug für mehrere Konsumenten ist.
- Kein festes Stat-Schema — künftige Stats (Angel-Fänge, Ernte-Mengen,
  Handwerk-Anzahl) sind einfach neue `add_stat()`-Aufrufer, kein
  struktureller Umbau.

### Negativ / Risiken
- Der `Player.gd`-Eingriff ist der bislang riskanteste Codepfad, der in
  dieser Session blind bearbeitet wurde — siehe "Risikobewertung" oben.
  Additiv/isoliert gehalten, aber nicht gegen echte Physik verifizierbar.
- "Gefallen" zählt jeden Abstieg aus der Luft, nicht nur echten
  Fallschaden — siehe "Bewusste Approximation" oben.

## Bewusst nicht Teil dieser Runde

- Kein Snapshot-/Sync-Pfad für spät joinende Clients (analog
  `AchievementService`s eigener, ebenfalls fehlender Sync-Pfad vor Round
  103 — hier gar nicht erst begonnen).
- Kein UI-Panel/Statistik-Anzeige, kein `UIContext`-Eintrag.
- Keine weiteren Stat-Quellen über die zwei genannten hinaus.
- Keine präzisere Fall-vs-Sprung-Unterscheidung (Mindesthöhe für
  "gefallen").

**Ehrlich offen:** wie in jeder Runde seit 89 — kein Godot-Editor/
Headless-Runner in dieser Entwicklungsumgebung verfügbar, nur strukturell
geprüft. Der `Player.gd`-Eingriff ist davon am stärksten betroffen — er
wurde bewusst minimal/additiv gehalten, um das Risiko zu begrenzen, aber
ein Test gegen echte Godot-Physik (Sprünge, Stürze, Kollisionen,
Reconciliation unter Latenz) steht aus und sollte vor einem Produktions-
Einsatz nachgeholt werden.

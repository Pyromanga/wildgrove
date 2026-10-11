> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-037: PvE-Tod-Loot (Grab-Hybrid-Timer)

**Status:** Vorgeschlagen — Entwurf, Round 68 Folge-Session
**Datum:** 2026-07
**Kontext:** Hängt an ADR-033 (Gold), unabhängig von ADR-032/036 (PvP).
Nutzt PvE-Todesschutz-Kategorie aus ADR-038. Neu: `Gravestone`-Entität,
`DeathLootService`.

## Problem

Stirbt ein Spieler durch PvE (nicht durch einen anderen Spieler), braucht es
einen fairen Mechanismus, verlorene Items wiederzubekommen, ohne dass sie
für immer weg sind oder ewig für andere blockiert bleiben.

## Optionen

### Option A: Items einfach am Boden verstreut (kein Grab-Objekt)
- ✅ Einfachste Umsetzung
- ❌ Kein klarer Besitz-Zeitraum, sofort für alle plünderbar, unübersichtlich
  bei vielen Items

### Option B: Grab-Hybrid-Timer (gewählt, laut ursprünglicher Skizze)
Ein Grabstein-Objekt spawnt am Todesort mit allen verlorenen (nicht
permanent geschützten, siehe ADR-038) Items/Gold.
- Phase 1 — **Personal Loot**: nur der verstorbene Spieler kann das Grab
  öffnen, für einen Zeitraum X
- Phase 2 — **Free-for-all**: nach Ablauf von X wird das Grab für alle
  Spieler plünderbar
- Phase 3 — **Despawn**: nach einem zweiten, längeren Zeitraum Y verschwindet
  das Grab endgültig (Items sind dann weg)
- ✅ Fairer Interimszeitraum für den Verlierer, verhindert aber ewiges
  Blockieren von Loot in der Welt
- ❌ Zwei Timer statt einem, mehr State zu verwalten

## Entscheidung

Option B. `Gravestone`-Entität (Welt-Objekt, serverautoritativ gespawnt über
`WorldService`, ähnlich zu bestehenden Entity-Spawn-Mustern) mit:

- `owner_player_id`, `personal_loot_until: float`, `despawn_at: float`
- Interaktion läuft über das bestehende Interaktionssystem (ADR-020) — Zugriff
  wird serverseitig gegen `owner_player_id`/aktuelle Phase geprüft
- Items/Gold, die laut ADR-038 permanent PvE-todesgeschützt sind, landen
  **nie** im Grab — sie verbleiben im Inventar des Spielers nach Respawn

Vorläufige Werte (Platzhalter, zur Balance-Anpassung in der Umsetzung):
- **X (Personal-Loot-Dauer): 10 Minuten**
- **Y (Gesamt-Despawn ab Todeszeitpunkt): 30 Minuten** — ergibt eine
  Free-for-all-Phase von 20 Minuten zwischen Ablauf von X und Y

## Konsequenzen

### Positiv
- Fairness für den Verlierer ohne dauerhafte Weltverschmutzung durch
  liegengebliebene Grabsteine
- Wiederverwendung des bestehenden Interaktionssystems statt neuer Mechanik

### Negativ / Risiken
- Zwei Timer-Zustände pro Grab bedeuten zusätzliche Zustandsprüfung bei jeder
  Interaktion (Phase-Check)

### Mitigationen
- Phase lässt sich rein aus den beiden Timestamps ableiten (kein separates
  Enum/State-Flag nötig) — reduziert Fehlerquelle auf reine Zeitvergleiche

## Ablösung

—

## Umsetzungsstand (Round 92)

`DeathLootService` und `Gravestone` sind umgesetzt und vollständig verdrahtet
(inklusive der Boot-Reihenfolge-Fallstricke, siehe unten).

### `DeathLootService` (`scripts/entities/combat/DeathLootService.gd`)
- Einziger Einstiegspunkt: `handle_pve_death(player_id, death_position)`,
  aufgerufen von `Player._on_player_died()` sobald der PvP-Zweig (ADR-036)
  NICHT gegriffen hat (`_apply_pvp_death_loss_if_applicable()` gibt jetzt
  `bool` zurück statt `void` — die beiden ADRs sind exklusiv, ein Tod ist
  entweder PvP oder PvE, nie beides).
- **Schutzkategorie:** nur `ItemInstance.is_pve_death_protected` zählt.
  `is_theft_protected`/`is_pvp_protected` sind für einen PvE-Tod irrelevant
  (ADR-038: drei unabhängige Kategorien) — permanent geschützte Items werden
  nie entfernt, landen nie im Grab-Config.
- **Kein Verlust ohne Grab:** Gold/Items werden erst entfernt, NACHDEM
  `WorldService` als verfügbar bestätigt ist — kein Fenster, in dem Besitz
  verloren geht, ohne dass irgendwo ein Grab dafür existiert.
- **Bootstrap-Zyklus-Vermeidung:** `DeathLootService` deklariert bewusst
  KEINE Abhängigkeit auf `world` (weder required noch optional) —
  `WorldService` selbst hängt optional von `death_loot` ab (für
  `EntityContext.get_death_loot()`), ein Rück-Dep hätte einen Zyklus erzeugt.
  Stattdessen injiziert `WorldService` sich direkt per `inject_world()`
  unmittelbar nach dem eigenen `configure()`.
- **Nicht persistiert:** aktive Gräber überleben einen Server-Neustart NICHT
  (kein eigener Save-Key). Bewusste Vereinfachung — ein Neustart während der
  30-Minuten-Frist eines Grabes ist ein seltener Grenzfall. `Gravestone`s
  Timestamps sind reine Unix-Zeiten, eine Save-Erweiterung wäre additiv,
  falls später gewünscht.

### `Gravestone` (`scripts/entities/death/Gravestone.gd`)
- Serverautoritativ gespawnt über `WorldService.spawn_entity("gravestone", ...)`,
  registriert in `WorldEntityRegistry` — bewusst NICHT im
  `ChunkEntitySpawner`-Biome-Pfad (kein natürlich vorkommendes Prop).
- **Phase ohne eigenes Enum:** wie in den "Mitigationen" oben spezifiziert —
  Personal-Loot/Free-for-all/bereits-despawnt wird ausschließlich aus dem
  Vergleich `now` gegen `personal_loot_until`/`despawn_at` berechnet.
- **Eine Interaktion = alles plündern:** anders als z.B. eine Bank wird ein
  Grab in einem Zug komplett geplündert (Gold + alle Items) und despawnt
  danach sofort — bewusst einfach gehalten, keine Teil-Plünderung-UI.
- **Pool-Reuse-Fix:** `Gravestone` wird (anders als dauerhafte NPCs wie
  Bank/Shop) tatsächlich wiederholt gespawnt/despawnt und landet damit im
  `EntityPool`. `_ready()` feuert bei einem wiederverwendeten Node nicht
  erneut — `_clear_visuals()` musste deshalb explizit sowohl
  `_interactable_comp` ALS AUCH die `CollisionShape3D` von der Löschung
  ausnehmen (sonst wäre die Kollision beim zweiten Spawn dauerhaft weg).
  Mit Regressionstest abgedeckt (`test_pool_reuse_keeps_collision_shape`).
- Nutzt `InteractionResolver` bewusst NICHT — dessen Loot-Table-System ist
  für statische, vordefinierte Ressourcen gedacht; ein Grab hat dynamische,
  pro-Instanz-Inhalte (abhängig davon, wer gestorben ist und was verloren
  ging). Direkter Gold-/Item-Transfer über `IEntityContext.get_currency()`/
  `get_inventory()` in `_on_interacted()` stattdessen.

### Nicht Teil dieser Runde
- Kein UI-Hinweis/Kompass-Marker zum eigenen Grab — aktuell nur über die
  Position selbst auffindbar (analog wie andere Welt-Objekte).
- Keine Persistenz aktiver Gräber über einen Server-Neustart hinweg (siehe
  oben).

Tests: `tests/unit/test_death_loot_service.gd`, `tests/unit/test_gravestone.gd`
(beide neu). `test_gravestone.gd` folgt demselben Muster wie
`test_harvestable_entity.gd`/`test_quest_npc.gd` (`add_child_autofree()` +
`EntityContext.for_test()`). **Ehrlich offen:** wie bei Round 89–91 — kein
Godot-Editor/Headless-Runner in dieser Entwicklungsumgebung verfügbar, alles
nur strukturell geprüft. Einmal im Editor testen, bevor mit ADR-039
weitergemacht wird.

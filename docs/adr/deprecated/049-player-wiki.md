> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-049: Spielerbefülltes Wiki

**Status:** Angenommen — umgesetzt (Round 107)
**Datum:** 2026-08
**Kontext:** TODO-Punkt "Spielerbefülltes Wiki" (siehe
`TODO-offene-probleme.md`) — Drop-Rates, Gegner-Übersicht, Skills, Quests
sollen sich WÄHREND des Spielens durch Spieler-Beobachtung selbst befüllen,
nicht vorab von Entwicklerseite geschrieben. Scoping-Fragen vom
Auftraggeber beantwortet:
1. **Geteilt oder pro Spieler lokal?** → pro Spieler lokal.
2. **Wie befüllt sich ein Eintrag konkret?** → automatisch aus vorhandenen
   autoritativen Quellen abgeleitet UND an tatsächliche Entdeckung durch
   den Spieler gekoppelt (kein manuelles Eintragen, kein Full-Unlock beim
   Boot).
3. **Welche Kategorie zuerst?** → alle vier ("enemies", "drops", "skills",
   "quests") in dieser Runde.

## Entscheidung

`WikiService` (`scripts/progression/wiki/WikiService.gd`) — pro Spieler
geführte Menge entdeckter `entry_id`s je Kategorie
(`_discovered[player_id][category] = Array[String]`). Eine `entry_id` ist
immer die domäneneigene ID (CombatProfile-ID, LootTable-Dateiname ohne
`.tres`, SkillDefinition-ID, QuestDefinition-ID) — kein eigenes
Wiki-ID-Schema, um Divergenz von der eigentlichen Datenquelle zu
vermeiden.

### "Pro Spieler lokal" — was das architektonisch bedeutet

Bewusst NICHT als "kein Netzwerkcode" missverstanden. Es bedeutet: derselbe
Per-Player-Bucket + gezielte Ein-Empfänger-RPC wie `AchievementService`,
aber NIE an andere Spieler weitergereicht (kein Auktionshaus-artiges
Broadcast). Der Server entscheidet weiterhin autoritativ (`discover()`
hinter `_require_authority()`), benachrichtigt aber ausschließlich den
betroffenen Spieler selbst — technisch identisch zu
`AchievementService.send_achievement_unlocked_for_player()`, nur dass
"geteilt" hier architektonisch nie vorgesehen ist.

### Drei autoritative Trigger-Quellen

1. **`EventBus.world().enemy_killed(enemy_type_id, position, peer_id)`** —
   bereits bestehend (siehe ADR-047), dritter Konsument nach
   `QuestService`/`StatsService`. Entdeckt sowohl den Gegner
   ("enemies") als auch dessen Loot-Tabelle ("drops", siehe
   `ENEMY_LOOT_TABLE_MAP` unten).
2. **`EventBus.quest().quest_started_for_player(player_id, quest_id)`** —
   NEU in dieser Runde. `QuestEvents.quest_started(quest_id)` trägt keine
   `player_id` (wurde bisher nur von `QuestPanelController` konsumiert,
   die braucht sie nicht). Statt das bestehende Signal zu verändern
   (Breaking-Change-Risiko für den einzigen bisherigen Konsumenten), wurde
   ein zusätzliches Signal ergänzt, emittiert an derselben Stelle
   (`QuestService.on_quest_start_confirmed()`, läuft nur auf der
   Autorität) — kein neuer Trigger-Pfad, nur ein zusätzliches Signal am
   bestehenden.
3. **`SkillSystem.skill_changed(skill_id, player_id)`** — bereits
   bestehend. Feuert sowohl aus `on_xp_add_confirmed()` (Autorität) als
   auch beim Economy-Sync-Empfang auf dem Client selbst. Harmlos für
   `WikiService`: `discover()` läuft trotzdem hinter
   `_require_authority()` — ein Client, der `skill_changed` über den
   Sync-Pfad empfängt, entscheidet hier nichts neu, er bekommt den Unlock
   stattdessen über die eigene gezielte Wiki-RPC von der Autorität.

### Gegner→Loot-Tabelle-Zuordnung (`ENEMY_LOOT_TABLE_MAP`)

Es gibt noch keine strukturierte `EnemyDefinition`-Ressource, die
Gegnertyp auf Loot-Tabelle abbildet — das war in der TODO-Notiz explizit
als offene Frage vermerkt ("sofern es diese Quellen bereits strukturiert
gibt"; siehe auch `EnemyNPC.gd`, wo `_loot_table_id`/`_combat_profile_id`
pro Instanz als Konfigurationsfelder mit Default existieren, aber nicht
zentral registriert sind). Statt für diese Runde eine neue
Ressourcenklasse zu erfinden (Scope-Creep gegenüber dem eigentlichen
Wiki-Auftrag), folgt `ENEMY_LOOT_TABLE_MAP` demselben Muster wie
`AchievementService.DEFAULT_DEFINITIONS`: ein eingebauter, additiv
erweiterbarer Fallback (aktuell nur `"goblin" -> "goblin_loot"`, der
einzige tatsächlich gespawnte Gegnertyp). Für unbekannte Gegnertypen
fällt `_loot_table_for_enemy()` auf die Namenskonvention
`"<enemy_type_id>_loot"` zurück, statt stillschweigend nichts zu
entdecken. Sobald eine echte `EnemyDefinition`-Ressource kommt, ist das
eine additive Erweiterung von `_loot_table_for_enemy()`, kein
Datenmodell-Umbau.

### `get_entry_details()` — reine Lese-Fassade, keine Datenkopie

Liefert Anzeige-Daten für eine `entry_id`, unabhängig davon, ob sie
entdeckt wurde — der Aufrufer (z. B. ein künftiges UI-Panel) filtert
selbst über `is_discovered()`, bevor er etwas anzeigt. Liest ausschließlich
aus `DataService` (`get_combat_profile()`/`get_loot_table()`/
`get_all_skills()`/`get_quest()`) — dieselbe Quelle, die die jeweiligen
Gameplay-Systeme selbst nutzen. Keine eigene Wiki-Datenkopie, bleibt
automatisch aktuell, wenn sich Balance-Werte ändern.

`get_drop_chances(loot_table_id)` berechnet `weight / total_weight` pro
Item als Prozent-Näherung. **Keine exakte Wahrscheinlichkeit** —
`LootTable.roll()`s `max_rolls`-Abbruch (siehe `LootTable.gd`) macht die
tatsächliche Verteilung von der Roll-Reihenfolge abhängig. Für eine
Wiki-Anzeige ausreichend, kein Ersatz für eine Simulation.

### Snapshot-Sync

`request_snapshot()`/`on_snapshot_requested()` +
`NetworkBridge.send_wiki_snapshot_request()`/
`send_wiki_snapshot_for_player()` — Pull-statt-Push für spät joinende/neu
gestartete Clients, exakt das `AchievementService`-Muster (dort erst in
Round 103 nachgezogen; hier gleich in der Grundrunde mitgebaut statt als
eigene Folge-Lücke offen zu lassen).

### Persistenz

`SAVE_KEY = "wiki"` — entdeckte Einträge überleben Sitzungen, Save-
Interface exakt nach `AchievementService`/`StatsService`-Muster.

## Optionen (verworfen)

- **Geteilte, alle-Spieler-Wissensbasis** (analog Auktionshaus-Broadcast)
  — explizit vom Auftraggeber verworfen (siehe "Kontext" oben).
- **Manuelles Eintragen durch den Spieler** — explizit verworfen; die
  Vorgabe war "automatisch abgeleitet UND an Entdeckung gekoppelt", kein
  Wiki-Editor.
- **Neue `EnemyDefinition`-Ressourcenklasse** für die Gegner→Loot-Tabelle-
  Zuordnung — verworfen für diese Runde, siehe "Gegner→Loot-Tabelle-
  Zuordnung" oben. Der eingebaute Fallback ist additiv erweiterbar, ohne
  Migration nötig, sobald diese Ressource kommt.
- **`quest_started(quest_id)` um `player_id` erweitern** statt eines
  zusätzlichen Signals — verworfen, um den einzigen bestehenden
  Konsumenten (`QuestPanelController`) nicht anzufassen; additiv ist
  risikoärmer als ein Signatur-Change an einem produktiv genutzten Signal.

## Konsequenzen

### Positiv
- Vierter Konsument von `enemy_killed` (nach `QuestService`/
  `StatsService`/`AchievementService` via `stat_changed`) — bestätigt
  erneut, dass das Signal generisch genug für mehrere Konsumenten ist.
- Kein neues Trigger-Muster — vollständig aus bereits etablierten
  Bausteinen zusammengesetzt (EventBus-Signale, direkte Service-Signale,
  `_require_authority()`, gezielte RPC-Zustellung, Snapshot-Pull).
- `get_entry_details()` ist bereits vollständig für ein künftiges
  UI-Panel nutzbar — kein Nacharbeiten der Service-API in der Folge-Runde
  nötig (Lehre aus Achievement Round 102→104).

### Negativ / Risiken
- `ENEMY_LOOT_TABLE_MAP` ist ein manuell gepflegter Fallback, kein
  strukturierter Datenquellen-Zugriff — divergiert stillschweigend, wenn
  ein künftiger Gegnertyp weder der Namenskonvention folgt noch hier
  ergänzt wird (bewusst in Kauf genommen, siehe "Gegner→Loot-Tabelle-
  Zuordnung").
- `get_drop_chances()`s Prozentzahlen sind eine Näherung, kein exaktes
  Modell (siehe oben) — bei extremen `max_rolls`-Werten könnte die Anzeige
  spürbar von der tatsächlichen Drop-Häufigkeit abweichen.

## Bewusst nicht Teil dieser Runde

- Kein UI-Panel (analog `AchievementService`: erst Grundgerüst, dann Panel
  in einer Folge-Runde — Round 102→104-Vorbild). `get_entry_details()`
  liefert bereits die vollständigen Anzeige-Daten dafür.
- Keine echte `EnemyDefinition`-Ressource — siehe oben.
- Kein Telemetrie-Event (anders als `AchievementService` — Entdeckungen
  sind kein Balancing-relevantes Ereignis in dieser Runde).
- Kein Zwei-Peer-Integrationstest für den RPC-Rückkanal — wie immer in
  dieser Umgebung nur gegen Spy-/Stub-Doubles geprüft (siehe "Ehrlich
  offen" unten).

**Ehrlich offen:** kein Godot-Editor/Headless-Runner in dieser
Entwicklungsumgebung verfügbar, nur strukturell geprüft. Der RPC-
Rückkanal (`send_wiki_entry_discovered_for_player()`/
`send_wiki_snapshot_for_player()` + die beiden `_rpc_receive_*`-Handler)
ist ausschließlich gegen `SpyNetworkBridge`/`MockEventBus` getestet, nicht
gegen einen echten Zwei-Peer-Roundtrip — derselbe strukturelle Vorbehalt
wie beim Round-106-RPC-Pfad der Charaktererstellung.

## Round 108: UI-Panel

Analog `AchievementService`s eigenem Zwei-Runden-Schnitt (Round 102/103
Grundgerüst → Round 104 Panel). `WikiPanelVisuals`/`WikiPanelController`/
`WikiPanelComponent` (`scripts/progression/wiki/ui/`) — programmatisch
gebaut, identisches Muster wie `AchievementPanelVisuals` (siehe dortiger
Klassenkommentar für die Begründung gegen ein blind gebautes `.tscn`).
Toggle 📖 bei Offset 400–480 (nächster freier Slot nach Skill/Quest/
Achievement), in `HUDBuilder.gd` als `"wiki_panel"` registriert.

### Katalog vs. entdeckte Einträge

`WikiService` kennt nur ENTDECKTE Einträge
(`get_all_discovered(player_id)`) — bewusst kein vollständiger Katalog
aller möglichen Einträge auf Service-Ebene (siehe ADR selbst,
"Entscheidung" oben). Der Controller baut den Katalog stattdessen selbst
aus `DataService` (`get_all_combat_profiles()`/`get_all_loot_tables()`
— Letzteres neu ergänzt, analog den bestehenden `get_all_items()`/
`get_all_quests()`/`get_all_skills()` —/`get_all_skills()`/
`get_all_quests()`). Unentdeckte Zeilen zeigen nur "🔒 ???" (siehe
`WikiPanelVisuals` "UNENTDECKT") — der NAME selbst ist damit aus dem
Katalog technisch ableitbar (derselbe Daten liegen dem Client ohnehin
bereits clientseitig vor, kein zusätzliches Leck gegenüber dem Status
quo), aber bewusst nicht angezeigt, bis `is_discovered()` wahr ist.
Beschreibung/Werte kommen ausschließlich aus `get_entry_details()`, das
der Controller nur bei tatsächlicher Entdeckung abfragt.

**Bewusster Kompromiss:** eine vollständige Verschleierung selbst der
Zeilen-EXISTENZ würde bedeuten, den Katalog serverseitig zu filtern und
den Client bei jeder Entdeckung neu zu befüllen (RPC-Payload pro
Entdeckung statt nur `{category, entry_id}`). Für ein reines
Info-Wiki ohne Wettbewerbs-Charakter (anders als z. B. ein Auktionshaus,
wo Informationsvorsprung einen echten Vorteil bedeutet) nicht den
Mehraufwand wert.

**Geändert (zusätzlich zu den oben genannten neuen UI-Dateien):**
- `scripts/persistence/DataService.gd` — `get_all_loot_tables()` (neu,
  analog `get_all_items()`/`get_all_quests()`/`get_all_skills()`/
  `get_all_combat_profiles()`).
- `scripts/platform/interfaces/IUIContext.gd`/`UIContext.gd` — neuer
  Getter `get_wiki_service()`, analog `get_achievement_service()`.

**Tests:** `tests/unit/test_wiki_panel_controller.gd` (neu, 8 Tests,
analog `test_achievement_panel_controller.gd`).

**Bewusst nicht Teil dieser Runde:** kein `hidden`-Flag, keine
Kategorien-Filter/Sortierung im Panel, kein Zwei-Peer-
Integrationstest (wie immer — nur strukturell/gegen Mocks geprüft).

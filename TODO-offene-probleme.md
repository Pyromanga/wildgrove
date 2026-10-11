# Offene Architektur-Probleme — To-Do

## 🔶 IN ARBEIT: Frauen & Männer + echte, an-/ausziehbare Kleidung (Nutzer-Wunsch)
## (Doku: `docs/wearables.md`)

Umgesetzt: Look-Feld `sex` mit eigener Körperform; Kleidung/Zubehör/Rüstung sind echte Items
(`WearableDefinition`/`ArmorDefinition`), Zustand im replizierten Look; EquipmentService bucht
Inventar ↔ Look um; NPCs nutzen dieselben Items (`NPCVisualBuilder.wear/take_off`).
Tests: `test_wearable_catalog`, `test_character_sex`, `test_worn_gear_visuals`, `test_npc_outfit`,
`test_equipment_wearables`.

**Offen / nicht verifiziert:**
- Kein Godot-Binary in der Bau-Umgebung: weder GUT noch Sichtprüfung gelaufen — `make test` und ein Blick auf
  Frau/Mann, nackt, Rüstung (Brust/Becken) stehen aus.
- Neue Kleidung ist im Spiel nirgends erhältlich (Shop/Loot/Schneiderei fehlen), nur Admin-Menü.
- Beim Aufbau gefunden: `docs/smithing-and-crafting.md`/`ArmorDefinition` beschrieben Rüstungs-Optik nicht;
  Rüstung war bis hierher am Körper unsichtbar (jetzt über `armor_*` gespiegelt).

## ✅ ERLEDIGT: Flüsse und Biome verschoben sich nach Speichern/Neuladen
## (Nutzer-Report, 2026-09-27)

Root Cause: `SaveSystem.gd` schreibt den Spielstand als JSON
(`JSON.stringify()`/`JSON.parse()`) — JSON kennt keinen Unterschied zwischen
`int` und `float`, `JSON.parse()` liefert JEDE Zahl als `float` zurück.
`world_seed` war beim Laden das EINZIGE Feld mit einem strikten
`seed_raw is int`-Check statt `var_to_str()`/`str_to_var()` (wie alle
anderen Felder hier) — der Check schlug nach dem JSON-Roundtrip **immer**
fehl, `world_seed` resettete bei jedem Laden auf 0, `WorldService.
configure()` würfelte über `Time.get_unix_time_from_system()` einen
komplett neuen Zufalls-Seed. Da Höhe, Klima/Biome UND Flüsse alle direkt aus
`world_seed` abgeleitet werden (`TerrainSeed.derive()`), sah die Welt nach
jedem Neuladen komplett anders aus. `day_time`/`day_count` u.a. blieben
unauffällig, weil sie entweder `var_to_str()` nutzen oder gar keinen
strikten Typ-Check haben.

**Fix:** `world_seed` wird jetzt ebenfalls über `var_to_str()`/`str_to_var()`
gespeichert/geladen, zusätzlich tolerant gegen `int` UND `float` (Fallback
für ältere Spielstände im rohen Zahlenformat).

## ✅ ERLEDIGT: Bepflanzte Felder waren nicht persistent
## (Nutzer-Report, 2026-09-27 — FarmPlot.gd dokumentierte das bereits selbst
## als bekannte Lücke, siehe dortiger Klassenkommentar "PERSISTENZ")

`FarmPlot.on_spawn()` setzte `stage` bisher IMMER auf `EMPTY`, unabhängig
vom vorherigen Zustand — kein SaveSystem-Provider vorhanden, laufendes
Wachstum ging bei jedem Neuladen verloren.

**Fix:** Neue `FarmPlotRegistry` (Sparse-Registry, Positions-Key via
`WorldData.make_key("farm_plot", global_position)` — Plots stehen an festen,
deterministischen Dorf-Layout-Positionen). Speichert `stage` + einen
ABSOLUTEN Reif-Zeitpunkt (`ready_at`, Unix-Zeitstempel) statt "verbleibende
Sekunden" — konsequent im Sinne von FarmPlot.gd's bereits bestehendem
Prinzip "Wachstum läuft weiter, während kein Spieler in der Nähe ist": eine
Pflanze wächst dadurch jetzt auch weiter, während die App komplett zu ist.
War die App länger zu als die Wachstumsdauer, ist der Plot beim nächsten
`on_spawn()` sofort `READY` statt erneut von vorne zu warten.

**Validierung beider Fixes (Godot-frei, siehe `make world-persistence-check`):**
- `scripts/agent/world_persistence_check.py` — 12 Struktur-Punkte + 10
  Verhaltens-Tests, u.a. eine echte Python-`json`-Roundtrip-Simulation, die
  den world_seed-Bug reproduziert (und beweist, dass der Fix ihn behebt),
  sowie das Kernszenario "während die App zu war fertig gewachsen".
- `tests/unit/test_farm_plot_registry.gd` (neu) — Save/Load-Roundtrip,
  Sparse-Prinzip, defensive Behandlung kaputter Einträge.
- Alle geänderten `.gd`-Dateien durch `check_gdscript_syntax.py` bestätigt.

## ✅ ERLEDIGT: Bodenmaterial war überall "Erde", egal welches Biom
## (Nutzer-Wunsch "natürlich Erde/Sand je nach Biom + Kiesschicht, Sand aus
## der Wüste bleibt Sand auch woanders abgelegt", 2026-09-26)

VORHER: `WorldService.request_terrain_edit()` vergab beim Graben IMMER das
Item `"dirt"`, unabhängig vom Biom (Wüste, Wald, Gebirge — alles gleich),
und Aufschütten verbrauchte ebenfalls immer nur `"dirt"`. Kein Materialbegriff
jenseits davon, keine Persistenz für abgelegtes Material.

**Neu:**
- `BiomeDefinition.surface_material` — natürliches Bodenmaterial pro Biom
  (Wüste → `sand`, Gebirge → `gravel`, alle anderen bleiben `dirt`).
- `TerrainField.SUBSOIL_DEPTH` (−2 m): ab dieser kumulierten Grabtiefe wird
  Kies zur natürlichen Antwort — UNABHÄNGIG vom Biom (Realismus: Kiesschicht
  unter dem Oberboden überall, kein endloser Sand/Waldboden in der Tiefe).
- `TerrainMaterialLayer` (neu, Geschwister zu `TerrainEditLayer`, gleiches
  Sparse-Gitter-Muster inkl. Save/Load): speichert bewusst abgelegtes
  Material dauerhaft. Auflösungsreihenfolge in
  `TerrainField.get_material_at()`: Override > Kies-Tiefe > Biom-Material —
  EINE Wahrheit für Gameplay (welches Item Graben liefert,
  `WorldService.request_terrain_edit()`) UND Optik
  (`TerrainChunkBuilder._biome_color()`), kann nicht auseinanderlaufen.
- Neue Items `data/items/Sand.tres`/`Gravel.tres`, im `DataManifest`
  registriert (sonst fehlen sie im Android-Export, siehe dortiger
  Klassenkommentar).
- `request_terrain_edit()` nimmt jetzt optional `material_id` entgegen;
  ohne Angabe wählt `_resolve_fill_material()` beim Aufschütten das erste
  Material aus `FILL_MATERIAL_PRIORITY` (`sand` → `gravel` → `dirt`), von
  dem der Spieler etwas trägt.

**Validierung (Godot-frei, siehe `make terrain-material-check`):**
- `scripts/agent/terrain_material_check.py` — 17 Struktur-Punkte über alle
  beteiligten Dateien + 7 Verhaltens-Tests (u.a. das exakte Szenario aus der
  Anfrage: Sand in der Wüste graben → im Wald ablegen → bleibt Sand → erneut
  ausgraben liefert Sand zurück UND der Override wird dabei aufgeräumt).
- `tests/unit/test_terrain_field.gd` + `tests/unit/test_biome_registry.gd`
  um die neuen Fälle erweitert (bestehende Edit-Layer-Tests waren die
  passende Vorlage).
- Alle geänderten `.gd`-Dateien durch `check_gdscript_syntax.py` bestätigt.

## ✅ ERLEDIGT: Pet-Menü aktualisiert sich nicht bei neuem Pet + unübersichtlich (2026-10-02)

1. **Kein Sofort-Update:** `PetPanelController` refreshte nur beim Öffnen des
   Panels (`visibility_changed`). Jetzt zusätzlich über
   `IEventBus.world().entity_spawned/entity_despawned` (`type_id == "pet"`),
   entprellt per `call_deferred()`. Deckt Fangen, Save-Restore und
   Netzwerk-Kopie ab (alle laufen durch `EntityOrchestrator.spawn_entity()`).
2. **Neues Menü:** Grid aus Kopf-Kacheln (`PetHeadIcon`, 2D aus
   Farbe/Ohren/Schnauze/Kopfschmuck), Tap öffnet Detailansicht mit den
   Fähigkeits-Toggles, dazu Namenssuche + Filter (Alle/Aktiv/Untätig/aktuell
   ausgeübte Fähigkeit). Live-Status per 1-s-Timer (`refresh_status()`, ohne
   Kachel-Rebuild). Neue Lese-API: `PetComponent.get_appearance()`,
   `PetComponent.get_current_activity()`, `PetAbilityComponent.get_activity_state()`.
3. Tests: `test_pet_panel_controller.gd` erweitert, neu
   `test_pet_component_activity.gd`. **Nicht in Godot ausgeführt** (kein Binary
   in der Sandbox) — nur `check_gdscript_syntax.py` + `service_graph.py`
   (keine neuen Findings, 45 wie vorher).

## ✅ ERLEDIGT: Pets konnten Ressourcen manchmal nicht abbauen/sammeln
## (gefunden per Bug-Report + Log, 2026-09-26)

Repro: 3 Pets gleichzeitig auf Holz/Erz/Pilze angesetzt — alle drei sind
erkannt hingelaufen, keine hat je fertig geerntet. Kampf war unauffällig.

**Root Cause**, per Log zweifelsfrei belegt:
```
resolve_for_player(...): peer_id=1 außerhalb Reichweite (9.3 > max 4.5).
resolve_for_player(...): peer_id=1 außerhalb Reichweite (7.4 > max 4.5).
```
`EntityOrchestrator.resolve_for_player()` maß die autoritative Reichweite
IMMER vom Besitzer-Spieler zum Ziel, nie vom Pet selbst. Ein Pet darf laut
`PetAbilityComponent.SEARCH_RADIUS` bis zu 7m von SICH SELBST aus nach einem
Ziel suchen — bleibt der Besitzer dabei stehen (z.B. weil er mehrere Pets auf
verschiedene, verstreute Ressourcen ansetzt), landet das Ziel locker
außerhalb der 4.5m, die der Server vom Spieler aus erlaubt. Kampf blieb
unauffällig, weil Gegner dem Besitzer meist nahe bleiben — Bäume/Erz/Pilze
stehen fest an Ort und Stelle. War im Code sogar schon als "BEKANNTE
EINSCHRÄNKUNG" dokumentiert (PetAbilityComponent-Klassenkommentar), nur mit
zu optimistischer Mitigation (kleiner SEARCH_RADIUS reicht nicht, wenn der
Besitzer selbst schon ein paar Meter vom Pet entfernt steht).

**Fix:** `actor_uuid` als optionaler Parameter durch die ganze Kette gezogen —
`EntityOrchestrator.resolve_for_player()` → `WorldService.
request_entity_interaction()`/`resolve_and_dispatch_interaction()` →
`NetworkBridge.send_entity_interaction()`/`_rpc_request_entity_interaction()`.
`PetAbilityComponent._complete_harvest()`/`_do_attack()` übergeben jetzt ihre
eigene `entity_uuid` — die Autorität misst die Reichweite dann ab dem Pet.
Leer (Default) = unverändertes Verhalten für jede normale Spieler-Interaktion.
Sicherheitsprinzip gewahrt (siehe NetworkContract.gd): actor_uuid zeigt immer
auf eine servereigene registrierte Entity, nie eine roh vom Client gemeldete
Position — exakt dasselbe Prinzip wie schon für die Ziel-`entity_uuid`.

**Validierung (Godot-frei, siehe `make pet-range-check`):**
- `scripts/agent/pet_range_check.py` — Struktur-Check über alle 7 Stellen der
  Signaturkette + Verhaltens-Simulation, die exakt die geloggten Distanzen
  (9.3m/7.4m) gegen alte vs. neue Logik prüft.
- `tests/unit/test_entity_orchestrator.gd` erweitert (bestehende
  `resolve_for_player()`-Tests waren die passende Basis) um 3 Fälle: Fix
  greift, Fix hebt die Prüfung nicht komplett auf (Pet selbst zu weit weg
  bleibt abgelehnt), Fallback bei unauflösbarer `actor_uuid`.
- Alle geänderten `.gd`-Dateien durch `check_gdscript_syntax.py` bestätigt.

## ✅ ERLEDIGT: NPC-Dialog kannte nur EINEN Quest-Strang gleichzeitig (ADR-051)
## (Stufe 1+2+3 gebaut, 2026-09-27/28 zusätzlich alle 6 Alt-NPCs konvertiert +
## scripts/agent/build/quest_npc_scaffold.py für neue Quest-NPCs)
## (Nutzer-Wunsch nach "mehreren Quests gleichzeitig von derselben Person" +
## NPCs mit mehreren Gesprächsoptionen wie in Runescape, 2026-09-26)

Siehe [ADR-051](adr/051-npc-dialogue-multi-quest.md) für die volle Herleitung.

**Befund:** `QuestNPC`/`QuestNPCDialogController` kennen genau EINEN aktiven
Quest-Strang pro NPC-Instanz (fest verdrahtet: `quest_id` → optional
`next_quest_id`, dann für immer `QUEST_DONE`). Dass z.B. Erik gleichzeitig
Träger seiner eigenen Kette UND TALK-Ziel für `quest_babatunde_tale` ist,
funktioniert nur, weil `npc_talked_to` ein globales Signal ist, das
JEDE aktive Quest im Hintergrund prüft (`QuestObjectiveHandler.resolve_talk()`)
— das Dialog-UI selbst (eine einzelne Label3D-Sprechblase) weiß davon nichts
und zeigt immer nur den Text des eigenen Strangs.

Für "ein NPC hat mehrere Gesprächsoptionen, je nachdem was gerade offen ist"
(Wunsch: RunScape-artig, aber modern) reicht das nicht — das bräuchte eine
Liste von Gesprächsoptionen statt eines festen Text-Zustands, plus eine
Auswahl-UI statt der bisherigen Einzel-Sprechblase.

**Entscheidung (siehe ADR-051 für Details):** Drei gestaffelte Ausbaustufen:
- [x] **Stufe 1 (klein, umgesetzt 2026-09-26):** NPC kann mehrere eigene,
      unabhängige Quest-Stränge gleichzeitig führen (noch einzelne
      Sprechblase, kein Auswahlmenü) — `QuestNPCDialogController`
      `add_independent_slot()`, `QuestNPC._add_extra_quest_slot()`. 100%
      rückwärtskompatibel (alle 6 bestehenden NPC-Subklassen unverändert,
      keine bestehende Test-Assertion angefasst).
- [x] Stufe 2 (mittel, umgesetzt 2026-09-26): + einfache Auswahlliste
      (Buttons) wenn mehrere Optionen anliegen — `NPCDialogueChoiceUI`,
      `QuestNPCDialogController.set_choice_ui_factory()`. Bei genau einem
      ansprechbaren Slot weiterhin kein Menü (Stufe-1-Verhalten bleibt Fallback).
- [x] Stufe 3 (groß, umgesetzt 2026-09-27): echtes verzweigendes
      Dialogsystem — `DialogueTreeController` (generische DialogueNode/
      DialogueChoice-Struktur, condition-Strings gegen QuestService,
      wiederverwendet NPCDialogueChoiceUI aus Stufe 2). NPCs reagieren jetzt
      auch auf FREMDE Quests (siehe `VillageElderNPC.gd`/Dorfältester
      Rasmus — Demo-NPC, reagiert auf `quest_babatunde_tale`, ohne diese
      selbst zu vergeben). `IEntityContext.get_quest_service()` neu für den
      dafür nötigen Lesezugriff auf fremden Quest-Status.

## ✅ ERLEDIGT: `HealthComponent.max_health`-Setter widersprach eigenem Kommentar
## (gefunden beim Bau des Admin-Menüs, 2026-09-25)

Beim Verdrahten von `AdminMenuCommands.gd` (`maxhealth`-Befehl) aufgefallen:
`HealthComponent.max_health` war als "Sync current mit max beim **ersten**
Setzen" dokumentiert, hat aber jedes Setzen gleich behandelt — jede spätere
`max_health`-Änderung an einer bereits laufenden Komponente (Buff,
Admin-Befehl, ein künftiges Level-Up-System) hat das aktuelle Leben
stillschweigend auf das neue Maximum gesetzt/geheilt, statt es unverändert
zu lassen. Alle drei bisherigen Produktiv-Call-Sites (`PlayerSetup.
_build_health()`, `EnemyNPC._setup_health()`, `EnemyNPC`-Pool-Reuse) waren
davon nicht betroffen, weil sie `max_health` ausschließlich vor `add_child()`
setzen bzw. direkt danach explizit `reset()` aufrufen — das Symptom hätte
erst einen neuen, späteren Call-Site getroffen (z.B. genau den neuen
`maxhealth`-Admin-Befehl).

**Fix:** Setter unterscheidet jetzt über `is_node_ready()` zwischen "erstes
Setzen" (vor `_ready()`, Konstruktions-Pattern — synct weiterhin current)
und "Live-Änderung" (Komponente bereits im Baum — klemmt current nur noch
nach unten, heilt nie implizit). Verhalten aller drei bestehenden Call-Sites
nachweislich unverändert (siehe Kommentar in `HealthComponent.gd`).
`AdminMenuCommands.gd`s `maxhealth`-Befehl entsprechend angepasst.

**Validierung (Godot-frei, siehe `make health-contract-check`):**
- `scripts/agent/health_contract_check.py` — Struktur-Regressionsschutz
  gegen `HealthComponent.gd` + Python-Verhaltens-Simulation (7 Fälle,
  `unittest`, stdlib-only wie der Rest von `scripts/agent/`).
- `tests/unit/test_health_component_max_health_contract.gd` — kanonische
  GutTest-Spezifikation im Projektstil (aktuell wie alle `tests/unit/*.gd`
  nicht automatisiert ausführbar, siehe Makefile "test-gd"-Target).
- Beide neuen/geänderten `.gd`-Dateien durch `check_gdscript_syntax.py`
  bestätigt.

## 🆕 NEU: Zwei parallele Pfade für dieselbe Sache — aufgedeckt via `service_graph.py`-Erweiterung (Round 109)

Beim Erweitern von `scripts/agent/service_graph.py` um Event-Graph +
Interface-Konformität aufgefallen: an drei Stellen existieren zwei
unterschiedliche Wege, dasselbe Problem zu lösen — kein bewusstes
Nebeneinander, sondern unfertige Migration bzw. ein Vertrag, der nur im
Kommentar existiert, nicht im Code. Dazu zwei weitere, beim Bau des Tools
selbst gefundene Punkte: eine rein mechanische Namenskonvention-Lücke (#5)
und eine echte Architekturfrage — der EventBus selbst ist ein Kompromiss,
kein Zielbild (#6). Reihenfolge unten = Bearbeitungsreihenfolge.

**Punkt 1 (EventBus Pfad A→B) ist raus (Round 109) — umgesetzt, nicht nur
entschieden:** `AppScope`/`IAppContext`/`AppContext` neu gebaut,
`MainMenuController` + `HUDManager` (toter `register_session_listener()`
entfernt) vollständig migriert, `tests/unit/test_event_bus_access_boundary.gd`-
Whitelist entsprechend verkleinert (+ zwei bisher nicht erfasste, aber im Code
bereits als "justified: Autoload" dokumentierte Bootstrap-Ausnahmen
nachgetragen: `DedicatedServerBootstrap.gd`, `IT03Harness.gd`). Neuer,
wiederverwendbarer Codemod `scripts/agent/build/fix_eventbus_direct_access.py`
(`service_build.py eventbus-direct`) migriert jede künftige Datei automatisch,
sobald sie einen Bus-Zugriffspunkt (`_bus: IEventBus` /
`_ctx: IUIContext|IAppContext`) hat — Dry-Run bestätigt: keine
Direktzugriffe außerhalb der Whitelist mehr im gesamten Projekt.

- [ ] **1. `## implements I*`-Kommentare durch echtes `extends I*` ersetzen und
      korrekt verdrahten.** 14 Provider (`SkillSystem`, `QuestService`,
      `SaveSystem`, `InventorySystem`, `EquipmentService`, `CurrencyService`,
      `TradeService`, `AuctionHouseService`, `DeathLootService`,
      `SettingsService`, `PlayerCredentialStore`, u.a.) behaupten
      `ISaveProvider`-Konformität nur per Kommentar — der Compiler prüft nichts,
      `is ISaveProvider` würde zur Laufzeit `false` liefern. **Entschieden
      (Round 109):** `Service extends ISaveProvider` verworfen (ISP-Verletzung)
      — bleibt `## implements`-Doku-Konvention, abgesichert durch
      `service_graph.py`s
      `UNVERIFIED_INTERFACE_CLAIM`(ERROR)/`MISSING_OVERRIDE`(WARN) als
      Interims-Contract-Test-Äquivalent (Decision 0013), bis ein echter
      GDScript-Test in Phase 3 möglich ist. **Round 110:** `WorldSaveHandler.gd`
      war der einzige echte `MISSING_OVERRIDE`-Fall — falsche Behauptung, nicht
      fehlender Code: nie über `register_save_provider()` registriert,
      `WorldService` ist der echte Provider und delegiert nur intern. Kommentar
      entfernt (Decision 0012), `MISSING_OVERRIDE` behoben. Verbleibend: 6 echte
      `UNVERIFIED_INTERFACE_CLAIM`-ERRORs (`SkillSystem`, `QuestService`,
      `CurrencyService`, `AuctionHouseService`, `InventorySystem`,
      `EquipmentService`) — strukturell vollständig, aber nicht
      test-verifiziert. Bleibt offen bis Phase 3.
- [ ] **2. Neue Konvention für "Interface-Methode muss überschrieben werden"
      statt `assert(false, ...)` bzw. stillem Default-Rückgabewert.** Beide
      aktuell benutzten Varianten sind in Release-Builds wirkungslos
      (`assert()` No-Op ohne Debug-Flag; `return null`/`return 1` fällt
      ohnehin still durch). Vorschlag aus der Analyse: `extends`-Beziehung
      (aus #2) + ein Contract-Test, der zur Testzeit über alle bekannten
      Implementierer iteriert und prüft, dass der Interface-Default
      tatsächlich überschrieben wurde — kein Runtime-Mechanismus, sondern
      CI-Zeit. **Bewusst nicht in #2 mit eingebaut** — das ist eine neue
      Konvention, keine 1:1-Migration, muss separat entschieden werden bevor
      sie projektweit ausgerollt wird.
- [ ] **3. `IServiceLifecycle`/`ITickable` sauber lösen.** Aktuell kein
      formaler Implementierer irgendwo (`Service`/`ServiceNode` haben kein
      `extends IServiceLifecycle`) — laut Interface-Kommentar Absicht, weil
      GDScript kein Mehrfach-Erben kennt (`Service extends RefCounted`,
      `ServiceNode extends Node`, beide können nicht zusätzlich das Interface
      erben). Geprüft wird stattdessen nur strukturell via
      `svc is IServiceLifecycle`/`is ITickable`. Fühlt sich nicht klar genug
      an für ein Projekt dieser Größenordnung — nicht verifiziert ob diese
      Laufzeit-Typ-Prüfung überhaupt wasserdicht ist, wenn `Service`/
      `ServiceNode` sich mal von den Interface-Signaturen entfernen (verhält
      sich `is IServiceLifecycle` dann wie erwartet, oder liefert es weiterhin
      `false`/`true` unabhängig von der tatsächlichen Methodenlage?). Zu
      klären: entweder ein GDScript-Muster finden das ohne echtes
      Mehrfach-Erben trotzdem einen Compile-Zeit-Vertrag herstellt, oder
      bewusst dokumentieren warum der Laufzeit-Typ-Guard hier ausreicht —
      dann aber mit einem Test der das auch beweist, nicht nur behauptet.
- [ ] **4. `service_graph.py` — strenger Finding-Typ für #2, plus
      Event-Graph für #1.** Das eigentliche Werkzeug für alles oben: neuer
      `interfaces`-Check meldet jede `## implements I*`-Stelle ohne
      passendes `extends I*` **immer** als Finding, unabhängig davon ob die
      Methoden zufällig richtig benannt sind (Kommentar-Vertrag zählt nicht
      als Vertrag). Neuer Event-Graph-Check zählt A- vs. B-Zugriffsmuster pro
      Event/Datei (#1) und findet nie emittierte/nie verbundene Signale.
      **Wird zuerst gebaut** — Voraussetzung um #1/#2 überhaupt messbar
      abzuarbeiten statt aus dem Bauch zu schätzen.
- [ ] **5. `EventBus` selbst ist ein Kompromiss, kein Zielbild — Migration zu
      einem typisierten Domain-Event-Layer.** Ein globaler String-/Symbol-
      benannter EventBus ist strukturell ein Service Locator für Events:
      zur Laufzeit gebunden, nicht compile-zeit-verifizierbar, unsichtbar
      im Abhängigkeitsgraphen. Für ein Projekt dieser Größe (41 Services,
      22 davon mit eigenen nativen `signal`-Deklarationen zusätzlich zum
      EventBus, mind. 8 Dateien die direkt auf native Signale statt über
      den Bus connecten) ist "Pfad A vs. Pfad B" (#1) nur die halbe
      Migration — die andere Hälfte ist der native-Signal-Wildwuchs, der
      komplett am EventBus vorbei läuft. Symptom bereits gefunden:
      `EventBus.player.inventory_changed` (tot) vs.
      `InventorySystem.inventory_changed` (nativ, breit genutzt) — zwei
      Kanäle für dieselbe Tatsache, Namenskollision rein zufällig.
      **Zielarchitektur:** ein kanonischer, typisierter Domain-Event-
      Mechanismus (keine rohen String-Signal-Namen) als einziger Kanal für
      schichtübergreifende/Bounded-Context-übergreifende Fakten. Native
      `signal`s bleiben erlaubt, aber nur noch für lokale, eng begrenzte
      Verdrahtung innerhalb eines Node-Subtrees (Parent-Child-UI-Kram) —
      nie für businessrelevante Zustandsänderungen, die woanders im System
      relevant sind. Trennlinie ist die Schichtgrenze, nicht "wer hat
      gerade per DI Zugriff" (das wäre zufällige, nicht geplante Kopplung).
      **Größte und riskanteste Migration der ganzen Liste** — bewusst
      zuletzt, weil #1 (Konsolidierung auf die `IEventBus`-Indirektion)
      genau die Abstraktionsgrenze schafft, hinter der sich die
      Bus-Implementierung später austauschen lässt, ohne 41 Services
      gleichzeitig anzufassen. Vor Code: eigenes Konzept/ADR mit
      Migrationsplan (welche der 22 nativen Signale lokal bleiben, welche
      in den neuen Layer wandern). `service_graph.py events` liefert die
      Mess-Grundlage bereits: Gesamtzahl nativer `signal`-Deklarationen im
      Projekt plus jede Namenskollision mit einem EventBus-Signal als
      `NATIVE_SIGNAL_EVENTBUS_COLLISION` (WARN, informativ — kein
      Migrationsplan bis zur ADR-Entscheidung).
      **Round 110:** Kategorisierungs-Tool `scripts/agent/analyze_native_signals.py`
      gebaut (`make signal-categorize`) — kategorisiert alle 99 nativen
      Signal-Deklarationen (91 eindeutige Namen) automatisch als LOCAL (21) /
      CROSS_LAYER (52) / NEEDS_HUMAN (18, davon 4 echte Namenskollisionen und
      14 mutmaßliche Parent-Child-UI-Fälle ohne `.tscn`-Bestätigung), Report
      unter `docs/manager/reports/native-signal-categorization.md` (Decision
      0015). Das ist die Datengrundlage für die ADR, **nicht** die ADR selbst
      — Punkt bleibt offen, bis Konzept/Migrationsplan auf Basis dieser
      Kategorisierung geschrieben ist. Zwei eigene Methodik-Fehler unterwegs
      gefunden und vor der ersten Ausgabe korrigiert (nicht erst hinterher):
      (1) `tests/`-Connects wurden anfangs als externe Kopplung mitgezählt —
      ein Unit-Test der ein Signal beobachtet ist kein Business-Konsument,
      hätte sonst praktisch jedes Signal fälschlich als CROSS_LAYER markiert;
      (2) "anderes File" wurde anfangs mit "andere Schicht" gleichgesetzt,
      obwohl Parent-Child-UI-Verdrahtung über Dateigrenzen (z.B.
      `*Visuals.gd` → `*UIController.gd` im selben `ui/`-Ordner) laut
      Zielarchitektur oben explizit lokal bleiben darf — diese 14 Fälle gehen
      jetzt nach NEEDS_HUMAN statt fälschlich nach CROSS_LAYER.
      **Konzept/ADR jetzt geschrieben:** [ADR-050](adr/050-native-signal-domain-event-migration.md)
      — Zielmechanismus (bestehende `EventBus`/`IEventBus`-Indirektion
      wiederverwenden, kein neuer Mechanismus) + 4-Phasen-Migrationsplan
      (Phase 1: 18 NEEDS_HUMAN-Fälle einzeln klären; Phase 2: 52
      CROSS_LAYER-Fälle in Domain-Batches; Phase 3: Codemod; Phase 4:
      Regressions-Finding in `service_graph.py`). Status bewusst `Proposed`/
      `unverified` in `adr_tool.py` — Konzept ist fertig, **Umsetzung
      (Phase 1) hat noch nicht begonnen**. Punkt bleibt offen bis mind.
      Phase 1 abgeschlossen ist.

**Zusätzlich beim Nachprüfen gefunden und sofort korrigiert (kein offener
Punkt, aber dokumentiert, weil es exakt die Sorte Fehler war, vor der im
Round-109-Gespräch gewarnt wurde):** `parse_signals()` hatte einen zweiten,
stilleren Namens-Rate-Mechanismus neben dem bereits gefixten
`emit_<wrapper>()`-Bug — wenn im Wrapper-Body kein eindeutiger
`<signal>.emit(...)`-Aufruf gefunden wurde, aber der Wrapper-Name zufällig
mit einem Signal-Namen übereinstimmte, wurde das stillschweigend als
"aufgelöst" gewertet, ohne dass die Vermutung irgendwo sichtbar war. In den
aktuellen Daten hat dieser Pfad nie gegriffen (0 Treffer verifiziert), aber
die Möglichkeit stillen Ratens war im Code vorhanden. Entfernt: kein
Namens-Fallback mehr, stattdessen neues Finding `EMIT_WRAPPER_UNRESOLVED`
(ERROR) für jeden Wrapper, dessen Ziel-Signal sich nicht aus dem Body
verifizieren lässt — muss von Hand geprüft werden statt automatisch als
korrekt zu gelten.

## 🆕 NEU: Tier-3-Admin-Zugang (ADR-040) — noch zu bauen

Siehe [ADR-040](adr/040-dedicated-server-admin-access.md) für die volle
Herleitung. Schließt die in [ADR-031](adr/031-permission-role-system.md) offen
gelassene Lücke ("Tier-3-Root-Konto existiert nicht, braucht eigene
Auth-Schicht").


  **Offen gebliebene Fragen — bewusst nicht stillschweigend als "erledigt"
  markiert, brauchen eine echte Godot-Runtime zur Verifikation (kein Zugriff
  darauf in dieser Sandbox, siehe auch Round 67 "Tests gegen echte
  Godot/GUT-Runtime"):**
  - [ ] **`AdminConsoleStdinReader.stop()` wartet bewusst NICHT auf den
        Thread** (`OS.read_string_from_stdin()` hat keinen
        Interrupt-Mechanismus — ein `wait_to_finish()` würde den
        Shutdown-Pfad aufhängen, solange niemand tippt). Ungeprüft: ob
        Godot beim harten Prozess-Exit (`get_tree().quit()`/OS-Kill) für
        einen noch laufenden, nicht gejointen `Thread` eine Fehlermeldung
        ausgibt oder sauber bleibt. Falls sich das als störend herausstellt:
        Optionen wären ein OS-Signal-Handler, der stdin aktiv schließt, oder
        ein Wechsel auf gepolltes `OS.get_stdin_type()`/nicht-blockierendes
        Lesen, falls Godot das in einer neueren Version anbietet.
  - [ ] **Verhalten ohne echtes TTY** (z.B. Prozess unter systemd ohne
        PTY-Zuweisung) ist nur angenommen, nicht verifiziert:
        `OS.read_string_from_stdin()` liefert dann vermutlich sofort `""`
        (vom Code als EOF behandelt, Thread beendet sich sauber) — aber
        ungetestet gegen eine echte Headless-Server-Umgebung.
  - [ ] `AdminConsoleTcpServer`/`AdminConsoleStdinReader` selbst haben keine
        Unit-Tests (brauchen echte Sockets/Threads/eine laufende
        Godot-Runtime, headless-GUT bildet das nicht sinnvoll ab — siehe
        SM-04 in `test_session_manager.gd` für dasselbe Muster bei
        `create_server()`). Nur die darunterliegende `AdminConsole`-Logik
        ist getestet (`test_admin_console.gd`). Ein manueller Testlauf
        (`godot --headless -- --dedicated-server`, dann `ssh -L
        7778:localhost:7778` + `nc localhost 7778`) steht noch aus.

- [ ] Bewusst NICHT in dieser Runde: unsichtbarer/noclip-fähiger
      Admin-Charakter in der Welt (eigenes State-Streaming-Thema),
      Passwort-Maskierung im rohen TCP-Protokoll (reine Client-UX, später).

## 🔴🔴 BLOCKER (höchste Priorität): `peer_id` als Save-/State-Schlüssel statt stabiler Spieler-Identität

Root-Cause-Fund bei der Vorbereitung von "Reconnect-Recovery" (siehe unten,
🟠). Siehe [ADR-029](adr/029-stable-player-identity.md) für die volle
Herleitung und die gewählte Lösung.


  **Phase 1 — Checkliste (Round 58 Vorarbeit, Round 59 Umsetzung begonnen):**
  Root-Cause-Check vor dem Coden ergab drei Architektur-Fakten, die den Umfang
  gegenüber der ersten verbalen Skizze vergrößern — siehe
  [ADR-029 "Implementierungsnotizen (Round 58/59)"](adr/029-stable-player-identity.md)
  für die Herleitung:
  - [x] `SaveSystem`: `player_uuid`/`player_secret` generieren + persistieren + Getter. **Erledigt Round 59** — dabei einen Leak-Fund mitgefixt: `get_full_state()` hätte das `player_secret` sonst an jeden Joiner verschickt.
  - [x] `PlayerCredentialStore` (neu, eigenständiges Datei-I/O statt `ISaveProvider`) — TOFU-Verifikation (gehashtes Secret). **Erledigt Round 60** (siehe Entscheidung unten).
  - [x] **Korrektur (Round 59):** Der Handshake gehört zu `SessionManager`, nicht
        zu `NetworkBridge` — `NetworkBridge` existiert erst innerhalb einer
        bereits gebooteten `CharacterScope`, der Handshake muss aber VOR der
        Charakterauswahl laufen. `SessionManager` (app-scoped, `ServiceNode`,
        lebt für die ganze App-Laufzeit) ist der richtige Ort.
  - [x] **Entscheidung (Round 60):** Persistenz-Timing-Problem gelöst — `PlayerCredentialStore`
        bekommt eine eigene, von der Charakter-Save unabhängige Datei
        (`user://server_credentials.json`), geladen einmalig beim
        `SessionManager`-Boot. TOFU-Secrets gehören zur Server-Installation,
        nicht zum Charakter — kein `ISaveProvider` mehr, eigenes Datei-I/O.
        Löst die Tier-2-Race aus Round 59 (Client verbindet bevor Host einen
        Charakter gewählt hat) vollständig auf statt sie zu umgehen.
  - [x] `SessionManager._rpc_join_handshake(player_uuid, player_secret)` +
        `_rpc_join_handshake_result(accepted, reason)` (Rückweg). **Erledigt
        Round 60.** Ruft bei Erfolg `register_player_slot(sender, player_uuid)`
        auf und emittiert `peer_joined` erneut mit der echten Identität (der
        synthetische `"peer_%d"`-Platzhalter aus `_on_peer_connected()` bleibt
        als Fallback bestehen, falls der Handshake nie eintrifft).
        **Bewusst offen gelassen — neuer TODO-Punkt:** kein Rate-Limiting auf
        diese RPC. `SessionManager` hat `NetworkBridge`s `_is_rate_limited()`-
        Infrastruktur nicht; Duplizieren für einen einzelnen Aufrufer war für
        Phase 1 nicht gerechtfertigt. Kein Brute-Force-Risiko (128-Bit-Secret),
        aber ein Compute-/Log-Spam-Vektor bei wiederholten Fehlversuchen.
  - [x] `MainMenuController`: neuer View-Zustand nach `joined_as_client` —
        Charakterauswahl (wie beim Host-/Solo-Flow) statt Auto-Boot, danach
        Handshake senden, erst nach Bestätigung booten. Der aktuelle Join-Flow
        springt direkt von IP:Port-Eingabe zu `PLAYING` — das entfällt.
        **Erledigt Round 62** (`_View.JOIN_CHARACTER_SELECT`, `inject_session_manager()`,
        `_start_join_handshake()`/`_on_join_handshake_result()`).
  - [x] `ServiceOrchestrator._on_client_connected()`: `"client_%d"`-Auto-Boot
        komplett entfernen (nicht nur die ID-Generierung), ersetzt durch
        UI-getriebenen Boot nach Handshake-Bestätigung. **Erledigt Round 62** —
        `SessionManager` wird jetzt zusätzlich zu `SaveSystem` ins MainMenu
        injiziert (musste mit rein, sonst wäre der neue View-Zustand toter
        Code gewesen, den der alte Auto-Boot sofort überholt hätte).
  - [x] **Nachträglich gefundener Guard-Bedarf (Round 62):** `SaveSystem.begin_session()`
        wird jetzt zweimal für dieselbe `player_id` aufgerufen — einmal vom
        `MainMenuController` vor dem Handshake (um `player_uuid`/`player_secret`
        zu lesen), einmal danach regulär von `BootPipeline.boot_character()`
        Phase C1. Ohne Idempotenz-Guard hätte der zweite Aufruf bei einem
        frisch angelegten Charakter (noch kein `save_game()` dazwischen) eine
        zweite, andere Zufalls-Identität erzeugt als die im Handshake bereits
        verschickte — der Client wäre mit einer vom Server nie akzeptierten
        Identität gebootet. Guard: zweiter Aufruf für dieselbe `player_id` bei
        bereits aktiver Session ist ein No-Op.
  - [x] Tests für `SaveSystem`-Teil (Round 59, `test_save_system.gd` +8,
        `test_uuid_gen.gd` neu).
  - [x] Tests für `PlayerCredentialStore`/`SessionManager`-Handshake. **Erledigt
        Round 61** (`test_player_credential_store.gd` neu, 13 Fälle;
        `test_session_manager.gd` +7 Fälle). Dabei `_rpc_join_handshake()` in
        eine testbare `_handle_join_handshake(sender, ...)`-Kernlogik
        aufgetrennt — Grund: `multiplayer.get_remote_sender_id()` liefert
        außerhalb eines echten eingehenden RPCs immer 0, exakt dasselbe
        Problem wie bei `NetworkBridge._is_rate_limited()`. Dabei außerdem ein
        Test-Seam ergänzt (`SessionManager.set_credentials_for_testing()`) —
        ohne den hätte jeder Handshake-Test in die echte Produktionsdatei
        `user://server_credentials.json` geschrieben.
  - [x] Tests für `MainMenuController`-Join-Flow + `SaveSystem`-Idempotenz-Guard.
        **Erledigt Round 62** (`test_main_menu_controller.gd` +9 Fälle über
        `SaveSystemDouble`/`SessionManagerDouble`, u.a. Handshake-Auslösung
        statt Direkt-Boot, akzeptiert/abgelehnt, verspätetes Ergebnis ohne
        laufenden Handshake, Verbindungsabbruch während des Handshakes;
        `test_save_system.gd` +5 Fälle für den Guard). Beim Schreiben des
        Ablehnungs-Tests einen echten Bug gefunden und gefixt: `_show_view(JOIN_CHARACTER_SELECT)`
        setzt selbst einen generischen Status-Text und wurde bisher VOR dem
        eigentlichen Ablehnungsgrund aufgerufen — hätte die Fehlermeldung für
        den Spieler unsichtbar sofort wieder überschrieben. Reihenfolge in
        `_on_join_handshake_result()` getauscht.

**Blockiert/hängt daran:**
- ~~🟠 "Kein Reconnect-Recovery" (unten)~~ — **erledigt/verifiziert Round 68**, fiel wie geplant beiläufig aus dem Identitäts-Fix heraus, kein separater Mechanismus nötig.
- ~~🟠 "Save-Konflikt-Handling fehlt" (unten)~~ — **erledigt/verifiziert Round 68**, Szenario (zwei Spieler schreiben denselben Save-Slot) ist strukturell ausgeschlossen — jeder Save-Slot hat genau einen schreibenden Prozess, kein Mechanismus nötig.

**Plan-Schritt 4 — Rekeying der Session-Services (Round 63 begonnen):**
Phase 1 (Checkliste oben) ist vollständig abgehakt; das hier ist der größere,
numerierte Schritt 4 aus dem ADR-Fließtext selbst (`peer_id: int` → `player_id:
String` in den vier Session-Services). Vorab-Recherche (siehe
[ADR-029 "Implementierungsnotizen (Round 63)"](adr/029-stable-player-identity.md))
ergab zwei zusätzliche, im Fließtext nicht erwähnte Kopplungsstellen — siehe dort.


**Save-Migration (Plan-Schritt 5) entfällt.** Auf Bestätigung: keine
nennenswerten Bestandsdaten in existierenden Coop-Saves — sauberer Schnitt statt
Migrationscode. Das ADR selbst nennt Plan-Schritt 5 nur für den Fall
"Bestandsdaten vorhanden", was hier nicht zutrifft.

---

## 🔴🔴 BLOCKER für ADR-025/026-Umsetzung: `multiplayer_authority` wird für zwei
## verschiedene Fragen missbraucht — GELÖST (2026-07)

**Gelöst.** `owner_peer_id` ist jetzt ein Entity-Meta (gesetzt in
`EntityOrchestrator.spawn_entity()`, neben `entity_uuid`/`entity_type`) —
unabhängig von `multiplayer_authority`. Alle fünf Fundorte umgestellt:

- `IUIContext.get_local_player()` → `get_meta("owner_peer_id", 1)`
- `IEntityContext.get_local_player()` → `get_meta("owner_peer_id", 1)`,
  plus neue Methode `get_owner_peer_id()` (Default 1, `EntityContext`
  überschreibt mit dem echten Feld)
- `WorldService._on_peer_cleanup_requested()` → `get_meta("owner_peer_id", 1)`
- `PetComponent._find_owner()` → `get_meta("owner_peer_id", 1)`
- `Player.gd`: neues Feld `_owner_peer_id`, gesetzt in `on_spawn()` aus
  `ctx.get_owner_peer_id()`; alle vier internen Stellen (RemoteInterpolator-
  Gating, `emit_movement_interrupted()`, `_on_action_interrupted()`-Filter,
  `get_context_actions()`s `acting_player_id`) umgestellt.

**Netter Nebeneffekt:** `Player.gd` ruft dadurch `multiplayer.get_unique_id()`
nirgends mehr direkt auf — der bisherige Whitelist-Eintrag in
`test_identity_access_boundary.gd` (ADR-017/AUDIT-05-Grenztest) ist entfernt,
Player.gd ist jetzt ohne Ausnahme regelkonform.

**Verbleibend, noch nicht geprüft:** ob der ursprüngliche Grep-Sweep
(`get_multiplayer_authority()`/`is_multiplayer_authority()`) tatsächlich
vollständig war — siehe unten, weiterhin offen. Die eigentliche
Authority-Umkehr aus ADR-025 (Autorität = Server für Player-Nodes) sowie die
Prediction/Reconciliation aus ADR-026 sind durch diesen Fix erst
*durchführbar geworden*, aber noch nicht umgesetzt.

## 🔴🔴 KRITISCH — Root-Cause-Recherche zu ADR-019-Folgearbeit (2026-07, vor Umsetzung)

Ausgangspunkt war der bekannte Punkt "Server validiert RPC-Werte nicht" (unten).
Beim Nachverfolgen der Root Cause (warum das nicht nur `_rpc_add_item` betrifft)
zeigt sich: **derselbe strukturelle Fehler — Gameplay-Ereignis wird auf dem
lokalen EventBus des ausführenden Peers aufgelöst statt auf der Autorität —
tritt an mindestens fünf Stellen auf, zwei davon bisher völlig unbekannt.**
Reihenfolge nach Schweregrad, nicht nach Fundzeitpunkt:

  würfelte Loot + bemaß XP client-seitig.** (`scripts/interaction/InteractionExecutor.gd`,
  Bäume/Erze/generisches Sammeln.) Die Berechnung selbst (`loot_table.roll()`,
  XP-Bemessung) läuft jetzt in `InteractionResolver.resolve()` — einer
  zustandslosen statischen Utility, aufgerufen aus dem bereits
  authority-geguardeten `_on_interacted()`-Hook von `HarvestableEntity`.
  `InteractionExecutor` selbst emittiert `loot_collected`/`xp_gained` nicht mehr
  (Regressionstests in `test_interaction_executor.gd`). Nebenbefund dabei
  behoben: `StatModifierService` war im alten `InteractionExecutor`-Pfad nie im
  `deps`-Array deklariert — Yield-Boni liefen in Produktion immer ungemoddet;
  der neue Pfad über `IEntityContext.get_stat_modifiers()` ist korrekt
  verdrahtet. Siehe [ADR-020](adr/020-interaction-authority-guard.md)
  „Umsetzungsstand (Round 43)" für Details, `tests/unit/test_interaction_resolver.gd`
  für die dedizierten Berechnungs-Tests (echte `LootTable`/`StatModifierService`,
  inkl. Skalierung pro `player_id`).

  Combat-Interaktion (`attack_enemy`) hing am selben ungeprüften Pfad
  wie Gathering — ADR-019 "Kampf ist schon sauber" galt nur für Schaden/Kill,
  nicht für die Interaktions-XP.** Die XP-Bemessung läuft jetzt ebenfalls über
  `InteractionResolver.resolve()`, aufgerufen aus `EnemyNPC._on_interacted()`
  nach der Schadensanwendung — dieselbe Autorität, derselbe Guard, kein
  separater Pfad mehr für Combat- vs. Gathering-XP. **Ursprünglicher Befund:**
  `EnemyAttack.setup_interactable()` (`scripts/entities/combat/EnemyAttack.gd`)
  registrierte `attack_enemy` als ganz normale `InteractableData` mit
  `xp_amount = 5`, die über denselben `InteractionExecutor`-Pfad wie R-1 lief —
  jeder abgeschlossene Schwung gab dadurch **client-bestätigte 5 Combat-XP**,
  unabhängig davon ob getroffen wurde, ob der Gegner noch lebt, oder ob
  überhaupt ein `EnemyNPC` in Reichweite ist. **Was Round 42 zusätzlich
  aufgedeckt hat:** Der Satz „komplett getrennt
  vom bereits korrekten autoritativen Schadenspfad in `EnemyNPC._on_interacted()`"
  war zu optimistisch — dieser Pfad hatte zwar den Guard, aber
  `InteractionExecutor` läuft pro Peer lokal (siehe R-6), also lief der Schadens-
  Hook auf einem Nicht-Host-Client bisher NIE auf der echten Autorität, sondern
  lief bei jedem Aufruf sofort in den (bis dahin unerreichbaren) Guard-Return.
  D.h. Nahkampf-Schaden auf Tier 2/3 kam von einem Nicht-Host-Spieler nie beim
  Server an — ein eigenständiger, funktionaler Multiplayer-Bug, nicht nur ein
  Cheat-Vektor. Siehe [ADR-020](adr/020-interaction-authority-guard.md)
  „Umsetzungsstand" — der neue `request_entity_interaction()`-Transport schließt
  genau diese Lücke; die XP-Menge bleibt bis zum `InteractionResolver` offen.

  `HarvestableEntity._on_interacted()` hatten keinen Autoritäts-Guard.**
  `AnimalBase._on_interacted()` und `HarvestableEntity._on_interacted()` haben
  jetzt denselben `is_multiplayer_authority()`-Guard wie `EnemyNPC` — UND
  erreichen (siehe R-6) jetzt die tatsächliche Autorität, nicht nur ihre eigene,
  auf einem Nicht-Host-Peer potenziell falsche Kopie des Guards. `QuestNPC`-
  Dialoge nutzen denselben Transport automatisch mit (zentral in
  `InteractableComponent._handle_completion()` gefixt, nicht pro Entity-Typ),
  wurden aber noch nicht mit einem eigenen Guard-Test abgedeckt — siehe
  [ADR-020](adr/020-interaction-authority-guard.md) „Umsetzungsstand".

  führte zu Server/Client-Desync, nicht nur zu einem fehlenden Guard.**
  `WorldService._on_entity_despawn_requested()` selbst ist unverändert (despawnt
  weiterhin lokal, sobald das Signal feuert) — der Fix liegt eine Ebene höher:
  `HarvestableEntity._on_interacted()` feuert dieses Signal jetzt nur noch auf
  der Autorität, weil die Interaktion selbst über
  `WorldService.request_entity_interaction()` → RPC dorthin gelangt, statt nur
  auf dem Peer zu laufen, der lokal zuerst seinen Tween beendet hat. Siehe
  [ADR-020](adr/020-interaction-authority-guard.md) „Umsetzungsstand" für Details
  zum neuen Transport-Mechanismus und den bewusst NICHT mitgelösten Rand-Lücken
  (Movement-Anti-Cheat, RPC-Rate-Limiting).

  Economy-Mutationen, UI-Panels waren auf Spieler 1 hartkodiert.**
  Gelöst in dieser Reihenfolge (siehe
  [ADR-022](adr/022-economy-backsync-and-ui-identity.md) „Umsetzungsstand" für
  die volle Herleitung inkl. zweier bewusster Abweichungen vom Entwurf):
    1. `NetworkBridge` bekommt einen generischen Rücksync-Kanal:
       `send_economy_update(player_id, kind, payload)` (Autoritäts-Seite,
       No-Op ohne Peer oder für den eigenen lokalen Peer) und
       `_rpc_receive_economy_update(kind, payload)` → `economy_state_received`
       (Client-Seite). Ein RPC für alle drei Domänen (`kind` ∈
       "inventory"/"skill"/"equipment"), nicht drei separate — die Transport-
       Guard-Logik ist identisch, nur die Payload-Interpretation ist
       service-spezifisch.
    2. `InventorySystem`/`SkillSystem`/`EquipmentService` verbinden
       `economy_state_received` sowohl in `configure()` (Test-Harness-Pfad) als
       auch in `inject_network_bridge()` (Produktions-Late-Inject, Phase C8 —
       `configure()`/Phase C6 läuft VOR dem Late-Inject, eine Verbindung nur
       dort wäre ein stiller No-Op gewesen) und wenden empfangene Updates auf
       ihren EIGENEN lokalen `player_id` an, nicht auf die `player_id` aus dem
       ursprünglichen Payload.
    3. `SkillSystem` bekommt ein neues `skill_changed(skill_id, player_id)`-
       Signal — es gab bisher GAR KEIN Signal, das auf jedem Prozess feuert;
       `SkillPanelController` hing an `EventBus.player().xp_gained`/`level_up`,
       die nur auf der Autorität lokal feuern (C-02-Guard in
       `on_xp_add_confirmed()`) — für jeden Nicht-Host-Spieler kam dort nie
       etwas an, unabhängig vom Rücksync selbst.
    4. `EquipmentService.equipment_changed` bekommt einen `player_id`-Parameter
       — fehlte bisher komplett, kein Listener konnte unterscheiden für wen
       sich Equipment geändert hat.
    5. Alle drei UI-Controller (`InventoryUIController`, `EquipmentUIController`,
       `SkillPanelController`) filtern jetzt explizit auf
       `ctx.get_local_peer_id()` statt implizit `player_id == 1` /
       Default-Argumente zu lesen.
  **Bewusst NICHT Teil dieser Runde:** 3D-Visual-Replikation von Equipment über
  Peers (nur der Daten-State wird synchronisiert). **Neuer, eigenständiger
  Fund während der Umsetzung** (nicht mitgefixt, siehe unten): `CombatSystem`
  liest die Waffe für den Schadensbonus ohne `player_id`.

  `CombatSystem.player_melee_damage()`/`apply_weapon_on_hit()` lasen
  `EquipmentService.get_equipped_weapon()` ohne `player_id`.**
  `scripts/entities/combat/CombatSystem.gd` Zeilen ~216-256: der
  Skill-Level-Bonus in derselben Funktion nutzte bereits korrekt
  `_skill_system.get_level("combat", player_id)` (den tatsächlichen
  Angreifer), aber der Waffenbonus direkt danach las
  `_equipment.get_equipped_weapon()` ohne Argument — Default `player_id = 1`.
  Bedeutete: der Waffenschadensbonus im Nahkampf kam strukturell IMMER aus
  Spieler 1s Ausrüstung, unabhängig davon, wer tatsächlich zuschlägt. Fix:
  beide Call-Sites übergeben jetzt explizit `player_id` — für
  `apply_weapon_on_hit()` mit einem `attacker_player_id`-Fallback auf 1 für
  bestehende Aufrufer ohne Angreifer-Kontext (identisch zum bisherigen
  impliziten Verhalten), echte Aufrufer wie `EnemyNPC._on_interacted()`
  übergeben bereits einen echten `attacker_player_id`. Regressionstest:
  `test_player_melee_damage_reads_weapon_of_correct_player_in_coop()` in
  `tests/unit/test_combat_system.gd`, analog zum bestehenden ADR-019-Test für
  den Skill-Level-Lookup.



  `InventorySystem.has_item()` — UND der eigentliche Equip-Codepfad im Spiel
  lief gar nicht über die Stelle, an der man diese Prüfung einbauen würde.**
  Gelöst in dieser Reihenfolge (siehe
  [ADR-027](adr/027-equip-authority-resolves-visuals.md) für die volle Herleitung):
  1. `EntityOrchestrator._find_player_by_id()` ist jetzt öffentlich
     (`find_player_by_id()`) — der eine kanonische "Player-Node für
     beliebigen `player_id`"-Lookup.
  2. `WorldService.get_player_by_id()` / `WorldService.get_player_visuals()`
     legen eine Fassade darüber — Letzteres ersetzt die bisher doppelt
     vorhandene PlayerVisuals-Kind-Lookup-Logik aus
     `InventoryUIController._find_local_player_visuals()` und
     `EquipmentUIController`'s Äquivalent.
  3. `EquipmentService.on_equip_confirmed()` verliert den `visuals`-Parameter
     komplett und löst `PlayerVisuals` selbst über
     `WorldService.get_player_visuals(player_id)` auf — via neuem Late-Inject
     `inject_world_service()` (analog zu `inject_network_bridge()`, da
     `WorldService` bereits "equipment" als eigenen Dep deklariert und ein
     Rückweg über `BootstrapConfig.tres` ein zirkulärer Dep-Fehler wäre).
  4. `InventoryUIController`/`EquipmentUIController` rufen jetzt
     `request_equip()`/`request_unequip()` statt `equip()`/`unequip()` direkt
     auf — die beiden lokalen `_find_local_player_visuals()`-Kopien entfallen.
  5. `on_equip_confirmed()` hat jetzt die `InventorySystem.has_item()`-Prüfung
     — auf dem einzigen Pfad, den das Spiel tatsächlich benutzt (`equipment`
     bekam dafür `inventory` als neuen configure()-Dep in `BootstrapConfig.tres`).

  **Ergebnis:** eine Mutationskette statt zwei parallelen Pfaden ("Mutations-
  Zwiebel" aufgelöst), Equip funktioniert auf Tier 2/3 jetzt korrekt inkl.
  Visual (vorher Solo-only durch die Lücke bedingt), Besitzprüfung greift
  tatsächlich. **Bewusst nicht mitgelöst:** die vier verbleibenden Kopien
  desselben Player-Lookup-Musters für den *lokalen* Peer
  (`IUIContext`/`IEntityContext.get_local_player()`, `PetComponent._find_owner()`,
  `WorldService._on_peer_cleanup_requested()`) — andere Fragestellung (lokal
  vs. beliebig), separate kleinere ADR-015-Folgearbeit. **Noch offen/ungetestet:**
  ein dedizierter Regressionstest für `on_equip_confirmed()`s has_item()-Guard +
  Visual-Auflösung über `WorldService` fehlt noch (nächster Schritt).

  `QuestService`s Objective-Tracking ist nicht netzwerkfähig — 5 von 6
  Event-Handlern hardcoden `player_id=1`, obwohl die Signale den echten Wert
  bereits mitführen.**~~ — **geschlossen (Round 45 Code-Umsetzung nach
  ADR-021 Option C, Round 46 Regressionsfix BUG-26).** Historischer Befund
  bleibt unten stehen, siehe ADR-021 „Umsetzungsstand" für den genauen Schnitt
  (was über `report_domain_event()` läuft vs. was bereits ohne neuen Kanal
  auskam) und BUG-26 für einen dabei gefundenen Doppel-Count bei
  `npc_talked_to` (fehlender Autoritäts-Guard in `QuestNPC._on_interacted()`,
  seither behoben). `_on_loot_collected(item_id, quantity)`,
  `_on_xp_gained(skill_name, _amount)`, `_on_interaction_finished(action_id, _label)`,
  `_on_enemy_killed(enemy_type_id, _position)`, `_on_npc_talked_to(npc_id)` (alle
  in `scripts/progression/quests/QuestService.gd`) rufen ausnahmslos
  `update_objective(quest_id, obj_id, delta)` **ohne** `player_id`-Argument auf —
  Default greift, alles landet in Spieler 1's Bucket. Für `loot_collected` und
  `xp_gained` ist das kein fehlendes Datum, sondern ein ignoriertes: beide Signale
  tragen laut `WorldEvents.gd`/`PlayerEvents.gd` bereits `player_id: int` als
  drittes Argument (seit ADR-015/Schritt 2) — der Handler nimmt es nur nicht
  entgegen. Zusätzlich läuft `QuestService` wie jeder Service pro Peer lokal:
  Da `loot_collected`/`interaction_finished`/`xp_gained` clientseitig emittiert
  werden (siehe R-1) und **niemals** an die Autorität weitergereicht werden (kein
  RPC dafür existiert, siehe EventBus-Befund unten), kann die Autorität COLLECT-/
  INTERACT-/SKILL-Objectives für jeden Spieler außer dem Host serverseitig
  praktisch nie feststellen — `on_quest_complete_confirmed()` (bereits korrekt
  Objective-validiert, siehe unten) hat für Nicht-Host-Spieler schlicht nie echte
  Fortschrittsdaten zum Prüfen. Das ist gleichzeitig ein Multiplayer-Breaking-Bug
  (Nicht-Host-Spieler können quest-relevante Aktionen nie server-seitig
  abschließen) und dieselbe Vertrauensgrenze wie R-1: sobald das behoben wird
  (Ereignis muss die Autorität erreichen, nicht nur lokal gefeuert werden), muss
  der `player_id`-Parameter gleichzeitig ehrlich durchgereicht werden — sonst
  wird aus "kann nie tracken" ein neues "trackt für den falschen Spieler".
  `_on_enemy_killed`/`_on_npc_talked_to` haben ihr fehlendes `player_id` bereits
  als bekannten Tech-Debt kommentiert (`enemy_killed`/`npc_talked_to` selbst
  tragen noch keine `player_id`) — `_on_loot_collected`/`_on_xp_gained` haben
  **keinen** solchen Kommentar, weil dort schlicht übersehen wurde, dass das
  Signal es längst hergibt.

### EventBus-Sweep — wo im RPC-Bereich strukturell etwas fehlt

Auf Anfrage `IEventBus`/`EventBus.gd`/`NetworkBridge.gd` gegenübergestellt.
Ergebnis: **Nur sechs Vorgänge im gesamten Spiel überqueren je das Netzwerk**
(`_rpc_add_item`, `_rpc_add_xp`, `_rpc_start_quest`, `_rpc_complete_quest`,
`_rpc_equip_item`, `_rpc_unequip_item`, dazu `_rpc_set_state` und die
Snapshot-RPCs für Boot). Jedes andere Signal auf `EventBus.player/world/quest/…`
ist eine **rein lokale Instanz pro Peer** (`EventBus.gd._ready()` erzeugt die
Namespaces einmal pro laufendem Spielprozess, kein Sync-Mechanismus dazwischen).
Konkret nicht-vernetzt, aber von Services konsumiert als wäre es global gültig:

- `loot_collected`, `xp_gained` — tragen `player_id`, überqueren aber nie direkt
  das Netz; nur ihre *Folgeaktion* (`request_add_item`/`request_add_xp`) tut das.
  Root Cause von R-1.
- `interaction_finished`, `enemy_killed`, `npc_talked_to`,
  `custom_objective_triggered` — haben **gar kein** RPC-Äquivalent, auch nicht
  indirekt. Jeder Consumer (aktuell nur `QuestService`) sieht ausschließlich was
  auf dem eigenen Peer passiert ist. Root Cause von R-5.
- Für `enemy_killed` ist das (aktuell) unkritisch, weil die Emission selbst schon
  hinter `is_multiplayer_authority()` hängt (`EnemyNPC._die()` wird nur über den
  autoritätsgeprüften `_on_interacted()`-Pfad erreicht) — die Autorität sieht also
  immer die echten Kills. Für `interaction_finished`/`npc_talked_to` gilt das
  **nicht** (R-1/R-3 zeigen: die auslösenden `_on_interacted()`-Hooks sind nicht
  durchgängig autoritätsgeprüft).
- Kein einziges der ungenverzten Signale hat ein Gegenstück in `NetworkBridge`
  (kein `send_*()`, kein `_rpc_*`) — das ist kein Bug an einer Stelle, sondern
  eine fehlende Kategorie: "Ereignis, das die Autorität über etwas informieren
  muss, das clientseitig passiert ist" hat aktuell nur die 6 oben genannten
  Instanzen als Beispiel, obwohl die Domain (Interaction/Quest) strukturell
  mehr Fälle hat als Economy (Inventory/Skill/Equipment), die bereits vollständig
  abgedeckt ist.

**Vorläufige Einschätzung (vor ADR):** R-1, R-2, R-3, R-4 sind eine Familie
("Autorität vertraut clientseitig aufgelöstem Ergebnis") und sollten in einem
gemeinsamen Architektur-Schnitt gelöst werden — vermutlich durch ein generisches
Muster "Autorität löst Reward/Effekt aus einem server-seitig getrackten Ereignis
auf, Client meldet nur die Absicht" (exakt das Muster, das
`on_quest_complete_confirmed()`/`QuestObjectiveHandler` für Quest-*Abschluss*
bereits vorexerziert). R-5 ist eng verwandt, aber ein eigenständiger Fund
(betrifft Tracking, nicht Reward-Auszahlung) und braucht vermutlich einen
zusätzlichen, kleinen "Ereignis erreicht die Autorität"-Mechanismus für
Interaction/Quest-Signale, den Economy (Inventory/Skill) schon hat.

**Update:** Drei ADRs liegen jetzt als Entwurf vor, entlang der drei
Problemfamilien:
- [ADR-020](adr/020-interaction-authority-guard.md) — R-1, R-2, R-3, R-4, R-6
- [ADR-021](adr/021-quest-objective-networking.md) — R-5
- [ADR-022](adr/022-economy-backsync-and-ui-identity.md) — R-7

Beim Versuch, mit ADR-020 konkret genug zu werden um Code zu schreiben, zeigte
sich eine tiefere, gemeinsame Lücke (wie referenziert ein Netzwerk-Request
eindeutig ein Server-Objekt) — dafür:
- [ADR-023](adr/023-entity-reference-contract.md) — liegt unter ADR-020/021,
  macht `entity_uuid` zum einzigen kanonischen Objekt-Bezeichner + Range-Check.
  **Umgesetzt (2026-07):** `EntityOrchestrator.resolve_for_player(uuid, player_id,
  max_range)` existiert jetzt inkl. Distanz-Plausibilitätsprüfung, dokumentiert
  in `NetworkContract.gd`, getestet in `tests/unit/test_entity_orchestrator.gd`.
  **Round 42:** ADR-020 nutzt diesen Mechanismus jetzt für Interaktionen
  (`WorldService.resolve_and_dispatch_interaction()`) — siehe R-2/R-3/R-6 oben.
  **Round 43:** Der Loot/XP-Resolver für R-1/R-2 ist jetzt ebenfalls umgesetzt
  (`InteractionResolver.resolve()`). **Noch offen:** ADR-021 (Quest-Trigger mit
  Objekt-Bezug) und die Equip-Besitzprüfung für R-4 sind noch nicht umgestellt.
- [ADR-024](adr/024-server-side-movement-validation.md) — löste ursprünglich den
  bei der ADR-023-Recherche entstandenen Punkt "Range-Check vertraut
  client-reported Position ungeprüft" (Speed-Cap gegen `move_speed`-Stat).
  **Mittlerweile abgelöst** von ADR-025/026 (Zielniveau angehoben, siehe
  eigener TODO-Punkt weiter unten).

ADR-020 Status: **umgesetzt** (Round 42 — Transport, R-3, R-6; Round 43 — Loot/XP-
Resolver für R-1/R-2; siehe ADR-020 „Umsetzungsstand" für den genauen Schnitt).
R-4 ist seit Round 44 geschlossen (ADR-027, siehe R-4-Eintrag oben) — die dort
gebaute "Player-Node für player_id"-Utility (`EntityOrchestrator.find_player_by_id()`
→ `WorldService.get_player_by_id()`/`get_player_visuals()`) ist bereits zweifach
im Produktivcode genutzt (Equip-Autorität, `WorldService.route_movement_input()`
für ADR-025) und **kein offener Blocker mehr für ADR-022/R-7** — der
gegenteilige Stand in dieser Zusammenfassung war ein Dokumentations-Rückstand
(dieser Absatz wurde nach Round 44 nicht mehr nachgezogen), keine reale Sperre.
ADR-021 ist seit Round 45 "Angenommen" und umgesetzt — R-5 geschlossen, Round 46
brachte einen Regressionsfix (BUG-26, siehe R-5-Eintrag oben und ADR-021
„Umsetzungsstand"). ADR-022/R-7 ist seit Round 49 "Angenommen — umgesetzt" —
R-7 geschlossen (siehe R-7-Eintrag oben und ADR-022 „Umsetzungsstand"), dabei
kam mit R-8 ein neuer, eigenständiger Fund in `CombatSystem` ans Licht — noch
im selben Round direkt mitbehoben (siehe eigener R-8-Eintrag oben).

---

## 🔴 Kritisch (blockiert echtes Multiplayer)

  **Round 68 Cheat-Audit (Nachtrag, kein neuer Fund):** Stichprobe gegen `QuestService`/`SkillSystem`/`EquipmentService` sowie gegen Spoofing/Impersonation über RPC-Parameter ergab keine offene Lücke — Muster ist konsistent überall durchgesetzt: `player_id`/`peer_id` kommt in jedem `any_peer`-RPC-Handler ausschließlich aus `_sender_as_peer_id()`/`_sender_as_player_uuid()` (`multiplayer.get_remote_sender_id()`), nie aus einem Client-Parameter; `EquipmentService.on_equip_confirmed()` prüft `has_item()` gegen den tatsächlichen (autoritativen) Inventarstand; `report_domain_event()` transportiert bewusst nur wertlose Boolean-Ereignisse, nie Mengen, und `on_quest_complete_confirmed()` re-validiert ohnehin gegen den servergetrackten Fortschritt statt dem Trigger-Event zu vertrauen. Einziger dabei gefundener Nachholbedarf: siehe neuer TODO-Punkt "Regressionstest für `EquipmentService.on_equip_confirmed()`s `has_item()`-Besitzprüfung fehlt" oben (🟠-Abschnitt) — Testlücke, kein Sicherheitsloch.
  `test_network_bridge.gd` / `test_session_manager.gd` laufen weiterhin komplett
  gemockt in Tier 1 (unverändert). `tests/integration/test_movement_two_peer.gd`
  deckt weiterhin nur die Verbindungsebene ab (IT-01/IT-02, ein GUT-Prozess,
  zwei `ENetMultiplayerPeer` auf Loopback) — der volle Gameplay-Round-Trip
  (IT-03) lebt als eigener, echter Zwei-*Prozess*-CI-Job:
  `scripts/testing/IT03Harness.gd` (CI-only Autoload, per Cmdline-User-Arg
  aktiviert) + Job „IT-03 — Two-Process Movement Round Trip" in
  `build-apk.yml`. Zwei getrennte `godot --headless`-Prozesse mit vollem
  App-Boot (kein Mock), Client sendet organischen Input über
  `Player._loop_free_predicted()`, Assert über den öffentlichen Getter
  `Player.get_last_processed_input_seq()` (Round 50). **Round 51:** die
  Loopback-Lücke (keine Latenz, kein Paketverlust) ist jetzt ebenfalls
  geschlossen — `scripts/ci/udp_latency_proxy.py` sitzt als UDP-Relay
  zwischen Host- und Client-Prozess und simuliert künstliche
  Latenz/Jitter/Verlust (Default: 80ms±20ms, 2% Verlust pro Richtung,
  reines Python-stdlib, kein Extra-Dependency im Runner). **Verbleibend,
  bewusst nicht gelöst:** die Tier-2-Geräte-Grenzmessung — das ist ein
  Hardware-Leistungsfrage (schwächere CPU/GPU), keine Netzwerkfrage, und
  braucht entweder einen gedrosselten oder einen echten Mobile-Runner.
  Details siehe ADR-025/026 „Update (Round 51)". **Round 52:** die
  Mess-*Infrastruktur* für die Tier-2-Geräte-Grenze existiert jetzt
  (`Player.get_tier2_perf_stats()`, Terminal-Befehle `tier2stats`/
  `tier2reset`, volles Protokoll in `docs/tier2-device-verification.md`) —
  **die eigentliche Messung selbst ist damit NICHT erledigt**, sondern bleibt
  bewusst ein manueller Action-Item für den Project Owner: ADR-025 verlangt
  explizit einen gemessenen, nicht geschätzten Wert auf echter Hardware, was
  sich strukturell nicht in dieser Sandbox durchführen lässt (kein Zugriff
  auf ein physisches Referenzgerät).

## 🟠 Wichtig (offene Migrationen)

  einzigen verbliebenen `peer_id: int`-Kernservices aus der ADR-029-Familie
  (siehe Vorrecherche/Plan unten).**~~ **`StatModifierService`-Hälfte erledigt
  Round 69** (Produktivcode + alle 5 Aufrufer + beide unten dokumentierten
  Bugs + Tests). **`WorldService.get_player_visuals()`/`get_player_by_id()`
  wurde in Round 70 geprüft und stellte sich als kein echter Migrationsfall
  heraus** — siehe eigener TODO-Punkt direkt im Anschluss für die volle
  Begründung (kurz: beide Methoden sind peer-/verbindungsscoped wie
  `find_player_by_id()`/`resolve_for_player()`, Round 67 hat dieselbe
  Kategorie Fall bereits geklärt).

  **Umsetzung (Round 69):**
  - `StatModifierService`: `_players`-Dict auf `String`-Keys umgestellt,
    `player_id: String` Pflichtparameter ohne Default auf allen öffentlichen
    Methoden (`add_modifier`/`remove_modifier`/`get_effective_stat`/
    `get_modifiers_for_stat`/`has_modifier`/`remove_modifiers_with_prefix`/
    `cleanup_expired`/`clear_player`/`get_debug_report`) — identische
    Konvention zu `InventorySystem`/`QuestService`/`SkillSystem`/
    `EquipmentService` (Round 63–66). `cleanup_all_expired()` unverändert.
  - Alle 5 Aufrufer umgestellt: `RewardDispatcher.dispatch()` (bereits
    vorhandene `_resolve_player_uuid()`-Variable wiederverwendet),
    `EquipmentService` (die drei `_resolve_peer_id()`-Übersetzungsstellen für
    `StatModifierService` entfallen — `player_id` geht jetzt direkt durch;
    `_resolve_peer_id()` selbst bleibt, wird noch für
    `WorldService.get_player_visuals()` gebraucht), `CombatSystem` (siehe
    Bug A/B unten), `PlayerMover.get_current_speed(player_id: String)` +
    `Player.gd` (neue eigene `_resolve_player_uuid()`, Call-Site Zeile ~466),
    `InteractionResolver.resolve()` (Signatur erweitert um
    `player_id: String` als Pflichtparameter neben dem weiterhin
    bestehenden `peer_id: int` — Option (a) aus der Vorrecherche, siehe
    Begründung unten).
  - **Bug A (`CombatSystem.calculate_damage()`) behoben:** `damage_bonus`
    wurde vorher ohne jedes Id-Argument gelesen — strukturell immer der
    Default-Bucket, unabhängig vom tatsächlichen Angreifer
    (`record.attacker_peer_id` wurde komplett ignoriert). Fix: Gate auf
    `attacker_peer_id != -1`, Auflösung über dieselbe
    `_resolve_player_uuid()`-Stelle wie `player_melee_damage()`.
    Regressionstest `test_calculate_damage_reads_damage_bonus_of_correct_attacker_in_coop()`
    + `test_calculate_damage_skips_damage_bonus_without_attacker_peer_id()`
    in `tests/unit/test_combat_system.gd` (Round 69, nachgezogen — fehlten
    im ursprünglichen Plan-Zeitpunkt noch, Testlücke selbst gefunden und
    geschlossen).
  - **Bug B (`CombatSystem.roll_critical()`) behoben:** las vorher
    `source_id.to_int()` (das Entity-Typ-Label, z. B. `"player"`) als
    vermeintliche `peer_id` — `"player".to_int()` == `0`, also strukturell
    immer ein leerer Bucket, bisher maskiert weil kein Content einen
    `"crit_chance"`-Modifier registrierte. Fix: Signatur →
    `roll_critical(attacker_peer_id: int = -1)`, Call-Site →
    `roll_critical(record.attacker_peer_id)`.

  **Test-Sweep (Round 69, vollständig):** `test_stat_modifier.gd` (volle
  mechanische Überarbeitung, ~30+ Call-Sites), `test_property_based.gd`
  (S-01 bis S-08 auf `player_id`-Argument nachgezogen),
  `test_equipment_service.gd`/`test_equipment_ui.gd` (alle
  `has_modifier()`/`get_effective_stat()`-Aufrufe inkl. zweier stiller
  Int-Literal-Reste, `1`/`10` statt `"p1"`/`"p10"`), `test_player_gd.gd`
  (PM-04/05/06/08), `test_interaction_resolver.gd`/`test_harvestable_entity.gd`
  (bereits korrekt mit `player_id` verdrahtet). Beim Sweep zusätzlich zwei
  vorbestehende, unabhängige Testbugs gefunden und mitbehoben (keine
  Regression dieser Migration, aber ohne Fix hätten die betroffenen
  Testdateien nicht kompiliert/wären falsch grün gewesen):
  - `test_network_bridge.gd`/`test_network_bridge_contract.gd`: mehrere
    `SkillSystem`/`InventorySystem`-Aufrufe (`request_add_xp`, `get_xp`,
    `on_xp_add_confirmed`, `on_item_add_confirmed`) nutzten noch rohe
    Int-Literale (`1`, `2`) statt `"p1"`/`"p2"`, oder ließen `player_id`
    ganz weg — Rest aus der Round-63/65-Migration, der beim damaligen Sweep
    übersehen wurde.
  - `test_entity_context.gd`: `ctx.get_skill_system().get_level("woodcutting")`
    mit nur einem Argument — kompiliert nicht, weil `get_skill_system()`
    statisch `SkillSystem` zurückgibt (der Default, den die `MockSkillSystem`-
    Unterklasse für `player_id` ergänzt hatte, zählt nicht, da GDScript beim
    Aufruf gegen die statische Rückgabetyp-Deklaration prüft, nicht gegen
    die Laufzeit-Unterklasse). Fix: expliziter `player_id`-Arg am Call-Site.
  - `test_combat_system.gd`: `roll_critical("player")` (String) gegen die
    neue `roll_critical(attacker_peer_id: int = -1)`-Signatur — Typfehler,
    behoben durch Entfernen des jetzt bedeutungslosen Arguments (Test prüft
    nur das aggregierte Krit-Band, keine Attribution, `stat_modifiers` ist in
    diesem Testkontext ohnehin nicht injiziert).

  **Verhältnis zu ADR-030 (Zonen-System):** kein Blocker — `ZoneService`
  ist bewusst `peer_id`-gekeyt (live-connection-scoped, siehe Entscheidung
  dort), unabhängig vom Migrationsstatus dieser beiden Services. Reihenfolge
  ist Owner-Priorität, keine technische Abhängigkeit.

  `player_id: String` migrieren — letzter verbliebener `peer_id: int`-
  Kernservice aus der ADR-029-Familie.**~~ **Round 70: keine Migration —
  Planungsannahme war falsch, dieselbe Kategorie Fehler wie die
  `_sender_as_player_id()`-Gegenprüfung in Round 67.**

  Beide Methoden sind reine Fassaden auf
  `EntityOrchestrator.find_player_by_id(peer_id)`, die ausschließlich über
  das Entity-Meta `owner_peer_id` auflöst (siehe `resolve_for_player()`
  direkt daneben in derselben Datei) — exakt derselbe Mechanismus, den
  Round 67 für `_rpc_request_entity_interaction`/`_rpc_submit_movement_input`
  bereits geprüft und als **bewusst weiterhin `peer_id`-basiert** eingestuft
  hat: die Player-Node ist an die Verbindung gebunden, nicht an die stabile
  Identität, und existiert nach einem Reconnect ohnehin neu. Round 69s
  Handoff-Notiz hatte das übersehen und `get_player_by_id()`/
  `get_player_visuals()` fälschlich in dieselbe Kategorie wie die vier
  bereits migrierten Save-Bucket-Services (`InventorySystem`/`QuestService`/
  `SkillSystem`/`EquipmentService`) einsortiert — sind sie nicht: dort ist
  der Dict-Key selbst per-Spieler-persistiert, hier ist die Node im
  Szenenbaum grundsätzlich per-Verbindung.

  Gegenprobe an `EquipmentService._resolve_peer_id()`, dem einzigen
  produktiven Aufrufer von `get_player_visuals()`: die Methode übersetzt
  `player_id` über `_network.get_peer_id_for_player()` — eine reine
  Routing-Tabellen-Abfrage über die *aktuell verbundenen* Peers. Eine
  Signatur-Migration würde diese Übersetzung nicht einsparen, sondern nur
  eine Ebene tiefer in `WorldService`/`EntityOrchestrator` verschieben (die
  dafür neu von `NetworkBridge` abhängig würden, was sie heute bewusst
  nicht sind) — kein Netto-Fortschritt, nur verschobene Komplexität. Die
  beiden verbleibenden echten Aufrufer (`route_movement_input(peer_id)`,
  `resolve_and_dispatch_interaction(peer_id)`, beide `WorldService`-intern)
  führen ohnehin bereits genuine `peer_id`-Werte aus RPC-Absendern.

  **Nebenbefund: die "verifizierte Aufrufer-Liste" aus Round 69 war
  teilweise falsch.** `InventoryUIController`/`EquipmentUIController` rufen
  `get_player_visuals()` gar nicht auf — die einzigen Treffer dort sind
  Kommentare, die dokumentieren, dass die Autorität (`EquipmentService`) es
  stellvertretend für sie tut. Einziger echter Produktiv-Aufrufer:
  `EquipmentService._resolve_peer_id()`. `tests/IT03Harness.gd` ruft
  `get_player_by_id()` mit einer echten `local_peer_id` eines simulierten
  Test-Peers auf — ebenfalls kein Kandidat für `player_id: String`.

  **Fazit:** kein offener Migrationspunkt mehr. `EquipmentService.
  _resolve_peer_id()` bleibt bestehen (kein totes Coder mehr, wie Round 69
  noch vermutet hatte) — es ist der korrekte, dauerhafte Übersetzungspunkt
  für diesen einen Aufruf, analog zu `_sender_as_player_id()`.

  (`peer_joined`, `peer_left`, `server_started`, `client_connected_to_server`, …)
  parallel zu `EventBus.session`/`EventBus.networking` — ADR-018 hat nur den
  EventBus-Teil bereinigt, SessionManager selbst nicht.~~ — **geschlossen
  (Runde 53).** Alle acht eigenen Signale entfernt, `NetworkingEvents.gd` um
  die vier fehlenden Äquivalente ergänzt (`peer_joined`, `peer_left`,
  `peer_cleanup_requested`, `retry_attempt`); `WorldService` und
  `ServiceOrchestrator` verbinden sich jetzt über `EventBus.networking()`
  statt direkt auf die SessionManager-Instanz. Siehe ADR-018 „Update
  (Runde 53)" für die volle Herleitung.

## 🟡 Fehlt komplett (fehlt vs. "echtes" Spiel)

  — **erledigt (Round 73).** Neues optionales `@export var hint_text: String`
  auf `QuestCustomTrigger` — wenn gesetzt, wird es beim Betreten zusätzlich
  lokal über `EventBus.ui().emit_notification()` angezeigt
  (`NotificationController` ist bereits Konsument davon, keine Änderung dort
  nötig). Bewusst als eigenes Feld statt Lookup aus `QuestObjective.label`,
  um den Trigger nicht an `QuestService`/Quest-Daten zu koppeln (siehe
  Klassenkommentar). Default `""` = kein Popup, rückwärtskompatibel zu allen
  bestehenden Platzierungen. Eigener Guard mit `is_own_player`
  (`owner_peer_id == multiplayer.get_unique_id()`), NICHT nur `is_server()`:
  auf Tier 2/3 passiert der bestehende Autoritäts-Guard bereits für jeden
  Spieler, der die Zone betritt — auch für fremde Clients, die der Host bloß
  beobachtet. Ohne den zusätzlichen Guard hätte der Host ein Popup für die
  Entdeckung eines ANDEREN Spielers auf seinem eigenen Bildschirm gesehen.
  Der Domain-Event-Round-Trip (autoritative Objective-Erfüllung) bleibt davon
  unberührt — reine lokale Zusatzanzeige, keine neue Wahrheitsquelle. Drei
  neue Tests in `test_quest_custom_trigger.gd`
  (`test_hint_text_emits_notification_for_own_player`,
  `test_empty_hint_text_emits_no_notification`,
  `test_hint_text_not_shown_for_remote_player_observed_by_authority`).

  **umgesetzt (Round 74 Terrain/Zonen, Round 75 Props/Gegner).** Gefunden
  Round 73 beim Versuch, eine PvP-Zone "im Wüsten-Biom" zu platzieren
  (ADR-030-Folgearbeit): `BiomeRegistry.get_biome_for(temp, humid)`/
  `get_biome_id_for()` hatten **null Aufrufer** im gesamten `scripts/`-Baum.
  Round 74:
    - `TerrainGenerator`: neue, unabhängige `_humidity_noise` (eigener Seed/
      Frequenz, s. dortiger Kommentar) ergänzt die bestehende `_biome_noise`
      als zweite Achse; neue `get_biome_at()`/`get_biome_id_at()` — beide
      rufen jetzt tatsächlich `BiomeRegistry.get_biome_for()`/
      `get_biome_id_for()` auf. `_biome_noise`/`_get_biome_factor()` für den
      Höhen-Multiplikator bewusst UNVERÄNDERT gelassen (kein Risiko für
      bestehende Terrain-Form).
    - `TerrainColorizer.height_to_color()`/`TerrainMeshBuilder`: der
      synthetische `0..1`-dry/lush-Lerp ist ersetzt durch die echte
      `BiomeDefinition.terrain_color_grass`-Farbe der jeweiligen Weltposition
      (`TerrainGenerator._get_biome_color()`) — Wasser/Sand/Hügel/Fels/Schnee-
      Bänder (höhenbasiert) unverändert, nur die Gras-Farbe kommt jetzt aus
      der Registry statt aus einer Konstante.
    - **Neu:** `DesertPvpZonePlacer` (`scripts/world/zones/`) — sucht zur
      Laufzeit spiralförmig um den Ursprung nach der ersten `"desert"`-Position
      (`TerrainGenerator.get_biome_id_at()`) und platziert dort eine PvP-
      `ZoneTriggerVolume`, aufgerufen aus `WorldService.on_world_scene_ready()`.
      Läuft auf jedem Peer identisch (feste globale Biom-Seeds, kein
      `is_server()`-Guard nötig). Suchlogik (`_find_desert_position()`) per
      Unit-Test mit Fake-Lookup abgedeckt (`test_desert_pvp_zone_placer.gd`);
      der Godot-Node-Teil (`place()`) NICHT — gleiche strukturelle Grenze wie
      bei den `_rpc_receive_*`-Handlern oben, hier zusätzlich nie gegen echte
      Godot-Laufzeit verifiziert.
  Round 75 (Anfrage "vermehrt Skelette und Kakteen"):
    - `ChunkEntitySpawner`: `_spawn_trees()` → `_spawn_props()`, jetzt echt
      biom-gewichtet über `BiomeDefinition.prop_chances`; neue `_spawn_enemy()`
      analog über das neue `BiomeDefinition.enemy_chances`-Feld (bewusst
      getrennt von `prop_chances` — Gegner sind Kampf-Entities, keine
      Deko/Harvestables, siehe dortiger Kommentar). Biom wird einmal pro
      Chunk am Chunk-Zentrum gesampelt, nicht pro Prop (Performance/
      Genauigkeits-Tradeoff, siehe Klassenkommentar).
    - Neue `WorldEntityRegistry.KNOWN_PROP_TYPES`/`KNOWN_ENEMY_TYPES` — Single
      Source of Truth, gegen die `prop_chances`/`enemy_chances`-Einträge
      gefiltert werden. Verhindert, dass nicht registrierte Typen (`cactus`,
      `rock_boulder`, `fallen_tree`, `mushroom_cluster`, `fern`, `pine_tree`)
      `EntityRegistry.instantiate()`-Fehler-Logs fluten — sie werden
      still­schweigend übersprungen statt zu spawnen.
    - `desert.enemy_chances = {"skeleton": 0.06}` — spawnt tatsächlich
      (`"skeleton"` ist registriert). `desert.prop_chances` (`cactus`,
      `rock_boulder`) spawnt weiterhin NICHT — beide fehlen in
      `KNOWN_PROP_TYPES`, s.u.
    - Tests: `test_chunk_entity_spawner_biome.gd` (reine `_roll_weighted_type()`-
      Logik + Regressionsschutz, dass `desert` wirklich `skeleton` in
      `enemy_chances` hat).
  **Korrektur (Round 86):** Beim Versuch, diesen Punkt umzusetzen, festgestellt,
  dass er bereits erledigt war — nur die TODO-Zeile war stehen geblieben.
  `FallenTree.gd`, `Fern.gd`, `MushroomCluster.gd`, `RockBoulder.gd` existieren
  bereits in `scripts/world/objects/`, sind vollständig (Typ-ID,
  `InteractableData` inkl. Loot-Tabelle, `_build_visuals()` → passende
  `Factory3D.create_X()`-Methode) und bereits in
  `WorldEntityRegistry.register_all()` + `KNOWN_PROP_TYPES` eingetragen — die
  eigenen Klassenkommentare datieren die Arbeit auf Round 79 (`RockBoulder.gd`
  nennt zusätzlich einen erwähnten, aber nie ausgelieferten "Round 78" —
  offenbar dort verlustig gegangen und in Round 79 nachgezogen, ohne dass
  diese TODO-Zeile mit aktualisiert wurde). Zugehörige Loot-Tabellen
  (`loot_fallen_tree.tres`, `loot_fern.tres`, `loot_mushroom_cluster.tres`,
  `loot_rock_boulder.tres`) liegen ebenfalls bereits in
  `data/loot_tables/`. Kein Code geändert — reine Doku-Korrektur. Damit ist
  **kein** Content aus der ursprünglichen fünfteiligen Liste mehr offen; siehe
  `test_chunk_entity_spawner_biome.gd`/`test_factory3d_nature.gd` für die
  bestehende Testabdeckung (Biom-Gewichtung bzw. Factory-Visuals — die
  dünnen Entity-Wrapper selbst haben bewusst keine eigenen Unit-Tests, gleiche
  Konvention wie bei `Cactus.gd`/`PineTree.gd`/`OakTree.gd`).

  **Ursprünglicher Stand (Round 77), zur Nachvollziehbarkeit belassen:**
  `rock_boulder`/`fallen_tree`/`mushroom_cluster`/`fern` hatten damals **keinen**
  registrierten Entity-Typ (Props: `oak_tree`/`willow_tree`/`maple_tree`/`iron_ore`/
  `copper_ore`/`cactus` (Round 76), `pine_tree`/`ice_crystal` (Round 77),
  Gegner: `goblin`/`skeleton`, siehe `WorldEntityRegistry.gd`). `pine_tree`
  ist mit Round 77 erledigt (`PineTree.gd`, siehe dortiger Eintrag) —
  `ice_crystal` war ursprünglich hier gar nicht gelistet (kein
  `winter.prop_chances`-Eintrag existierte), wurde aber im selben Round auf
  Wunsch neu ergänzt (Biom-Eintrag UND Entity-Typ). Gleiches Muster wie bei
  Cactus/PineTree: sobald ein Entity-Skript für z.B. `fern` existiert und in
  `WorldEntityRegistry.register_all()` + `KNOWN_PROP_TYPES` eingetragen wird,
  spawnt es automatisch über die bereits vorhandenen `prop_chances`-Angaben —
  kein weiterer Verdrahtungs-Code nötig, nur der fehlende Content selbst.
  **Korrektur (Round 76, Cactus-Nachtrag):** "fehlender Content" war zu
  pessimistisch formuliert — die eigentliche Visual-Arbeit für alle fünf steckt
  bereits fertig in `Factory3D`/`MeshCache` (`create_pine_tree()`,
  `create_fern()`, `create_fallen_tree()`, `create_mushroom_cluster()`,
  `create_rock_boulder()`, je mit eigenem Test in `test_factory3d_nature.gd`),
  nur bisher ohne Aufrufer. Es fehlt jeweils nur die dünne Entity-Wrapper-Klasse
  nach `Cactus.gd`/`OakTree.gd`-Muster (Typ-ID, `InteractableData`,
  `_build_visuals()` → `factory.create_X(self)`) + Registrierung — keine neue
  Mesh-/Prefab-Arbeit nötig.


  **umgesetzt (Round 47).**
  [ADR-024](adr/024-server-side-movement-validation.md) (Plausibilitätsfilter)
  ist **abgelöst** von
  [ADR-025](adr/025-server-authoritative-movement.md) (Server-autoritatives
  Movement, Input statt Position) und
  [ADR-026](adr/026-client-side-prediction-reconciliation.md) (Client-Side
  Prediction & Reconciliation) — Zielniveau ist jetzt Server-Simulation als
  einzige Wahrheit statt ein enger gezogener Filter auf eine weiterhin
  client-autoritative Position. Beide ADRs zusammen als ein Umsetzungsschritt
  implementiert (Authority-Flip, reines `PlayerMover.calculate_velocity()`,
  Input-RPC, Prediction-Ringpuffer, Reconciliation). Determinismus-Voraussetzung
  durch Unit-Test `PM-07` verifiziert. **Offen geblieben:** der geforderte
  echte Zwei-Peer-Integrationstest unter realer Latenz (siehe TODO-Punkt oben)
  sowie die Tier-2-Geräte-Grenzmessung (siehe ADR-025 „Umsetzungsstand") — beide
  ehrlich als nicht erfüllt markiert, siehe jeweiliges ADR.
- [ ] **NEU (2026-08, Spike vorgemerkt):** Wirkung der Charakterzüge aus
      der Charaktererstellung (ADR-048) — noch nicht entschieden zwischen
      (a) reiner Flavor-Wirkung (NPC-Dialoge/Reaktionen lesen
      `CharacterCreationService.get_traits()`) und (b) echten Stat-Boni
      (z.B. über `StatModifierService`). `get_traits()` existiert bereits,
      damit ein künftiger Spike ohne Datenmodell-Umbau andocken kann.
- [ ] **AKTUALISIERT (2026-08, Round 108):** Spielerbefülltes Wiki —
      Backend UND UI-Panel fertig. `WikiService`
      (`scripts/progression/wiki/WikiService.gd`, ADR-049) deckt alle
      vier Kategorien ab (Gegner, Drop-Rates, Skills, Quests), pro
      Spieler lokal, automatisch aus `DataService` abgeleitet UND an
      tatsächliche Entdeckung gekoppelt. `WikiPanelVisuals`/
      `WikiPanelController`/`WikiPanelComponent`
      (`scripts/progression/wiki/ui/`, Round 108) zeigen unentdeckte
      Einträge als "🔒 ???", programmatisch gebaut analog
      `AchievementPanelVisuals`, Toggle 📖 bei Offset 400–480. **Offen:**
      keine echte `EnemyDefinition`-Ressource
      (`ENEMY_LOOT_TABLE_MAP`-Fallback stattdessen, siehe ADR-049), kein
      Zwei-Peer-Integrationstest für den RPC-Rückkanal.
- [ ] **Umgraben/Bauen im Koop (Tier 2/3).** Gelände-Änderungen
      (WorldData.terrain_edits) und Bauteile (WorldData.build_registry) sind
      vorerst SOLO-ONLY: in Mehrspieler-Sitzungen sind sie ausgeschaltet und
      unsichtbar, damit Host und Clients nicht verschiedene Welten sehen
      (WorldService._edits_active). Fehlt: (1) Broadcast von
      Delta-/Record-Änderungen über NetworkBridge.broadcast_to_all_peers, (2)
      Snapshot beim Beitritt (get_full_state enthält die Save-Keys schon, aber
      apply_remote_state baut Chunks nicht neu), (3) Client-Wünsche an den
      Server (build_place_requested nur auf der Autorität ausführen).
      Architektur + Erweiterungspunkt: docs/terrain-and-building.md. Außerdem
      offen: Schwimmen/Waten (TerrainField.get_water_depth_at ist der Haken),
      Bauteil-Trefferpunkte/Besitzrechte, bestehende Bäume folgen späteren
      Geländeänderungen nicht.

## 🟢 Kurz zu verifizieren (vermutlich ok, aber nicht geprüft)

(keine offenen Punkte mehr in dieser Kategorie)

---

## Nächster Schritt

**Round 112 — ADR-050 Phase 2, erster Migrations-Batch (Bank, 3 Signale).**
Auf "Fang an" wurde der erste tatsächliche Signal-Batch umgesetzt statt nur
geplant: `deposit_completed`/`withdraw_completed`/`transaction_failed` von
`BankService` sind jetzt `EventBus.bank()` (neue `BankEvents.gd`,
Path B/ADR-012) statt native Signale. Beide Konsumenten
(`BankUIController`/`AuctionHouseUIController`) umgestellt, Tests
nachgezogen, `BootstrapConfig.tres` um `event_bus`-Dep ergänzt (Round-98-
Bug-Präzedenzfall von vornherein vermieden). Volle Aufschlüsselung siehe
ADR-050 „Nachtrag (Round 112)". Davor, im selben Round: die vier
verbleibenden NEEDS_HUMAN-Namenskollisionen aus Round 110/111 einzeln über
Signatur-/Connect-Ziel-Vergleich aufgelöst (kein Raten) — siehe ADR-050
„Nachtrag (Round 111)" für die volle Tabelle. Phase 1 ist damit
abgeschlossen. **Ehrlich offen:** wie immer — kein Godot-Editor/Headless-
Runner verfügbar, nur strukturell geprüft (Klammern-Balance, Signaturen
gegen echte Service-APIs). Als Nächstes: weitere economy-Sub-Batches
(Currency/Inventory/Equipment einzeln, oder die AuctionHouse/Shop/Trade-
Hälfte der `transaction_failed`/`purchase_completed`-Kollision), dann
progression/ (7 Signale), networking/ (7), onboarding/ (3).

**Round 111 — ADR-050 Phase 4 gebaut (`service_graph.py --native-signals`),
Phase 1 zu 14/18 mechanisch erledigt statt nur konzeptionell offen.**
Auf Nachfrage ("schau dir das an") wurden die 7 verbliebenen NEEDS_HUMAN-
Fälle aus Round 110 einzeln untersucht statt pauschal auf ".tscn nötig"
verwiesen — vier echte Tool-Lücken gefunden und in
`analyze_native_signals.py` behoben, nicht nur dokumentiert:
1. `multiplayer.connection_failed`/`server_disconnected` waren Fehltreffer
   auf Godots eingebautes `MultiplayerAPI`-Singleton, nicht auf unsere
   eigenen gleichnamigen Signale (die haben projektweit null echte
   Connects) — neue `ENGINE_BUILTIN_SINGLETONS`-Ausschlussliste.
2. `toggled`/`entry_added` (`SimpleTerminalUI._terminal = get_parent()`) —
   Scene-Tree-Traversal wurde bisher nicht als "direkt" erkannt, nur
   `.new()`. Neuer `SCENE_TREE_RE`-Marker.
3. `on_log` (`AppLogger`, Godot-AutoLoad) — AutoLoads sind global ohne DI
   erreichbar, zählen aber bisher nicht als Cross-Layer-Marker. Neue
   `AUTOLOAD_NAMES`-Liste, automatisch aus `project.godot`s
   `[autoload]`-Sektion geladen (kein Hardcoding).
4. `character_creation_confirmed` (`_svc()`-Helper) und `died`
   (`PlayerSetup.build(self)` → Dictionary-Return → `HealthComponent.new()`)
   — DI-Lookups bzw. direkte Konstruktion, aber hinter einem oder mehreren
   Funktionsaufrufen versteckt. Neue scope-saubere Ausdrucksauswertung
   (`_eval_expr`/`_resolve_call`/`_resolve_dict_value`) mit
   Klassen-Index (`CLASS_FILE_INDEX`, aus `class_name`-Deklarationen) für
   cross-file statische Aufrufe.

Ergebnis: von den ursprünglich 18 NEEDS_HUMAN-Fällen sind nur noch die 4
echten Namenskollisionen übrig (`close_requested`, `health_changed`,
`purchase_completed`, `transaction_failed`) — die bleiben absichtlich
NEEDS_HUMAN (ADR-050 Phase 1 verlangt hier Handarbeit, kein Automatismus,
siehe "Alternativen erwogen"). Neue Gesamtzahlen: LOCAL 52 / CROSS_LAYER 35
/ NEEDS_HUMAN 4 (vorher 21/52/18). `docs/manager/reports/native-signal-
categorization.md` und ADR-050 selbst sind bei jedem `make
signal-categorize`-Lauf ohnehin live neu berechnet, kein manueller Nachtrag
nötig.

**ADR-050 Phase 4** (neuer `service_graph.py`-Finding-Typ) ist jetzt
ebenfalls gebaut: `python3 scripts/agent/service_graph.py --native-signals`
(`make signal-migration-status`) importiert `analyze_native_signals.py`
direkt statt die im ADR-Text noch beschriebene, mittlerweile überholte
"gleicher ui/-Ordner"-Heuristik zu reimplementieren — ein zweiter,
einfacherer Klassifikationspfad hätte hier exakt das "zwei Kanäle für
dieselbe Tatsache"-Problem reproduziert, vor dem ADR-050 selbst warnt, nur
auf Tool-Ebene. Neuer WARN-Finding `NATIVE_SIGNAL_EXTERNAL_CONNECT`, einer
pro CROSS_LAYER-Signal — kostenloser Regressionsindikator für Phase 2: die
Zahl sollte nach jedem Migrations-Batch sinken, nie stillschweigend wieder
steigen. Bewusst NICHT im Default-Lauf von `service_graph.py` (eigener,
teurerer Scan, analog `--claims`) — WARN-only, kein Fail-Exit.

**Phase 2 (35 CROSS_LAYER-Signale in Domain-Batches migrieren) ist der
nächste inhaltliche Schritt**, sobald gewünscht — Reihenfolge/Batches siehe
ADR-050. Phase 1 ist mit den 4 verbleibenden Namenskollisionen fast fertig
(eigene, kleine Entscheidungsrunde pro Kollisionsgruppe, siehe ADR-050
Phase 1).

**Round 110 — Datengrundlage/Konzept für Punkt 5 (native-Signal-Migration)
geschaffen, ADR-050 verfasst.** [siehe Punkt 5 oben für die volle
Herleitung; Konzept steht, Umsetzung startete mit Round 111 oben].

**Round 69 — `StatModifierService`-Hälfte abgeschlossen; Round 70 — zweite
Hälfte geprüft und als kein echter Migrationsfall verworfen:** Round 69s
Produktivcode, alle 5 Aufrufer, beide dabei gefundenen Bugs (A: `damage_bonus`
las nie den echten Angreifer; B: `roll_critical()`s Crit-Chance-Modifier-Lookup
war strukturell tot) und der volle Test-Sweep sind erledigt. Round 70 hat die
vermeintlich verbleibende Hälfte (`WorldService.get_player_visuals()`/
`get_player_by_id()`) untersucht und festgestellt, dass sie — anders als
Round 69s Handoff-Notiz annahm — **nicht** zur ADR-029-Familie gehört: beide
Methoden sind reine Fassaden auf denselben peer-/verbindungsscoped
`find_player_by_id()`-Mechanismus, den Round 67 bereits für die vier
verbleibenden `_rpc_*`-Handler geprüft und bewusst bei `peer_id: int`
belassen hat. Kein Code geändert, nur die TODO-Punkte oben korrigiert
(siehe dort für die volle Begründung inkl. der Korrektur der Round-69-
Aufrufer-Liste). **Die ADR-029-Familie ist damit vollständig abgeschlossen** —
alle vier Save-Bucket-Services migriert (Round 63–66), `StatModifierService`
migriert (Round 69), die verbleibenden peer-/verbindungsscoped Stellen
(`_sender_as_player_id()`-Handler, `find_player_by_id()`/`resolve_for_player()`,
`get_player_by_id()`/`get_player_visuals()`) bewusst und geprüft bei
`peer_id: int` belassen. **Round 70–72: ADR-030 (Zonen-System) — Mechanik + Client-Broadcast stehen.** `ZoneService`, `ZoneConfig`, `ZoneTriggerVolume`, `EventBus.zones()`-Namespace, Service-Registrierung + `WorldService`-Verdrahtung (Round 70); `NetworkBridge.send_zone_update_for_peer()`/`_rpc_receive_zone_update()` (Round 72) — der betroffene Client bekommt seine eigene Zonen-Mitgliedschaft jetzt per gezieltem RPC mitgeteilt, angewendet über dieselbe `ZoneService`-API wie auf der Autorität. Details siehe ADR-030 „Implementierungsnotizen (Round 70)"/„(Round 72)". Bewusst ungetestet: `_rpc_receive_zone_update()`s `is_server()`-Guard — jetzt konsolidiert mit den beiden anderen identisch betroffenen Handlern in einem TODO-Punkt (siehe "Zwei-Peer-Integrationstests für alle `_rpc_receive_*`-Handler" oben). Offen für Folge-Runden: tatsächliche Zonen-Platzierung in den Weltszenen (Level-Design, keine Mechanik mehr), `QuestCustomTrigger`-Migration (out of scope laut ADR), danach 031–039.

**Round 73 — `QuestCustomTrigger` bekommt lokales Sofort-Feedback (`hint_text`).**
Kein ADR-030-Folgepunkt, sondern eine eigenständig gefundene Lücke: das lokale
`custom_objective_triggered`-Signal (ADR-021) hatte anders als
`interaction_finished`/`npc_talked_to` keinen UI-Konsumenten und feuerte ins
Leere. Behoben über ein neues optionales `hint_text`-Feld auf dem Trigger
selbst (kein Lookup aus Quest-Daten, siehe dortiger Kommentar) — Details und
Guard-Begründung siehe TODO-Punkt oben. Kein ADR-030-Code geändert, `ZoneTrigger-
Volume` unberührt.

**Round 74 — PvP-Zone im Wüsten-Biom (Anfrage) + `BiomeRegistry` erstmals
verdrahtet.** Beim Platzieren-Versuch aufgefallen: `BiomeRegistry` war totes
Datenmodell (eigener TODO-Punkt oben, jetzt teilweise erledigt). Umgesetzt:
zweite (Feuchtigkeits-)Noise-Achse in `TerrainGenerator`, echte
`BiomeRegistry`-Abfrage für Terrain-Grasfarbe (`TerrainColorizer`/
`TerrainMeshBuilder` entsprechend angepasst), neues `DesertPvpZonePlacer`
(sucht zur Laufzeit die erste Wüsten-Koordinate statt einer geratenen
Fixkoordinate, s. dortiger Klassenkommentar) — aufgerufen aus
`WorldService.on_world_scene_ready()`. Prop-Spawning je Biom (Kaktus etc.)
bewusst nicht angegangen — fehlende Entity-Typen, siehe TODO-Punkt. Zusätzlich
konsolidiertes TODO für alle drei `_rpc_receive_*`-Handler mit demselben
untestbaren `is_server()`-Guard (vorher an drei Stellen verstreut erwähnt).
`ZoneTriggerVolume`/ADR-030-Kernmechanik weiterhin unberührt. Als Nächstes:
ADR-031 (Permission/Role-System).

**Round 75 — Prop-/Gegner-Spawning tatsächlich biom-gewichtet ("vermehrt
Skelette und Kakteen").** `ChunkEntitySpawner._spawn_trees()` →
`_spawn_props()`, jetzt über `BiomeDefinition.prop_chances`; neues
`enemy_chances`-Feld + `_spawn_enemy()` für Gegner (bewusst getrennt von
Props). Neue `WorldEntityRegistry.KNOWN_PROP_TYPES`/`KNOWN_ENEMY_TYPES` als
Filter — nur tatsächlich registrierte Typen spawnen wirklich.
`desert.enemy_chances = {"skeleton": 0.06}` spawnt jetzt echt (registriert).
Kaktus spawnt jetzt (Round 76). `ZoneTriggerVolume`/ADR-030
unberührt. Als Nächstes: ADR-031 (Permission/Role-System) — oder, falls
gewünscht, Cactus-Entity als eigener Content-Schritt.

**Round 76 — Cactus-Entity angelegt, letzte Lücke aus Round 74/75 geschlossen.**
Neues `Cactus.gd` (`extends HarvestableEntity`, wie `OakTree`/`IronOre`),
registriert in `WorldEntityRegistry.register_all()` + `KNOWN_PROP_TYPES`.
Neuer Skill `foraging` (`data/skills/foraging.tres`, in `DataManifest.SKILLS`)
— erster echter Konsument, vorher nur `farming` tot-registriert ohne
Nutzung. Neues Item `cactus_fiber` (`data/items/CactusFiber.tres`, in
`DataManifest.ITEMS`) + `data/loot_tables/loot_cactus.tres`. Keine Änderung
an `ChunkEntitySpawner`/`BiomeRegistry` nötig — `desert.prop_chances["cactus"]`
stand seit Round 74 schon bereit, greift jetzt automatisch. Reminder-Test aus
Round 75 (`test_desert_biome_cactus_is_correctly_unspawnable_for_now`)
umgedreht zu `test_desert_biome_cactus_is_now_spawnable`. `ZoneTriggerVolume`/
ADR-030 unberührt.
**Nachtrag (noch Round 76):** `_build_visuals()` hatte zunächst eigene
Kaktus-Meshes von Hand gebaut (Stamm + 2 Arme), obwohl `Factory3D.create_cactus()`
bereits ein fertiges, gecachtes Prefab dafür liefert (samt `create_pine_tree()`/
`create_fern()`/`create_fallen_tree()`/`create_mushroom_cluster()`/
`create_rock_boulder()` — alle ungenutzt, nur von `test_factory3d_nature.gd`
aufgerufen). Ursache: Recherche vor dem Schreiben hat `WorldEntityRegistry`
geprüft ("gibt's einen Entity-Typ"), aber nicht `Factory3D`/`MeshCache`
("gibt's schon eine fertige Visual-Funktion"). Korrigiert auf
`factory.create_cactus(self)`, exakt nach dem `OakTree`-Muster
(`factory.create_simple_tree(self)`), inkl. Placeholder-Fallback falls
`Factory3D` nicht verfügbar ist. Das Duplikat ist raus. Als Nächstes:
ADR-031 (Permission/Role-System).

**Round 77 — PineTree- und IceCrystal-Entity angelegt (Anfrage), zweite
Content-Lücke aus Round 75/76 geschlossen.** Neues `PineTree.gd`
(`extends HarvestableEntity`, wie `OakTree`/`Cactus`), registriert in
`WorldEntityRegistry.register_all()` + `KNOWN_PROP_TYPES` — `winter.
prop_chances["pine_tree"]` stand seit Round 74 schon bereit, greift jetzt
automatisch, kein `ChunkEntitySpawner`/`BiomeRegistry`-Code geändert.
Visual über `Factory3D.create_pine_tree(self, true)` (Schnee-Variante,
existierte bereits fertig, nur ohne Aufrufer — gleiches Muster wie
`create_cactus()` in Round 76). Skill `woodcutting` (wie `OakTree`), neues
Item `log_pine` (`data/items/LogPine.tres`) + `data/loot_tables/
loot_pine_tree.tres`.

Zusätzlich (auf Wunsch, "gleicher Skill wie bei Kakteen"): neues
`IceCrystal.gd`, Foraging-Interaktion analog `Cactus.gd`
(`xp_type = "foraging"`, `yield_stat_id = "gathering_yield_foraging"`).
Anders als PineTree/Cactus gibt es in `Factory3D` noch **kein** fertiges
Prefab dafür (`create_ice_crystal()` existiert nicht — geprüft gegen die
Methodenliste in `Factory3D.gd`) — Visual ist deshalb bewusst ein
dauerhafter Placeholder nach `IronOre`-Muster (`_add_placeholder_box()`),
nicht der Factory3D-Fallback-Pfad wie bei Cactus/PineTree, da es aktuell
keine bessere Alternative gäbe. `winter.prop_chances` hatte bisher **keinen**
`ice_crystal`-Eintrag (anders als `pine_tree`, das schon seit Round 74
bereitstand) — mit `0.07` neu ergänzt (`BiomeRegistry._make_winter()`),
analog zum Cactus/Desert-Muster aus Round 74/75. Neues Item `ice_crystal`
(`data/items/IceCrystalShard.tres`) + `data/loot_tables/
loot_ice_crystal.tres`. Beide neuen Items in `DataManifest.ITEMS` ergänzt.

Damit ist von der Round-76-„weiterhin offen"-Liste (`rock_boulder`/
`fallen_tree`/`mushroom_cluster`/`fern`/`pine_tree`) nur noch `pine_tree`
abgehakt — `rock_boulder`/`fallen_tree`/`mushroom_cluster`/`fern` haben
weiterhin kein Entity-Skript, obwohl ihre Factory3D-Prefabs ebenfalls
bereits fertig sind (`create_fern()`/`create_fallen_tree()`/
`create_mushroom_cluster()`/`create_rock_boulder()`) — gleiches Muster,
falls als Nächstes gewünscht. `ZoneTriggerVolume`/ADR-030 unberührt.

**Round 78 — `rock_boulder` bekommt einen Entity-Typ + neues Biom "Gebirge"
(Anfrage).** Root-Cause-Check vor dem Coden: `rock_boulder` stand bereits in
VIER `prop_chances` (`forest` 0.03, `meadow` 0.02, `desert` 0.08, `winter`
0.06) — komplett ungenutzt, da wie `cactus`/`pine_tree` vor ihrer jeweiligen
Round kein registrierter Entity-Typ existierte (fehlte in
`WorldEntityRegistry.KNOWN_PROP_TYPES`, siehe Round-76-„weiterhin offen"-
Absatz oben). Neues `RockBoulder.gd` (`extends HarvestableEntity`, Mining-
Interaktion analog `IronOre`/`CopperOre`, kein `yield_stat_id` — gleiche
Konvention wie bei den beiden Erzen, anders als Holz/Foraging), registriert
in `WorldEntityRegistry.register_all()` (Gruppe `"ores"`, mineralisch wie
Erz, keine neue Gruppe) + `KNOWN_PROP_TYPES` — spawnt dadurch jetzt in
**allen vier** bereits bestehenden Biomen, nicht nur im neuen. Visual über
das bereits fertige, biom-eingefärbte `Factory3D.create_rock_boulder(self,
biome_id)` (existierte seit vor Round 74, nur ohne Aufrufer — der
`match biome_id`-Zweig hatte sogar schon `"desert"`/`"winter"`-Fälle
vorbereitet, aber niemand rief die Methode je auf). Neues Item `stone`
(`data/items/Stone.tres`) + `data/loot_tables/loot_rock_boulder.tres`.

Für "Gebirge" selbst gab es noch **kein** Biom — anders als bei
Cactus/PineTree/IceCrystal (dort ging's nur um fehlenden Content für
bereits bestehende `prop_chances`-Einträge). `BiomeRegistry._resolve_id()`
kennt bisher nur zwei Achsen (temp/humid, Round 74) und keine Höhen-/
Elevations-Achse — ein "echtes" Gebirge (hohe Terrain-Höhe) hätte eine
dritte Achse gebraucht, die den `get_height_at()`-Heightmap-Wert mit der
Biom-Wahl verknüpft; das wäre ein größerer Architektur-Schnitt gewesen
(TerrainGenerator generiert Höhe und Biom bisher komplett unabhängig
voneinander, siehe Klassenkommentar dort) und stand nicht zur Debatte für
diese Anfrage. Stattdessen, im bereits etablierten Bucket-Muster (wie
Round 74 "desert"/"winter" auf temp/humid gelegt hat): neue Nische
`temp < -0.5` bleibt `winter`, aber ein bisher unbenutzter Bereich direkt
daneben (`-0.5 ≤ temp < -0.15`, trocken/`humid ≤ 0`) fiel vorher
unterschiedslos auf `meadow` — dieser Ausschnitt ist jetzt `mountain`
("kalt und trocken" statt "gemäßigt und trocken"), warm-trockenes `meadow`
bleibt bei `temp ≥ -0.15` unverändert. `mountain.terrain_color_grass`
bewusst steinern-grau statt grün (siehe Klassenkommentar in
`BiomeRegistry._make_mountain()`). `rock_boulder` dort mit 0.30 deutlich
höher gewichtet als in den vier Nebenrollen-Biomen — hier die
Hauptattraktion; zusätzlich ein kleiner `pine_tree`-Anteil (0.06,
"vereinzelte Baumgrenze"), kein eigenes `snow_coverage`.

`Factory3D.create_rock_boulder()` bekommt einen eigenen `"mountain"`-Fall
im `match biome_id` (dunkleres Granitgrau statt dem generischen
Default-Grau) — reine Politur, der generische Fallback wäre für Gebirge
ebenfalls plausibel gewesen. `RockBoulder._build_visuals()` übergibt
`"mountain"` fest als `biome_id`-Parameter (Entity kennt sein eigenes Biom
nicht, siehe dortiger Klassenkommentar — gleiche strukturelle Lücke wie bei
jedem anderen `HarvestableEntity`, keine neue).

Tests: `test_biome_registry.gd` (alle Sechs-Biome-Arrays auf sieben erweitert,
`test_all_six_biomes_registered` → `test_all_seven_biomes_registered`, neue
Grenzfall-Tests `test_cold_dry_gives_mountain`/
`test_mountain_boundary_stays_meadow_when_not_cold_enough`,
`test_mountain_has_rock_boulder_prop`), `test_chunk_entity_spawner_biome.gd`
(`test_mountain_biome_rock_boulder_is_now_spawnable`, analog zum
Cactus-Regressionstest aus Round 76), `test_factory3d_nature.gd`
(`"mountain"` im Biom-Farb-Crashtest ergänzt). `ZoneTriggerVolume`/ADR-030
unberührt. Als Nächstes: `fallen_tree`/`mushroom_cluster`/`fern` (gleiches
Muster, Prefabs bereits fertig) — oder ADR-031 (Permission/Role-System).

**Round 79 — "Wald: Pilze & viel Baum spawn" + neues Biom "Toter Wald"
(Anfrage).** Zwei Entity-Typen nachgezogen, gleiches Root-Cause-Muster wie
Round 78 (`rock_boulder`): `mushroom_cluster` stand bereits in drei
`prop_chances` (forest/dense_forest/swamp), `fallen_tree` in vieren
(forest/dense_forest/winter/swamp) — beide ohne registrierten Entity-Typ,
beide überall stillschweigend gefiltert. Neue `MushroomCluster.gd`
(Foraging, gleicher Skill wie Cactus/IceCrystal, Typ zufällig aus
`Factory3D`s drei bereits fertigen Farbvarianten "brown"/"red"/"orange" —
bisher hatte das noch niemand aufgerufen) und `FallenTree.gd` (Woodcutting,
Drop bewusst das bereits existierende generische `log_normal`-Item statt
eines neuen "Rotholz"-Items — kein Content-Bedarf für eine eigene
Holzsorte). Beide in `WorldEntityRegistry.register_all()` (`fallen_tree` →
Gruppe `"trees"`, `mushroom_cluster` → Gruppe `"plants"`) +
`KNOWN_PROP_TYPES` registriert — spawnen dadurch automatisch in ALLEN
Biomen, die sie bereits in `prop_chances` listen, nicht nur den neu
angefassten. Neue Items `wild_mushroom` (`data/items/WildMushroom.tres`) +
`data/loot_tables/loot_mushroom_cluster.tres`/`loot_fallen_tree.tres`
(letztere nutzt `log_normal`, kein neues Item nötig).

**"Wald" (forest) getunt** — `oak_tree` von 0.15 auf 0.28 fast verdoppelt
("viel Baum spawn"), `mushroom_cluster` von 0.08 auf 0.12 leicht erhöht
("Pilze", zusätzlich zur reinen Spawnbarkeit selbst). `dense_forest` bewusst
NICHT angefasst — Anfrage nannte explizit "Wald", nicht "dichter Wald".

**Neues Biom "Toter Wald" (`dead_forest`)** — gleiche strukturelle Lücke wie
"Gebirge" in Round 78: kein bestehendes Biom passte, `_resolve_id()` bekommt
eine weitere Nische im etablierten Bucket-Muster statt einer neuen Achse.
Bisher fiel jede "warm-trockene" Zone (temp ≥ -0.15, humid ≤ 0)
unterschiedslos auf `meadow` — der besonders trockene Ausschnitt davon
(humid < -0.5) wird jetzt `dead_forest` (Bäume, die an Wassermangel
eingegangen sind), gemäßigt-trocken (humid zwischen -0.5 und 0) bleibt
weiterhin `meadow`, unverändert. `prop_chances`: `fallen_tree` 0.28 (klar
dominant), `oak_tree` 0.03 ("ein paar lebende Bäume") — bewusste Umkehrung
des frisch getunten forest-Verhältnisses. Terrain-Farben aschig-braungrau
statt grün, leichter `fog_density` (0.25).

`Factory3D.create_fallen_tree(parent, biome_id)`: beim Nachschlagen
aufgefallen, dass der `biome_id`-Parameter dort (anders als bei
`create_rock_boulder()`) aktuell gar keine Farbverzweigung hat — toter
Parameter, funktional ohne Wirkung. Nicht mitgefixt (kein Teil dieser
Anfrage), aber in `FallenTree.gd`s Klassenkommentar dokumentiert, damit es
beim nächsten Fund nicht erneut recherchiert werden muss.

Tests: `test_biome_registry.gd` (Sieben- → Acht-Biome-Arrays,
`test_all_seven_biomes_registered` → `test_all_eight_biomes_registered`,
neue Grenzfall-Tests `test_very_dry_gives_dead_forest`/
`test_dead_forest_boundary_stays_meadow_when_not_dry_enough`,
`test_dead_forest_has_dominant_fallen_tree_and_sparse_oak`),
`test_chunk_entity_spawner_biome.gd`
(`test_forest_biome_mushroom_cluster_is_now_spawnable`/
`test_dead_forest_biome_fallen_tree_is_now_spawnable`, analog zu den
Cactus-/RockBoulder-Regressionstests aus Round 76/78). `ZoneTriggerVolume`/
ADR-030 unberührt. Als Nächstes: `fern` ist der letzte verbleibende
Prefab-ohne-Entity-Typ aus der Round-75/76-Liste — oder ADR-031
(Permission/Role-System).

**Round 80 — "Farn in jedem Biom außer Eis und Wüste" (Anfrage) + Lücke aus
Round 78 geschlossen.** `fern` war der letzte verbleibende Prefab-ohne-
Entity-Typ aus der Round-75/76-Liste (siehe `WorldEntityRegistry`-
Klassenkommentar) — stand bereits in `forest`/`dense_forest`/`swamp`-
`prop_chances`, ohne registrierten Entity-Typ überall stillschweigend
gefiltert. Neue `Fern.gd` (Foraging, gleicher Skill wie Cactus/IceCrystal/
MushroomCluster, nutzt das bereits fertige `Factory3D.create_fern()`-Prefab
— nur ohne Aufrufer, gleiches Muster wie zuvor). In
`WorldEntityRegistry.register_all()` (Gruppe `"plants"`) +
`KNOWN_PROP_TYPES` registriert. Neues Item `fern_fiber`
(`data/items/FernFiber.tres`) + `data/loot_tables/loot_fern.tres`.

`prop_chances["fern"]` neu ergänzt in `meadow` (0.10), `mountain` (0.05) und
`dead_forest` (0.04) — zusammen mit den bereits bestehenden Einträgen in
`forest`/`dense_forest`/`swamp` spawnt Fern damit in ALLEN Biomen außer
`winter` (Eis) und `desert` (Wüste), wie angefragt. Bewusst NICHT in
winter/desert ergänzt — passt thematisch nicht (Schnee/Sand statt
Unterholz-Grün) und es existiert auch keine Farn-Prefab-Variante dafür in
`Factory3D`/`MeshCache`.

**Lücke aus Round 78 geschlossen.** Beim Zusammenführen ist aufgefallen,
dass `WorldEntityRegistry.register_all()`/`KNOWN_PROP_TYPES` sowie
`DataManifest.ITEMS` bereits auf `RockBoulder.gd` bzw.
`data/items/Stone.tres` verwiesen (Kommentare "Round 78"), diese Dateien
im Repo-Stand aber fehlten — die Runde, die sie eingeführt haben muss, war
nie eingecheckt. Nachgezogen im etablierten Muster (siehe Cactus/PineTree/
IceCrystal/MushroomCluster/FallenTree): `RockBoulder.gd` (Mining-
Interaktion, nutzt das bereits vorhandene `Factory3D.create_rock_boulder()`),
`data/items/Stone.tres`, `data/loot_tables/loot_rock_boulder.tres`.
Zusätzlich fehlte der `"mountain"`-Farbfall in
`Factory3D.create_rock_boulder()` (nur `desert`/`winter`/Default vorhanden,
obwohl `_make_mountain()`s Klassenkommentar aus Round 78 ihn bereits
erwähnt) — hier ergänzt (dunkleres Granitgrau), inkl. `"mountain"` in
`test_factory3d_nature.gd`s Biom-Farb-Crashtest.

Tests: `test_chunk_entity_spawner_biome.gd`
(`test_fern_is_now_spawnable`, analog zu den bisherigen Regressionstests;
`test_fern_spawns_in_every_biome_except_winter_and_desert` — deckt die
eigentliche Anfrage direkt ab, inkl. der expliziten Negativ-Prüfung für
winter/desert). `test_biome_registry.gd`s generischer
`test_prop_chances_all_in_valid_range()`-Test deckt die neuen fern-Einträge
automatisch mit ab (Range-Check über alle Biome). `ZoneTriggerVolume`/
ADR-030 unberührt. Als Nächstes: ADR-031 (Permission/Role-System).

**Round 81 — ADR-031 (Permission/Role-System), Teil 1 (Anfrage "lass das mal
angehen").** Rollen-Datenmodell + Service umgesetzt, siehe
`docs/adr/031-permission-role-system.md` "Umsetzungsstand (Round 80)" für die
vollständige Aufschlüsselung. Kurzfassung: `Role.gd` + drei `.tres`-Rollen
(`player`/`moderator`/`admin`, Capability-Sets exakt nach ADR-Entscheidung),
`PermissionService` (App-Scope, `user://roles.json`, atomic write wie
`SettingsService`) mit `has_capability()`/`assign_role()`/`revoke_role()`/
`ensure_default_role()`. In `BootstrapConfig.tres` unter `global_services`
registriert. `SessionManager.is_solo()` als neuer Baustein für die noch
offene Tier-Verdrahtung ergänzt.

**Bewusst NICHT Teil dieser Runde:** die eigentliche Tier-basierte
Auto-Zuweisung (`ensure_default_role()` an `ServiceOrchestrator.
_on_session_requested()`/`SaveSystem.begin_session()` anschließen) sowie das
Tier-3-Root-Konto mit Pflicht-Passwort-Rotation (braucht eine Auth-Schicht,
die es im Projekt noch nicht gibt — aktuell nur TOFU-Secrets über
`PlayerCredentialStore`, kein Username/Passwort). Beides bewusst nicht
huckepack mitgenommen, siehe ADR-Umsetzungsstand für die Begründung. Tests:
`tests/unit/test_permission_service.gd` (Rollen laden, alle drei
Capability-Sets, Zuweisung/Widerruf, `ensure_default_role()`s Idempotenz —
insbesondere dass eine manuelle Moderator-Beförderung nicht durch einen
späteren Tier-Default überschrieben wird —, Persistenz-Roundtrip,
korrupte/unbekannte Daten in der Datei). Als Nächstes: ADR-031 Teil 2
(Tier-Verdrahtung) — oder ADR-032 (Admin-PvP-Ausnahme, baut direkt auf
diesem Rollenmodell auf).

**Round 82 — ADR-031 (Permission/Role-System), Teil 2: Tier-Verdrahtung
(Anfrage "Tier Verdrahtung wäre jetzt sinnvoll").** Die in Round 81 bewusst
offen gelassene Lücke ist geschlossen: `PermissionService.ensure_default_role()`
ist jetzt an den Session-Boot angeschlossen.
`ServiceOrchestrator._on_session_requested()` ruft vor `create_character_scope()`
ein neues `_ensure_default_role_for_tier(player_id)` auf — Tier 1 (Solo, kein
aktiver Peer) und Tier 2 (Host) bekommen automatisch die Rolle `admin`
zugewiesen, sobald ihre eigene Session bootet; Tier 2 Client fällt durch (kein
automatischer Eintrag, Fallback bleibt `PermissionService.DEFAULT_ROLE_ID`
`"player"`). Die eigentliche Tier-Entscheidung
(`ServiceOrchestrator._should_get_default_admin(is_server, is_dedicated_server)`)
ist als eigene `static func` von den AppScope-Service-Lookups getrennt — analog
zu `SessionManager._handle_join_handshake()` vs. dessen `@rpc`-Hülle —, damit
sie ohne gebootete App isoliert testbar ist. `ensure_default_role()`s
Idempotenz (Round 80/81) greift unverändert: eine manuelle Vorab-Beförderung
(z.B. zu `moderator`) wird durch den Tier-Default nicht überschrieben, und ein
wiederholter Aufruf über den Reload-Pfad (`_on_scene_reload_requested()` →
`_on_session_requested()` erneut) ist gefahrlos.

**Bewusst weiterhin NICHT Teil dieser Runde:** Tier 3 (Dedizierter Server) ist
explizit von der Auto-Zuweisung ausgenommen —
`SessionManager.is_dedicated_server()` schließt den Fall in
`_should_get_default_admin()` hart aus, unabhängig davon, ob `is_server()`
true ist. Grund unverändert seit Round 80: ein Tier-3-Root-Konto mit
Pflicht-Passwort-Rotation braucht eine Auth-Schicht, die es im Projekt noch
nicht gibt (nur TOFU-Secrets über `PlayerCredentialStore`). Ein automatischer
Rollen-Eintrag für `SessionManager.DEDICATED_SERVER_WORLD_ID` wäre nur ein
Datenbankeintrag ohne echten Zugriffsschutz — bewusst nicht vorgetäuscht, wie
schon im ADR "Umsetzungsstand" vermerkt.

Tests: `tests/unit/test_service_orchestrator_tier_roles.gd` — vier
Kombinationen für `_should_get_default_admin()` isoliert (T-01…T-04), Tier 1
Solo bekommt `admin` (T-05), Tier-3-Dedicated-Flag bekommt keinen (T-06),
bestehende manuelle Rolle wird nicht überschrieben (T-07), fehlende
PermissionService/SessionManager in der Registry crasht nicht (T-08/T-09).
Echtes Tier-2-Hosting (`create_server()`) ist in headless-CI nicht auslösbar
(siehe SM-04 in `test_session_manager.gd`) und deshalb nur über die reine
`_should_get_default_admin()`-Logik abgedeckt, nicht end-to-end. ADR-031 ist
damit bis auf das Tier-3-Root-Konto (braucht eigene Auth-Schicht, separates
Thema) vollständig umgesetzt. Als Nächstes: ADR-032 (Admin-PvP-Ausnahme, baut
direkt auf diesem Rollenmodell auf).

**Round 83–88 — ADR-035-Vorarbeiten (ADR-034 Bank, ADR-033 Currency,
Shop-Migration), diese Datei nicht laufend nachgeführt.** Diese Datei wurde
zwischen Round 82 und Round 89 nicht Runde für Runde mit dem Produktivstand
synchron gehalten — die Detailnarrative dafür fehlt hier bewusst, statt sie
nachträglich zu rekonstruieren. Der tatsächliche Code- und Test-Stand jener
Runden ist in `docs/adr/033-player-currency.md`/`034-bank-storage-service.md`
„Umsetzungsstand (Round 88)" korrekt festgehalten (`CurrencyService`,
`BankService`, `BankNPC`+Panel-UI, `ShopService` netzwerksicher gemacht) —
diese ADRs sind die verlässliche Quelle für das „Was", nicht diese Datei.

**Round 89 — ADR-035 (Trading: Handshake-Handel + Auktionshaus)
abgeschlossen.** Beide Teile aus der ADR-Entscheidung umgesetzt:
`TradeService` (Einstieg über die bestehende Interaktions-Pipeline wie bei
PvP, danach eigenes `NetworkBridge`-Routing wie Bank/Shop; Scam-Schutz über
Reset-bei-Änderung + Zwei-Stufen-Gate; bewusst kein Escrow, dafür
Neuvalidierung des Bestands unmittelbar vor dem atomaren Swap) und
`AuctionHouseService` (Quellen-Priorität Inventar-vor-Bank beim Listen,
Escrow ab Listing-Zeitpunkt, Gold ohne Escrow direkt über `CurrencyService`,
eigener Save-Bucket). Je eigenes UI (`TradeVisuals`/`TradeUIController`/
`TradeComponent`, `AuctionHouseVisuals`/`AuctionHouseUIController`/
`AuctionHouseComponent`, beide analog zu `BankComponent`), registriert in
`HUDBuilder.gd`. Dabei gefundener Bug: `BootPipeline.gd`s
Phase-C8-Late-Inject-Liste für `inject_network_bridge()` hatte
`ServiceKeys.TRADE`/`ServiceKeys.AUCTION_HOUSE` vergessen — beide Services
wären im Mehrspieler-Betrieb dauerhaft auf dem Tier-1-„kein Peer"-Pfad hängen
geblieben. Behoben. Volle Aufschlüsselung inkl. Architektur-Prinzipien
(Single-Source-of-Truth-Controller, kein eigener Angebots-State im UI) siehe
ADR-035 „Umsetzungsstand (Round 89)". Tests:
`tests/unit/test_trade_service.gd`/`tests/unit/test_auction_house_service.gd`,
gleiches Muster wie `test_bank_service.gd`/`test_shop_service.gd` (echte
Kollaboratoren statt Stubs für die interessanten Pfade). **Ehrlich offen:**
kein Godot-Editor/Headless-Runner in dieser Entwicklungsumgebung verfügbar —
alle neuen Dateien nur strukturell geprüft (Klammern, Signaturen gegen die
echten Service-APIs abgeglichen), nicht gegen die echte Godot/GUT-Runtime
gelaufen. Vor dem nächsten Schritt einmal im Editor öffnen und
durchklicken/testen lassen. Als Nächstes: Wetter-Events, PvP-Events
(`player_killed_by_player`), oder eines der weiterhin offenen 🟡-Themen oben.

**Round 90 — ADR-038 (Item-Schutz-Dreiklang) abgeschlossen, inklusive
UI-Interaktion.** Als Grundlage für ADR-036/037/039 vorgezogen (alle drei
konsumieren den hier eingeführten `ItemProtectionService`). Umgesetzt:
`ItemProtectionService` (zustandslos — die drei `is_pve_death_protected`/
`is_theft_protected`/`is_pvp_protected`-Flags leben direkt auf `ItemInstance`
und werden von `InventorySystem` mit-persistiert/mit-synchronisiert, kein
eigener Save-Bucket nötig), drei neue Scroll-Items
(`data/items/Scroll{Pve,Theft,Pvp}Protection.tres`, normale stapelbare Items
über das neue `ItemDefinition.grants_protection_type`-Feld), und die
"Scroll auf Item anwenden"-UI direkt im bestehenden 🎒-Inventar-Panel (kein
neues Panel — zweiter optionaler Button pro Zeile in `InventoryVisuals`,
Zwei-Klick-Fluss "📜 Anwenden" → "🎯 Ziel" in `InventoryUIController`).
**Bewusste Abweichung von der ADR-Pseudo-Signatur:** `request_apply_protection()`
nimmt keinen `protection_type`-Parameter vom Aufrufer entgegen — der wird
ausschließlich serverseitig aus der `ItemDefinition` des eingereichten Scrolls
gelesen, sonst könnte ein Client ein billiges Scroll mit einem
selbstgewählten `protection_type="pvp"` einreichen. `consume_pvp_protection()`
ist bereits fertig für ADR-036, wird aber von diesem Round noch nicht
aufgerufen (kein Trigger-Event existiert vor ADR-036 selbst). Volle
Aufschlüsselung siehe ADR-038 „Umsetzungsstand (Round 90)". Tests:
`tests/unit/test_item_protection_service.gd` (neu, gleiches Muster wie
`test_bank_service.gd` — echte `InventorySystem`-Instanz statt Stub),
`test_inventory_system.gd` um Round-Trip-Tests für die drei neuen Flags
ergänzt (inkl. Legacy-Save-ohne-die-Felder-Fall), `test_network_bridge.gd` um
einen Tier-1-Routing-Test ergänzt. **Ehrlich offen:** wie schon in Round 89 —
kein Godot-Editor/Headless-Runner in dieser Entwicklungsumgebung verfügbar,
alle neuen/geänderten Dateien nur strukturell geprüft, nicht gegen die echte
Godot/GUT-Runtime gelaufen. Einmal im Editor öffnen und durchklicken/testen
lassen, bevor mit ADR-036/037/039 weitergemacht wird. Als Nächstes: ADR-036
(PvP-Tod-Verlust) und ADR-037 (PvE-Tod-Loot) — parallel möglich, beide
unabhängig voneinander außer der hier gebauten gemeinsamen Basis — danach
ADR-039 (Pickpocketing, zusätzlich abhängig von den bereits existierenden
Diebes-Zonen aus ADR-030).

**Round 91 — ADR-036 (PvP-Tod-Verlust/Skull-Loot + Aura/Gesinnung)
abgeschlossen, inklusive PvP-Targeting.** PvP-Targeting/Angriffs-Interaktion
existierte bereits aus einer früheren Runde (`PlayerAttack.gd`,
`CombatSystem.resolve_pvp_hit()`) — musste nicht neu gebaut werden, nur der
Tod-Hook ergänzt. Umgesetzt: `PvPDeathLossService` (Skull-abhängige
Verlust-Logik — 100% bei geskulltem Opfer, sonst 5–70% gestaffelt nach
Killer-Risiko; respektiert alle drei ADR-038-Schutzkategorien; **Loot geht
an den Killer**, mit dem Auftraggeber abgestimmt, da die ADR das selbst nicht
explizit festlegt), `AuraService` (Reputationswert, Kill-Strafe, "Danken"-
Interaktion mit 24h-Cooldown/Paar, inkl. Cooldown-Persistenz gegen
Neustart-Exploits), neue `PlayerThank`-Interaktion (drittes
`InteractableComponent` auf dem Player-Node, exaktes Gegenstück zu
`PlayerTrade` aus ADR-035), und die Aura-Erweiterung des ADR-032
Safe-Zone-Vulnerabilitäts-Fensters (`is_skulled` ODER niedrige Aura löst das
10s-Fenster aus). **Interpretationsentscheidung** (ADR spezifiziert es nicht
mechanisch): "skull-auslösender Kill" = der Killer war selbst zum
Zeitpunkt des Kills geskullt — nutzt den bereits vorhandenen Skull-Status
statt einer zweiten Parallel-Buchführung. `AURA_VULNERABILITY_THRESHOLD`
und `KILL_PENALTY` sind dokumentierte Platzhalter, kein finaler Balance-Wert
(wie schon die Dank-Formel in der ADR selbst). Netzwerk-Sicherheit: sowohl
`send_aura_thank()` als auch das bereits aus Round 90 bekannte
`send_item_protection_apply()`-Muster leiten die Spieler-Identität
serverseitig aus dem RPC-Absender-Peer ab, statt einem client-gesendeten
Identitäts-Parameter zu vertrauen. Volle Aufschlüsselung siehe ADR-036
„Umsetzungsstand (Round 91)". Tests: `test_pvp_death_loss_service.gd`,
`test_aura_service.gd` (beide neu, gleiches Muster wie
`test_item_protection_service.gd`), `test_pvp_service.gd` um
Aura-Integrationstests ergänzt. **Ehrlich offen:** wie in Round 89/90 — kein
Godot-Editor/Headless-Runner in dieser Entwicklungsumgebung verfügbar, alles
nur strukturell geprüft, nicht gegen die echte Godot/GUT-Runtime gelaufen.
Einmal im Editor testen, bevor mit ADR-037 (PvE-Tod-Loot, kann parallel zu
ADR-036 laufen, ist aber noch offen) oder ADR-039 (Pickpocketing)
weitergemacht wird.

**Round 92 — ADR-037 (PvE-Tod-Loot/Grab-Hybrid-Timer) abgeschlossen.**
Umgesetzt: `DeathLootService` (`handle_pve_death()`, aufgerufen von
`Player._on_player_died()` immer dann, wenn der ADR-036-PvP-Zweig NICHT
gegriffen hat — `_apply_pvp_death_loss_if_applicable()` gibt dafür jetzt
`bool` zurück statt `void`, ein Tod ist exklusiv entweder PvP oder PvE),
neue `Gravestone`-Welt-Entität (Grab-Hybrid-Timer — Personal-Loot-Phase nur
für den Besitzer, danach Free-for-all, danach automatischer Despawn; Phase
wird bewusst OHNE eigenes Enum rein aus zwei Unix-Timestamp-Vergleichen
abgeleitet, wie in der ADR unter "Mitigationen" festgehalten). Nur
`is_pve_death_protected` (ADR-038) schützt vor dem Grab — die anderen beiden
Schutzkategorien sind für einen PvE-Tod irrelevant. **Bootstrap-Zyklus
gelöst:** `DeathLootService` bräuchte `WorldService` zum Spawnen, aber
`WorldService` hängt selbst optional von `death_loot` ab (für
`EntityContext.get_death_loot()`) — ein Rück-Dep hätte einen Zyklus erzeugt.
Gelöst über direkte Injection (`WorldService.inject_world()` unmittelbar
nach dem eigenen `configure()`) statt einer deklarierten Abhängigkeit,
derselbe Grundgedanke wie `inject_network_bridge()`/Phase C8, nur punktuell.
**Pool-Reuse-Bug gefunden und gefixt:** anders als dauerhafte NPCs (Bank/
Shop, die nie despawnen) wird ein Grab tatsächlich wiederholt gespawnt/
despawnt und landet im `EntityPool` — `_ready()` feuert bei einem
wiederverwendeten Node nicht erneut, wodurch die einmalig dort gebaute
`CollisionShape3D` beim zweiten Spawn durch `_clear_visuals()` gelöscht und
nie wiederhergestellt worden wäre. Mit Regressionstest abgedeckt. Volle
Aufschlüsselung siehe ADR-037 „Umsetzungsstand (Round 92)". Tests:
`test_death_loot_service.gd`, `test_gravestone.gd` (beide neu — letzterer
folgt dem `add_child_autofree()`/`EntityContext.for_test()`-Muster aus
`test_harvestable_entity.gd`/`test_quest_npc.gd`). **Ehrlich offen:** wie in
Round 89–91 — kein Godot-Editor/Headless-Runner in dieser
Entwicklungsumgebung verfügbar, alles nur strukturell geprüft. Einmal im
Editor testen, bevor mit ADR-039 (Pickpocketing) weitergemacht wird.

**Round 93 — ADR-039 (Pickpocketing) abgeschlossen. Damit ist der
ursprünglich geplante Item-Schutz/Tod-Verlust/Diebstahl-Dreiklang
(ADR-036/037/038/039) vollständig umgesetzt.** Umgesetzt: `PickpocketService`
(Formel 1:1 aus dem ADR-Vorschlag — drei lineare Rampen zwischen den
Meilenstein-Leveln 100/1.000/10.000 auf Basis von `max(0, täter_level -
opfer_level)`, additiver Kristall-Bonus), neuer `Diebstahl`-Skill
(`pickpocketing.tres`, `max_level=-1`/linear, exakt wie in der ADR unter
"Lineare statt exponentieller XP-Kurve" gefordert), drei Diebstahl-Kristall-
Items über neues `ItemDefinition.pickpocket_crystal_tier`-Feld (Beschaffung
bewusst nicht Teil dieser Runde — eigener Folge-ADR für NPC-Shops, wie in
ADR-039 selbst unter "Ablösung" festgehalten), drei feste Kontextmenü-
Aktionen (`PlayerPickpocket.gd`, eine pro Kristallstufe — anders als bei
ADR-038s Scrolls sind Kristall-Wahl und Ziel-Spieler hier zwei unabhängige
Dinge, deshalb keine Auswahl-UI wie im Inventar-Panel). Zonen-Kopplung prüft
bewusst die Zone DES OPFERS, nicht des Täters (ADR-Vorgabe). Nur
`is_theft_protected` (ADR-038) schließt Items vom stehlbaren Pool aus.
Kristall-Verbrauch UND Cooldown werden VOR der Erfolgsberechnung gesetzt
("unabhängig von Erfolg/Fehlschlag", exakt wie in der ADR gefordert),
Cooldown ist Paar-basiert und persistiert (Neustart-Exploit-Schutz, analog
`AuraService`). **Korrektur während der Umsetzung:** beim Nachverfolgen des
tatsächlichen Trigger-Pfads (Kontextmenü → `InteractableComponent.
_handle_completion()`) festgestellt, dass dieser das Client→Autorität-
Routing bereits GENERISCH selbst übernimmt — `Player.
_on_pickpocket_requested()` rief deshalb zunächst `on_pickpocket_confirmed()`
direkt auf statt über `request_pickpocket()`, wodurch der öffentliche
Einstiegspunkt fast ungenutzt geblieben wäre. Korrigiert: ruft jetzt
`request_pickpocket()` auf (den einheitlichen Einstiegspunkt, konsistent mit
`ItemProtectionService.request_apply_protection()`). Dieselbe Korrektur
wurde an `AuraService.request_thank()` aus Round 91 nachgezogen
(`Player._on_thank_requested()` rief dort ebenfalls direkt
`on_thank_confirmed()` auf). Kein Verhaltensunterschied für den aktuellen
Kontextmenü-Trigger (der läuft schon hinter einem `is_multiplayer_authority()`-
Guard, der Netzwerk-Zweig in `request_*()` greift also praktisch nie von
hier aus) — der Sinn ist, dass es nur noch EINEN öffentlichen Einstiegspunkt
pro Service gibt statt zwei mit unterschiedlichen Garantien. Volle
Aufschlüsselung siehe ADR-039 „Umsetzungsstand (Round 93)". Tests:
`test_pickpocket_service.gd` (neu — Erfolg/Fehlschlag über Level-Extremfälle
deterministisch erzwungen statt echtem RNG zu vertrauen, um Flakiness zu
vermeiden). **Ehrlich offen:** wie in Round 89–92 — kein Godot-Editor/
Headless-Runner in dieser Entwicklungsumgebung verfügbar, alles nur
strukturell geprüft, nicht gegen die echte Godot/GUT-Runtime gelaufen.
Einmal im Editor testen. Als Nächstes: NPC-Shop-System (Kristall-/Scroll-
Beschaffung, von ADR-038 UND ADR-039 als Folge-ADR referenziert), oder eines
der weiterhin offenen 🟡-Themen oben.

**Round 94 — NPC-Shop-System (Kristall-/Scroll-Beschaffung) abgeschlossen.**
Der in Round 93 als "Als Nächstes" markierte Punkt ist erledigt, aber ohne
neuen Service/ADR: der bestehende `ShopService` (Round 88) bot bereits genau
den benötigten Mechanismus (Gold-Kauf gegen Katalog-Item, netzwerksicher,
serverseitig neu validiert) — alle sechs Items aus ADR-038 (drei
Schutz-Scrolls, 40/40/80 Gold) und ADR-039 (drei Diebstahl-Kristalle,
15/60/400 Gold, gestaffelt nach `PickpocketService.TIER_BONUS`/
`TIER_COOLDOWN_SEC`) sind jetzt in `ShopService.BUY_CATALOG` gelistet.
Preise sind wie alle anderen Balance-Werte in diesem Projekt dokumentierte
Platzhalter. Volle Aufschlüsselung siehe ADR-038/ADR-039 „Update (Round 94)".
Tests: `tests/unit/test_shop_service.gd` (+6 Preis-/Kauf-Fälle). **Ehrlich
offen:** wie in Round 89–93 — kein Godot-Editor/Headless-Runner in dieser
Entwicklungsumgebung verfügbar, nur strukturell geprüft.

**Round 95 — ADR-041 (Wetter-Events, `weather_changed`) abgeschlossen.**
Erster der drei in Round 90 gebündelten Punkte ("Wetter-Events, PvP-Events,
Achievement-Events"); die beiden anderen bleiben offen. Neuer
`WeatherService` (Sibling zu `WorldTimeService`) würfelt Wetter
deterministisch aus `world_seed` + `day_count` — bewusst KEIN neues RPC/kein
Broadcast an alle Peers (das Projekt hat dafür weiterhin keinen Mechanismus,
siehe ADR-035 „Umsetzungsstand"), sondern dasselbe Seed-Prinzip wie
`TerrainGenerator`/`ChunkManager`: gleicher Seed + gleicher Tag ⇒ überall
identisches Ergebnis, ganz ohne Netzwerk-Traffic. Wurf einmal pro Ingame-Tag
(gekoppelt an `WorldTimeService.day_count`-Rollover), plus einmalig beim
Booten für den aktuellen/wiederhergestellten Tag. `WorldService` bekommt eine
neue `current_weather`-Property; `WorldSaveHandler` persistiert
`weather`/`weather_last_rolled_day` (Konstruktor-Parameter optional, Default
`null` — Alt-Aufrufer/Tests bleiben unverändert kompilierbar). Lokale
UI-Rückmeldung bei Wechsel über `EventBus.ui().emit_notification()` (rein
pro Peer, gleiches Prinzip wie `QuestCustomTrigger.hint_text`, Round 73).
Volle Optionsabwägung inkl. der verworfenen RPC-Broadcast-Variante siehe
ADR-041. Tests: `tests/unit/test_weather_service.gd` (neu, 13 Fälle:
Determinismus, Idempotenz, Signal-Emission, Save/Restore, Alt-Save-Fallback),
`tests/unit/test_world_save_handler.gd` (+4), `tests/unit/test_world_service.gd`
(+2). **Ehrlich offen:** wie in Round 89–94 — kein Godot-Editor/
Headless-Runner in dieser Entwicklungsumgebung verfügbar, nur strukturell
geprüft (Klammern, Signaturen gegen die echten Service-APIs abgeglichen),
nicht gegen die echte Godot/GUT-Runtime gelaufen. Zusätzlich bewusst nicht
Teil dieser Runde: visuelle Wetter-Effekte, Gameplay-Auswirkungen (Angel-/
Ernte-Boni etc.), Biom-Abhängigkeit der Wetter-Gewichtung, serverseitig
erzwungene Wetterwechsel — siehe ADR-041 „Bewusst nicht Teil dieser Runde"
für die volle Liste. Als Nächstes: PvP-Events (`player_killed_by_player`)
oder Achievement-Events.

**Round 96 — ADR-042 (An-alle-Peers-Broadcast-Mechanismus) abgeschlossen.**
Schließt die seit ADR-035/ADR-041 dokumentierte Infrastruktur-Lücke ("das
Projekt hat keinen an-alle-Peers-Broadcast-Mechanismus") als eigenständigen
Schritt, ohne einen konkreten Feature-Konsumenten mitzuliefern.
`NetworkBridge.broadcast_to_all_peers(kind, payload)` (neu) folgt exakt dem
`send_economy_update_for_player()`/`send_zone_update_for_peer()`-Muster
(R-7/ADR-030), iteriert aber über alle aktuell verbundenen Ziel-Peers statt
genau einen — dafür eine neue Fassade `get_all_joined_peer_ids()` auf
`SessionManager.get_all_slots().keys()`, bewusst NICHT
`multiplayer.get_peers()` (letzteres enthielte auch Peers ohne
abgeschlossenen Join-Handshake, RPC liefe ins Leere — derselbe Boot-Race-
Grund wie beim bestehenden Einzel-Snapshot-Pfad, E-4). Empfangsseite:
`_rpc_receive_broadcast_event(kind, payload)`
(`@rpc("authority", "call_remote", "reliable")`, wie
`_rpc_receive_economy_update()`), reicht durch an neues Signal
`broadcast_event_received(kind, payload)`. `WeatherService` bleibt bewusst
unverändert beim deterministischen Wurf aus ADR-041 — siehe ADR-042
„Verhältnis zu ADR-041" für die Begründung. Tests:
`tests/unit/test_network_bridge.gd` (+5: Tier-1-No-Op, keine lokale
Emission auf der Autorität, leere Peer-Liste ohne SessionManager, Peer-
Liste spiegelt registrierte Slots, `_rpc_receive_broadcast_event()`-Guard
gegen die eigene Autorität). **Ehrlich offen:** wie in Round 89–95 — kein
Godot-Editor/Headless-Runner in dieser Entwicklungsumgebung verfügbar, nur
strukturell geprüft, nicht gegen eine echte Zwei-Peer-Verbindung gelaufen
(kein Integrationstest analog `test_network_bridge_rpc_guards_two_peer.gd`
in dieser Runde — reine Infrastruktur ohne Konsument, ein solcher Test wäre
ohne echten `kind`-Anwendungsfall nur ein Transport-Rauchtest). Bewusst
nicht Teil dieser Runde: kein konkreter Konsument (Auktionshaus-Live-
Broadcast, PvP-/Achievement-Events), kein Sync-Pfad für spät joinende
Clients — siehe ADR-042 „Bewusst nicht Teil dieser Runde" für die volle
Liste. Als Nächstes: PvP-Events (`player_killed_by_player`) oder
Achievement-Events — beide könnten jetzt entweder den bestehenden
Einzel-RPC-Weg (nur der betroffene Spieler ist Ziel) oder diesen neuen
Broadcast-Weg nutzen, je nach Trigger-Analyse.

**Round 97 — Live-Broadcast-Konsument für `AuctionHouseService` (ADR-035
Round-89-Rückstellung, jetzt via ADR-042 möglich).** Explizit angeforderter
nächster Schritt aus Round 96 ("als nächsten Konsumenten und sync"), Wahl:
Auktionshaus-Live-Updates. Jede Listing-Mutation
(`on_list_item_confirmed()`/`on_buy_confirmed()`/
`on_cancel_listing_confirmed()`) broadcastet jetzt zusätzlich zur
bestehenden 1:1-Bestätigung an den Akteur einen vollen Listings-Snapshot
per `NetworkBridge.broadcast_to_all_peers()` an alle verbundenen Spieler
(`_broadcast_listings_update()`, neu). Fehlgeschlagene Aktionen
broadcasten bewusst nicht. Client-seitig jetzt an beide Signale
angeschlossen (`economy_state_received` UND `broadcast_event_received`),
derselbe Handler `_on_economy_state_received()` verarbeitet beide, da
Signatur und Payload-Format identisch sind. **Sync-Frage geklärt:** der
Pull-Pfad (`request_listings_snapshot()`) bleibt unverändert der Weg für
den initialen Stand beim ersten Öffnen des Marktplatz-Panels — auch für
spät beigetretene Spieler, die das Panel noch nie geöffnet hatten. Der
Broadcast liefert nur laufende Änderungen an Clients mit bereits offenem
Panel. Damit ist der in ADR-042 offen gelassene Late-Join-Sync-Punkt für
diesen konkreten Konsumenten bereits abgedeckt, ohne einen zusätzlichen
Baustein zu brauchen — siehe ADR-035 „Umsetzungsstand (Round 97)" für die
volle Begründung. Tests: `tests/unit/test_auction_house_service.gd` (+5,
Spy-`NetworkBridge` analog `test_zone_service.gd`). **Ehrlich offen:** wie
immer — kein Godot-Editor/Headless-Runner verfügbar, nur strukturell
geprüft. Als Nächstes: PvP-Events oder Achievement-Events (beide könnten
den Broadcast-Weg ebenfalls nutzen, je nach Trigger-Analyse), oder eines
der weiterhin offenen Themen (Chat/Social, Reporting/Moderation,
Telemetrie, Tutorial/Onboarding).

**Round 98 — Konsument: PvP-Kill-Feed-Broadcast (`player_killed_by_player`).**
Zweiter der beiden in Round 97 offen gelassenen Konsumenten (Auktionshaus
war Round 97, Achievement-Events bleibt s.u. offen). Neuer EventBus-
Namespace `CombatEvents`/`EventBus.combat` schließt die seit ADR-018
(Round 53) dokumentierte Lücke. `PvPDeathLossService.apply_death_loss()`
emittiert nach jedem Tod zusätzlich zu `death_loss_applied` (autoritative
Quelle mit vollen Item-Details, unverändert) ein schmaleres
`player_killed_by_player`-Signal (nur `items_lost_count`, keine
Item-Liste) — lokal direkt auf der Autorität UND per
`broadcast_to_all_peers("pvp_kill", …)` an alle Clients, die es über eine
neue `broadcast_event_received`-Verdrahtung empfangen (Dual-Channel-Muster
wie `AuctionHouseService` in Round 97). `IEventBus`/`EventBusAdapter`/
`MockEventBus` um `combat()` ergänzt. Tests:
`tests/unit/test_pvp_death_loss_service.gd` (+5). **Achievement-Events
bewusst nicht Teil dieser Runde:** es gibt im Projekt noch kein
Achievement-System (keine Definitionen/Trigger/Persistenz) — ein
Broadcast-Konsument dafür setzt voraus, dass es überhaupt etwas zu
broadcasten gibt; das wäre ein eigenes, deutlich größeres Feature (Daten-
modell + Trigger-Punkte über mehrere Systeme + Persistenz), kein reiner
Konsumenten-Anschluss wie bei Auktionshaus/PvP. **Ehrlich offen:** wie
immer — kein Godot-Editor/Headless-Runner verfügbar, nur strukturell
geprüft. Als Nächstes: Achievement-System von Grund auf (eigene
Design-Runde nötig), oder eines der weiterhin offenen Themen (Chat/Social,
Reporting/Moderation, Telemetrie, Tutorial/Onboarding).

**Round 99 — Chat/Social (ADR-043), erste Umsetzung.** Neuer `ChatService`
(`scripts/social/chat/`, kein eigener Save-Key — bewusst transient) mit
zwei Kanälen: `global` (über `broadcast_to_all_peers()`, ADR-042) und
`whisper` (neues dediziertes RPC-Paar `send_chat_message_for_player()`/
`_rpc_receive_chat_message()` — bewusst NICHT über den bestehenden
`economy_state_received`-Kanal oder den als Single-Consumer-für-QuestService
dokumentierten `domain_event_received`-Kanal recycelt, siehe ADR-043
„Entscheidung" für die volle Begründung, u. a. Privatsphäre: ein Whisper
darf nicht als Broadcast an alle laufen, nur UI-gefiltert). Validierung:
leer/Whitespace verworfen, auf 240 Zeichen gekappt (nicht hart abgelehnt),
einfaches Rate-Limit pro Absender zusätzlich zum bestehenden RPC-Rate-Limit.
Autoritäts-lokale Emission folgt der ADR-042-Konvention (kein RPC-Rundweg
zu sich selbst) — für `whisper` zusätzlich mit einer Bystander-Prüfung
(Autorität nur dann lokal emittieren, wenn sie selbst Absender oder Ziel
ist — sonst Privatsphäre-Leck für einen unbeteiligten Host). Neue
ServiceDefinition in `config/BootstrapConfig.tres`
(`Resource_chat`, keine Deps), `ServiceKeys.CHAT`, in `BootPipeline.gd`s
NetworkBridge-Injektionsliste ergänzt. **Nebenbei gefunden und behoben:**
ein echter Bug aus Round 98 — `PvPDeathLossService.configure()` liest seit
Round 98 `ServiceKeys.EVENT_BUS`, aber `BootstrapConfig.tres` listete
`event_bus` nie in dessen `optional_deps`, wäre also in Produktion still
`null` geblieben (nur die Unit-Tests hätten das verdeckt, weil sie
`ServiceDeps.from_dict()` direkt befüllen). Jetzt ergänzt. Tests:
`tests/unit/test_chat_service.gd` (neu, 19 Tests). **Ehrlich offen:** wie
immer — kein Godot-Editor/Headless-Runner verfügbar, nur strukturell
geprüft. Bewusst nicht Teil dieser Runde: Chat-Verlauf/Persistenz,
Moderation/Wortfilter/Reporting, Gruppen-/Party-Kanäle, UI-Panel (siehe
ADR-043). Als Nächstes: Achievement-System von Grund auf, Reporting/
Moderation, Telemetrie, oder Tutorial/Onboarding.

**Round 100 — Reporting/Moderation (ADR-044), erste Umsetzung.** Zwei
bewusst getrennte Bausteine: `ReportService` (neu,
`scripts/social/moderation/`, persistiert Meldungen — `SAVE_KEY =
"reports"`, `savesystem`-optional-dep) für Melder→Autorität-Meldungen mit
festen Grund-Kategorien, Details-Cap, Rate-Limit (30s/Melder); und
`ChatService.mute_player()`/`unmute_player()`/`is_muted()` (neu, in Round
99s `ChatService` selbst ergänzt, nicht in `ReportService`) für rein
lokales, transientes Stummschalten — keine Netzwerk-Wirkung, keine
Persistenz, keine Kopplung an Meldungen. `context`-Dictionary bei
`ReportService` macht es wiederverwendbar für jedes künftige meldbare
System, nicht nur Chat, ohne dass `ReportService` `ChatService` kennen
müsste. Neues Client→Autorität-only-RPC-Paar `send_report_submit()`/
`_rpc_report_submit()` (kein Gegenstück — Meldungen sind nie für andere
Spieler sichtbar). `ServiceKeys.REPORT`, `BootPipeline`-Injektionsliste,
neue `ServiceDefinition` `Resource_report` in
`config/BootstrapConfig.tres`. Tests: `tests/unit/test_report_service.gd`
(neu, 16 Tests), `tests/unit/test_chat_service.gd` (+7 Mute-Tests). **Bewusst
nicht Teil dieser Runde:** kein Review-/Admin-UI, keine automatischen
Konsequenzen (Bans/Kicks/serverseitige Mutes), kein Wortfilter — siehe
ADR-044. **Ehrlich offen:** wie immer — kein Godot-Editor/Headless-Runner
verfügbar, nur strukturell geprüft. Als Nächstes: Achievement-System von
Grund auf, Telemetrie, oder Tutorial/Onboarding.

**Round 101 — Telemetrie/Crash-Reporting (ADR-045).** Zwei Hälften, beide
bewusst auf der bestehenden `AppLogger`-Infrastruktur aufgebaut statt sie
zu duplizieren. Crash-Reporting DIREKT in `AppLogger`
(`scripts/logger/Logger.gd`): neues `build_crash_report()` (reine
Dictionary-Konstruktion — Grund, Zeitstempel, Godot-/Plattform-Info,
Log-Zusammenfassung, letzte Fehler, kompletter Ring-Puffer) getrennt von
`write_crash_report()` (Datei-I/O, dieselbe Downloads-Ordner-
Degradationskette wie der bestehende Log-Export). Aufgerufen aus `fatal()`
(vor dem bestehenden synchronen Flush) und neu aus
`_notification(NOTIFICATION_CRASH)` — bewusst als eigener Zweig, NICHT im
bisherigen gemeinsamen Flush-Block (der auch bei normalem Fenster-
Schließen läuft, kein Absturz). Neuer `TelemetryService`
(`scripts/telemetry/`, keine Deps, kein NetworkBridge — kein Upload-
Endpunkt existiert): `record_event()` ist nur ein dünner Wrapper um
`AppLogger.log_trace(..., "Telemetry")`, liefert zusätzlich Session-
Zähler pro Event-Name (`get_event_counts()`, transient). Automatische
`session_start`/`session_end`-Events eingebaut, damit die Infrastruktur
nicht mit null Aufrufern startet. Tests:
`tests/unit/test_telemetry_service.gd` (neu, 9 Tests),
`tests/unit/test_logger_crash_report.gd` (neu, 6 Tests — `fatal()` selbst
wird NIE in Tests aufgerufen, da es den Prozess beendet). **Bewusst nicht
Teil dieser Runde:** kein Netzwerk-Upload/Server, kein Dashboard/UI, kein
Rate-Limiting für `record_event()`, keine konkreten Gameplay-Events über
`session_start`/`session_end` hinaus — siehe ADR-045. **Ehrlich offen:**
wie immer — kein Godot-Editor/Headless-Runner verfügbar, nur strukturell
geprüft; `write_crash_report()` allerdings mit echtem Datei-I/O getestet
(nicht nur die reine Datenkonstruktion). Als Nächstes: Achievement-System
von Grund auf, oder Tutorial/Onboarding.

**Round 102 — Achievement-System, erste Umsetzung (ADR-046).** Neuer
`AchievementService` (`scripts/progression/achievements/`), feste
`DEFINITIONS`-Liste (kein Editor-Workflow) mit fünf Beispiel-Achievements
über drei bestehende Domänen: `first_blood`/`pvp_veteran` (Combat, an
`PvPDeathLossService.death_loss_applied` gehängt), `first_sale`/
`auctioneer` (Economy, an `AuctionHouseService.listing_created`),
`community_watch` (Social, an `ReportService.report_submitted`). Alle drei
Trigger-Quellen bewusst gewählt, weil sie nachweislich nur auf der
Autorität feuern (`_require_authority()`-Guard in ihrem jeweiligen
`on_..._confirmed()`) — bewusst NICHT `ChatService.message_received` als
Quelle, weil das auf JEDEM Client feuert, nicht nur der Autorität, und ein
daran gehängter Fortschritt Multiplayer-inkonsistent wäre. Fortschritt
persistiert (`SAVE_KEY = "achievements"`). Neues RPC-Paar
`send_achievement_unlocked_for_player()`/
`_rpc_receive_achievement_unlocked()` für entfernte Clients — ohne
Tier-1-Fallback-Zweig und ohne Rückreferenz in `NetworkBridge` (einfacher
als Chat/Report, da Achievements nie durch einen Client-Request
ausgelöst werden). `ServiceKeys.ACHIEVEMENT`, `BootPipeline`-
Injektionsliste, neue `ServiceDefinition` `Resource_achievement`
(`optional_deps = ["pvp_death_loss", "auction_house", "report",
"savesystem", "telemetry"]`). Tests:
`tests/unit/test_achievement_service.gd` (neu, 19 Tests — unkonfigurierte
echte Instanzen der drei Quell-Services als Signal-Quellen injiziert, kein
separates Mock nötig). **Bewusst nicht Teil dieser Runde:** kein Resource-
/Editor-Workflow, keine Belohnungen, kein Snapshot-/Sync-Pfad für spät
joinende Clients, kein UI-Panel — siehe ADR-046. **Ehrlich offen:** wie
immer — kein Godot-Editor/Headless-Runner verfügbar, nur strukturell
geprüft.

Damit sind alle vier zuletzt offenen TODO-Themen (Chat/Social, Reporting/
Moderation, Telemetrie/Crash-Reporting, Achievement-Events) umgesetzt.
Als Nächstes: Tutorial/Onboarding (letztes verbliebenes Thema aus der
Round-53-Liste), oder ein neues Achievement/eine neue Trigger-Quelle als
kleinere Folge-Runde.

**Round 103 — Statistiken (ADR-047) + Achievement-Erweiterung (ADR-046
„Umsetzungsstand (Round 103)").** Explizit angefordert: stat-basierte
Achievements (Meter gelaufen/gesprungen/gefallen, NPCs getötet) +ausdrücklich
alle vier in Round 102 offen gelassenen Punkte (Editor-Workflow für
Definitionen, Belohnungen, Sync-Pfad, UI-Panel).

Neuer `StatsService` (`scripts/progression/stats/`) — zwei autoritative
Quell-Signale: `EventBus.world().enemy_killed` (bereits von QuestService
genutzt) und neu `PlayerEvents.movement_stats_batch`, emittiert aus
`Player.gd._track_movement_stats()`. Bewusst NUR im autoritativen
Bewegungs-Zweig (`_loop_free_authoritative()`), nie in Prediction/
Resimulation — sonst Doppelzählung/Client-Manipulation. Rein additiver,
minimal gehaltener Eingriff in die reconciliation-kritischste Datei des
Projekts (siehe ADR-047 „Risikobewertung" — der riskanteste blinde
Codepfad dieser Session, nicht gegen echte Physik testbar ohne Editor).
Gebündelt alle 5 Sekunden geflusht, kein Pro-Tick-Signal-Spam.

`AchievementService` umfassend erweitert:
- Vierte Trigger-Quelle (`stat_changed`), vier neue Achievements.
- `grant_progress()` auf `float` umgestellt (Meter-Werte).
- Datengetriebene Definitionen: `AchievementDefinition.gd` + `data/
  achievements/*.tres` (9 Dateien) + `DataManifest`/`DataService` — exakt
  das etablierte Quest/Item/Skill-Muster. Eingebauter Code-Fallback bleibt
  bestehen (Ergänzung, kein Ersatz).
- Gold-Belohnungen bei Unlock, direkt über `CurrencyService` (nicht
  `RewardDispatcher` — quest-spezifisch gekoppelt).
- Snapshot-Sync für spät joinende Clients (`request_snapshot()`, neues
  RPC-Paar, Pull-statt-Push wie beim Auktionshaus).

**Bewusst NICHT umgesetzt: UI-Panel.** Höchstes Risiko aller offen
gelassenen Punkte — ein `.tscn` blind zu bauen, ohne es im Editor
verifizieren zu können, hätte das größte Potenzial gehabt, etwas kaputt
zu Liefern, das niemand vor der nächsten Editor-Sitzung bemerkt hätte.
Alle Backend-Signale, die ein künftiges Panel bräuchte, sind vorhanden.

Tests: `tests/unit/test_achievement_service.gd` (+14),
`tests/unit/test_stats_service.gd` (neu, 16 Tests). **Ehrlich offen:** wie
immer — kein Godot-Editor/Headless-Runner verfügbar; der `Player.gd`-
Eingriff zusätzlich ausdrücklich als ungetesteter Risikopunkt markiert
(siehe ADR-047). Als Nächstes: Tutorial/Onboarding, oder den `Player.gd`-
Eingriff im Editor verifizieren, bevor weitere Bewegungs-Features darauf
aufbauen.

**Danach weiter offen, zur Auswahl:**

- **ADR-029 Plan-Schritt 4 ist abgeschlossen, inklusive Gegenprüfung (Round 67).**
  `EquipmentService` — Produktivcode UND Tests — ist Round 66 auf `player_id:
  String` migriert (`InventorySystem` Round 63, `QuestService` Round 64,
  `SkillSystem` Round 65 — alle vier Session-Services jetzt umgestellt, siehe
  oben). Der Identitäts-Bug im produktiven Tier-2-Pfad selbst ist behoben.
  Round 67 hat zusätzlich geklärt, dass `_sender_as_player_id()` **kein**
  Übergangs-Code ist, der noch aufzuräumen wäre — die vier verbleibenden
  `_rpc_*`-Handler adressieren peer-/verbindungsscoped Ziele (transienter
  Session-State bzw. der laufende Szenenbaum über `owner_peer_id`), keine
  Save-Buckets, und bleiben deshalb bewusst auf `peer_id: int` (siehe eigener
  Punkt oben). Einzig verbleibendes loses Ende: Tests einmal gegen die echte
  Godot/GUT-Runtime laufen lassen, sobald verfügbar — kein Code mehr, nur
  Durchführung.

- **Tier-2-Geräte-Grenzmessung durchführen** (nicht mehr bauen — die
  Mess-Infrastruktur existiert seit Round 52: `Player.get_tier2_perf_stats()`,
  Terminal-Befehle `tier2stats`/`tier2reset`,
  `docs/tier2-device-verification.md`). Was fehlt, ist kein Code mehr,
  sondern die eigentliche Durchführung auf physischer Referenz-Hardware durch
  den Project Owner (oder wer immer Zugriff auf ein Tier-2-Referenzgerät hat)
  — das kann eine Entwicklungs-Sandbox strukturell nicht selbst leisten.
  Sobald Messwerte vorliegen, gehören sie laut Protokoll als datierter Absatz
  in ADR-025 „Umsetzungsstand".

(Zuletzt geschlossen: Tutorial-/Onboarding-Struktur vollständig — Teil 2,
`TutorialGuideNPC` (`scripts/onboarding/`, stationärer NPC nahe dem
Player-Spawnpunkt, sieben wiederholbare UI/UX-Tipps über
`TutorialGuideDialogController`) — Round 106, siehe
`docs/adr/048-character-creation.md` „Round 106: Tutorial-Teil 2". Davor
im selben Round: Charaktererstellung Multiplayer-RPC-Pfad — ein
Nicht-Host-Client konnte `submit_answers()`/`skip_creation()` bis Round
105 nicht selbst auslösen. `request_submit_answers()`/
`request_skip_creation()` + gezielter Rückkanal
(`character_creation_confirmed`) — Round 106, siehe
`docs/adr/048-character-creation.md` „Round 106: Multiplayer-RPC-Pfad".
Davor Charaktererstellung Teil 1 — Fragenreihe →
Aussehen/Charakterzüge (`scripts/onboarding/`, `CharacterCreationService`
+ Vollbild-UI-Overlay, kein `.tscn`) — Round 105, siehe
`docs/adr/048-character-creation.md`. Zwei neue Achievements
(Abschluss/Übersprungen) als fünfte/sechste `AchievementService`-Trigger-
Quelle. Davor Achievement-UI-Panel (`scripts/progression/
achievements/ui/`, programmatisch wie Skill/Quest/etc., kein `.tscn`) —
Round 104, siehe ADR-046 „Umsetzungsstand (Round 104)". Dabei gefunden und
mitgefixt: der seit Round 103 tote Client-Empfangspfad für
`achievement_unlocked_received`/`achievement_snapshot_received` (nie ein
Listener, siehe `AchievementService.gd` „CLIENT-EMPFANG"); davor
`Settings.gd`-Persistenz — neuer globaler `SettingsService`
(`user://settings.json`, atomic write wie SaveSystem) ersetzt das reine
In-Memory-Dictionary; Antwort auf die Verifikationsfrage war NEIN, nichts wurde
persistiert. Settings.gd hält jetzt keinen eigenen State mehr, sondern pullt/
pusht ausschließlich über `IUIContext.get_settings()` (Cross-Scope-Bridge in
BootPipeline, analog DATA/SAVE_SYSTEM/EVENT_BUS). Runde 54, siehe
`scripts/persistence/SettingsService.gd` + `tests/unit/test_settings_service.gd`;
davor SessionManager-Rest — eigene rohe Signale durch
`EventBus.networking()` ersetzt, Runde 53, siehe ADR-018 „Update (Runde 53)";
davor Mess-Infrastruktur + Protokoll für die Tier-2-Geräte-Grenzmessung,
Round 52 — siehe Eintrag oben und
`docs/tier2-device-verification.md`; davor künstliche Latenz/Paketverlust-
Simulation für IT-03, Round 51 — siehe ADR-025/026 „Update (Round 51)"; davor
echter Zwei-Prozess-IT-03-Gameplay-Round-Trip, Round 50; davor R-8 —
Waffenbonus in `CombatSystem` las immer Spieler 1s Ausrüstung statt der des
tatsächlichen Angreifers, Round 49, direkt im Zuge des Funds behoben (siehe
Eintrag oben); davor R-7 — Server→Client-Rücksync für Economy-Mutationen +
UI-Spieler-Identität, Round 49 (ADR-022, siehe „Umsetzungsstand" dort); davor
Rate-Limiting auf `any_peer`-RPCs, Round 48 (Schritt 3, siehe Eintrag oben
unter 🔴 Kritisch).)

---
*Nicht mehr Teil dieser Liste (umgesetzt): QuestService-Sicherheitslücke (Objective-Validierung
vor Reward), ADR-015 Phase 1–6 komplett (Per-Player Interaction State + player_id-Durchreichung),
ADR-018 (SystemEvents-Split), Schritt 2 (`loot_collected`/`xp_gained`/`level_up`/`RewardDispatcher`
player_id-Durchreichung), ADR-019 (CombatSystem-Angreifer-Identität, Option B), "Server validiert
RPC-Werte nicht" (Round 45 — `_rpc_add_item`/`_rpc_add_xp`-Fläche entfernt statt validiert,
ADR-020 „Umsetzungsstand Round 45").*

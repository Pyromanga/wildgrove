# WildGrove — Bugfix-Zwischenstand

Stand: Folgesession 2 (Fortsetzung). Dieses Dokument hält fest, was
bereits gefixt ist, was root-caused aber noch nicht gefixt ist, und was noch
gar nicht untersucht wurde — damit die nächste Session direkt weitermachen kann.

---

## ✅ Bereits gefixt (im Code)

### BUG-1: UI dupliziert sich manchmal
- **Ort:** `scripts/platform/ServiceOrchestrator.gd` (`_wire_hud()`)
- **Ursache (bestätigt):** `_wire_hud(char_scope)` läuft bei JEDEM
  Session-Boot — initial UND beim Reload-Pfad (`_on_scene_reload_requested()`,
  z.B. Charakterwechsel oder "Laden" im Pause-Menü). Jeder Aufruf ruft
  `HUDManager.boot(get_tree(), factory)` — das erzeugt IMMER eine neue
  `HUDManager`-Instanz + einen neuen `HUD`-Node unter `/root`.
  `HUDManager` ist aber kein DI-Service in einer `ServiceRegistry`, sondern
  ein manuell verwalteter Scene-Tree-Node außerhalb des Boot-Systems —
  `BootPipeline.teardown_character()`/`teardown_world()` laufen nur über
  `registry`-Boot-Orders und erfassen ihn nie. Die alte
  HUDManager+HUD-Kombination blieb beim Reload also einfach hängen, während
  `boot()` daneben eine zweite aufbaute: zwei parallele HUD-Bäume mit je
  eigenem Controller-Satz (inkl. Quest-Panel), beide sichtbar, beide an
  Signale gebunden.
- **Fix:** `ServiceOrchestrator` hält jetzt eine Referenz `_hud_manager` auf
  die aktive Instanz. `_wire_hud()` ruft vor jedem `boot()` `queue_free()`
  auf einer evtl. noch vorhandenen alten Instanz auf — das löst
  `HUDManager._exit_tree()` aus, das bereits korrekt aufräumt (Bus-Disconnects,
  `teardown()` auf allen Controllern, HUD-Node freigeben).
- **Status:** Fertig, sollte funktionieren. Nicht getestet (kein Godot-Runtime
  hier verfügbar).

### BUG-2: Text über Spieler überlagert sich
- **Ort:** `scripts/ui/controllers/FloatingTextController.gd`, außerdem
  beim Untersuchen entdeckt und mitgefixt: `scripts/interaction/ui/
  InteractionUIController.gd`, `scripts/economy/equipment/ui/
  EquipmentUIController.gd`, `scripts/ui/controllers/ContextMenuController.gd`
- **Ursache (bestätigt):** dieselbe "Zombie-Controller"-Klasse, die im Code
  bereits für `NotificationController` und `InventoryUIController` gefixt war
  (siehe deren `_is_setup`-Kommentare) — `FloatingTextController` (und die drei
  oben genannten) sind RefCounted statt Node und bieten bislang kein
  `teardown()`. `HUDManager._on_world_scene_ready()` ruft zwar bereits
  generisch `teardown()` auf jedem alten Controller auf, der die Methode
  anbietet — diese vier boten sie schlicht nicht an. Jeder HUD-Rebuild
  (`world_scene_ready`, nicht nur volle Session-Reloads — auch der
  In-Session-Hot-Reload-Fall aus BUG-B) hinterließ also einen weiteren
  dauerhaft lauschenden Zombie. Bei `FloatingTextController` heißt das
  konkret: jedes `xp_gained`/`level_up`/Loot-Event spawnt N überlappende
  Text-Labels an derselben Bildschirmposition, N = Anzahl bisheriger
  HUD-Rebuilds — exakt das gemeldete Symptom "Text über Spieler überlagert
  sich".
- **Fix:** `teardown()` nach demselben Muster wie `NotificationController`
  ergänzt (Signal-Disconnects + `_is_setup`-Flag) für alle vier Controller.
- **Status:** Fertig, sollte funktionieren. Nicht getestet (kein Godot-Runtime
  hier verfügbar). `InteractionUIController`/`EquipmentUIController`/
  `ContextMenuController` waren nicht explizit in der Bug-Liste genannt,
  sondern beim gezielten Audit auf dasselbe Muster gefunden (siehe unten) —
  bitte im Spieltest zusätzlich im Auge behalten, ob sich dort etwas ändert
  (Fortschrittsbalken bei Interaktionen, Ausrüstungs-Panel, Kontextmenü).

### BUG-5: Mining-Quest zeigt 0/3 statt tatsächlichem Fortschritt
- **Ort:** `scripts/progression/quests/QuestObjectiveHandler.gd` (`resolve_xp()`),
  `scripts/progression/quests/QuestService.gd` (`on_quest_start_confirmed()`)
- **Ursache (bestätigt, zwei Teile):**
  1. `resolve_xp()` vergab bei erreichtem Ziel-Level nur ein fixes `delta: 1`
     — `update_objective()`/`QuestProgressRecord.update_progress()` arbeiten
     aber rein additiv (`current + delta`, geclamped). Ein SKILL-Objective
     soll den ABSOLUTEN Skill-Level widerspiegeln (Anzeige `Level/required`,
     z.B. `obj_reach_mining_3`), bekam durch das feste `+1` aber nie den
     tatsächlichen Wert — blieb bei Level 1/2 bei 0, weil der Delta-Zweig
     erst ab `cur_level >= required` überhaupt feuerte.
  2. `on_quest_start_confirmed()` initialisiert neue Records pauschal mit 0
     (`QuestProgressRecord.create_new()`) und synct SKILL-Objectives nicht
     mit dem beim Queststart bereits vorhandenen Skill-Level — die Anzeige
     blieb bis zum nächsten `xp_gained`-Event bei 0, selbst wenn der Spieler
     den Skill schon vorher auf Level 1/2 hatte.
- **Fix:**
  1. `resolve_xp()`: `delta = cur_level - aktueller_objective_progress`
     (nur wenn positiv) statt fixem `+1` — Fortschritt entspricht danach
     nach jedem `xp_gained`-Event exakt dem echten Skill-Level.
  2. `on_quest_start_confirmed()`: SKILL-Objectives werden direkt beim
     Queststart einmalig mit `SkillSystem.get_level()` synchronisiert
     (geclamped auf `required`).
- **Status:** Fertig, sollte funktionieren. Nicht getestet (kein Godot-Runtime
  hier verfügbar).

### BUG-C: Lebenspunkte werden nicht gespeichert
*(unverändert — siehe vorherige Fassung dieses Dokuments für Details)*

### BUG-D: Gegner nach Respawn nicht angreifbar
*(unverändert — siehe vorherige Fassung dieses Dokuments für Details)*

### BUG-B: Tiere/Pets werden beim Charakterwechsel in die Luft geschleudert
- **Ort:** `scripts/platform/ServiceOrchestrator.gd` (`_on_state_changed()`)
- **Ursache (bestätigt via Log `wildgrove_2026-09-25_00-38-22.log`):** der
  frühere Fix in `InteractionExecutor.gd` (Debounce über `_last_started`,
  Kommentar "BUGFIX 2026-09-20") behandelt nur doppelte Signal-Emissionen
  INNERHALB derselben Instanz. Tatsächliche Ursache war eine ZWEITE, lebende
  `InteractionExecutor`-Instanz: `_on_state_changed(MAIN_MENU)` — der Pfad,
  der beim Charakterwechsel läuft — rief `_app_scope.destroy_character_scope()`
  bisher DIREKT auf, ohne vorher `_pipeline.teardown_world()` /
  `_pipeline.teardown_character()` laufen zu lassen (anders als der
  Reload-Pfad `_on_scene_reload_requested()`, der das schon immer richtig
  macht). `CharacterScope.destroy()`/`WorldScope.destroy()` räumen selbst
  nichts ab — kein `ServiceTeardownManager`-Aufruf, nur Logging + Nullsetzen
  von Referenzen. Jeder Character-Service (nicht nur InteractionExecutor —
  potenziell auch Quest/Inventory/SkillSystem/etc.) blieb also mit offener
  Verbindung zum globalen `IEventBus` (App-Scope, überlebt Charakterwechsel)
  am Leben. Der nächste Charakter bootet einen zweiten `InteractionExecutor`,
  der sich auf denselben Bus registriert → jede Interaktion (u.a.
  "Tier fangen") lief doppelt ab → zwei Pets exakt an derselben Position →
  CharacterBody3D-Capsules überlappen komplett → Godots Physik-Auflösung
  schießt eines auf absurde Koordinaten (>1e18 units) — im Log an den
  `look_at()`-Fehlern in `PetComponent.gd:144` sowie an zwei identischen
  "Starte (Spieler 1): 'Tier fangen'"-Logzeilen im selben Sekundenfenster
  erkennbar.
- **Fix:** `_on_state_changed()` ruft jetzt vor `destroy_character_scope()`
  dieselbe Teardown-Sequenz wie `_on_scene_reload_requested()` auf
  (`teardown_world()` dann `teardown_character()`) — das löst `on_cleanup()`
  auf jedem Character-/World-Service aus und trennt alle Bus-Verbindungen
  des alten Charakters zuverlässig, bevor der neue Charakter seine eigenen
  Services bootet.
- **Status:** Fertig, sollte funktionieren. Nicht getestet (kein Godot-Runtime
  hier verfügbar). Da dieselbe Zombie-Ursache (fehlender Teardown bei
  `_on_state_changed`) potenziell JEDEN Character-Service betrifft, im
  Spieltest zusätzlich beobachten, ob doppelte Quest-Trigger, doppelte
  XP/Loot-Vergabe o.ä. nach mehrfachem Charakterwechsel verschwunden sind.

### BUG-A: Skelette zeigen "Ein Goblin..."-Text
*(unverändert — siehe vorherige Fassung dieses Dokuments für Details)*

### BUG-G: Equipment wird nicht 3D gerendert (Axt/Spitzhacke/Schaufel)
- **Ort:** `scripts/economy/equipment/EquipmentService.gd` (`equip()`) +
  `scripts/entities/combat/WeaponVisual3D.gd` + `scripts/economy/equipment/ToolDefinition.gd`
- **Ursache:** `equip()` hängte ein `WeaponVisual3D` bisher nur an, wenn
  `item_def is WeaponDefinition`. `ToolDefinition` (Gathering-Werkzeuge,
  `SLOT_TOOL`) erbt aber unabhängig direkt von `ItemDefinition` — ist also
  KEIN `WeaponDefinition`-Subtyp — und wurde von dieser Bedingung nie
  erfasst. Zusätzlich hatte `ToolDefinition` bislang gar keine
  Visual-Felder (`visual_offset`/`visual_rotation`/Typ-Diskriminator für die
  Mesh-Form) — selbst ein reiner Bedingungs-Fix hätte also nur einen
  generischen grauen Platzhalter ohne Unterscheidung zwischen Axt/
  Spitzhacke/Schaufel ergeben.
- **Fix:**
  1. `ToolDefinition.gd`: neues `tool_type`-Enum (AXE/PICKAXE/SHOVEL) +
     `visual_offset`/`visual_rotation` (analog `WeaponDefinition`).
  2. `WeaponVisual3D.gd`: Parametertyp von `WeaponDefinition` auf die
     gemeinsame Basisklasse `ItemDefinition` geweitet; `_build_mesh()`/
     `_get_mesh_size()` branchen jetzt zusätzlich auf `ToolDefinition` und
     geben Werkzeugen eine eigene Form/Farbe je `tool_type`. Offset/Rotation
     werden per `.get()` (duck-typed) übernommen, falls vorhanden.
  3. `EquipmentService.equip()`: Bedingung auf
     `item_def is WeaponDefinition or item_def is ToolDefinition` erweitert.
  4. `data/items/tools/Pickaxe.tres`/`Shovel.tres`/`WoodAxe.tres`: `tool_type`
     explizit gesetzt (vorher implizit 0/AXE für alle drei — hätten sonst
     alle identisch als "Axt" ausgesehen).
- **Status:** Fertig, ungetestet (kein Godot-Runtime hier verfügbar). Beide
  betroffenen Typen nutzen weiterhin nur das prozedurale BoxMesh-Placeholder
  — falls es später echte Werkzeug-Meshes/-Modelle gibt, ist das der Punkt,
  an dem `_build_mesh()` erweitert werden müsste (aktuell nur Form + Farbe).

### BUG-E: Waffe bleibt nach dem Anlegen im Inventar
- **Ort:** `scripts/economy/equipment/EquipmentService.gd` (`on_equip_confirmed()`)
- **Ursache:** `equip()` selbst mutiert bewusst nur den Slot-State (siehe
  Klassenkommentar: "NICHT VERANTWORTLICH für Inventar-Abzug beim Equip").
  Diese Verantwortung sollte laut Kommentar in der UI-/Interaction-Schicht
  liegen — aber weder `InventoryUIController` noch `EquipmentUIController`
  haben sie je übernommen (beide rufen nur `request_equip()` auf). Ergebnis:
  ein angelegtes Item blieb parallel im Inventar sichtbar/nutzbar.
- **Fix:** `on_equip_confirmed()` — der einzige Pfad, über den das Spiel
  tatsächlich equippt (siehe TODO zu ADR-027) — entfernt das Item jetzt nach
  erfolgreichem `equip()` explizit aus dem Inventar. Symmetrisch dazu gibt
  `on_unequip_confirmed()` es beim Ablegen zurück. Slot-Swap (ein anderes
  Item war schon im Slot) behandelt: das verdrängte Item wird nicht mehr
  ersatzlos verworfen, sondern ebenfalls zurück ins Inventar gebucht.
- **Status:** Fertig, ungetestet (kein Godot-Runtime hier verfügbar).

### BUG-F: PvE-Schutz-Scroll überlebt Anlegen/Ablegen nicht (Item trotz Schutz beim Tod verloren)
- **Ort:** `scripts/economy/equipment/EquipmentService.gd` +
  `scripts/economy/inventory/InventorySystem.gd` (neue Methode
  `restore_item_instance()`)
- **Ursache:** direkte Folge von BUG-E, beim Beheben mit aufgefallen. Der
  Schutz-Zustand (`is_pve_death_protected`/`is_theft_protected`/
  `is_pvp_protected`, dazu `durability`/`uuid`) lebt auf der `ItemInstance`
  im Inventar — `EquipmentService` merkte sich beim Equip aber nur die
  `ItemDefinition` (den Item-*Typ*, ohne Instanz-Zustand). Mit dem BUG-E-Fix
  entfernt `on_equip_confirmed()` das Item jetzt aus dem Inventar — dabei
  wird ohne Gegenmaßnahme die einzige `ItemInstance` mit dem Schutz-Flag
  zerstört. Wird die Waffe später wieder abgelegt, erzeugt
  `request_add_item()` eine **neue, ungeschützte** Instanz. Konkreter Ablauf
  aus dem Bugreport: Scroll auf Waffe angewendet → Waffe angelegt (Schutz-
  Instanz zerstört) → PvE-Tod → Waffe war nie tatsächlich geschützt, sobald
  der Zyklus einmal durchlaufen wurde.
- **Fix:** `EquipmentService` merkt sich zusätzlich (`_equipped_instances`,
  nur für den Equip/Unequip-Rückbau) die tatsächliche `ItemInstance` des
  angelegten Items. `InventorySystem.restore_item_instance()` (neu) fügt
  diese beim Ablegen/Verdrängen unverändert wieder ein, statt wie
  `request_add_item()` eine frische Instanz mit Default-Werten zu erzeugen.
  `clear_player()` räumt die neue Ablage mit auf.
- **Status:** Fertig, ungetestet. Bekannter Rand-Fall (dokumentiert im Code):
  wurde während des Equips ein weiteres Exemplar desselben Item-Typs neu
  aufgesammelt, werden beim Zurücklegen die Mengen zusammengeführt und der
  Schutz-Zustand der zurückgegebenen (alten) Instanz gewinnt — dieselbe
  bekannte Einschränkung wie "eine ItemInstance pro item_id pro Spieler"
  generell (siehe `ItemInstance`-Klassenkommentar), kein neues Problem.

---

## 🆕 Neu: Speicher-/Objekt-Telemetrie (2026-09-25)

- **Anlass:** Anfrage nach Telemetrie/Monitoring, um Speicherprobleme künftig
  selbst zu erkennen — direkte Reaktion auf die "Zombie"-Bugs dieser Session
  (BUG-1, BUG-2, BUG-B), die sich ohne aktives Monitoring nur über zufällig
  sichtbare Symptome (doppelte UI, doppelte Interaktionen) bemerkbar gemacht
  haben. Ein Leak, der sich NICHT verdoppelt, sondern nur RAM/Objekte über
  Zeit ansammelt, wäre bisher unbemerkt geblieben.
- **Ort:** `scripts/telemetry/TelemetryService.gd` (neue Methode
  `record_memory_snapshot()`, neuer `on_tick()`), `config/BootstrapConfig.tres`
  (telemetry bekommt jetzt `ticker` als optionale Dep), `scripts/debug/
  SimpleTerminal.gd` (neue Befehle `mem`/`memhistory`).
- **Was es macht:** Snapshot aus Godots eingebauten Performance-Monitoren
  (Objekt-/Node-/Resourcen-Zahl, **verwaiste Nodes** — der wichtigste Wert
  für genau die heutige Bug-Klasse) + statischem Speicherverbrauch
  (`OS.get_static_memory_usage()`), mit Delta zum letzten Snapshot, geloggt
  über die bestehende `AppLogger`-Infrastruktur (Kategorie "Telemetry", INFO
  + WARN falls verwaiste Nodes > 0). Automatisch an drei Stellen:
  1. `EventBus.session.session_ready` (nach jedem Charakter-Boot)
  2. `EventBus.session.session_unloaded` (nach jedem Charakter-Teardown)
  3. periodisch alle `MEMORY_SAMPLE_INTERVAL_SEC` (60s) über den bestehenden
     `ServiceTicker` (Pattern von `RespawnService`/`PvPService` übernommen)
  Zusätzlich manuell abrufbar per Debug-Terminal: `mem` (sofortiger
  Snapshot) und `memhistory` (kompletter Verlauf der Sitzung).
- **So findet man damit einen Leak wie BUG-B:** mehrfach Charakter wechseln,
  dann `memhistory` im Debug-Terminal — die `session_unloaded`-Snapshots
  sollten sich alle ungefähr gleichen (Rückkehr zur Baseline). Wächst
  `node_count`/`orphan_node_count`/`static_memory_bytes` stattdessen mit
  jedem Wechsel weiter, bleibt irgendwo etwas am Leben, das nicht sollte —
  exakt das Muster von BUG-1/BUG-2/BUG-B.
- **Bewusst NICHT Teil dieser Runde:** kein Upload/Server-Endpunkt (bleibt
  rein lokal in der Log-Datei, siehe `TelemetryService`-Klassenkommentar),
  kein Dashboard/UI-Chart — nur Log-Zeilen + die beiden Terminal-Befehle.
  Für ein visuelles Diagramm über die Zeit wäre das der nächste Schritt.
- **Status:** Fertig, ungetestet (kein Godot-Runtime hier verfügbar) — bitte
  im Editor kurz gegenchecken, dass `Performance.OBJECT_ORPHAN_NODE_COUNT`
  etc. in der genutzten Godot-4.3-Version so heißen (sollten seit Godot 3
  stabil sein, aber ohne Runtime hier nicht verifizierbar).

---

## 🆕 Neu: Item-Dropdown im Admin-Panel statt Freitext-item_id (2026-09-25)

- **Anlass:** Admin-Panel-Item-Vergabe brauchte bisher die exakte `item_id`
  als Freitext — bei ~40+ Items (Tendenz steigend) unpraktikabel zum
  Auswendiglernen.
- **Ort:** `scripts/debug/AdminPanelUI.gd` (`_build_item_row()` +
  neu `_categorize_item()`/`_refresh_item_catalog()`/`_populate_item_dropdown()`),
  `scripts/economy/inventory/InventorySystem.gd` (neue Methode
  `get_all_item_definitions()`).
- **Was es macht:** zwei Dropdowns (Kategorie → Item), Anzeige per
  `display_name` statt `item_id`. Kategorisierung wird zur Laufzeit aus dem
  bereits vorhandenen Item-Typ/Feldern abgeleitet (`WeaponDefinition`/
  `ToolDefinition`-Subtyp, `grants_protection_type`/`pickpocket_crystal_tier`/
  `plants_crop_id`) — **kein neues Datenfeld**, das ab jetzt bei jedem neuen
  Item von Hand gepflegt werden müsste. Kategorien: Waffen, Werkzeuge,
  Schutz-Scrolls, Diebstahl-Kristalle, Samen, Rohstoffe & Sonstiges (Rest).
  Katalog wird bei jedem Öffnen des Panels frisch geladen (nicht einmalig
  gebaut), da `InventorySystem` ein Character-Scope-Service ist und beim
  ersten Erstellen der UI (Hauptmenü) evtl. noch nicht existiert.
- **Status:** Fertig, ungetestet (kein Godot-Runtime hier verfügbar).

---



---

## ❌ Noch gar nicht untersucht

| # | Bug (aus Original-Liste) | Notiz |
|---|---|---|
| 3 | Quests enden ohne NPC-Gespräch | `scripts/progression/quests/QuestService.gd` + Trigger in `scripts/progression/quests/triggers/`. **Erst nach dem UI-Duplikat-Fix (BUG-1/BUG-2) neu gegentesten** — möglich, dass sich das Symptom durch doppelte/zombie Controller erklärt hat. Falls es weiter auftritt: Verdacht bleibt ein Trigger, der Quest-Completion fälschlich auslöst (z.B. KILL/COLLECT-Objective erreicht komplettiert automatisch ohne Rückgabe-Dialog-Schritt). |
| 4 | Quest-Fortschritt wird gespeichert, UI zeigt ihn nach Save/Reload nicht an | Ebenfalls **erst nach BUG-1/BUG-2-Fix neu gegentesten**. Falls weiter auftritt: fehlender UI-Refresh-Call beim Session-Start prüfen — `QuestPanelController._refresh_active_quests()` existiert bereits und sollte das eigentlich abdecken (siehe Code), also ggf. Timing-Problem statt fehlender Call. |
| 6 | Skill für Kondition fehlt (XP fürs Laufen, Effekt: schneller laufen) | Feature-Wunsch, kein Bug. Noch nicht angefasst. `Player._track_movement_stats()` sammelt bereits `_stat_walked_accum` und emittiert `movement_stats_batch` — natürlicher Hook für ein neues "Ausdauer"-Skill. |
| 7 | UI teils klein / nicht modern | Design-/Polish-Thema, kein klassischer "Bug". Braucht eigene Design-Pass-Session. |
| 8 (neu, geprüft — kein Bug) | Weitere Zombie-Controller? | Beim Audit für BUG-2 wurden `InteractionUIController`/`EquipmentUIController`/`ContextMenuController` gefunden und mitgefixt (siehe BUG-2). Zusätzlich geprüft: `TerminalController.gd`, `QuestNPCDialogController.gd`, `TutorialGuideDialogController.gd` — alle drei haben KEINE eigenen Bus-Signal-Verbindungen (nur direkte Methodenaufrufe bzw. bereits korrektes `on_spawn()`/`on_despawn()`-Paar bei `QuestNPC`/`TutorialGuideNPC`, analog `EnemyNPC`). Kein Zombie-Risiko, keine Änderung nötig. |

---

## Empfehlung für die nächste Session

1. ~~BUG-B (Pets)~~ / ~~BUG-D (Gegner)~~ / ~~BUG-C (HP-Save)~~ — erledigt.
2. ~~BUG-1 (UI-Duplikat)~~ / ~~BUG-2 (Text-Überlagerung + weitere Zombie-Controller)~~ / ~~BUG-5 (Mining-Quest-Progress)~~ — erledigt.
3. **Zuerst im Spiel gegentesten:** Charakterwechsel bzw. "Laden" mehrfach
   hintereinander auslösen und prüfen, ob UI jetzt sauber bleibt, ob XP/Loot-
   Text nicht mehr überlagert UND ob #3/#4 dadurch mit verschwunden sind.
4. Falls #3/#4 weiter auftreten: isoliert wie oben notiert angehen.
5. Feature-Wunsch Kondition-Skill und UI-Modernisierung — separate,
   nicht-Bugfix-Sessions.

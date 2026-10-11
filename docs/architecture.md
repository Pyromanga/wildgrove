# WildGrove — Architektur & System-Übersicht

> **Stand:** v32 — aktuelle Produktionsarchitektur  
> **Vorgänger:** `scripts/debug/architecture.md` (v28) — dieser Datei ersetzt sie  
> **Ergänzende Dokumente:** `docs/adr/` (Warum-Entscheidungen), `CONTRIBUTING.md` (Konventionen), `docs/principles.md` (Coding-Regeln)  
> **⚠ Staleness-Hinweis (Session 5):** Diese Datei wurde seit v32 nicht mehr durchgängig gepflegt — `docs/review.md` ist seitdem bei v37 und hat mehrere der unten gelisteten Tech-Debt-Positionen bereits behoben (siehe Abschnitt 9). Bei Widerspruch zwischen dieser Datei und `docs/review.md`: **`docs/review.md` glauben**, es ist die aktuellere, session-für-session gepflegte Quelle. Eine vollständige Überarbeitung dieser Datei steht noch aus.

---

## 1. Schichtenmodell

```
┌─────────────────────────────────────────────────────────────┐
│  PRESENTATION LAYER                                         │
│  HUDManager · *Controller · *Visuals · LayoutManager       │
│  → nur lesen via EventBus, nie direkt Services mutieren     │
├─────────────────────────────────────────────────────────────┤
│  ENTITY LAYER                                               │
│  Player · OakTree · EnemyNPC · AnimalBase · QuestNPC · …   │
│  → kommunizieren AUSSCHLIESSLICH via EntityContext + Events │
│  → KEIN direkter Services.xyz-Zugriff                       │
├─────────────────────────────────────────────────────────────┤
│  SERVICE LAYER                                              │
│  InventorySystem · QuestService · SkillSystem · WorldService│
│  SaveSystem · DataService · PlayerStateService · …          │
│  → erhalten Deps via configure(deps) injiziert              │
│  → kommunizieren via EventBus (Notifications)               │
│  → fragen andere Services via Services.xyz (Data Requests)  │
├─────────────────────────────────────────────────────────────┤
│  INFRASTRUCTURE LAYER                                       │
│  ServiceOrchestrator · EventBus · Logger · Services         │
│  → AutoLoads, leben für die gesamte Spiellaufzeit           │
└─────────────────────────────────────────────────────────────┘
```

**Schichten-Regeln (unverletzlich):**
- Pfeile zeigen nur nach unten (Presentation → Entity → Service → Infrastructure)
- Entities kennen `Services.xyz` NICHT — nur `EntityContext`
- Services kennen UI NICHT — nur EventBus-Emissions
- Infrastructure kennt keinen Game-Code

---

## 2. Boot-Pipeline

`ServiceOrchestrator._ready()` startet die Pipeline einmalig beim App-Start. Services überleben alle Szenenwechsel.

```
Phase 1 — Validate      ServiceValidator prüft BootstrapConfig.tres
Phase 2 — Resolve       ServiceDependencyResolver (Kahn's Algorithmus → Topological Sort)
Phase 3 — Instantiate   ServiceFactory erzeugt Instanzen (Node oder RefCounted)
Phase 4 — Configure     ServiceInitializer ruft configure(deps) auf — Services.xyz ist hier LEER
Phase 5 — Activate      ServiceInitializer ruft on_ready() auf — Services.xyz ist befüllbar
Phase 6 — Tick Start    ServiceTicker.start_ticking()
Phase 7 — Install       Services-Container wird befüllt (Services.populate(registry))
Phase 8 — Game Start    GameManager.start_game() → Szenenwechsel
```

**Kritische Timing-Regel:** Niemals `Services.xyz` in `configure()` aufrufen. `Services` ist in Phase 4 noch leer. Erst ab Phase 5 (`on_ready()`) sicher.

---

## 3. Suffix-Konventionen

Jeder Klassenname signalisiert seine Rolle durch das Suffix. Bei Unsicherheit: Entscheidungsbaum in `CONTRIBUTING.md` Abschnitt 3.3.

| Suffix | Basisklasse | Verantwortung | Beispiele |
|--------|-------------|---------------|-----------|
| `Service` / `System` | `ServiceNode` (→ Node) | Langlebiger Singleton-Service, Lifecycle via Orchestrator | `QuestService`, `InventorySystem` |
| `Manager` | `Node` | Lokaler Bereichs-Manager, lebt im SceneTree | `ChunkManager`, `HUDManager` |
| `Orchestrator` | `Node` | Koordiniert Sub-Systeme, keine eigene Fachlogik | `EntityOrchestrator`, `ServiceOrchestrator` |
| `Handler` | `RefCounted` | Verarbeitet einen Event-Typ, stateless | `QuestObjectiveHandler`, `WorldSaveHandler` |
| `Builder` | `RefCounted` | Erzeugt ein Objekt und gibt es zurück | `TerrainMeshBuilder`, `HUDBuilder` |
| `Factory` | `RefCounted` / `Node` | Erzeugt mehrere verschiedene Typen | `ServiceFactory`, `Factory3D` |
| `Controller` | `Node` (UI) | Verbindet UI-Signale mit EventBus | `QuestPanelController`, `PauseMenuController` |
| `Visuals` | `Node` | Nur Render-/Layout-Logik, kein Gameplay | `QuestPanelVisuals`, `EnemyVisuals` |
| `Component` | `Node3D` / `Node` | Fügt einer Entity eine Fähigkeit hinzu | `InteractableComponent`, `HealthComponent` |
| `Detector` / `Sensor` | `Node3D` | Physik-basierter Sensor, emittiert Signale | `ProximityDetector`, `InteractionSensor` |
| `Executor` | `Node` | Führt Operation mit Dauer aus | `InteractionExecutor` |
| `Spawner` | `RefCounted` | Instanziiert und platziert Entities | `WorldSpawner`, `EnemySpawner` |
| `Placer` | `RefCounted` | Wie Spawner, für Nicht-Entities | `WaterBodyPlacer` |
| `Dispatcher` | `Node` / `RefCounted` | Verteilt etwas an mehrere Empfänger | `RewardDispatcher` |
| `Registry` | `RefCounted` | Hält Definitionen/Typen, kein Gameplay | `EntityRegistry`, `ServiceRegistry` |
| `Pool` | `RefCounted` | Object-Pool: acquire/release | `EntityPool` |
| `Resolver` | `RefCounted` | Löst Abhängigkeiten oder Konflikte auf | `ServiceDependencyResolver` |
| `Validator` | `RefCounted` | Prüft Zustand, verändert nichts | `ServiceValidator`, `StateValidator` |
| `Helper` / `Utils` | `RefCounted` (statisch) | Statische Utility-Methoden | `MathHelper`, `UIUtils` |
| `NPC` | `Node3D` | Nicht-spielbare Figur | `QuestNPC`, `EnemyNPC` |
| `AI` | `RefCounted` | State-Machine-Logik für NPC | `EnemyAI` |
| `Data` | `Resource` / `RefCounted` | Reines Daten-Objekt, kein Verhalten | `WorldData`, `InteractableData` |
| `Definition` | `Resource` | Unveränderliche Typ-Beschreibung (.tres) | `QuestDefinition`, `ItemDefinition` |
| `Config` | `Resource` | Konfiguration für ein System | `RespawnConfig`, `GameConfig` |

---

## 4. Entity-Lifecycle

```gdscript
# EntityOrchestrator.spawn_entity() injiziert Context:
entity.on_spawn(config: Dictionary, ctx: IEntityContext)

# Entity speichert Context, greift nie direkt auf Services zu:
func on_spawn(config: Dictionary, ctx: IEntityContext) -> void:
    _ctx = ctx
    _ctx.get_inventory().request_add_item(...)  # ✅
    Services.inventory.request_add_item(...)     # ❌ VERBOTEN

# Cleanup:
entity.on_despawn()
```

Entities werden entweder neu instanziiert oder aus dem `EntityPool` geholt (Pool-first, dann frisch wenn Pool leer).

---

## 5. Networking-Kontrakt

**Dokumentiert in:** `scripts/interfaces/core/NetworkContract.gd`

**Server-autoritativ** (request_/confirmed_-Pattern Pflicht):
- `InventorySystem` — add_item, remove_item, trade
- `QuestService` — start_quest, complete_quest, update_objective
- `EntityOrchestrator` — spawn_entity, despawn_entity
- `PlayerStateService` — health, position
- `SkillSystem` — xp_gain, level_up

**Client-autoritativ** (darf State direkt mutieren):
- `TouchInput`, `PlayerCamera` — Input, Kamera
- `HUDManager`, `LayoutManager` — UI-State, Animation
- `Settings` — lokale Display/Audio-Präferenzen

**Heute:** `request_*()` ruft `on_*_confirmed()` synchron und lokal auf.  
**Morgen:** `request_*()` sendet an Server; Server ruft `on_*_confirmed()` via RPC.  
**Der Aufruf-Code ändert sich nicht** — nur der Body von `request_*()`.

---

## 6. Save-System

**Provider-Pattern:** Jeder save-relevante Service implementiert `ISaveProvider`:

```gdscript
func get_save_key() -> String  # eindeutiger Key im Save-Dictionary
func get_save_data() -> Dictionary  # immer .duplicate() zurückgeben
```

Registration in `configure()`:
```gdscript
_save_system.register_save_provider(self)
```

**Save-Provider (aktuell):**

| Service | Key | Inhalt |
|---------|-----|--------|
| `InventorySystem` | `inventory` | `{ item_id: quantity }` |
| `SkillSystem` | `skills` | `{ skill_name: { xp, level } }` |
| `QuestService` | `quest_progress` | `{ active, completed, available }` |
| `WorldService` | `world_state` | `{ day_time, day_count, typed_tree_positions, typed_ore_positions, player_pos, harvested, saved_pets, world_seed }` |

**Migration:** `SaveMigrationService.CURRENT_VERSION` erhöhen + `_migrate_vN_to_vN1()` implementieren.

**Bekannte Lücken** (Tech Debt aus ADR-005):
- Kein Atomic Write (Crash-Risiko)
- Kein Rotating Backup
- Kein Save-Slot-System

---

## 7. EventBus-Architektur

Alle Events sind über namespaced Objekte organisiert. Neues Signal:
1. In den passenden `scripts/events/*Events.gd` eintragen
2. In `docs/services.md` dokumentieren

**Namespaces:**
- `EventBus.player` — Health, XP, Level, Input, State
- `EventBus.world` — Entities, Terrain, Day/Night, Interaction
- `EventBus.system` — Boot, Teardown, Save, Szenenwechsel
- `EventBus.quest` — Quest-Lifecycle, Objectives
- `EventBus.ui` — Menü-Zustände, HUD-Updates

**Signal-Richtung:** Entities emittieren → EventBus → Services reagieren. Services emittieren → EventBus → UI reagiert. Nie umgekehrt.

---

## 8. Faustregeln (Quick Reference)

```
≤ 150 Zeilen    → OK
150–200 Zeilen  → Prüfen ob Verantwortungen gemischt sind
> 200 Zeilen    → Aufteilen (Ausnahme: Logger.gd, SimpleTerminal.gd dokumentiert)

RefCounted > Node     — wenn kein SceneTree nötig
Signale nur aufwärts  — Entity → EventBus → Service, nie Service → Entity
DI in configure()     — nie Services.xyz in configure() aufrufen
EntityContext immer   — nie Services.xyz aus einer Entity
request_/confirmed_   — für alle server-autoritativen State-Mutationen
.duplicate() im Save  — SaveSystem hält keine Referenzen
```

---

## 9. Bekannte Tech-Debt-Positionen

Diese Punkte sind dokumentierte Schulden — keine Bugs. Jeder Eintrag hat einen ADR-Verweis.

| # | Beschreibung | ADR | Priorität |
|---|-------------|-----|-----------|
| TD-01 | `Player.gd` greift auf `Services.xyz` direkt zu (Schichtverletzung) | ADR-006 | Mittel |
| TD-02 | Die meisten Services nutzen `ServiceNode` obwohl `Service` reicht — Stand Session 5: `InventorySystem`/`SkillSystem`/`QuestService` migriert (3/6), Rest (`DataService`/`SaveSystem`/`PlayerStateService`) offen | ADR-003 | Niedrig |
| TD-03 | SaveSystem ohne Atomic Write, ohne Slots | ADR-005 | Hoch |
| TD-04 | `QuestService`/`SkillSystem` nutzen nicht vollständig das request_/confirmed_-Pattern | ADR-004 | Mittel |
| TD-05 | `HUDManager` ist als Service registriert, ist aber UI (Lifecycle-Mismatch) | — | Mittel |
| TD-06 | `GameSaveService` und `SaveSystem` — Aufteilung unklar | — | Mittel |
| TD-07 | Kein `INetworkAdapter`-Interface — der Networking-Layer hat keinen Code-Stub | — | Hoch |
| TD-08 | Kein `StatModifierService` — Equipment-Boni, Buffs, Debuffs haben kein Fundament | — | Hoch |
| TD-09 | Kein CombatSystem mit typisiertem DamageRecord | — | Hoch |
| TD-10 | DataService lädt synchron alles beim Boot — kein Lazy Loading | — | Niedrig |

---

## 10. Nächste Architektur-Sessions (Priorisiert)

### Sofort (blockiert weiteres Feature-Development)
1. `SaveSystem` — Atomic Write (`savegame.tmp` → rename)
2. `HUDManager` aus dem Services-Container entfernen
3. `GameSaveService` vs `SaveSystem` — klare Aufteilung oder Zusammenführung

### Nächste Architektur-Session
4. `INetworkAdapter`-Interface anlegen (LocalNetworkAdapter als Stub)
5. `StatModifierService` Grundgerüst
6. `Player.gd` von `Services.xyz` entkoppeln

### Langfristig (jetzt designen, später implementieren)
7. `CombatSystem` mit `DamageRecord`, `DamageType`-Enums
8. `DataRepository` als Lazy-Loading-Wrapper um `DataService`
9. Save-Slot-System
10. Test-Framework-Konvention formalisieren (GUT oder Custom)

# Contributing to WildGrove

> **Zielgruppe:** Jede Person die Code beisteuert — einschließlich des ursprünglichen Autors in sechs Monaten.
> Dieses Dokument ist ein verbindlicher Kontrakt, kein Vorschlag.

---

## 1. Vor dem ersten Commit — Pflichtlektüre

Lies diese Dokumente in dieser Reihenfolge:

1. `docs/architecture.md` — Systemüberblick, Schichtenmodell, Boot-Pipeline
2. `docs/principles.md` — Coding-Regeln mit Beispielen (positiv + negativ)
3. `docs/adr/` — Architecture Decision Records: warum wir Entscheidungen so getroffen haben
4. `docs/services.md` — Service-Registry, EventBus-Signale, Save-Provider

Wenn du eine Entscheidung in diesen Dokumenten nicht verstehst, frage **bevor** du code schreibst — nicht danach.

---

## 2. Review-Checkliste (vor jedem Commit)

Jeder Commit muss diese Checks bestehen. Kein Ausnahme.

### 2.0 ADR-003 Lint (automatisiert)

Vor jedem Push läuft `scripts/ci/lint_servicenode.sh` — entweder lokal oder in CI.

- [ ] Hast du einen neuen Service mit `extends ServiceNode` angelegt?
  → Braucht er wirklich `add_child()`, `get_tree()` oder `call_deferred()`?
  → Wenn **nein**: `extends Service` verwenden.
  → Wenn **ja**: `# justified: <konkreter Grund>` in Zeile 2 einfügen **und** Datei in `JUSTIFIED_FILES` im Lint-Skript und in ADR-003 nachtragen.
  → Lint-Script lokal ausführen: `bash scripts/ci/lint_servicenode.sh`

### 2.1 Schichtentrennung

- [ ] Greift eine **Entity oder Component** direkt auf `Services.xyz` zu?
  → **Review-Blocker.** Services werden via `EntityContext` injiziert oder via EventBus konsumiert. Direkte `Services.xyz`-Zugriffe sind nur in `ServiceNode`-Implementierungen erlaubt.

- [ ] Kennt ein **Service** einen anderen Service über `Services.xyz` statt via injiziertem Dependency?
  → **Review-Blocker** innerhalb von `configure()`. In `on_ready()` ist `Services.xyz` erlaubt, muss aber mit `is_instance_valid()` abgesichert sein.

- [ ] Ruft eine **Component** direkt Methoden auf ihrem Parent-Node auf (`get_parent()._on_something()`)?
  → **Review-Blocker.** Components kommunizieren via Signals aufwärts, nie via direktem Parent-Aufruf.

- [ ] Greift ein **UI-Controller** (`scripts/ui/controllers/*.gd`) direkt auf `EventBus.xyz` zu?
  → **Review-Blocker.** EventBus wird via injiziertem `IUIContext.bus()` konsumiert (ADR-012),
  analog zu Services über `IEventBus`/`deps.require(EVENT_BUS)` (ADR-011). `setup(visuals, ctx)`
  ist die einzige Stelle, an der ein Controller einen `IUIContext` annimmt — kein zweiter,
  paralleler Namespace-Parameter (`UIEvents`, `PlayerEvents`, untypisiertes `Object`) daneben.

### 2.2 Statische Typisierung

- [ ] Gibt es `var x = something` ohne Typ-Annotation wo der Typ bekannt ist?
  → **Review-Blocker.** Immer `var x: ClassName = something` oder `var x := something` (Type Inference).

- [ ] Gibt es `registry.get_service("name")` ohne sofortiges `as ClassName`?
  → **Review-Blocker.** Duck-Typing auf Service-Rückgaben ist verboten.

- [ ] Gibt es `Array` ohne Typ-Parameter wo der Inhalt homogen ist?
  → **Warnung.** `Array[Node3D]` statt `Array`.

### 2.3 Networking-Kontrakt

- [ ] Mutiert eine Methode in einem server-autoritativen System State direkt, ohne `request_`/`on_*_confirmed`-Pattern?
  → **Review-Blocker** für: `InventorySystem`, `QuestService`, `SkillSystem`, `EntityOrchestrator`, `PlayerStateService`, `CombatSystem`.
  
  Erlaubte Muster:
  ```gdscript
  func request_add_item(item_id: String, qty: int = 1, player_id: int = 1) -> bool  # Client-seitig
  func on_item_add_confirmed(item_id: String, qty: int, player_id: int = 1) -> void  # Einzige State-Mutation
  ```
  
  Implementierung (MIGRATION-010 Phase 2+): Godot `MultiplayerAPI` + `@rpc`, **nicht** `INetworkAdapter`.
  `NetworkBridge.gd` hostet alle `@rpc`-Methoden für RefCounted-Services (ADR-010).
  `INetworkAdapter` / `LocalNetworkAdapter` sind entfernt.

- [ ] Wurde `NetworkContract.gd` gelesen bevor ein neues server-autoritatives System angelegt wurde?
  → Neues System in `NetworkContract.gd` dokumentieren (Authority-Matrix).

- [ ] Haben neue öffentliche Methoden in server-autoritativen Services `player_id: int = 1` als Default-Parameter?
  → **Pflicht** für Methoden die pro-Spieler-State mutieren (MIGRATION-010 Multi-Tenanz).

### 2.4 Lifecycle-Compliance

- [ ] Ruft `configure(deps)` irgendetwas auf `Services.xyz` auf?
  → **Review-Blocker.** `Services` ist in Phase 4 noch leer. Nur `deps.get("name")` ist erlaubt.

- [ ] Nutzt ein `ServiceNode` `_process()` oder `_physics_process()` statt `on_tick()`?
  → **Review-Blocker.** Alle Update-Logik in Services läuft über `ServiceTicker`.

- [ ] Hat ein neuer Service eine `on_cleanup()`-Implementierung die Signals trennt und Ressourcen freigibt?
  → **Pflicht** wenn `on_ready()` Connections anlegt.

### 2.5 Save-System

- [ ] Gibt `get_save_data()` ein `.duplicate()` zurück oder direkte Referenzen?
  → **Review-Blocker.** Das SaveSystem darf keine Referenzen auf interne State-Strukturen halten.

- [ ] Wurde für neue save-relevante Felder `SaveMigrationService.CURRENT_VERSION` erhöht?
  → **Pflicht** bei jedem Save-Schema-Änderung.

### 2.6 Logging

- [ ] Hat jede neue Klasse eine `const LOG_CAT := "ClassName"` Konstante?
  → **Pflicht.**

- [ ] Loggt jede `configure()` und `on_ready()` Implementierung Start und Ende via `Logger.log_begin` / `Logger.log_end`?
  → **Pflicht** für ServiceNodes.

- [ ] Sind alle fehlschlagenden `null`-Checks geloggt mit Kontext (welche Variable, welcher Aufrufer)?
  → **Pflicht.**

### 2.7 Dokumentation

- [ ] Wurde `docs/services.md` aktualisiert wenn ein neuer Service hinzugekommen ist?
  → **Pflicht.**

- [ ] Wurde `docs/services.md` (EventBus-Sektion) aktualisiert wenn ein neues Signal hinzugekommen ist?
  → **Pflicht.**

- [ ] Wurde eine neue ADR (`docs/adr/NNN-titel.md`) angelegt wenn eine nicht-triviale Architektur-Entscheidung getroffen wurde?
  → **Pflicht** bei: neuer Basisklasse, neuem Pattern, Abweichung von bestehenden Konventionen, Technologie-Entscheidungen.

---

## 3. Klassen- und Datei-Regeln

### 3.1 Eine Verantwortung, eine Datei

Jede Klasse muss in einem Satz beantwortet werden können: **"Was macht diese Klasse?"**

Wenn die Antwort "X und Y" lautet → Datei aufteilen.

### 3.2 Größenlimits

| Zeilen | Status |
|--------|--------|
| ≤ 150 | ✅ OK |
| 150–200 | ⚠️ Prüfen ob Verantwortungen gemischt sind |
| > 200 | ❌ Fast immer aufteilen |

**Ausnahmen** (müssen explizit in einem Kommentar am Dateikopf begründet werden):
- `Logger.gd` — Autoload, Ausnahme dokumentiert
- `SimpleTerminal.gd` — Debug-only, nicht im Production-Build

### 3.3 Suffix-Konvention

Jede neue Klasse bekommt das richtige Suffix. Entscheidungsbaum in `docs/architecture.md` Abschnitt 1. Kurzzusammenfassung:

| Ich brauche… | Suffix | Basisklasse |
|---|---|---|
| Einen langlebigen Service | `Service` / `System` | `ServiceNode` |
| Einen lokalen Bereichs-Manager | `Manager` | `Node` |
| Etwas das nur koordiniert | `Orchestrator` | `Node` |
| Etwas das Objekte baut | `Builder` / `Factory` | `RefCounted` |
| Etwas das Events verarbeitet (stateless) | `Handler` | `RefCounted` |
| UI-Logik (Verknüpfung) | `Controller` | `Node` |
| UI-Logik (nur Render) | `Visuals` | `Node` |
| Eine Entity-Fähigkeit | `Component` | `Node3D` / `Node` |
| Statische Hilfsfunktionen | `Helper` / `Utils` | `RefCounted` |

### 3.4 Ordnerstruktur

Neue Dateien gehören in den semantisch richtigen Ordner:

```
scripts/
├── core/           → Boot-Infrastruktur (Orchestrator, Registry, Factory)
│   ├── entity/     → EntityOrchestrator, EntityPool, EntityRegistry
│   └── helpers/    → MathHelper, StateValidator
├── events/         → EventBus + alle *Events.gd
├── interfaces/
│   └── core/       → ISaveProvider, IEntityContext, NetworkContract
├── player/         → Player.gd + alle Player-spezifischen Scripts
├── quest/          → QuestDefinition, QuestProgressRecord, QuestReward
├── resources/      → ItemDefinition, SkillDefinition, PlayerData
├── services/       → InventorySystem, QuestService, SkillSystem, SaveSystem …
├── ui/
│   ├── components/ → BaseUIComponent und Unterklassen
│   ├── controllers/→ *Controller.gd — verbinden UI ↔ EventBus
│   └── visuals/    → *Visuals.gd — nur Render-Logik
└── world/
    ├── animals/    → AnimalBase, Deer, Rabbit, Boar
    ├── chunks/     → ChunkManager, ChunkEntitySpawner, ChunkWaterPlacer
    ├── combat/     → EnemyNPC, EnemyAI, HealthComponent, EnemySpawner
    ├── npc/        → QuestNPC, NPCVisualBuilder
    ├── objects/    → OakTree, IronOre
    ├── pets/       → PetComponent, AnimalCatcher, PetRestorer
    ├── terrain/    → TerrainGenerator, TerrainMeshBuilder, TerrainColorizer
    └── water/      → WaterBody, WaterBodyPlacer
```

**Faustregel:** Services die Entities *verwalten* (`WorldService`) → `world/`. Services die reine Logik sind (`InventorySystem`) → `services/`.

---

## 4. Commit-Konventionen

Format: `type(scope): kurze Beschreibung`

| Type | Bedeutung |
|------|-----------|
| `feat` | Neues Feature |
| `fix` | Bug-Fix |
| `refactor` | Code-Umbau ohne Verhaltensänderung |
| `arch` | Architektur-Änderung (neue Schicht, neues Pattern) |
| `docs` | Nur Dokumentation |
| `test` | Tests hinzugefügt oder geändert |
| `perf` | Performance-Optimierung |
| `chore` | Build, Config, Abhängigkeiten |

**Scope** = betroffenes Subsystem: `inventory`, `quest`, `world`, `ui`, `save`, `boot`, `entity`

Beispiele:
```
feat(inventory): slot-based weight system with request/confirm pattern
fix(respawn): heap sort instead of O(n) scan per tick
arch(network): NetworkBridge RPC hub replaces INetworkAdapter (ADR-010 Phase 2)
docs(adr): ADR-003 service locator vs full DI
refactor(skill): extract SkillLevelCalculator as pure static helper
```

**Session-Referenzen gehören nicht in Commit-Messages und nicht in Produktionscode.**  
`## Fehlte im Fallback (Bug-Fix Session 5)` → stattdessen: `## Fallback für fehlende SkillDefinition`

---

## 5. Neue Features — Ablauf

```
1. ADR anlegen (wenn Architektur-Entscheidung)
   → docs/adr/NNN-feature-name.md

2. Interface zuerst
   → <domain>/ (Contract-Realization erst bei zweitem Nutzer, siehe docs/adr/016)
   → Mindestens public API als Kommentar-Kontrakt in der Zieldatei

3. ServiceDefinition in BootstrapConfig.tres eintragen
   → deps korrekt setzen (Kahn's Resolver validiert Reihenfolge)

4. configure() implementieren
   → Deps injecten, ISaveProvider registrieren, Daten laden

5. on_ready() implementieren
   → EventBus-Connections, Ticker registrieren

6. Services.gd aktualisieren
   → Neue Zeile im richtigen Abschnitt

7. docs/services.md aktualisieren
   → Service-Tabelle + EventBus-Signale

8. on_cleanup() implementieren
   → Alle in on_ready() angelegten Connections trennen

9. Checkliste in Abschnitt 2 durchgehen
```

---

## 6. Multiplayer-Readiness — Pflichtfragen für neue State-Mutation

Jede neue Methode die State mutiert muss diese Fragen beantworten (Antworten als Kommentar in der Methode):

```gdscript
## AUTHORITY: server | client
## PATTERN: request_/confirmed_ | direct (nur client-autoritativ)
## CHEAT-RISK: hoch | mittel | keines
func request_do_something(...) -> void:
```

Wenn `AUTHORITY: server` und `PATTERN: direct` → Review-Blocker.

---

## 7. Verbotene Muster (Zero Tolerance)

Diese Muster werden immer abgelehnt, ohne Ausnahme:

```gdscript
# ❌ 1. Entity greift direkt auf Services zu
class_name OakTree extends Node3D
func on_spawn(cfg, ctx):
    Services.inventory.request_add_item("wood")  # VERBOTEN

# ❌ 2. Component kennt ihren Parent
func _handle_completion():
    get_parent()._on_interacted(data.id)  # VERBOTEN — Signal stattdessen

# ❌ 3. Services.xyz in configure()
func configure(deps):
    _inv = Services.inventory  # VERBOTEN — Services ist noch leer

# ❌ 4. _process() in ServiceNode
func _process(delta):
    _update_world(delta)  # VERBOTEN — on_tick() via ServiceTicker

# ❌ 5. Hardcoded Ressource-Pfade im Logic-Code
var item = load("res://data/items/CopperOre.tres")  # VERBOTEN — via DataService

# ❌ 6. Session-Referenzen in Produktionscode
## Bug-Fix Session 7  # VERBOTEN — gehört in git commit message

# ❌ 7. Direkte State-Mutation in server-autoritativen Systemen
func add_item_direct(id: String):
    _items[id] += 1  # VERBOTEN ohne request_/confirmed_-Wrapper

# ❌ 8. UI-Controller greift direkt auf EventBus zu (ADR-012)
func setup(visuals, ctx: IUIContext) -> void:
    _ctx = ctx
    EventBus.player.xp_gained.connect(_on_xp_gained)  # VERBOTEN — ctx wird ignoriert
    # Richtig: _ctx.bus().player().xp_gained.connect(_on_xp_gained)
```

---

## 8. Wenn du eine bestehende Konvention brechen musst

Das ist manchmal legitim. Der Prozess:

1. Lege eine neue ADR an (`docs/adr/NNN-abweichung-von-X.md`)
2. Beschreibe: Was ist das Problem? Warum reicht die bestehende Konvention nicht?
3. Beschreibe: Was sind die Konsequenzen der Abweichung?
4. Beschreibe: Wie wird die Abweichung eingegrenzt (kein globales Pattern)?
5. Review durch eine zweite Person (oder asynchron via Kommentar im ADR)

**Ohne ADR: kein Merge.**

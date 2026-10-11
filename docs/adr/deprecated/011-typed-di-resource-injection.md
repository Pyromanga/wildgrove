> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-011 — Typisiertes DI-Interface: `ServiceDeps` + Injectable Resources

**Status:** Accepted  
**Datum:** 2026-06  
**Löst ab:** ADR-001 (Teilmenge: Service-Interface für `configure()`)  
**Beibehaltenes:** `configure()`/`on_ready()`-Lifecycle, BootPipeline-Modell, App-/Character-/World-Scope-Architektur (ADR-009)

---

## Kontext

16 Services, 12 Test-Dateien, 0 Laufzeit-Warnungen bei inkorrekter Injektion.

```gdscript
# ADR-001 (alt) — kein Schutz vor Tippfehlern, falschen Typen, fehlenden Deps:
func configure(deps: Dictionary) -> void:
    _save_system = deps.get("savesystem") as SaveSystem
    # "savesystem" falsch geschrieben → null. Falscher Typ → null. Dep fehlt → null.
    # Kein Fehler. Keine Warnung. Stilles null.
```

Neun Findings aus AUDIT-04 (H-01 bis H-09) sind Symptome dieses einen Defekts:
Das `deps: Dictionary`-Interface hat keine Typsicherheit, keine Pflicht-Dep-Erzwingung,
keinen lesbaren Fehler bei falscher Injektion. Für ein System auf 20-Jahres-Horizont
nicht tragfähig.

---

## Entscheidung

### Säule 1 — `ServiceDeps` ersetzt `deps: Dictionary`

```gdscript
class_name ServiceDeps extends RefCounted

static func from_dict(d: Dictionary) -> ServiceDeps
func require(key: String) -> Object       # push_error() + assert() wenn fehlt
func get_optional(key: String) -> Object  # stilles null wenn fehlt
func has(key: String) -> bool
func keys() -> Array[String]              # sortiert, für deterministisches Logging
```

**Interface-Änderung:**
```gdscript
# Vorher (ADR-001):
func configure(_deps: Dictionary) -> void: pass

# Nachher (ADR-011):
func configure(_deps: ServiceDeps) -> void: pass
```

`ServiceInitializer.run()` wrапpt das interne Dictionary:
```gdscript
svc.configure(ServiceDeps.from_dict(dependencies))
```

#### `require()` vs `get_optional()` — Entscheidungsbaum

```
Kann der Service seinen Job ohne diese Dep erledigen?
  (auch eingeschränkt, mit Degradation)
    JA  → get_optional()
           Beispiele: StatModifierService (Boni optional),
                      Ticker (Service läuft ohne Ticks),
                      NetworkBridge (offline-fähig)
    NEIN → require()
           Beispiele: SaveSystem (ohne Persistenz kein Charakter-State),
                      DataService (ohne Daten keine Items/Skills),
                      GameConfig (ohne Config keine State-Transitions)
```

### Säule 2 — `ResourceDefinition`: Injectable `.tres`-Dateien

```gdscript
class_name ResourceDefinition extends Resource

@export var resource_name: String = ""
@export_file("*.tres", "*.res") var path: String = ""
```

Deklariert in `BootstrapConfig.gd`:
```gdscript
@export var global_resources: Array[ResourceDefinition] = []
@export var session_resources: Array[ResourceDefinition] = []
```

`BootPipeline.boot_app()` lädt Phase 1.5 alle deklarierten Resources und
registriert sie via `ServiceRegistry.register_resource()` (ohne Interface-Assertions —
Resources implementieren `configure()`/`on_ready()` nicht).

**Warum diese Abstraktion statt One-Off-Fix in GameManager?**
Ein direkter Fix würde `GameConfig.load_default()` in `BootPipeline` hard-coden —
das dritte Mal, dass eine Pipeline-Klasse einen spezifischen Ressourcentyp kennt.
`ResourceDefinition` macht das zu einem deklarierten Mechanismus: jede `.tres`-Datei
die als Dep gebraucht wird, bekommt einen Eintrag in `BootstrapConfig.tres`.
Kein Pipeline-Code ändert sich wenn ein neuer injectable Resource hinzukommt.

### Säule 3 — Konkrete Fixes (H-02 bis H-06, H-09)

| Finding | Fix |
|---|---|
| H-02 | `GameManager.configure()`: `load()` entfernt, `deps.require(GAME_CONFIG)` |
| H-03 | `CombatSystem`, `WorldService`, `RespawnService`: `_ticker` via deps, kein `Services.ticker` |
| H-04 | `CombatSystem`: `_equipment` via deps, kein `Services.equipment` in Berechnungsmethoden |
| H-06 | `ServiceRegistry.register()`: Interface-Assertions in Phase 3 |
| H-09 | `ServiceInstaller`: Magic Strings → `ServiceKeys` |

---

## Interface-Assertions (H-06)

`ServiceRegistry.register()` prüft jetzt in Phase 3 (Registrierung):

```gdscript
assert(service.has_method("configure"), ...)
assert(service.has_method("on_ready"), ...)
assert(service.has_method("on_cleanup"), ...)
```

**Warum Phase 3 statt Phase 4?**
Ein Tippfehler in einem Methodennamen ist damit beim Boot sichtbar, nicht erst
beim ersten `configure()`-Aufruf. Schnelleres Feedback = günstigerer Fix.

`register_resource()` hat diese Assertions nicht — Resources sind kein Service.

---

## Konsequenzen

**Positiv:**
- Tippfehler in Dep-Keys → `push_error()` + `assert()` sofort sichtbar
- Fehlende Pflicht-Dep → expliziter Fehler mit Liste der vorhandenen Keys
- Jede neue injectable `.tres` → ein Eintrag in `BootstrapConfig.tres`, kein Pipeline-Code
- Interface-Verletzungen → sichtbar in Phase 3 (Boot), nicht erst zur Laufzeit
- Tests: `ServiceDeps.from_dict({...})` ist minimal mehr Tipparbeit, aber klar deklarierend

**Neutral:**
- `configure()`-Signaturen in 16 Services + 2 Basisklassen geändert → mechanical, einmalig
- Test-Calls auf `.configure()` in 12 Test-Dateien geändert → `from_dict()` hinzugefügt

**Nicht geändert (explizit außerhalb dieses ADR):**
- H-07 (EventBus als Injectable): ~50 Dateien, kein akuter Bug. Separater ADR.
  → UI-Hälfte (10 Controller in `scripts/ui/controllers/`, später ergänzt um `HUDManager`/
  `HUDBuilder`) gelöst in [ADR-012](012-ui-eventbus-injection.md) (AUDIT-03 I-02). Rest
  (Scene-Tree-Nodes wie `World.gd`, `MainMenuController.gd`) bleibt zurückgestellt.
- H-08 (Logger als Injectable): Null-Logger-Pattern korrekt. P2.
- `DataService` + `PlayerData.tres`: gleicher Mechanismus wie GameConfig, separates Ticket.

---

## Alternativen erwogen

**Typed Dictionary (`Dict[String, Object]`)** — GDScript unterstützt das nicht nativ.

**Statische `configure()`-Overloads mit echten Typ-Parametern** — würde das DI-Framework
erfordern jeden Service-Typ zu kennen. Nicht skalierbar für 16+ Services.

**Weiter mit `Dictionary`** — Status quo. Jede neue Dep ist eine neue potenzielle
Fehlerquelle ohne Laufzeit-Feedback. Für 20 Jahre nicht vertretbar.

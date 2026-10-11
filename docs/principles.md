# WildGrove — Engineering Principles (20-Year Horizon)

> Vorgänger: `scripts/debug/principles.md` + `scripts/debug/coding.md`  
> Diese Datei ersetzt beide. Die alten Dateien können nach Migration gelöscht werden.

---

## 1. Statische Typsicherheit (The "No-Guessing" Rule)

```gdscript
# ❌ FALSCH — dynamisch, keine Autovervollständigung, Fehler erst zur Laufzeit
var svc = registry.get_service("inventory")
svc.add_item("wood")

# ✅ RICHTIG — typisiert, Tippfehler fallen zur Compile-Zeit auf
var inv: InventorySystem = registry.get_service("inventory") as InventorySystem
inv.request_add_item("wood")
```

**Pflicht:**
- Immer `as ClassName` beim Rückgabewert von `get_service()`, `deps.get()`, `get_node()`
- Immer `Array[ClassName]` statt `Array` wenn der Inhalt homogen ist
- Immer `: Type` oder `:=` (Type Inference) bei Variablendeklaration — nie nackte `var x = value`

---

## 2. Exzessives Logging (The "Flight Recorder" Rule)

Da kein Live-Debugger verfügbar ist, ist der Logger das primäre Diagnose-Werkzeug. **Der Test:** Kannst du aus den Logs allein den genauen Bug lokalisieren, ohne die Source-Datei zu öffnen? Wenn nein → mehr Kontext in den Log.

```gdscript
# ❌ Nutzlos
Logger.log_info("Speed changed", LOG_CAT)

# ✅ Audit-fähig
Logger.log_info(
    "Speed geändert: %.1f → %.1f (Modifier: '%s', Actor: 'powerup')"
    % [old_speed, new_speed, modifier_id],
    LOG_CAT
)
```

**Pflicht-Logs:**
- Jeder Service-Boot: `Logger.log_begin()` in `configure()`, `Logger.log_end()` am Ende
- Jede State-Änderung (Game State, Player State, Quest State)
- Jeder Save/Load-Vorgang mit Ergebnis
- Jeder Entity-Spawn/Despawn mit UUID und Position
- Jeder fehlschlagende `is_instance_valid()`- oder `null`-Check

**GDScript-Falle — Multiline Logger Calls:**
```gdscript
# ❌ PARSE ERROR — Extra-Klammer-Gruppe + Multiline in manchen GDScript-Versionen
Logger.log_warn(
    ("HUD im Tree: %s" % parent_name),
    LOG_CAT
)

# ✅ Korrekt — Variable verwenden
var msg := "HUD im Tree: %s" % parent_name
Logger.log_warn(msg, LOG_CAT)
```

---

## 3. Lifecycle-Phasen (The "Timing Is Everything" Rule)

```
┌──────────────────┬──────────────────────────────────────────────────────────┐
│ Phase            │ Was ist erlaubt?                                         │
├──────────────────┼──────────────────────────────────────────────────────────┤
│ configure(deps)  │ deps.get("name") aufrufen, Variablen setzen,             │
│                  │ ISaveProvider registrieren, Daten laden                  │
│                  │ ❌ Services.xyz NICHT aufrufen — Container ist noch leer! │
├──────────────────┼──────────────────────────────────────────────────────────┤
│ on_ready()       │ Services.xyz aufrufen (mit is_instance_valid()-Guard),   │
│                  │ EventBus.*.connect(), Ticker registrieren                 │
├──────────────────┼──────────────────────────────────────────────────────────┤
│ on_tick(delta)   │ Update-Logik, Welt-Simulationen, Timer-Checks            │
│                  │ ❌ Kein _process() in ServiceNodes — nur on_tick()!       │
├──────────────────┼──────────────────────────────────────────────────────────┤
│ on_cleanup()     │ Signale trennen, Ressourcen freigeben                    │
│                  │ Wird in umgekehrter Boot-Reihenfolge aufgerufen          │
└──────────────────┴──────────────────────────────────────────────────────────┘
```

**GDScript-Falle — Wer disconnectet den EventBus?**

`Node`-basierte Objekte trennen ihre Godot-eigenen Signal-Connections automatisch wenn sie freigegeben werden. `BaseEvents`-Objekte (also alle EventBus-Namespaces wie `EventBus.inventory`, `EventBus.quest`) sind `RefCounted`-basiert — sie trennen Connections **nicht** automatisch.

Wenn ein Service stirbt ohne sich vom EventBus zu disconnecten, ruft Godot beim nächsten emittierten Signal eine Methode auf einem null-Objekt auf. Das Ergebnis ist entweder ein stiller Fehler oder ein Crash — beide schwer zu debuggen weil das Event weit vom Todeszeitpunkt des Services entfernt passieren kann.

**Ownership-Regel:** Wer sich connected, muss sich auch disconnecten.

```gdscript
# ✅ Korrekt — Service verbindet und trennt symmetrisch
func on_ready() -> void:
    EventBus.inventory.item_added.connect(_on_item_added)
    EventBus.quest.quest_completed.connect(_on_quest_completed)

func on_cleanup() -> void:
    if EventBus.inventory.item_added.is_connected(_on_item_added):
        EventBus.inventory.item_added.disconnect(_on_item_added)
    if EventBus.quest.quest_completed.is_connected(_on_quest_completed):
        EventBus.quest.quest_completed.disconnect(_on_quest_completed)
```

**Merkhilfe:** `on_ready()` und `on_cleanup()` sind ein Paar. Jede `connect()`-Zeile in `on_ready()` braucht eine spiegelbildliche `disconnect()`-Zeile in `on_cleanup()`. Wenn ein Service kein `on_cleanup()` hat und sich in `on_ready()` connected: das ist ein Bug.

**GDScript-Falle — ServiceTicker statt _process():**
```gdscript
# ❌ ServiceNode umgeht den Ticker-Vertrag
func _process(delta: float) -> void:
    _update_time(delta)

# ✅ Konform mit ServiceTicker
func on_ready() -> void:
    Services.ticker.register_service(self)

func on_tick(delta: float) -> void:
    _update_time(delta)
```

---

## 4. Signal-First Design (The "Hollywood Principle")

*"Don't call us, we'll call you."*

```gdscript
# ❌ Tight Coupling — Service kennt UI direkt
func request_add_item(id: String) -> bool:
    _items[id] += 1
    HUDManager.refresh_inventory()  # VERBOTEN — Service kennt UI nicht!

# ✅ Loose Coupling — UI hört auf Service-Signal
func on_item_add_confirmed(id: String, qty: int) -> void:
    _items[id] += qty
    inventory_changed.emit(get_all_items())  # UI reagiert selbst
```

**Kommunikationsregel:**
- **Service → Service:** Direkte Anfragen (synchron) via `Services.xyz` für Daten-Abfragen
- **Service → Welt:** Notifications (asynchron) via EventBus-Emission
- **Entity → Service:** Via `EntityContext` oder EventBus — NICHT via `Services.xyz`
- **Component → Parent:** Via Signal, NIEMALS via `get_parent()._method()`

---

## 5. Defensive Programming (Trust No One)

```gdscript
# ❌ Explodiert wenn inventory null ist
Services.inventory.request_add_item("wood")

# ✅ Explizite Null-Prüfung mit Kontext im Fehlerlog
if not is_instance_valid(Services.inventory):
    Logger.log_error(
        "InventorySystem nicht verfügbar in '%s' — request_add_item abgebrochen." % LOG_CAT,
        LOG_CAT
    )
    return
Services.inventory.request_add_item("wood")
```

**Pflicht-Checks:**
- Jedes `Services.xyz` vor der Nutzung in Entity-Code
- Jedes `deps.get()` mit `as ClassName` und nachfolgendem Null-Check
- Alle `load()` / `ResourceLoader.load()` Rückgaben
- Timer-Callbacks nach Nodes die zwischenzeitlich freed werden könnten:
  ```gdscript
  get_tree().create_timer(2.0).timeout.connect(
      func() -> void:
          if is_instance_valid(self):  # ← Pflicht
              _respawn()
  )
  ```

---

## 6. Data-Driven Design (Resource-First)

```
Logik   → .gd files      (Verhalten, Algorithmen)
Config  → .tres files     (Werte, Pfade, Abhängigkeiten)
State   → SaveSystem      (Laufzeitwerte, Spielerstand)
```

```gdscript
# ❌ Hardcoded
var player_speed := 6.0

# ✅ Data-Driven
var player_speed := Services.data.get_player_stat("speed", 6.0)
```

Kein Ressource-Pfad darf hardcoded im Logic-Code stehen. Alle Definitionen kommen über `DataService`.

---

## 7. Networking-Readiness — Multiplayer-Check bei jeder State-Mutation

Bei jeder neuen Methode die State in einem server-autoritativen System mutiert, frage:

1. **Wer darf das?** Client-Vorhersage oder Server-Autorität?
2. **Kann ein manipulierter Client diese Mutation direkt auslösen?**
3. **Ist das ein Request (Client→Server) oder eine Bestätigung (Server→alle)?**

```gdscript
## AUTHORITY: server
## PATTERN: request_/confirmed_
## CHEAT-RISK: hoch — direkter Inventar-Zugriff
func request_add_item(item_id: String, quantity: int) -> bool:
    # Heute: lokal synchron. Morgen: sendet an Server.
    on_item_add_confirmed(item_id, quantity)
    return true

## Einzige Methode die _items direkt mutiert.
func on_item_add_confirmed(item_id: String, quantity: int) -> void:
    _items[item_id] = _items.get(item_id, 0) + quantity
```

---

## 8. Naming Conventions

| Typ | Konvention | Beispiel |
|-----|-----------|---------|
| Service-Key (Registry) | `snake_case` | `"skill_system"`, `"save_system"` |
| Klassen-Name | `PascalCase` | `SkillSystem`, `SaveSystem` |
| LOG_CAT | `"PascalCase"` | `"SkillSystem"`, `"World"` |
| Event-Emitter | `emit_*` | `emit_xp_gained()`, `emit_quest_started()` |
| Lifecycle | `on_*` | `on_ready()`, `on_tick()`, `on_cleanup()`, `on_spawn()` |
| Private Vars | `_snake_case` | `_save_system`, `_current_state` |
| Konstanten | `UPPER_SNAKE` | `LOG_CAT`, `SAVE_KEY`, `CURRENT_VERSION` |
| Request-Pattern | `request_*` | `request_add_item()`, `request_start_quest()` |
| Confirm-Pattern | `on_*_confirmed` | `on_item_add_confirmed()` |

**Verboten in Produktionscode:**
- Session-Referenzen: `## Bug-Fix Session 7` → gehört in git commit message
- Abkürzungen die nicht selbsterklärend sind: `p_spd_m` → `player_speed_modifier`
- Kommentare die veralten: lieber selbsterklärender Code als lügender Kommentar

---

## 9. Separation of Concerns (SoC)

Eine Klasse hat genau eine Antwort auf: **"Was macht diese Klasse?"**

Wenn die Antwort "X und Y" lautet → aufteilen.

Dateigröße als Indikator, nicht als Grenze:

Viele Zeilen sind ein Warnsignal, kein automatischer Fehler. Wenn eine Datei groß wird,
ist die Frage nicht "überschreitet sie 200 Zeilen?" sondern:

**1. Ist die Architektur falsch gewählt?**
Mehrere Verantwortlichkeiten in einer Klasse, fehlende Abstraktion, Service der eigentlich
zwei Services sein sollte — das sind echte Probleme. Aufteilen ist die richtige Antwort.

**2. Ist es ein Workaround statt einer echten Lösung?**
Viel defensiver Code, viele Sonderfälle, Kommentare die Inkonsistenzen erklären — das sind
Symptome einer falschen Grundlage. Aufteilen verteilt das Problem nur, löst es nicht.

**3. Ist es legitime Komplexität?**
`QuestService` koordiniert Multi-Tenant-State, Save/Load, EventBus-Subscriptions,
Objective-Resolution und Reward-Dispatch — das sind sieben klar benannte Methoden,
keine versteckte Komplexität. `CombatSystem` deckt Damage-Kalkulation, Status-Effekte,
deterministischen RNG und Authority-Guards ab — alles in einer Domäne.
Hier wäre Aufteilen künstlich.

Daumenregel: Eine Datei über ~200 Zeilen bekommt eine kurze Investigation:
*Gibt es hier eine zweite Verantwortung, einen Workaround, oder eine Abstraktion die fehlt?*
Wenn nein → Größe ist kein Problem. Wenn ja → aufteilen.

---

## 10. Das Legacy-Mindset

Schreibe Code immer so, als müsste ihn eine Person warten, die:
1. Deine Architektur nicht kennt
2. Keinen Godot-Editor hat — nur Logs als Diagnose-Werkzeug
3. In 10 Jahren daran arbeitet wenn du nicht mehr erreichbar bist

**Was das konkret bedeutet:**
- Jeder Fehlerfall ist geloggt mit dem vollständigen Kontext (was war der State, was wurde erwartet, was ist passiert)
- Jede Architektur-Entscheidung hat einen ADR (`docs/adr/`)
- Jedes TODO im Code hat ein GitHub Issue oder einen ADR-Verweis — kein `# TODO: fix this someday`
- Stubs und leere Klassen mit Kommentar sind besser als gemischte Klassen: `## STUB: StatModifierService — siehe ADR-TODO`

## 11. Entity-Identität ist nicht optional (ADR-023)

Jede Node mit Netzwerk-Bezug (Interactable, NPC, Tier, Loot-Quelle — alles was
ein Client per Interaktion referenzieren kann) entsteht **ausschließlich** über
`EntityOrchestrator.spawn_entity()`, nie durch statische Platzierung in einer
`.tscn`. Grund: nur so bekommt sie eine `entity_uuid` — den einzigen
kanonischen Bezeichner, über den Netzwerk-Requests ein konkretes Objekt
referenzieren (ADR-023). Eine neue Entity-Art ohne Orchestrator-Spawn ist kein
Sonderfall, sondern eine Lücke, die denselben Fund reproduziert, der zu
ADR-020/023 geführt hat — vor dem Anlegen einer neuen Entity-Art diesen
Abschnitt gegen `WorldEntityRegistry.register_all()` prüfen.

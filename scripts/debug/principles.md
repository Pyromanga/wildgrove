# 🧠 WildGrove — Engineering Principles (20-Year Horizon)
*Für Blind-Coding ohne Editor — diese Regeln erzwingen Stabilität.*

---

## 1. Statische Typsicherheit (The "No-Guessing" Rule)

```gdscript
# ❌ FALSCH — dynamisch, keine Autovervollständigung, kein Fehler-Feedback
var svc = registry.get_service("inventory")
svc.add_item("wood")

# ✅ RICHTIG — typisiert, Tippfehler fallen zur Compile-Zeit auf
var inv: InventorySystem = registry.get_service("inventory") as InventorySystem
inv.add_item("wood")
```

**Regel:** Immer `as ClassName` beim Rückgabewert von `get_service()`, `deps.get()`, `get_node()`.

---

## 2. Exzessives Logging (The "Flight Recorder" Rule)

Da kein Live-Debugger verfügbar ist, ist der Logger das primäre Diagnose-Werkzeug.

```gdscript
# ❌ Nutzlos
Logger.log_info("Speed changed")

# ✅ Audit-fähig
Logger.log_trace(
    "Speed modified",
    {"from": old_speed, "to": new_speed, "reason": modifier_id, "actor": "powerup"},
    LOG_CAT
)
```

**Pflicht-Logs:**
- Jeder Service-Boot (configure + on_ready)
- Jede State-Änderung (Game State + Player State)
- Jeder Save/Load-Vorgang
- Jeder Entity-Spawn/Despawn
- Alle `null`-Checks die fehlschlagen

**Verboten:**
- `Logger.log_debug()` für normale Operations ohne Datensnapshot — nutze `log_trace()`

---

## 3. Lifecycle-Phasen (The "Timing Is Everything" Rule)

```
┌──────────────────┬──────────────────────────────────────────────────┐
│ Phase            │ Was ist erlaubt?                                 │
├──────────────────┼──────────────────────────────────────────────────┤
│ configure(deps)  │ deps.get("name") aufrufen, Variablen setzen      │
│                  │ ❌ Services.xyz NICHT aufrufen — noch leer!       │
├──────────────────┼──────────────────────────────────────────────────┤
│ on_ready()       │ Services.xyz aufrufen, EventBus.*.connect()      │
│                  │ Ticker registrieren: Services.ticker.register()  │
├──────────────────┼──────────────────────────────────────────────────┤
│ on_tick(delta)   │ Update-Logik, Welt-Simulationen                  │
│                  │ ❌ Kein _process() in ServiceNodes!               │
├──────────────────┼──────────────────────────────────────────────────┤
│ on_cleanup()     │ Signale trennen, Ressourcen freigeben            │
│                  │ Wird in umgekehrter Boot-Reihenfolge aufgerufen  │
└──────────────────┴──────────────────────────────────────────────────┘
```

---

## 4. Signal-First Design (The "Hollywood Principle")

*"Don't call us, we'll call you."*

```gdscript
# ❌ Tight Coupling — InventorySystem kennt HUDManager
func add_item(id: String) -> void:
    _items[id] += 1
    HUDManager.refresh_inventory()  # Verboten!

# ✅ Loose Coupling — HUDManager hört auf InventorySystem
func add_item(id: String) -> void:
    _items[id] += 1
    inventory_changed.emit(get_all_items())  # Gut
# HUDManager.on_ready(): Services.inventory.inventory_changed.connect(refresh)
```

**Services → Services:** Für **Datenanfragen** (synchron, typsicher via `Services.xyz`)
**Services → Welt:** Für **Benachrichtigungen** (asynchron, via `EventBus`)

---

## 5. Defensive Programming (Trust No One)

```gdscript
# ❌ Explodiert wenn inventory null ist
Services.inventory.add_item("wood")

# ✅ Explizite Null-Prüfung mit sinnvollem Fehlerlog
if not is_instance_valid(Services.inventory):
    Logger.log_error("InventorySystem nicht verfügbar — add_item abgebrochen.", LOG_CAT)
    return
Services.inventory.add_item("wood")
```

**Pflicht-Checks:**
- Jedes `Services.xyz` vor der Nutzung in Entity-Code (nicht in Services selbst — dort via DI gesichert)
- Jedes `deps.get()` mit `as ClassName` und null-Check
- Alle `load()` / `ResourceLoader.load()` Rückgaben

---

## 6. Data-Driven Design (Resource-First)

```
Logic  → .gd files      (Verhalten, Algorithmen)
Config → .tres files     (Werte, Pfade, Abhängigkeiten)
State  → SaveSystem      (Laufzeitwerte, Spielerstand)
```

```gdscript
# ❌ Hardcoded in Logic
var player_speed := 6.0

# ✅ Aus Resource geladen
var player_speed := Services.data.get_player_stat("speed", 6.0)
```

---

## 7. Naming Conventions

| Typ | Konvention | Beispiel |
|-----|-----------|---------|
| Service-Key | `snake_case` | `"skill_system"`, `"save_system"` |
| Service-Klasse | `PascalCase` | `SkillSystem`, `SaveSystem` |
| LOG_CAT | `"PascalCase"` | `"SkillSystem"`, `"World"` |
| Event-Emitter | `emit_*` | `emit_xp()`, `emit_quest_started()` |
| Lifecycle | `on_*` | `on_ready()`, `on_tick()`, `on_cleanup()` |
| Private Vars | `_snake_case` | `_save_system`, `_current_state` |
| Constants | `UPPER_SNAKE` | `LOG_CAT`, `SAVE_KEY`, `MAX_BUFFER` |

---

## 8. GDScript-Fallen (Project-Spezifisch)

### Multiline Logger Calls
```gdscript
# ❌ PARSE ERROR — Extra-Klammer-Gruppe + Multiline
Logger.log_warn(
    (
        "HUD im Tree: %s" % parent_name
    ),
    LOG_CAT
)

# ✅ Korrekt — Variable verwenden
var msg := "HUD im Tree: %s" % parent_name
Logger.log_warn(msg, LOG_CAT)
```

### ServiceTicker vs. _process()
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

### Lambda-Kommentare
```gdscript
# ❌ Kommentar direkt vor ( kann Parser verwirren
_commands["foo"] = {
    "fn": func(_args: Array) -> void:
        # Kommentar hier ist ok
        do_stuff()
    # Kommentar ZWISCHEN commands ist ok
}
```

---

## 9. Das Legacy-Mindset

Schreibe Code immer so, als müsste ihn eine Person warten, die:
1. Deine Architektur nicht kennt
2. Keinen Godot-Editor hat
3. Nur den Log-Output als Diagnosewerkzeug hat

**Test:** Kannst du aus den Logs allein den genauen Bug lokalisieren, ohne die Sourcedatei zu öffnen?
Wenn nein → mehr `log_trace()`.

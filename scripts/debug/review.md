# 🔍 WildGrove — Code Review & Session Log
*Lebendiges Dokument — nach jeder Session aktualisieren*

---

## Session 1 — Initial Review + Bug Fixes (Juni 2026)

### Gefundene und behobene Bugs

#### 🔴 KRITISCH: HUDManager.gd — Parse Error (Zeile 63)
**Problem:** Geschachtelter Klammer-Ausdruck in `Logger.log_warn()` verursachte:
```
Unexpected token Token('_INDENT', '\t') at line 63, column 23
```
**Ursache:** GDScript-Parser kann `Logger.log_warn((multiline_string % expr), LOG_CAT)` mit
extra Klammer-Gruppe nicht auflösen wenn über mehrere Zeilen umbrochen.

**Fix:** Variable für die Nachricht extrahiert, einzeiliger `log_warn()`-Call.

---

#### 🔴 KRITISCH: SimpleTerminal.gd — Datei-Korruption
**Problem:** Die Datei-Header wurden während einer früheren Formatter-Session in jeden
Lambda-Körper von `_register_default_commands()` eingefügt. GDScript konnte die Datei nicht parsen.

**Fix:** Vollständige Neuerstellung der Datei. Neue Commands hinzugefügt:
`status`, `service <n>`, `stats`, `errors`, `time`, `save`.

---

#### 🟡 ARCHITEKTUR: Main.gd — Falscher Autoload-Lookup
**Problem:** `Main.gd` suchte den `ServiceOrchestrator` als Kind-Node mit
`get_node_or_null("ServiceOrchestrator")`. Da er ein Autoload ist, lebt er bei
`/root/ServiceOrchestrator` — der Check lieferte immer `null` und loggte einen Fehler.

**Fix:** `Main.gd` überarbeitet — erklärender Kommentar, doppelte `is_connected()`-Guard,
Fallback wenn Services schon befüllt sind.

---

#### 🟡 ARCHITEKTUR: WorldService.gd — `_process()` statt `on_tick()`
**Problem:** `WorldService._process()` wurde direkt von Godot aufgerufen, umging damit
den `ServiceTicker`-Vertrag. Das macht den Ticker-Mechanismus inkonsistent.

**Fix:** `_process()` entfernt, `on_tick(delta)` implementiert, in `on_ready()` beim
`ServiceTicker` registriert.

---

#### 🟡 ARCHITEKTUR: WorldData.gd — `extends Node` ohne Tree-Einhängung
**Problem:** `WorldData` erbte von `Node`, wurde aber nie in den SceneTree eingehängt.
Node-Overhead ohne Nutzen.

**Fix:** `extends RefCounted` — keine Allocations, kein verstecktes Godot-Objekt.

---

#### 🟡 SERVICE-LÜCKE: ServiceOrchestrator bot keine Debug-API
**Problem:** `SimpleTerminal`s `services`-Command griff direkt auf `orch.registry` zu
(enge Kopplung an interne Implementierung).

**Fix:** `get_registered_names()` und `get_service_info(name)` als öffentliche API
zu `ServiceOrchestrator` hinzugefügt.

---

#### 🟢 DATEINAME: ServiceInitalizer.gd (Tippfehler)
**Problem:** Dateiname hatte Tippfehler (`Initalizer` statt `Initializer`).
`class_name ServiceInitializer` war korrekt — funktionierte auf case-insensitiven
Systemen (macOS/Windows), aber nicht auf Linux-Servern.

**Fix:** Korrekte Kopie als `ServiceInitializer.gd` erstellt.

---

### Neue Features

#### ✅ EntityOrchestrator (`scripts/core/EntityOrchestrator.gd`)
**Motivation:** ServiceOrchestrator sollte keine Entity-Lifecycle-Logik tragen.
Entities (NPCs, Ressourcen, Truhen) haben einen anderen Lebenszyklus als Services.

**Verantwortung:**
- Spawn/Despawn von World-Entities per `type_id`
- Object Pooling (max. `POOL_SIZE = 10` pro Typ)
- UUID-basiertes Entity-Tracking
- `on_world_unloaded()` für sauberes Cleanup

**Noch zu tun:** `EntityOrchestrator` in `WorldService.on_world_scene_ready()` integrieren
und `OakTree`/`IronOre` über ihn spawnen statt direkt über `WorldFactory`.

---

#### ✅ Logger — Enterprise-Erweiterungen
- **File-Logging:** `user://wildgrove.log` automatisch im Debug-Build aktiv
- **`log_begin()`/`log_end()`:** Elapsed-Zeit-Tracking für Operationen
- **`get_errors()`:** Alle ERROR-Logs aus dem Puffer abrufbar
- **`get_log_stats()`:** Counter pro Level
- **`peek_log_buffer()`:** Puffer lesen ohne Leeren
- MAX_BUFFER von 200 auf 500 erhöht

---

### Offene TODOs

| Priorität | Task | Datei |
|-----------|------|-------|
| 🔴 HIGH | `EntityOrchestrator` in `WorldService` integrieren | WorldService.gd |
| 🔴 HIGH | `BootstrapConfig.tres` Pfad für `ServiceInitializer.gd` prüfen (Tippfehler-Fix) | BootstrapConfig.tres |
| 🟡 MEDIUM | `QuestService._data_service` wird nie genutzt — Interface definieren | QuestService.gd |
| 🟡 MEDIUM | `GameSaveService` sollte `EventBus.system.save_started` connecten | GameSaveService.gd |
| 🟡 MEDIUM | `InteractionSensor.gd` noch nicht geprüft | InteractionSensor.gd |
| 🟢 LOW | `WorldFactory` nutzt immer noch Kommentar "Kernel.factory3d" | WorldFactory.gd |
| 🟢 LOW | `HUD.gd` ist leer — CanvasLayer-Setup fehlt | HUD.gd |
| 🟢 LOW | `SimpleTerminalUI.gd` nicht geprüft | SimpleTerminalUI.gd |

---

## Health-Check Protokoll

Vor jeder Session ausführen:
1. **`status`** im SimpleTerminal → alle Services grün?
2. **`errors`** im SimpleTerminal → keine unerwarteten Fehler?
3. **`services`** im SimpleTerminal → alle 15 Services registriert?
4. Log-Datei öffnen: `user://wildgrove.log`
5. Boot-Zeit im Log suchen: `╚══ BOOT FERTIG (X ms) ══╝` — unter 500ms?

---

## Bekannte GDScript-Fallen in diesem Projekt

1. **Multiline-Logger-Calls:** Niemals `Logger.log_xyz(("string %s" % val), CAT)` mit
   extra Klammer-Gruppe über mehrere Zeilen — Parser-Fehler. → Variable benutzen.
2. **`configure()` vs. `on_ready()`:** `Services.xyz` erst in `on_ready()` — in `configure()`
   ist der Container noch leer.
3. **`_process()` in Services:** Verboten — immer `on_tick()` + `ServiceTicker.register_service()`.
4. **`class_name`-Tippfehler:** Dateiname ≠ class_name → crasht auf Linux-Servern.
5. **Lambda in Dictionary:** Kommentare zwischen Lambda-Zeilen sind erlaubt, aber
   KEINE mehrzeiligen Expressions mit `(` direkt nach dem Kommentar.

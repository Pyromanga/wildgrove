> **Resolution (2026-07): [ADR-017](../adr/017-cross-scope-service-access.md).**
> Mechanismus 2 (expliziter Bridge) wurde zur alleinigen Norm erklärt, der
> implizite Fallback in `ServiceInitializer` wurde entfernt. `SessionManager`
> ist jetzt Teil der Session-Registry-Bridge; `NetworkBridge.get_local_peer_id()`
> delegiert an sie statt selbst zu rechnen. `tests/unit/test_identity_access_boundary.gd`
> verhindert einen Rückfall. Dieses Dokument bleibt als Bestandsaufnahme stehen —
> siehe ADR-017 für die Entscheidung selbst.

# AUDIT-05 — Saubere Zwiebel vs. Mutations-Zwiebel

**Scope:** Grundlagen-Dokument, bevor ADR-015/MIGRATION-015 fortgesetzt wird.
**Anlass:** Beim Versuch, ADR-015 ("wer ist der lokale Spieler") sauber umzusetzen, hat
sich herausgestellt, dass jede saubere Lösung eine weitere unsaubere Schicht darunter
freigelegt hat — dreimal in Folge. Das ist kein Implementierungsfehler, sondern ein
Symptom: die Architektur hat zwei unabhängige "Zwiebel"-Modelle (Schichten + Scopes),
von denen nur eines dokumentiert ist, und die Regel für "wie überquert man eine
Scope-Grenze" existiert nirgends kodifiziert — nur an einer Stelle vorgemacht, nie
wieder konsistent wiederholt.
**Methode:** Code zuerst, jeder Befund mit Datei+Zeile belegt. Kein Fix in diesem
Dokument — nur Bestandsaufnahme, als Grundlage für eine bewusste Entscheidung.
**Datum:** 2026-07

---

## Teil 1 — Die saubere Zwiebel (wie es gedacht ist)

Es gibt in diesem Projekt **zwei orthogonale Zwiebeln**, keine einzige. Das ist an sich
nicht falsch — die meisten nicht-trivialen Architekturen haben das. Das Problem ist,
dass nur eine der beiden dokumentiert ist.

### Zwiebel A — Schichten (dokumentiert in `docs/architecture.md`)

```
Presentation (UI-Controller)
    ↓ nur via IUIContext
Entity (Player, OakTree, EnemyNPC, ...)
    ↓ nur via IEntityContext
Service (InventorySystem, QuestService, SkillSystem, ...)
    ↓ nur via configure(deps)
Infrastructure (ServiceOrchestrator, EventBus, ...)
```

Regel: Pfeile zeigen nur nach unten. Entities/UI kennen nie einen Service direkt,
nur die schmale Fassade (`IEntityContext`/`IUIContext`).

### Zwiebel B — Scopes (nirgends als Diagramm dokumentiert, nur aus `BootPipeline.gd`
rekonstruierbar)

```
App-Scope        (lebt: Programmstart bis -ende)
    ↓
Character-Scope  (lebt: Login bis Logout)
    ↓
World/Session-Scope (lebt: Welt betreten bis verlassen)
```

Jeder Scope hat seine eigene `ServiceRegistry`. `SessionManager` lebt in App-Scope
(`global_services` in `BootstrapConfig.tres`), `NetworkBridge`/`InventorySystem`/
`WorldService`/etc. leben in Character/Session-Scope (`session_services`).

**Diese zweite Zwiebel taucht in `docs/architecture.md` nicht auf.** Das Dokument
beschreibt nur Zwiebel A. Wer nur `architecture.md` liest, weiß nicht, dass es Scopes
gibt — und würde beim Bauen einer neuen Facade-Methode nicht auf die Idee kommen, dass
"welcher Service ist von wo aus sichtbar" überhaupt eine Frage ist.

### Wie man sauber eine Scope-Grenze überquert (die Regel, die es geben *sollte*)

Aus dem Code lassen sich zwei tatsächlich verwendete Mechanismen rekonstruieren:

**Mechanismus 1 — impliziter Fallback bei `configure()`:**
`ServiceInitializer.run(ordered, registry, fallback_registry)` (`ServiceInitializer.gd`)
sucht jede in `ServiceDefinition.deps` deklarierte Abhängigkeit zuerst in der eigenen
Registry, dann in `fallback_registry` (der Eltern-Scope-Registry). Das ist der
ADR-009-Mechanismus. Er greift **nur für Services, die `configure(deps)` durchlaufen**,
und **nur wenn die Dependency explizit in `deps = Array[String]([...])` gelistet ist**.

**Mechanismus 2 — expliziter Bridge via `register_resource()`:**
`BootPipeline.gd:120-121`:
```gdscript
var app_bus := app_reg.get_service(ServiceKeys.EVENT_BUS)
if app_bus != null:
    registry.register_resource(app_bus, ServiceKeys.EVENT_BUS)
```
Holt den App-Scope-Service explizit und registriert ihn zusätzlich direkt in der
Session-Registry. Danach ist er über **beide** Wege sichtbar: `configure(deps)` UND
direkter `registry.get_service(...)`-Aufruf.

**Beide Mechanismen sind an sich legitim.** Das Problem ist: **es gibt keine Regel,
wann welcher gilt** — nirgends dokumentiert, kein Test, der das erzwingt. Genau dieser
fehlende Konsens ist die Wurzel der jetzt gefundenen Duplikate.

---

## Teil 2 — Die Mutations-Zwiebel (was tatsächlich im Code ist)

### Mutation 1 — Dieselbe Information, drei unabhängige Quellen

| Ort | Code | Scope |
|-----|------|-------|
| `SessionManager.gd:203-204` | `func get_local_peer_id() -> int: return multiplayer.get_unique_id() if _has_active_peer() else 1` | App |
| `NetworkBridge.gd:119-120` | `func get_local_peer_id() -> int: return multiplayer.get_unique_id() if _has_peer() else 1` | Session |
| 10 Call-Sites (`InteractionButtonController.gd` u.a.) | `get_nodes_in_group("player")[0]` | UI/Entity |

Drei Implementierungen derselben Berechnung. Keine kennt die anderen beiden.

### Mutation 2 — Zugriffsweg zu App-Scope-Services ist pro Konsument neu erfunden

| Konsument | Wie er `SessionManager` erreicht | Mechanismus |
|-----------|-----------------------------------|--------------|
| `WorldService.configure()` | `deps.get_optional(ServiceKeys.SESSION_MANAGER)` | Mechanismus 1 (Fallback), weil `worldservice.deps` in `BootstrapConfig.tres:117` `"session_manager"` listet |
| `BootPipeline.boot_character()` (Phase C9) | `app_reg.get_service(ServiceKeys.SESSION_MANAGER)` direkt | Direkter App-Registry-Zugriff, kein Fallback nötig — der Code hat die App-Registry ja schon in der Hand |
| `ServiceOrchestrator._connect_session_manager()` | `_app_scope.get_service(ServiceKeys.SESSION_MANAGER)` direkt | Dasselbe wie oben, andere Stelle |
| `InventorySystem`/`EquipmentService` (Log-Zeilen) | **gar nicht** — nutzen `_network.get_local_peer_id()` (Mutation 1) statt `SessionManager` überhaupt anzufragen | Umgehung des Problems statt Lösung |
| `UIContext.from_registry(registry)` | **würde `registry.get_service(ServiceKeys.SESSION_MANAGER)` aufrufen** — aber `SessionManager` ist nie in die Session-Registry gebridged worden (kein `register_resource()`-Aufruf dafür existiert, anders als bei `EVENT_BUS`) → **liefert `null`, still, ohne Fehler** | Keiner der beiden Mechanismen — Lücke |

Vier verschiedene Zugriffsmuster für dieselbe Frage ("gib mir den SessionManager"),
plus eine fünfte Stelle, die dem Problem komplett ausweicht, plus eine sechste, die
bei Verwendung still `null` zurückgeben würde. Das ist der eigentliche Befund: **nicht
die fehlende `get_local_peer_id()`-Methode war das Kernproblem, sondern dass es für
"App-Scope-Service aus Session-Scope erreichen" nie eine einzige verbindliche Antwort
gab.**

### Mutation 3 — `NetworkBridge` trägt eine Verantwortung, die nicht seine ist

`NetworkBridge`s eigene Doku-Kopfzeile (`NetworkBridge.gd:2`) beschreibt seine Aufgabe:
RPC-Dispatch. `get_local_peer_id()` beantwortet aber "wer bin ich", eine
Identitäts-Frage — die laut `SessionManager`s eigener Doku
(`SessionManager.gd:9-11`) **explizit dessen Verantwortung ist**:
> "NetworkBridge und die Session-Services sehen denselben `multiplayer.multiplayer_peer`
> — kein separater Peer-State nötig."

Der Kommentar sagt selbst, dass es keinen zweiten Peer-State geben sollte — `NetworkBridge`
hat trotzdem eine zweite Berechnung derselben Sache. Das ist keine böswillige
Dopplung, sondern der naheliegende Verstoß, wenn ein Service Zugriff auf `multiplayer`
hat und die Information "gerade brauche ich sie hier" wichtiger scheint als "wo sollte
sie eigentlich herkommen".

### Warum das immer wieder passiert (Muster, nicht Einzelfall)

Kein Architektur-Test verhindert:
- eine zweite `get_local_peer_id()`-Methode irgendwo im Code (analog zum bereits
  existierenden `test_event_bus_access_boundary.gd`, das *EventBus*-Zugriffsverstöße
  verhindert — für Identität gibt es kein Äquivalent)
- einen `registry.get_service()`-Aufruf auf einen Service, der in dieser Registry gar
  nicht registriert ist (schlägt nicht beim Kompilieren fehl, nur zur Laufzeit mit
  `null` — und nur wenn der Rückgabewert tatsächlich benutzt wird)

Beides sind strukturelle Lücken, nicht einzelne Bugs — beheben einer einzelnen Stelle
lässt die nächste zufällig auftauchen.

---

## Teil 3 — Wo das hinführt, wenn man immer weiter schält

An diesem Punkt lohnt sich die ehrliche Frage, die in der Konversation aufkam: **hört
das je auf?** Antwort: ja, aber nicht von selbst. Die drei gefundenen Mutationen sind
alle Instanzen *eines* fehlenden Elements — einer kodifizierten Antwort auf "wie
überquert Code eine Scope-Grenze in diesem Projekt". Sobald das einmal explizit
entschieden und (im Idealfall) durch einen Architektur-Test erzwungen ist, ist die
Zwiebel an dieser Stelle wieder sauber — es entsteht keine vierte Ebene, weil die
Frage nicht mehr "wo hole ich mir das jetzt her" ist, sondern "folge der einen
dokumentierten Regel".

**Das ist der Unterschied zu einer echten unendlichen Rekursion:** Mutation 1, 2 und 3
sind nicht drei unabhängige Zufallsfunde, sondern derselbe fehlende Baustein, dreimal
an unterschiedlichen Stellen sichtbar geworden.

---

## Offene Entscheidung (nicht Teil dieses Dokuments)

Dieses Dokument beantwortet bewusst nicht, welcher der beiden Mechanismen (Fallback
vs. expliziter Bridge) zur Norm werden soll, oder ob `SessionManager` in die
Session-Registry gebridged wird. Das ist der nächste Schritt — vermutlich ein eigenes
ADR ("Cross-Scope Service Access"), auf dem ADR-015 dann aufbaut, statt es nebenbei
mitzuentscheiden.

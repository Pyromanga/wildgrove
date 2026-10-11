> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-003: ServiceNode (Node) vs Service (RefCounted) als Basisklassen

**Status:** Akzeptiert — Migrations-Backlog vollständig abgearbeitet (Session 6)  
**Datum:** 2026-06  
**Kontext:** Alle Service-Implementierungen

---

## Problem

GDScript bietet zwei sinnvolle Basisklassen für Services:

- `Node` — lebt im SceneTree, hat `_ready()`, `_process()`, kann `add_child()` nutzen
- `RefCounted` — kein SceneTree, kein Node-Overhead, garbage-collected wenn keine Referenzen mehr existieren

Die falsche Wahl kostet entweder Flexibilität (`RefCounted` wenn SceneTree nötig) oder Performance und Korrektheit (`Node` wenn kein SceneTree gebraucht wird — Node-Overhead, implizite Lifecycle-Erwartungen).

---

## Optionen

### Option A: Alles extends Node (ServiceNode)
Einfach, konsistent, immer SceneTree-fähig.
- ✅ Konsistenz, kein mentaler Overhead bei der Wahl  
- ❌ Node-Overhead für Services die keinen SceneTree brauchen  
- ❌ Impliziert `_ready()` / `_process()` — verführt zu falschen Lifecycle-Mustern  
- ❌ ServiceFactory muss alle Services als Node-Children hinzufügen

### Option B: Alles extends RefCounted (Service)
Kein SceneTree-Overhead, pure Logik.
- ✅ Leicht, kein SceneTree-Overhead  
- ❌ Services die Nodes als Children brauchen (HUDManager, ServiceTicker) scheitern

### Option C: Zwei Basisklassen nach Bedarf (gewählt)
`ServiceNode extends Node` für Services die den SceneTree brauchen.  
`Service extends RefCounted` für pure Logik-Services.

---

## Entscheidung

**Option C.** Die Wahl der Basisklasse folgt dem Entscheidungsbaum: "Braucht dieser Service `add_child()`, `_ready()`, oder `get_tree()`?" Wenn nein → `Service extends RefCounted`.

---

## Bekannter Migrations-Backlog

Bei der Einführung von `Service extends RefCounted` wurden bestehende Services nicht migriert. Folgende Services extendeten `ServiceNode` obwohl sie keinen SceneTree-Zugriff brauchen und auf `Service extends RefCounted` migriert werden sollten:

| Service | Grund für Migration | Status |
|---------|---------------------|--------|
| `InventorySystem` | Reine Inventar-Logik, kein SceneTree nötig | ✅ Migriert (Session 5) |
| `SkillSystem` | Reine XP/Level-Logik, kein SceneTree nötig | ✅ Migriert (Session 5) |
| `QuestService` | Reine Quest-State-Logik, kein SceneTree nötig | ✅ Migriert (Session 5) |
| `DataService` | Reines Daten-Repository, kein SceneTree nötig | ✅ Migriert (Session 6) |
| `SaveSystem` | File-IO, kein SceneTree nötig | ✅ Migriert (Session 6) |
| `PlayerStateService` | Reiner State-Container | ✅ Migriert (Session 6) |

**Migriert (Session 5):** `InventorySystem`, `SkillSystem`, `QuestService` — alle drei extendeten `ServiceNode` ohne `add_child()`/`get_tree()`/`_process()` zu nutzen. Audit vor der Migration bestätigte: kein Call-Site behandelt sie als `Node` (kein `get_node()`, kein `add_child()`, kein `queue_free()` von außen), `ServiceTicker`/`ServiceRegistry`/`ServiceFactory` arbeiten ohnehin duck-typed über `has_method()`. Migration verlief ohne Breaking Change, wie unten vorhergesagt.

**Migriert (Session 6):** `DataService`, `SaveSystem`, `PlayerStateService` — gleiches Audit-Muster wie Session 5. `SaveSystem` ist das einzige der drei, das in einem Test (`tests/unit/test_save_system.gd`) zuvor via `add_child_autofree()` in den SceneTree gehängt wurde — dieser Aufruf war ein Test-Implementierungsdetail (GUT-Cleanup-Helper), keine echte SceneTree-Abhängigkeit von `SaveSystem` selbst. Im Produktionscode bestätigte das Audit: kein `get_node()`, kein `add_child()`, kein `queue_free()`, keine `.tree_exiting`-Signale auf einer dieser drei Instanzen. Test angepasst (direkte Instanziierung statt `add_child_autofree()`).

**Backlog-Tabelle ist jetzt leer — siehe "Ablösung" unten.**

**Diese Migration ist kein Breaking Change** — `ServiceFactory` und `ServiceOrchestrator` behandeln beide Basisklassen transparent. Die Migration kann schrittweise, Service für Service, in Refactoring-Sessions erfolgen.

---

## Konsequenzen

### Positiv
- Klare Trennung: `ServiceNode` = braucht SceneTree, `Service` = pure Logik
- Geringerer Overhead für Logik-Services nach Migration
- Seit Session 6: keine `ServiceNode`-Instanz mehr ohne echten SceneTree-Bedarf — die Zwei-Klassen-Wahl ist jetzt immer eindeutig per Entscheidungsbaum beantwortbar, nicht mehr "historisch gewachsen"

### Negativ / Risiken
- Zwei Basisklassen erhöhen leicht die mentale Last für neue Contributors

### Mitigationen
- `CONTRIBUTING.md` Suffix-Konventionstabelle macht die Wahl explizit
- Entscheidungsbaum aus diesem ADR gilt für jeden neuen Service ab sofort: "Braucht `add_child()`, `_ready()` oder `get_tree()`?" → nein bedeutet `Service`.

## Ablösung

**Trigger-Bedingung erreicht (Session 6):** Der Migrations-Backlog ist vollständig abgearbeitet.

**Nachverifikation (Prio 3 / Audit-03):** `StatModifierService`, `RewardDispatcher` und `GameSaveService` wurden als `extends ServiceNode` ohne jeden SceneTree-Zugriff identifiziert und auf `extends Service` korrigiert. Verbleibende `ServiceNode`-Services (`CombatSystem`, `SceneManager`, `GameManager`, `WorldService`, `WorldGenerationService`, `RespawnService`, `InteractionExecutor`, `ServiceTicker` u.a.) wurden geprüft — sie nutzen SceneTree-Features und sind korrekt klassifiziert. `ServiceTicker` fehlte diesem Audit ursprünglich (kein `# justified:`-Kommentar, nicht in `JUSTIFIED_FILES`) und wurde nachgetragen — es treibt via `_process()`/`_physics_process()` den globalen Tick-Loop und braucht daher zwingend SceneTree-Zugriff. Eine vollständige Migration *aller* Services ist kein Ziel von ADR-003: die Zwei-Klassen-Entscheidung (Option C) bleibt aktiv, der Backlog ist leer.

**Dieser ADR bleibt aktiv** (Option C ist weiterhin die gültige Architektur-Entscheidung), wird aber nicht mehr durch einen offenen Backlog "getrübt". Neue Services folgen dem Entscheidungsbaum direkt bei ihrer Erstellung — kein nachträglicher Migrations-Aufwand mehr nötig, wenn die Wahl von Anfang an korrekt getroffen wird.

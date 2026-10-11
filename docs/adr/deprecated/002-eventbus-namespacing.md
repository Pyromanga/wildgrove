> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-002: EventBus mit typisierten Namespaces

**Status:** Akzeptiert  
**Datum:** 2026-06  
**Kontext:** Gesamte Event-Kommunikation zwischen Services, Entities und UI

---

## Problem

Services und Entities müssen entkoppelt kommunizieren. Godot's eingebautes Signal-System bindet Sender und Empfänger direkt — `node.signal.connect(other_node.method)` erzeugt eine harte Kopplung. Bei 20+ Services und dutzenden Entity-Typen entsteht ein Coupling-Graph der unmöglich zu warten ist.

Die Alternative (ein globaler Bus als flache Signal-Liste) führt zu Naming-Konflikten (`health_changed` von wem?), fehlender Auffindbarkeit, und keiner semantischen Gruppierung.

---

## Optionen

### Option A: Direktes Godot-Signal per Node
`inventory.inventory_changed.connect(hud._refresh)` — Standard Godot.
- ✅ Engine-nativ, keine Infrastruktur  
- ❌ Erzeugt direkte Kopplung zwischen konkreten Implementierungen  
- ❌ Nicht testbar ohne echte Nodes  
- ❌ Bei vielen Subsystemen: O(n²) Dependency-Graph

### Option B: Flacher globaler EventBus
Ein Autoload mit allen Signalen: `EventBus.loot_collected`, `EventBus.player_died`, etc.
- ✅ Entkoppelt  
- ❌ Namespace-Konflikte bei wachsendem Projekt  
- ❌ Keine semantische Gruppierung — was gehört zusammen?  
- ❌ Autocomplete zeigt 60+ Signale ohne Kontext

### Option C: Typisierter EventBus mit Namespace-Objekten (gewählt)
`EventBus.player`, `EventBus.world`, `EventBus.system`, `EventBus.quest`, `EventBus.ui` — jeder ein Objekt vom Typ `BaseEvents` mit seinen eigenen Signals.

- ✅ Namespace-Isolation: `EventBus.player.health_changed` vs `EventBus.world.entity_spawned`  
- ✅ Autocomplete funktioniert auf Namespace-Ebene  
- ✅ Neue Signale in einem Namespace berühren keine anderen  
- ✅ `BaseEvents` als gemeinsame Basisklasse erlaubt einheitliche Handhabung

---

## Entscheidung

**Option C.** Neue Signale kommen immer in den semantisch passenden Namespace. Neuer Namespace = neue `*Events.gd`-Datei + eine Zeile in `EventBus.gd`.

---

## Konsequenzen

### Positiv
- Signale sind gruppiert und auffindbar
- Compiler-Fehler bei Typo im Namespace-Namen (statt stillem nil)
- Namespace-Wachstum ist linear, nicht exponentiell

### Negativ / Risiken
- Alle Signal-Connections müssen `EventBus.namespace.signal_name.connect()` nutzen — kein direktes Node-Signal
- Godot-Signale sind synchron: massive gleichzeitige Emissions blockieren den Main-Thread

### Mitigationen
- `docs/services.md` dokumentiert alle Signals pro Namespace
- Zukünftig: Event-Batching für High-Frequency-Events (separate ADR wenn nötig)
- `on_cleanup()` muss alle in `on_ready()` angelegten Connections wieder trennen

> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-004: request_/on_*_confirmed als Networking-Kontrakt

**Status:** Akzeptiert — Teilweise umgesetzt, offener Tech Debt dokumentiert  
**Datum:** 2026-06  
**Kontext:** Alle server-autoritativen Systeme: InventorySystem, QuestService, SkillSystem, EquipmentService, PlayerStateService

---

## Problem

WildGrove ist als MMORPG-artiges Coop-Spiel konzipiert. State-Mutationen müssen server-autoritativ sein — Inventar, Quest-Fortschritt, XP. Wenn ein Client direkt State schreibt, ist das ein Cheating-Vektor.

Das Problem: Zum jetzigen Zeitpunkt gibt es zwar `NetworkBridge`, aber noch keine echten RPC-Verbindungen für alle Services. Wenn Tier-2-Multiplayer kommt, müssen die State-Mutationen klar abgegrenzt sein — sonst ist ein Service-weites Refactoring nötig.

---

## Optionen

### Option A: Direkte State-Mutation jetzt, Refactor später
`_items[id] += qty` direkt im Handler. Wenn Netzwerk kommt: alles umschreiben.
- ✅ Einfach jetzt  
- ❌ Der Refactor trifft jeden Service, jede Mutation — unkontrollierbar bei wachsender Codebase

### Option B: Jetzt schon vollständiger Server-Code (Overkill)
Vollständige Server/Client-Trennung mit RPCs, Godot Multiplayer API.
- ✅ Korrekt für Multiplayer  
- ❌ Massiver Overhead bevor der erste Gameplay-Loop fertig ist

### Option C: Naming-Convention als Kontrakt (gewählt)
`request_*()` für Client-seitige Anfragen (gehen später zum Server).  
`on_*_confirmed()` für State-Mutation (wird Server-RPC-Handler sein) — **muss public sein**.  
Heute: `request_add_item()` ruft direkt `on_item_add_confirmed()` auf — lokal und synchron.  
Morgen: `request_add_item()` sendet an Server, Server ruft `on_item_add_confirmed()` via RPC.

---

## Entscheidung

**Option C.** Die Konvention ist dokumentiert in `NetworkContract.gd`.

**Regeln:**
- `request_*()` — darf nur validieren und weiterleiten, niemals direkt State mutieren
- `on_*_confirmed()` — einzige Methode die internen State direkt schreibt. **Muss public sein** (für RPC)
- Kein Code außerhalb dieser beiden Methoden mutiert den State

**Server-autoritative Systeme:**
- `InventorySystem` — `request_add_item()` / `on_item_add_confirmed()` ✅ korrekt public
- `EquipmentService` — `request_equip()` / `on_equip_confirmed()` ✅ korrekt public
- `QuestService` — `request_start_quest()` / `on_quest_start_confirmed()` ✅ public (Round 15, I-01)
- `SkillSystem` — `request_add_xp()` / `on_xp_add_confirmed()` ✅ public (Round 15, I-01)
- `PlayerStateService` — State ist flüchtig, niedrige Priorität

---

## Konsequenzen

### Positiv
- State-Mutation ist in jeder server-autoritativen Klasse auf eine einzige Methode isoliert
- Netzwerk-Integration erfordert keinen Refactor der Aufrufer

### Negativ / Risiken
- ~~`QuestService` und `SkillSystem` haben die Konvention noch nicht vollständig umgesetzt~~ — **behoben (AUDIT-03 I-01, Round 15):** `on_quest_start_confirmed()` und `on_xp_add_confirmed()` sind jetzt public mit typisierten Parametern. `receive_*_from_network()` ist zum reinen Authority-Guard-Delegat geworden.

### Mitigationen
- `CONTRIBUTING.md` Abschnitt 2.3: Verletzung des Patterns ist Review-Blocker
- `NetworkContract.gd` als lebendiges Dokument mit expliziter Authority-Matrix

---

## Offener Tech Debt

~~**AUDIT-03 I-01:** `QuestService._on_quest_start_confirmed()` und `SkillSystem._on_xp_add_confirmed()` sind private.~~ — **✅ Behoben (Round 15):** Handler sind public, typisierte Parameter, `receive_*_from_network()` delegiert als Authority-Guard.

---

## Ablösung

Dieser ADR wird durch einen Netzwerk-ADR abgelöst sobald Tier-2-Multiplayer implementiert wird. Zu diesem Zeitpunkt ändert sich nur der Body von `request_*()` von einem lokalen Direktaufruf zu einem Server-RPC — die Konvention bleibt.

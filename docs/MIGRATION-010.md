# MIGRATION-010 — Multiplayer Authority Tiers

**Referenz:** [ADR-010](adr/010-multiplayer-authority-tiers.md)  
**Ziel:** Session-Services von Single-Tenant auf Multi-Tenant umstellen;
`INetworkAdapter`/`LocalNetworkAdapter` (ADR-007) entfernen;
`request_*()`-Implementierungen direkt auf Godot-RPC verdrahten.

---

## Gesamtstatus

| Phase | Beschreibung | Status |
|-------|-------------|--------|
| 1 | Multi-Tenant State in Session-Services | ✅ Abgeschlossen |
| 2 | `INetworkAdapter` entfernen | ✅ Abgeschlossen |
| 3 | Authority Guards hardenen | ✅ Abgeschlossen |
| 4 | RPC-Verdrahtung (`request_*` → Godot-RPC) | ✅ Abgeschlossen |
| 5 | Equipment-Sync im NetworkBridge | ✅ Abgeschlossen |

---

## Phase 1 — Multi-Tenant State ✅

**Ziel:** Alle Session-Services trennen internen State per `player_id`/`peer_id`.

| Service | Vorher | Nachher | Status |
|---------|--------|---------|--------|
| `InventorySystem` | `_items: Dictionary` (flat) | `_players: { peer_id: {...} }` | ✅ |
| `PlayerStateService` | `_current: State` (single) | `_current: { peer_id: State }` | ✅ |
| `EquipmentService` | `_slots: Dictionary` (flat) | `_players: { player_id: slots }` | ✅ |
| `QuestService` | `_quests` per player_id | bereits multi-tenant | ✅ |
| `SkillSystem` | `_skills` per player_id | bereits multi-tenant | ✅ |
| `CombatSystem` | `_active_effects` per source_id | bereits per source_id gekeyt | ✅ |

> **Nachtrag 2026-07:** `InteractionExecutor` fehlt in dieser Tabelle — er wurde in
> Sprint F4 nicht mitmigriert und hält weiterhin globalen Singleton-State
> (`_active_action`/`_active_tween`, keine `player_id`-Trennung). Siehe
> [ADR-015](adr/015-local-player-identity.md) / [MIGRATION-015](MIGRATION-015.md).
> Diese Zeile wird bewusst nicht nachträglich in die Tabelle oben eingefügt und nicht
> auf 🔲 zurückgesetzt — die Tabelle dokumentiert, was Sprint F4 tatsächlich umfasste.

---

## Phase 2 — INetworkAdapter entfernen ✅

`INetworkAdapter.gd` und `LocalNetworkAdapter.gd` wurden entfernt.
`NetworkContract.gd` und `CONTRIBUTING.md` (Abschnitt 2.3) wurden aktualisiert.
`request_*()` / `on_*_confirmed()` als Naming-Konvention bleibt (ADR-004).

---

## Phase 3 — Authority Guards hardenen ✅

| Ort | Vorher | Nachher | Status |
|-----|--------|---------|--------|
| `CombatSystem.roll_critical()` | `assert(multiplayer.is_server())` — No-Op in Release | `if not is_server(): return false` | ✅ |
| `CombatSystem.roll_critical()` | `chance` ignorierte StatModifier | `chance += get_effective_stat("crit_chance", ...)` | ✅ |

---

## Phase 4 — RPC-Verdrahtung ✅

> **Korrektur 2026-07:** Diese Phase war als 🔲 markiert, ist aber tatsächlich fertig.
> Die Doku lag hier falsch in die andere Richtung als sonst üblich — sie unterschätzte
> den Ist-Stand statt ihn zu beschönigen. Verifiziert im Code, nicht nur behauptet.

`NetworkBridge.gd` hostet die zentrale RPC-Dispatch-Schicht mit echten
`@rpc("any_peer", "call_remote", "reliable")`-Methoden für Item/Quest/XP/Equipment/State
(`_rpc_add_item`, `_rpc_start_quest`, `_rpc_complete_quest`, `_rpc_add_xp`,
`_rpc_set_state`, `_rpc_equip_item`, `_rpc_unequip_item`). Die `send_*()`-Wrapper rufen
`rpc_id(1, ...)` auf; die Services rufen ihre `request_*()`-Methoden auf, die intern
prüfen, ob ein Peer aktiv und die lokale Instanz nicht die Autorität ist, und in dem Fall
über `_network.rpc_id(1, "_rpc_*", ...)` gehen statt den State direkt zu mutieren
(`InventorySystem.request_add_item()`, analog in `QuestService`, `SkillSystem`,
`EquipmentService`). Tier-1-Fallback (kein Peer) bleibt der direkte Aufruf von
`on_*_confirmed()`, kein separater Code-Pfad nötig — wie ursprünglich geplant.

Zusätzlich existiert eine Snapshot-Übertragung für neu verbundene Peers
(`_rpc_client_requests_initial_state` / `_rpc_receive_initial_state`), die im
ursprünglichen Phase-4-Scope nicht vorgesehen war, aber zum selben Zweck gehört.

---

## Phase 5 — Equipment-Sync im NetworkBridge ✅

> **Korrektur 2026-07:** ebenfalls bereits umgesetzt, siehe Phase 4 oben —
> `send_equip_item()` / `_rpc_equip_item()` und `send_unequip_item()` /
> `_rpc_unequip_item()` sind in `NetworkBridge.gd` vorhanden. Andere Spieler sehen
> Equipment-Änderungen ab Tier 2.

---

## Offene Schulden nach Phase 3

> **Korrektur 2026-07:** Der folgende Punkt zu fehlenden Authority Guards ist überholt.
> `InventorySystem.on_item_add_confirmed()`, `QuestService`, `SkillSystem` und
> `EquipmentService` haben je einen `C-02`-Guard (`if ... not _network.is_server(): return`),
> der Nicht-Autorität-Aufrufe verweigert und loggt. Verifiziert im Code für alle vier
> Services, nicht nur für `InventorySystem`.

> **Korrektur Round 55 (Node-Wrapper):** Der im ADR-010-Abschnitt "Negativ/Risiken"
> beschriebene "dünne `Node`-Wrapper pro Service" existiert bereits — als **ein**
> zentraler Wrapper, nicht pro Service: `NetworkBridge extends ServiceNode` hostet
> alle `@rpc`-Methoden; jeder `RefCounted`-Service (`InventorySystem`, `QuestService`,
> `SkillSystem`, `EquipmentService`, `WorldService`) ruft bei aktivem Peer
> `rpc_id(1, "_rpc_*", …)` darüber auf, statt selbst `Node` zu sein. Die Reibung
> zwischen `RefCounted`-Services und Godots `Node`-gebundenem `rpc_id()` war zum
> Zeitpunkt der ADR-Formulierung noch offen, ist aber seit `NetworkBridge`
> tatsächlich gelöst — nur nie hierher zurückgemeldet worden.

- UUID-Vergabe in `EntityOrchestrator` noch nicht authority-gebunden (ADR-010, Punkt 2).

> **Korrektur Round 55 (Slot-/Gewichts-Re-Validierung):** Der folgende Punkt beschrieb
> einen `_rpc_add_item()`-RPC-Pfad, über den ein modifizierter Client
> `on_item_add_confirmed()` direkt mit beliebiger Menge hätte erreichen können. Dieser
> RPC wurde in Round 45 vollständig entfernt — `request_add_item()` wird seither
> ausschließlich autoritäts-seitig aufgerufen (`RewardDispatcher`, `InteractionResolver`,
> nie von einem Client über das Netz). Der beschriebene Angriffsweg existiert seit
> Round 45 nicht mehr; verifiziert per Grep, `on_item_add_confirmed()` hat aktuell genau
> einen Aufrufer im gesamten Code: `request_add_item()` selbst. Trotzdem wurde in
> Round 55 (ADR-010-Update) die Re-Validierung direkt in `on_item_add_confirmed()`
> ergänzt — nicht weil eine konkrete Lücke bestand, sondern als Verteidigung in der
> Tiefe für Tier 3 ("Server vertraut niemandem" heißt: nicht nur der Caller-Konvention
> vertrauen, sondern an der Mutationsstelle selbst prüfen).

- ~~**Neu (2026-07): Fehlende serverseitige Re-Validierung von Slot-/Gewichtslimits.**~~
  Siehe Korrektur Round 55 oben — erledigt.

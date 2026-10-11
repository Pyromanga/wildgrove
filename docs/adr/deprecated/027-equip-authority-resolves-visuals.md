> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-027: Equip-Autorität löst PlayerVisuals selbst auf (schließt R-4)

**Status:** Angenommen — umgesetzt (2026-07)
**Datum:** 2026-07
**Kontext:** `EntityOrchestrator`, `WorldService`, `EquipmentService`,
`InventoryUIController`, `EquipmentUIController`, `NetworkContract`. Schließt
R-4 aus `TODO-offene-probleme.md` ab. Nutzt denselben Objekt-Auflösungs-Gedanken
wie ADR-023, hier für "Player-Node zu `player_id`" statt "Entity zu `entity_uuid`".

## Problem

Der `request_*()` / `on_*_confirmed()`-Vertrag (ADR-004) trägt serialisierbare
Absicht über eine RPC-Grenze — Slot-Name, Item-ID, Spieler-ID. Das funktioniert
für jede andere bestätigte Mutation im Code.

Equipment ist anders: eine Waffe auszurüsten hat einen zweiten Effekt, der keine
Daten sind — das Anhängen eines `WeaponVisual3D` an einen konkreten
`PlayerVisuals`-Node. Eine Node-Referenz lässt sich weder über eine RPC
serialisieren, noch wäre sie auf dem empfangenden Prozess sinnvoll (sie zeigt
in den Szenenbaum des Aufrufers, nicht der Autorität).

`on_equip_confirmed()` bekam deshalb einen optionalen `visuals`-Parameter
angehängt (funktioniert nur wenn Aufrufer == Autorität, also Tier 1 Solo, und
der Aufrufer zufällig bereits die richtige Referenz hält) — aber nie durch
`request_equip()` hindurch verdrahtet, weil es dafür keinen korrekten Weg gibt.
Da der "sichere" Pfad Visuals also nie liefern konnte, riefen die UI-Panels
stattdessen `equip()` direkt auf — wodurch der besitzprüfungsfreie Pfad zum
**einzigen tatsächlich genutzten** Pfad im Spiel wurde.

Die eigentliche Ursache ist nicht "fehlende `has_item()`-Prüfung", sondern:
**die Autorität kann "den PlayerVisuals-Node von `player_id`" nicht selbst
auflösen** — diese Fähigkeit fehlte komplett. Genau dieselbe Auflösung
("Player-Node zu beliebigem `player_id`") existierte bereits einmal, aber
privat und ohne Visual-Accessor: `EntityOrchestrator._find_player_by_id()`.

## Optionen

### Option A: `visuals`-Parameter durch die RPC durchreichen
Nicht möglich — Node-Referenzen sind weder serialisierbar noch prozessübergreifend
gültig. Verworfen ohne Machbarkeits-Prüfung nötig.

### Option B: Autorität löst `PlayerVisuals` selbst über `player_id` auf
`EntityOrchestrator._find_player_by_id()` öffentlich machen, über `WorldService`
als Fassade für `EquipmentService` erreichbar machen (gleicher Zugriffsweg wie
`_network`), dort einen `get_player_visuals(player_id)`-Accessor ergänzen.
`on_equip_confirmed()` ruft ihn selbst auf, statt eine Referenz entgegenzunehmen.
- ✅ Kein Node überquert je eine Prozessgrenze
- ✅ Ein einziger, kanonischer "Player für `player_id`"-Lookup statt fünf
  Kopien desselben Scans
- ✅ `on_equip_confirmed()` ist jetzt auf Tier 2/3 korrekt (löst die Kopie des
  Ziel-Spielers auf der Autorität auf, nicht die des Aufrufers)
- ❌ `EquipmentService` braucht einen Rückweg zu `WorldService` — zirkuläre
  Dep in `BootstrapConfig.tres` (`world` deklariert bereits `equipment` als Dep)

### Option C: Zweiter, equipment-eigener Gruppen-Scan in `EquipmentService`
Würde denselben Scan ein sechstes Mal duplizieren. Verworfen — genau die
Wiederholung, die R-4s Bestandsaufnahme bereits als Symptom benannt hat.

## Entscheidung

**Option B.** Der zirkuläre Dep wird nicht über `configure()`/`BootstrapConfig.tres`
aufgelöst (das würde der Resolver als Fehler ablehnen), sondern über denselben
Late-Inject-Mechanismus, der bereits für `NetworkBridge ↔ WorldService` existiert:
`EquipmentService.inject_world_service()`, aufgerufen in `BootPipeline.boot_character()`
direkt nach Phase C7 (beide Services sind dann in der Session-Registry instanziiert).

Konkreter Schnitt:
1. `EntityOrchestrator._find_player_by_id()` → public `find_player_by_id()`.
2. `WorldService.get_player_by_id(player_id)` delegiert dorthin;
   `WorldService.get_player_visuals(player_id)` baut darauf den
   `PlayerVisuals`-Kind-Lookup (vorher dupliziert in beiden UI-Controllern).
3. `EquipmentService.on_equip_confirmed()` verliert den `visuals`-Parameter,
   löst `PlayerVisuals` selbst über `_world.get_player_visuals(player_id)` auf.
4. `InventoryUIController`/`EquipmentUIController` rufen `request_equip()`/
   `request_unequip()` statt `equip()`/`unequip()` direkt auf — ihre eigene
   `_find_local_player_visuals()`-Kopie entfällt, weil die Autorität jetzt
   selbst auflöst.
5. `on_equip_confirmed()` bekommt die `InventorySystem.has_item()`-Prüfung —
   jetzt auf dem einzigen Pfad, den das Spiel tatsächlich benutzt.

## Konsequenzen

### Positiv
- Ein Mutationspfad für Equip statt zwei parallelen (Mutations-Zwiebel R-4 geschlossen).
- Ein kanonischer "Player-Node zu `player_id`"-Lookup statt fünf Kopien (vier bleiben
  vorerst bestehen — Vereinheitlichung ist die separate, kleinere ADR-015-Folgearbeit).
- `has_item()`-Prüfung greift jetzt tatsächlich, statt in einem toten Codepfad zu liegen.
- Equip funktioniert auf Tier 2/3 jetzt auch mit korrektem Visual (vorher: Solo-only-Bug).

### Negativ / Risiken
- Ein weiterer Late-Inject-Sonderfall in `BootPipeline` (gleiches Muster wie
  `NetworkBridge`, aber ein zusätzlicher Aufruf, den man beim Lesen kennen muss).
- `get_player_visuals()` gibt `null` zurück wenn eine Entity (noch) keine
  `PlayerVisuals`-Kindnote hat (Race zwischen Spawn und erstem Equip) — `equip()`
  selbst behandelt `visuals == null` bereits defensiv (kein Visual, aber Item
  wird trotzdem ausgerüstet), das bleibt unverändert.

### Mitigationen
- Late-Inject ist idempotent und wird an derselben Boot-Phase wie der bestehende
  NetworkBridge-Inject vorgenommen — kein neuer Zeitpunkt im Boot-Ablauf.
- Bestehende Tests (`test_equipment_service.gd`) rufen `equip()`/`unequip()`
  weiterhin direkt auf — die low-level Mutatoren bleiben unverändert, nur der
  Confirmed-Pfad ändert sich.

## Ablösung

Die verbleibenden vier Kopien des "Player-Node zu `player_id`"-Scans
(`IUIContext.get_local_player()`, `IEntityContext.get_local_player()`,
`PetComponent._find_owner()`, `WorldService._on_peer_cleanup_requested()`)
sind bewusst nicht Teil dieser ADR — sie decken nur den *lokalen* Peer ab,
nicht "beliebiger `player_id`", und ihre Vereinheitlichung ist die kleinere,
separat begonnene ADR-015-Folgearbeit.

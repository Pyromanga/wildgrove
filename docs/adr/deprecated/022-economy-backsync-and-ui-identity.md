> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-022: Server→Client-Rücksync für Economy-Mutationen + lokale Spieler-Identität in den UI-Panels

**Status:** Angenommen — umgesetzt (Round 49)
**Datum:** 2026-07
**Kontext:** `NetworkBridge`, `InventorySystem`, `SkillSystem`, `EquipmentService`,
`InventoryUIController`, `EquipmentUIController`, `SkillPanelController`,
`IUIContext`. Root-Cause-Fund R-7 aus `TODO-offene-probleme.md`. Kein
Cheat-Vektor, aber Coop ist für ehrliche Mitspieler strukturell unsichtbar.

## Problem

Zwei getrennte, sich verstärkende Lücken:

1. **Kein Rücksync.** Nach `on_item_add_confirmed()`/`on_xp_add_confirmed()`/
   `on_equip_confirmed()` auf der Autorität passiert für einen **entfernten**
   Client nichts. `NetworkBridge` hat außer dem einmaligen Boot-Snapshot
   (`_rpc_receive_initial_state`) keinen `rpc_id(player_id, …)`-Rückweg für
   Inventar/XP/Equipment. Die Autorität mutiert ihre eigene Kopie für Spieler X
   korrekt — Spieler X's eigener Client erfährt davon nie.
2. **UI ist auf Spieler 1 hartkodiert**, unabhängig vom Rücksync-Problem:
   `InventoryUIController.setup()` filtert explizit `if player_id == 1`,
   `EquipmentUIController.setup()` identisch, `SkillPanelController` liest über
   `SkillSystem.get_level(skill_id)`/`get_xp(...)` ganz ohne `player_id` (Default
   1 greift). `IUIContext.get_local_peer_id()`/`get_local_player()` existieren
   bereits (ADR-015, genutzt von `PlayerHPController` & Co. für 3D-Visuals) —
   die Verkabelung wurde nie bis zu den drei Economy-Panels durchgezogen.

Beide Lücken zusammen bedeuten: selbst ein perfekt reparierter R-1..R-6
(ADR-020/021) bleibt für jeden Nicht-Host-Spieler in dessen eigenem UI
unsichtbar — sein Inventar/Skills/Equipment aktualisiert nie.

## Optionen

### Option A: UI-Filter auf `get_local_peer_id()` umstellen, Rücksync später
Ersetzt `if player_id == 1` durch `if player_id == ctx.get_local_peer_id()` in
allen drei Panels, ohne den fehlenden Rücksync zu adressieren.
- ✅ Kleinster Diff
- ❌ Löst nichts: ohne Rücksync mutiert die Autorität weiterhin nur ihre eigene
  Kopie für Spieler X — das UI würde jetzt korrekt filtern, aber auf Daten, die
  nie ankommen. Behebt nur die zweite Lücke, verdeckt die erste.

### Option B: Rücksync über Polling (Client fragt periodisch den State ab)
Client sendet periodisch `_rpc_client_requests_initial_state()`-artige Anfragen
(das Boot-Snapshot-RPC existiert ja schon) statt einmalig beim Boot.
- ✅ Nutzt vorhandene Infrastruktur (`_rpc_receive_initial_state` gibt es schon)
- ❌ Polling ist strukturell verzögert und erzeugt unnötigen Traffic — bei N
  Spielern N-mal den vollen State, nicht nur das Delta
- ❌ Ist ein Fallback-Muster („wenn wir's nicht push-basiert sauber lösen,
  fragen wir halt öfter nach") — genau die Art von praktischem Workaround,
  die hier vermieden werden soll, statt die fehlende Push-Route zu bauen

### Option C: Push-Rücksync pro Mutation + `get_local_peer_id()`-Filter in allen drei Panels (gewählt)
Jede der drei bestehenden `on_*_confirmed()`-Methoden auf der Autorität sendet
nach der Mutation zusätzlich `rpc_id(player_id, "_rpc_sync_inventory", …)` /
`_rpc_sync_xp` / `_rpc_sync_equipment` an genau den betroffenen Client (Tier 1:
direkter Aufruf, kein RPC nötig — derselbe Kontrakt wie die bestehenden
`send_*()`-Methoden). Der Client empfängt das RPC und emittiert dasselbe lokale
Signal (`inventory_changed`, `xp_gained`, `equipment_changed`), das die UI
bereits abonniert hat — die UI-Panels selbst müssen nur noch von
`if player_id == 1` auf `if player_id == _ctx.get_local_peer_id()` umgestellt
werden (`SkillPanelController` bekommt zusätzlich einen `player_id`-Parameter
in `get_level()`/`get_xp()`, statt sich auf den Default zu verlassen).
- ✅ Kein Polling, kein Fallback — Push direkt aus der bestehenden
  `on_*_confirmed()`-Mutation heraus, symmetrisch zu den bestehenden
  `send_*()`-Methoden in `NetworkBridge`
- ✅ Nutzt exakt die Infrastruktur, die ADR-015 für 3D-Visuals schon aufgebaut
  hat (`get_local_peer_id()`), statt eine zweite Identitätsquelle zu erfinden
- ✅ Kein Sonderfall für Tier 1: dort ist Sender = Empfänger = derselbe Prozess,
  der Push-Aufruf wird zum direkten Funktionsaufruf, kein RPC — dasselbe Muster
  wie überall sonst in `NetworkBridge`
- ❌ Größter Diff der drei Optionen: drei neue RPCs in `NetworkBridge` plus
  Anpassung an drei UI-Controllern plus `SkillSystem`-Signatur-Änderung
- ❌ `SkillSystem.get_level()`/`get_xp()` bekommen ein Pflicht-`player_id`-Argument
  statt Default — jeder bestehende Call-Ort muss angepasst werden

## Entscheidung

**Option C.** Push-Rücksync pro Mutation, keine Polling-Krücke (Option B), UI-Filter
wird über die bereits etablierte `get_local_peer_id()`-Identität gelöst statt über
einen isolierten Patch ohne Datengrundlage (Option A).

## Konsequenzen

### Positiv
- Coop wird für Nicht-Host-Spieler tatsächlich sichtbar — Inventar/Skills/
  Equipment aktualisieren im eigenen UI, nicht nur auf der Autorität.
- Dieselbe Identitätsquelle (`get_local_peer_id()`) wird jetzt konsistent für
  3D-Visuals (ADR-015) *und* Economy-UI genutzt — keine zweite, abweichende
  Vorstellung von „wer bin ich" im UI-Layer.
- Der Rücksync-Kanal ist symmetrisch zum bestehenden `send_*()`-Muster in
  `NetworkBridge` — Erweiterung des bekannten Kontrakts, keine neue Kategorie.

### Negativ / Risiken
- `SkillSystem.get_level(skill_id)`/`get_xp(skill_id)` ohne `player_id`-Argument
  zu belassen wäre der bequemere, aber falsche Weg — die Signaturänderung ist
  ein Breaking Change für jeden bestehenden Call-Ort (auch in Tests), bewusst
  **ohne** überladene Default-Variante, die den alten Aufruf weiter erlauben
  würde. Ein solcher Default wäre exakt der Mechanismus, der R-7 erst
  unentdeckt gelassen hat.
- Erhöhter RPC-Traffic bei sehr häufigen Mutationen (z. B. schnelles
  Nacheinander-Sammeln) — ein RPC pro Mutation statt gebatchter Updates.

### Mitigationen
- Kein Kompatibilitäts-Overload für `get_level()`/`get_xp()`: der Compiler/die
  Testsuite soll jeden nicht angepassten Call-Ort sichtbar brechen lassen,
  statt ihn über einen Default 1 stillschweigend weiterlaufen zu lassen.
- Batching (mehrere Mutationen pro Tick zu einem RPC zusammenfassen) ist eine
  spätere Optimierung, kein Launch-Blocker — der Push-Kontrakt selbst bleibt
  dabei unverändert (ein `_rpc_sync_*` pro betroffenem Client, nur ggf. mit
  mehreren Deltas im Payload).

## Ablösung

[Leer lassen bis dieser ADR durch einen neuen abgelöst wird]

## Umsetzungsstand (Round 49)

Option C umgesetzt, mit zwei bewussten Abweichungen vom ursprünglichen Entwurf:

1. **Ein generisches RPC statt drei separate.** Statt `_rpc_sync_inventory`/
   `_rpc_sync_xp`/`_rpc_sync_equipment` gibt es genau ein
   `NetworkBridge._rpc_receive_economy_update(kind: String, payload: Dictionary)`
   mit `kind` ∈ {"inventory", "skill", "equipment"} als Diskriminator, plus
   `send_economy_update(player_id, kind, payload)` auf der Sendeseite. Grund:
   der Transport-Teil (Guard-Logik: nicht senden ohne Peer, nicht senden an
   sich selbst, `@rpc("authority", …)`) ist für alle drei Domänen identisch —
   drei separate RPCs hätten dieselbe Guard-Logik dreifach dupliziert, ohne
   einen Unterschied im Kontrakt. Jeder Service interpretiert `payload` selbst
   (siehe `_on_economy_state_received()` in `InventorySystem`/`SkillSystem`/
   `EquipmentService`).
2. **Kein Breaking Change bei `SkillSystem.get_level()`/`get_xp()`.** Der
   Entwurf sah vor, den `player_id`-Default zu entfernen, damit nicht
   angepasste Call-Sites sichtbar brechen. Bei der Umsetzung war
   `player_id: int = 1` als Default bereits an beiden Methoden vorhanden
   (Multi-Tenancy-Konvention, konsistent mit `InventorySystem`/
   `EquipmentService` im gesamten restlichen Code) — ihn zu entfernen hätte
   nur diese zwei Methoden inkonsistent zum Rest der Codebase gemacht, ohne
   zusätzliche Sicherheit: **alle** tatsächlichen Call-Sites (`SkillPanelController`,
   `CombatSystem`, `QuestObjectiveHandler`) wurden ohnehin einzeln geprüft und
   übergeben `player_id` explizit — der Default greift nur noch dort, wo er
   schon vorher korrekt war (Tier-1-Solo-Pfad).

**Was NICHT Teil dieser Runde ist:** 3D-Visual-Replikation von Equipment über
Peers (`WeaponVisual3D` auf dem empfangenden Client) — der Rücksync
synchronisiert nur den Daten-State (`_equipped`), damit `EquipmentUIController`
korrekt aktualisiert. Ob/wie ein entferntes Visual auf jedem Client sichtbar
gerendert wird, ist ein separates, noch nicht untersuchtes Thema (Szenenbaum-
Replikation vs. eigener Rücksync-Kanal) — kein Blocker für dieses ADR, da UI-
Panels und Equipment-Daten bereits ohne dieses Stück korrekt sind.

**Fund während der Umsetzung, direkt im selben Round mitbehoben (R-8, eigener
TODO-Eintrag):** `CombatSystem.player_melee_damage(player_id)`/
`apply_weapon_on_hit()` lasen die Waffe über `_equipment.get_equipped_weapon()`
**ohne** `player_id` — anders als der danebenliegende
`_skill_system.get_level("combat", player_id)`-Aufruf in derselben Funktion,
der korrekt den Angreifer nutzte. Der Waffenbonus im Schaden kam dadurch
strukturell immer aus Spieler 1s Ausrüstung, unabhängig davon wer tatsächlich
zuschlägt. Kein Teil von R-7 selbst (das ist UI-Rücksync, nicht
Schadensberechnung) — daher eigener R-8-Eintrag statt Vermischung in diesem
ADR, aber trivial genug (identisches Muster, gleiche Datei, ein Call-Site-Fix
ohne Signaturänderung), um ihn nicht liegen zu lassen.

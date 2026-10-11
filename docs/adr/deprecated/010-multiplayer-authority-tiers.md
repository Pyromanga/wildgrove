> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-010: Multiplayer-Authority — Listen-Server/Dedicated-Server-Dualität auf Godots MultiplayerAPI

**Status:** Akzeptiert — vollständig umgesetzt durch Sprint F + G  
**Datum:** 2026-06  
**Kontext:** Beantwortet die in der externen Review (v39, Abschnitt 1.3) explizit geforderte Grundsatzentscheidung. Betrifft `ServiceOrchestrator`, `BootstrapConfig`, `NetworkContract.gd`, `INetworkAdapter`/`LocalNetworkAdapter` (vollständig entfernt, ADR-007 gelöscht), sowie alle server-autoritativen Services: `InventorySystem`, `QuestService`, `SkillSystem`, `EntityOrchestrator`, `PlayerStateService`, `CombatSystem`. Ergänzt ADR-004 und ADR-009. **Löst ADR-007 ab.**

---

## Problem

Die externe Review (Abschnitt 1) hat mit Datei:Zeile belegt, dass die gesamte "Server-autoritativ"-Erzählung (ADR-004, ADR-007, ADR-009, `NetworkContract.gd`) ein MMORPG beschreibt, während jede konkrete Code-Entscheidung darunter für genau einen lokalen Client mit genau einer Welt gebaut ist:

- `ServiceOrchestrator.gd:32-34` hält genau eine `_session_registry` und ein einziges `_session_active`-Bool.
- `InventorySystem.gd:19` hält `_items: Dictionary` als flaches Dict — kein `player_id`-Schlüssel.
- `PlayerStateService.gd:15` hält `_current: State` als einzigen Zustand, nicht pro Spieler.
- `LocalNetworkAdapter.is_server()` (Zeile 81-82) gibt unbedingt `true` zurück — der einzige heute existierende Build hält sich selbst für den Server.
- Im gesamten Projekt kommt `MultiplayerAPI`/`multiplayer_authority`/`rpc(` **kein einziges Mal** vor (verifiziert per Grep über alle `.gd`-Dateien, Stand v39/Session 7).

Die Review (Abschnitt 1.3) fordert, explizit zu entscheiden: bleibt das Spiel Singleplayer/Hosted-Coop, oder wird es ein echtes Server-Farm-MMO? Diese Formulierung als binäre Wahl ist selbst eine Vereinfachung, die zu unnötig teuren Konsequenzen führen würde — sie unterstellt, "Hosted Coop" und "dedizierte Server" bräuchten unterschiedliche Codebasen. Das ist nicht der Fall: Valheim, Minecraft und Terraria lösen genau dieses Problem mit einem einzigen, etablierten Architekturmuster — **Listen-Server/Dedicated-Server-Dualität**. Derselbe Code läuft in drei Rollen, nicht in drei Codebasen.

Unabhängig von dieser Frage gilt: Solange `InventorySystem` und `PlayerStateService` strukturell auf genau einen Spieler gebaut sind, bricht das nicht erst bei MMO-Skala, sondern beim **zweiten Freund**, der einer Hosted-Coop-Welt beitritt — und zwar unabhängig davon, ob danach je ein dedizierter Server existiert.

---

## Optionen

### Option A: `INetworkAdapter`-Abstraktion (Status quo, ADR-007) beibehalten, Adapter beim "Netzwerk-Sprint" tauschen

`request_*()` bleibt gegen `INetworkAdapter.send_request()` programmiert; `LocalNetworkAdapter` wird irgendwann durch einen `ServerNetworkAdapter` ersetzt.

- ✅ Kein zusätzlicher Migrationsaufwand jetzt
- ❌ Löst die eigentliche Blockade nicht: `INetworkAdapter` trennt nur `request_*()`/`on_*_confirmed()` voneinander, sagt aber nichts darüber, **wer** die Autorität ist und **wie** State pro Spieler getrennt wird (Review 1.2)
- ❌ Baut auf Dauer eine Parallel-Implementierung von etwas, das Godots eingebaute `MultiplayerAPI` (Peer-IDs, `multiplayer_authority`, RPC-Routing, `MultiplayerSynchronizer`) bereits liefert — ohne deren eingebaute Vorteile (Authority-Prüfung, Replikation) je zu nutzen
- ❌ Der in ADR-007 versprochene "nur den Adapter tauschen"-Migrationspfad adressiert nicht das strukturelle Single-Tenant-Problem aus Review 1.1 — ein Tausch von `LocalNetworkAdapter` zu `ServerNetworkAdapter` ändert nichts an `_items: Dictionary` ohne `player_id`-Schlüssel

### Option B: Vollständige Server-Farm-Architektur jetzt (Simulationsschicht ohne SceneTree, N Sessions pro Prozess, dediziertes Sharding)

- ✅ Korrekt für ein klassisches MMORPG mit tausenden gleichzeitigen Spielern in unabhängigen Welten/Shards in einem Serverprozess
- ❌ Massiver Overhead, der nichts mit dem nächsten konkreten Ziel (zweiter Spieler in Hosted Coop) zu tun hat
- ❌ Das Zielkonzept des Spiels (Coop-Exploration, Farming, Village-Aufbau) braucht kein serverseitiges Multi-World-Sharding in einem Prozess — klassische MMORPGs nutzen dafür separate Welt-Server-Prozesse, nicht N Welten in einem Prozess
- ❌ Würde ADR-009 (App-/Character-/World-Scope-Architektur) nicht erweitern, sondern grundlegend ablösen — genau die Migrationskostenexplosion, vor der Review 1.1 warnt (`ServiceOrchestrator`, `ServiceValidator`, `ServiceDependencyResolver`, `ServiceInitializer`, `ServiceInstaller` müssten für Multi-Session-pro-Prozess umgebaut werden)

### Option C: Listen-Server/Dedicated-Server-Dualität auf Godots `MultiplayerAPI` — ein Prozess = eine Welt = eine Session (gewählt)

Drei Rollen, ein Code-Pfad. Autorität wird zur Laufzeit-Eigenschaft (`multiplayer_authority`), nicht zur Build-Zeit-Adapter-Wahl. Voraussetzung: Session-Services trennen ihren internen State pro Spieler (s. Entscheidung, Punkt 3) — unabhängig davon, ob je ein echtes Netzwerk existiert.

- ✅ Nutzt Godots eingebaute Authority-/RPC-Infrastruktur statt sie nachzubauen
- ✅ "Solo" wird zum Trivialfall (kein Peer gesetzt), keine separate Code-Pfad-Familie
- ✅ Beantwortet Review 1.3, ohne einen Server-Farm-Umbau zu erzwingen
- ⚠️ Erfordert eine Vorab-Investition (Multi-Tenanz der Session-Services), bevor irgendein RPC verdrahtet wird

---

## Entscheidung

**Option C.**

### Die drei Tiers (eine Codebasis, drei Rollen)

| Tier | Wer ist Autorität | Lokaler Spieler? | Validierung in `on_*_confirmed()` |
|---|---|---|---|
| **Tier 1 — Solo** | Man selbst (kein `MultiplayerPeer` gesetzt) | Ja | Trivialfall — keine echte RPC-Strecke nötig |
| **Tier 2 — Hosted Coop** | Host-Client (`ENetMultiplayerPeer`, `create_server()`) | Ja — Host ist gleichzeitig Spieler *und* Autorität | Locker — Host vertraut seinen Freunden |
| **Tier 3 — Dedizierter Server** | Headless-Instanz | Nein | Streng — Server vertraut niemandem |

Tier 1 ist der Trivialfall von Tier 2/3 (kein Peer gesetzt), kein separater Code-Pfad. Wer die Autorität betreibt (eigener PC vs. dediziertes Hosting) und wie streng validiert wird, ist eine **Deployment-Konfiguration**, kein Architektur-Fork.

### Was sich konkret ändert

1. **`NetworkContract.gd`/ADR-004 bleibt als Vokabular-Vertrag bestehen.** `request_*()` und `on_*_confirmed()` sind weiterhin die richtigen Namen — das Vokabular war laut externer Einschätzung von Anfang an richtig. Aber: `request_*()` muss ab jetzt direkt gegen Godots `MultiplayerAPI` gebaut werden (`rpc_id(get_multiplayer_authority(), ...)`, `on_*_confirmed()` als `@rpc("authority")`-Handler) — **nicht** gegen einen `INetworkAdapter`, der "später ersetzt" wird.
2. **ADR-007 (`INetworkAdapter`/`LocalNetworkAdapter`) wird durch dieses ADR abgelöst.** Status in `docs/adr/007-network-adapter.md` wird auf "Abgelöst von ADR-010" gesetzt. `INetworkAdapter.gd`/`LocalNetworkAdapter.gd` werden im Migrationsschritt entfernt, nicht weitergepflegt.
3. ~~**Voraussetzung vor jeder RPC-Verdrahtung: Session-Services trennen ihren internen State pro Spieler**~~ ✅ **Erledigt in Sprint F4.** `InventorySystem`, `PlayerStateService` und `QuestService` halten State als `{ peer_id: ... }`-Dictionary mit `_ensure_player(peer_id)`-Lazy-Init. `EntityOrchestrator` vergibt UUIDs peer-unabhängig. `CombatSystem`-Krit-Würfe sind server-autoritativ via `is_multiplayer_authority()`-Guard. Diese Zeilen beschreiben den Stand **vor** Sprint F4 — das ADR wurde nicht zeitgleich aktualisiert. Reviewers: Punkt 3 ist **kein offenes TODO** mehr.
4. **ADR-009 (Global-/Session-Registry) bleibt vollständig gültig und wird NICHT abgelöst.** Klarstellung, die hiermit Teil der Architektur wird: *"Ein Prozess = eine Welt = eine Session"* ist eine bewusste Entscheidung dieses ADR, keine zufällige Einschränkung. das Spiel skaliert — falls je nötig — über mehrere unabhängige Serverprozesse (ein Prozess pro Welt/Shard), nicht über N Sessions in einem Prozess. Das nimmt der in Review 1.1 befürchteten Migrationskostenexplosion die Grundlage: diese Umstellung wird nicht gebraucht.
5. **Anti-Cheat (Tier 2 vs. Tier 3)** wird ausschließlich über die Validierungsstrenge in `on_*_confirmed()` gelöst, nicht über zwei Code-Pfade (s. Tabelle oben).
6. **Save-System (ADR-005, `ISaveProvider`) bleibt unverändert.** Lokal: `user://saves/*.json`. Dedizierter Server: später eine zweite `ISaveProvider`-Implementierung (DB-Backing) — kein Redesign.
7. **Headless-Server-Build-Pfad** (Tier 3: `--headless`, kein Rendering) ist ein expliziter, aber zurückgestellter Punkt dieses ADR. Er wird erst gebraucht, wenn Tier 3 tatsächlich gebaut wird — nicht für Tier 2, wo der Host ohnehin rendert.

### Spawn-Replikation (Sprint F — Konkretisierung)

`MultiplayerSpawner` repliziert Server-seitig gespawnte Entities an verbundene Clients.
Da das Projekt Entities via `GDScript.new()` instanziiert (kein `.tscn`-Workflow),
schlägt `add_spawnable_scene()` zur Laufzeit fehl — es akzeptiert ausschließlich `.tscn`-Pfade.

**Entscheidung gegen `.tscn`-Wrapper:** 8 leere Wrapper-Szenen nur für den Spawner wären
Architektur-Fremdkörper, die jedes Mal manuell synchron gehalten werden müssten wenn ein
Entity-Typ hinzukommt oder umbenannt wird.

**Gewählter Weg:** `MultiplayerSpawner.spawn_function` / `despawn_function` (Custom Callables).
- `spawn_function(data: Variant) -> Node`: empfängt den script_path-String des Servers,
  löst ihn via `EntityRegistry.get_path_to_type_map()` zu einem `type_id` auf,
  ruft `EntityRegistry.instantiate(type_id)` auf. Kein `on_spawn()`, kein UUID-Tracking —
  State-Sync läuft via `MultiplayerSynchronizer`.
- `despawn_function(node: Node)`: ruft `node.queue_free()` auf. Server führt die
  autoritative UUID-Buchführung; Clients brauchen nur den Node zu entfernen.

Die Path-Map wird einmalig beim `_setup_multiplayer_spawner()`-Aufruf gebaut
(`EntityRegistry.get_path_to_type_map()`), nicht bei jedem Spawn-Vorgang. Neue Entity-Typen
werden automatisch erfasst sobald sie in `WorldEntityRegistry.register_all()` registriert sind —
kein separater Spawner-Eintrag nötig.

**Sync-Richtung:** Ein einzelner `MultiplayerSynchronizer` auf einem Node sendet immer
vom Autoritäts-Peer zu allen anderen. Authority wird in `EntityOrchestrator.spawn_entity()`
nach `add_child()` und vor `on_spawn()` gesetzt — der Synchronizer (erstellt in `on_spawn()`)
arbeitet damit von Anfang an mit der korrekten Authority. Player-Sync: 20 Hz.
Server-Entity-Sync (EnemyNPC): 10 Hz.

### Reihenfolge (was zuerst)

1. ~~Multi-Tenanz der Session-Services (Punkt 3)~~ ✅ Erledigt Sprint F4.
2. ~~RPC-Verdrahtung / ENet-Infrastruktur (SessionManager, NetworkBridge)~~ ✅ Erledigt Sprint B–F.
3. ~~Multiplayer-Stabilität: Reconnect, ChunkManager multi-player-aware, Interpolation~~ ✅ Erledigt Sprint G.
4. Tier 3 (dedizierter, headless Server) — erst wenn Tier 2 (Hosted Coop) in echter Umgebung nachweislich stabil läuft.

Der konkrete Migrationsplan (Reihenfolge im Detail, betroffene Dateien, Aufwand pro Schritt) ist Gegenstand eines separaten Dokuments: [`docs/MIGRATION-010.md`](../MIGRATION-010.md).

---

## Konsequenzen

### Positiv
- Beantwortet Review 1.3 explizit, ohne einen Server-Farm-Umbau zu erzwingen, den keines der vier Genre-Vorbilder braucht.
- ADR-009 bleibt vollständig gültig — keine der in Review 1.1 (letzter Absatz) befürchteten Migrationskosten materialisiert sich.
- `request_*()`/`on_*_confirmed()` (ADR-004) bleibt als Naming-Konvention erhalten — kein Methoden-Rename nötig, nur die Implementierung darunter wechselt von `INetworkAdapter` zu Godot-RPC.
- Löst implizit auch die zwei in Review 1.2 belegten Lecks: UUID-Vergabe (`EntityOrchestrator`) und Krit-Würfe (`CombatSystem.roll_critical`) werden durch `@rpc("authority")`-Bindung strukturell auf die Autorität beschränkt, statt nur als Kommentar dokumentiert zu sein.
- Der Multi-Tenanz-Fix (Punkt 3) ist für Tier 1 folgenlos (ein Spieler = ein Schlüssel im Dictionary), aber Voraussetzung für Tier 2 — kein verschwendeter Aufwand.

### Negativ / Risiken
- `INetworkAdapter`/`LocalNetworkAdapter` (ADR-007) wird verworfen — der Sprint-3/4-Aufwand für die Adapter-Schicht (`InventorySystem`, `QuestService`, `SkillSystem` migriert) wird nicht weiterverwendet; die `request_*()`-Bodies werden ein zweites Mal angefasst, diesmal gegen RPC statt gegen `INetworkAdapter`.
- Godots `MultiplayerAPI` bindet Authority-Konzepte (`multiplayer_authority`, `rpc_id()`) typischerweise an `Node`. Session-Services sind laut ADR-003 bewusst `RefCounted` (`Service`), nicht `Node`. Diese Reibung muss im Migrationsplan konkret gelöst werden (z. B. ein dünner `Node`-Wrapper pro Service, der nur RPCs empfängt und an den `RefCounted`-Service weiterreicht).
- Kein dedizierter Headless-Build-Pfad existiert noch — Tier 3 bleibt bis zu seiner tatsächlichen Umsetzung eine dokumentierte Absicht, kein Code.

### Mitigationen
- `NetworkContract.gd` wird im Migrationsschritt aktualisiert: Authority-Matrix bleibt inhaltlich, der Implementierungshinweis wechselt von "`INetworkAdapter`" zu "Godot RPC / `multiplayer_authority`".
- `CONTRIBUTING.md` Abschnitt 2.3 wird im Migrationsschritt aktualisiert (referenziert aktuell `INetworkAdapter`, Zeilen 151/196).
- Die `Node`-Wrapper-Frage wird als erster Punkt des Migrationsplans behandelt, nicht nachträglich entdeckt.

---

## Ablösung

Dieses ADR löst **ADR-007** ab.

Es wird selbst abgelöst, sobald Tier 3 tatsächlich gebaut wird und sich dabei zeigt, dass "ein Prozess = eine Welt" nicht mehr ausreicht (z. B. weil Hosting-Kosten pro Welt-Prozess unwirtschaftlich werden). Zu diesem Zeitpunkt wäre ein eigener ADR für "N Sessions pro Serverprozess" fällig — mit genau den in Review 1.1 beschriebenen Migrationskosten für `ServiceOrchestrator`/`ServiceValidator`/`ServiceDependencyResolver`. Bis dahin gilt: nicht gebraucht, nicht gebaut.

---

## Update (Round 55)

Tier 3 (dedizierter, headless Server) wurde umgesetzt — mit einer bewussten Abweichung von der oben stehenden "Reihenfolge"-Bedingung (Punkt 4), die hier dokumentiert wird, statt sie stillschweigend zu übergehen.

**Abweichung von der Reihenfolge-Bedingung.** Die ursprüngliche Bedingung ("erst wenn Tier 2 in echter Umgebung nachweislich stabil läuft") bezog sich auf reale Feldvalidierung von Client-Performance unter Last (Geräte-Grenzmessung, siehe Round 52 — physisch blockiert, da diese Sandbox keinen Zugriff auf reale Zielhardware hat). Diese Messung steht weiterhin aus. Der Projekt-Owner hat entschieden, die Sequenzierung dennoch zu überschreiben: die Tier-3-Code-Pfade (Boot-Verhalten, Autoritäts-Härtung) sind unabhängig von Client-seitiger Geräte-Performance korrekt oder falsch — sie lassen sich per Zwei-Prozess-CI (`IT03Harness`-Muster) prüfen, ohne die ausstehende Feldmessung. Was durch das Überschreiben **nicht** gedeckt ist: eine produktive Tier-3-Bereitstellung unter realer Netzwerklast bleibt bis zur Geräte-Grenzmessung unvalidiert — dieses Risiko wird hiermit bewusst in Kauf genommen, nicht wegargumentiert.

**Strukturelle Lücke, die beim Bauen sichtbar wurde.** ADR-009s Session-Modell setzt voraus, dass jede Session genau einen lokal spielenden Charakter hat (`BootPipeline.boot_character()` lädt immer einen `player_id`-gebundenen Save). Ein dedizierter Server hat keinen spielenden Menschen, braucht aber trotzdem eine dauerhafte Welt-Session (Terrain-Harvest-Zustand, Quest-Fortschritt — geteilter Zustand über alle verbindenden Spieler hinweg, unabhängig von jedem Einzelnen). Lösung: eine reservierte, echte (nicht simulierte) Save-Identität `SessionManager.DEDICATED_SERVER_WORLD_ID`, die denselben `boot_character()`-Pfad durchläuft wie jeder andere Charakter — kein Sonderfall in der Persistenz-Schicht, nur ein anderer `player_id`-Wert. Einzige Abweichung: `WorldSpawner.spawn_all(..., spawn_local_player=false)` überspringt das Spawnen eines Player-Entities für diese Session — die Welt existiert, aber niemand spielt sie lokal.

**Umsetzungsstand:**
- `SessionManager.enable_dedicated_server_mode()` / `is_dedicated_server()` — Deployment-Flag, kein zweiter Code-Fork (`create_server()` unverändert für Tier 2 und 3).
- `DedicatedServerBootstrap.gd` (Autoload) — Cmdline-gated (`--dedicated-server`), bootet Host + reservierte Welt-Session, fail-fast bei Hosting-Fehlern (`get_tree().quit(1)`).
- `WorldSpawner.spawn_all()` — `spawn_local_player`-Parameter, Default `true` (Tier 1/2 unverändert).
- `export_presets.cfg` — Preset "Linux Dedicated Server" (`dedicated_server=true`).
- `InventorySystem.on_item_add_confirmed()` — Slot-/Gewichtslimit als Verteidigung in der Tiefe direkt an der Mutationsstelle, nicht nur in `request_add_item()` (Tier-3-Prinzip "Server vertraut niemandem").
- Die im "Negativ/Risiken"-Abschnitt oben beschriebene `Node`-Wrapper-Frage war bereits vor dieser Runde gelöst (`NetworkBridge extends ServiceNode` als zentraler RPC-Dispatch für alle `RefCounted`-Services) — nur nicht als solche dokumentiert; siehe `docs/MIGRATION-010.md` "Korrektur Round 55".

**Bewusst nicht Teil dieser Runde:**
- Kein CI-Job, der den "Linux Dedicated Server"-Export tatsächlich baut/deployed — der Export-Preset existiert, ein automatisierter Build dafür nicht.
- Keine Lastvalidierung mit mehreren realen Clients gegen eine echte Tier-3-Instanz (s.o. — bleibt offen bis zur Geräte-Grenzmessung aus Round 52).
- Kein Admin-/Ops-Tooling (Server-Restart, Graceful-Shutdown-Signal-Handling, Monitoring) — reiner Boot-Pfad, kein Betriebs-Werkzeug.

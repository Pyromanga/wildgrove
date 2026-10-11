> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-018: SystemEvents nach Domain aufsplitten

**Status:** Umgesetzt (Runde 5)
**Datum:** 2026-07
**Kontext:** `scripts/eventbus/SystemEvents.gd`, `EventBus.gd`, `IEventBus.gd`,
`EventBusAdapter.gd`, `MockEventBus.gd`, plus alle Consumer aus Persistence-,
Session- und Networking-Domain. Ergänzt [ADR-002](002-eventbus-namespacing.md)
(typisierte Namespaces) und [ADR-016](016-domain-first-restructure.md)
(Domain-First-Umbau).

---

## Problem

`EventBus.gd` dokumentiert seine eigene Regel selbst: neue Events gehören in
eine `*Events.gd` in der jeweiligen Fach-Domain, nicht in den domänenlosen
`eventbus/`-Ordner. `PlayerEvents`, `WorldEvents`, `QuestEvents` und `UIEvents`
halten sich daran. `SystemEvents` nicht: es bündelte vier fachlich unabhängige
Bereiche in einer Datei —

- Save/Load (`save_started`, `save_requested`, `save_pre_flush`, `save_completed`,
  `save_slot_deleted`, `load_started`, `load_completed`)
- Session-Lifecycle (`session_requested`, `session_ready`, `session_unloaded`)
- Netzwerk-Lifecycle (`host_game_requested`, `join_game_requested`,
  `hosting_started`, `joined_as_client`, `connection_to_server_failed`,
  `network_peer_disconnected`)
- App-Lifecycle (`state_changed`, `setting_changed`, `boot_failed`,
  `services_initialized`) — das einzige davon, das tatsächlich domänenlos ist.

Für die ersten drei existiert längst ein eigener Domain-Ordner
(`scripts/persistence/`, `scripts/session/`, `scripts/networking/`, jeweils mit
eigenem Service — `SaveSystem`/`GameSaveService`, `SessionManager`,
`NetworkBridge`). `SystemEvents.gd` entstand vor ADR-016 und wurde beim
Domain-First-Umbau nicht mitgezogen — derselbe Fehler-Typ, den auch
`_find_local_player_visuals()` in ADR-015 zeigte: ein Name, der eine
Eigenschaft verspricht (hier: "das ist System-weit"), die die Datei nicht mehr
für alle ihre Inhalte einlöst.

## Entscheidung

`SystemEvents` in vier Namespaces aufgeteilt:

| Namespace | Datei | Signale |
|---|---|---|
| `EventBus.persistence` | `scripts/persistence/PersistenceEvents.gd` | Save/Load |
| `EventBus.session` | `scripts/session/SessionEvents.gd` | Session-Lifecycle |
| `EventBus.networking` | `scripts/networking/NetworkingEvents.gd` | Netzwerk-Lifecycle |
| `EventBus.system` | `scripts/eventbus/SystemEvents.gd` (bleibt) | App-Lifecycle (domänenlos) |

`IEventBus`/`EventBusAdapter`/`MockEventBus` bekamen je drei neue
Accessor-Methoden (`persistence()`, `session()`, `networking()`) nach demselben
Muster wie die bestehenden (`player()`, `world()`, `system()`, `ui()`,
`quest()`). Kein neues Infrastruktur-Konzept — dieselbe Struktur, nur mehr
Instanzen davon.

Alle bisherigen Consumer (`SaveSystem`, `GameSaveService`, `WorldService`,
`SessionManager`, `MainMenuController`, `PauseMenuController`,
`ServiceOrchestrator`, `GameManager`, `HUDManager`) wurden auf den jeweils
richtigen Namespace umgestellt. `state_changed`/`setting_changed`/
`boot_failed`/`services_initialized` blieben unverändert auf `system()` —
`PlayerStateService`s Nutzung von `state_changed` (GameState PLAYING/PAUSED)
ist die domänenlose App-Lifecycle-Variante und war nie Teil dieses Splits.

## Konsequenzen

- ✅ Alle fünf Event-Domains folgen jetzt derselben Regel wie ihre
  Ordner-Domains (siehe `EventBus.gd`-Kommentar).
- ✅ Keine neue API-Form — Consumer rufen `_bus.persistence().emit_save_requested()`
  statt `_bus.system().emit_save_requested()`, sonst identisch.
- ⚠️ Breaking Change für jeden Code außerhalb dieses Repos, der
  `EventBus.system.save_requested` o. ä. direkt referenziert — betrifft hier
  niemanden, da es keine externen Konsumenten gibt.
- Kein Einfluss auf ADR-015 (Per-Player Interaction State) — beide Änderungen
  sind unabhängig, wurden in derselben Runde umgesetzt, weil die Feedback-Runde
  beide zusammen priorisiert hat.

## Bewusst nicht behoben

Die im selben Feedback genannten fehlenden Event-Kategorien (Chat/Trading
zwischen Spielern, `weather_changed`, `player_killed_by_player`,
Achievement-Events) sind funktionale Lücken, keine Struktur-Lücken — sie
gehören zu neuen Features, nicht zu diesem Refactor, und sind hier bewusst
nicht angelegt. **Update:** `weather_changed` wurde in Round 95 nachgezogen
(ADR-041), `player_killed_by_player` in Round 98 (ADR-036 „Umsetzungsstand
(Round 98)", `EventBus.combat`). Trading zwischen Spielern siehe ADR-035
(Round 89). Chat zwischen Spielern siehe ADR-043 (Round 99, `ChatService`
— bewusst als eigener Service mit eigenem Signal statt als weiterer
EventBus-Namespace, siehe dortige Begründung). Achievement-Events bleiben
offen — es bräuchte vor jedem Event-Namespace erst ein tatsächliches
Achievement-System (Definitionen, Trigger, Persistenz), das im Projekt noch
nicht existiert (0 Treffer im Code), siehe TODO-Punkt.

## Update (Runde 53) — SessionManager-Rest geschlossen

`TODO-offene-probleme.md` trackte seit ADR-018 einen Rest: `SessionManager`
emittierte zusätzlich zu den `EventBus.networking()`-Events acht eigene, rohe
Godot-Signale (`peer_joined`, `peer_left`, `peer_cleanup_requested`,
`server_started`, `client_connected_to_server`, `client_connection_failed`,
`server_connection_lost`, `retry_attempt`) — Doppel-Emission für denselben
Sachverhalt. Zwei Consumer verbanden sich direkt auf die Service-Instanz statt
über den Bus: `WorldService` (`_session_manager.peer_cleanup_requested`,
raw Connect) und `ServiceOrchestrator` (`sm.client_connected_to_server`,
raw Connect nach `boot_app()`, weil die Instanz erst dann im Registry stand).

**Fix:**
- `NetworkingEvents.gd` bekam vier neue Signale + `emit_*()`-Methoden:
  `peer_joined`, `peer_left`, `peer_cleanup_requested`, `retry_attempt`.
  Die anderen vier hatten bereits ein Äquivalent (`server_started` →
  `hosting_started`, `client_connected_to_server` → `joined_as_client`,
  `client_connection_failed` → `connection_to_server_failed`,
  `server_connection_lost` → `network_peer_disconnected`).
- `SessionManager.gd`: alle acht eigenen `signal`-Deklarationen entfernt.
  Jeder Emissionspunkt läuft jetzt ausschließlich über
  `_bus.networking().emit_*()`, konsistent guarded mit
  `is_instance_valid(_bus)` (vorher inkonsistent — manche Stellen hatten
  gar keinen Guard, andere brauchten keinen weil sie eigene Signale waren).
- `WorldService.on_ready()`/`on_cleanup()`: Connect/Disconnect auf
  `_bus.networking().peer_cleanup_requested` statt auf die
  `_session_manager`-Instanz — identisches Muster zu den bereits
  bestehenden `_bus.world()`/`_bus.persistence()`-Connects im selben Service.
- `ServiceOrchestrator`: `_connect_session_manager()` entfernt.
  `EventBus.networking.joined_as_client.connect(_on_client_connected)` läuft
  jetzt direkt in `_ready()`, zusammen mit den beiden anderen BUG-23-Connects
  — das war vorher nicht möglich, weil der Connect an die SessionManager-
  Service-Instanz gebunden war (existiert erst nach `boot_app()`);
  `EventBus.networking` ist ein AutoLoad und existiert schon vorher.
- `test_session_manager.gd`: `before_each()` injiziert jetzt `MockEventBus`;
  alle Signal-Assertions laufen über `_bus.networking()` statt über `_sm`
  selbst. Neuer Regressionstest `test_peer_disconnected_without_event_bus_does_not_crash()`
  für den jetzt echten "kein Crash ohne Bus"-Vertrag.

**Ergebnis:** `SessionManager` hat keine eigenen Lifecycle-Signale mehr —
jeder Cross-Service-Consumer geht über `EventBus.networking()`, wie es die
Domain-Regel aus `EventBus.gd` seit ADR-002/016 für alle anderen Namespaces
bereits verlangt. Kein direkter Service-zu-Service-Signal-Connect mehr im
gesamten `scripts/session/`/`scripts/world/`/`scripts/platform/`-Dreieck.

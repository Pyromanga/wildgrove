> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-042: An-alle-Peers-Broadcast-Mechanismus

**Status:** Angenommen — umgesetzt (Round 96)
**Datum:** 2026-07
**Kontext:** In [ADR-035](035-trading.md) ("Live-Broadcast bei Auktionshaus-
Änderungen", bewusst zurückgestellt) und erneut in
[ADR-041](041-weather-events.md) (Wetter-Events, Option A verworfen) als
fehlende Infrastruktur dokumentiert: **das Projekt hatte keinen
"an-alle-aktuell-verbundenen-Peers"-Broadcast-Kanal.** Jeder bisherige
Server→Client-Sync-Weg (`NetworkBridge.send_economy_update_for_player()`,
`send_zone_update_for_peer()`, `_rpc_receive_initial_state`) adressiert genau
einen Ziel-Peer. Dieses ADR schließt die Lücke als eigenständigen
Infrastruktur-Schritt, ohne selbst einen konkreten Konsumenten zu liefern —
Wetter bleibt bewusst beim deterministischen Wurf aus ADR-041 (siehe
"Verhältnis zu ADR-041" unten).

## Problem

Ohne diesen Mechanismus muss jedes künftige Feature, das eine Nachricht an
ALLE Spieler gleichzeitig schicken will (Auktionshaus-Live-Updates,
Server-Ankündigungen, künftige PvP-/Achievement-Broadcast-Events aus dem
TODO-Punkt "🟡 Fehlt komplett"), entweder selbst eine Peer-Iteration
nachbauen oder auf eine Krücke wie "jeder Client pollt periodisch" ausweichen.

## Entscheidung

`NetworkBridge.broadcast_to_all_peers(kind: String, payload: Dictionary)` —
generischer Sender, folgt exakt demselben Muster wie
`send_economy_update_for_player()`/`send_zone_update_for_peer()` (R-7/ADR-030),
nur mit einer Peer-Iteration statt Einzel-Ziel:

- Läuft nur auf der Autorität (`_has_peer() and multiplayer.is_server()`),
  sonst No-Op — analog zu jedem bisherigen `send_*()`.
- Iteriert über `get_all_joined_peer_ids()` — eine neue Fassade auf
  `SessionManager.get_all_slots().keys()` — **nicht** über
  `multiplayer.get_peers()`. Begründung: `get_peers()` enthält auch frisch
  ENet-verbundene Peers, die ihren Join-Handshake
  (`SessionManager._rpc_join_handshake`) noch nicht abgeschlossen haben — ein
  RPC an so einen Peer liefe ins Leere, weil dessen Session noch nicht
  gebootet ist. Derselbe Boot-Race-Grund, aus dem `_on_peer_connected()`
  schon bisher keinen Snapshot direkt verschickt, sondern auf den
  Client-Request wartet (E-4).
- Die Autorität selbst nimmt NICHT an ihrem eigenen Broadcast teil (ihr
  lokaler State ist bereits direkt mutiert, bevor sie broadcastet) — exakt
  dieselbe Konvention wie bei `send_zone_update_for_peer()`.
- Empfangsseite: `_rpc_receive_broadcast_event(kind, payload)`,
  `@rpc("authority", "call_remote", "reliable")` — Godot verweigert den
  Aufruf für jeden Nicht-Autorität-Sender bereits auf Transport-Ebene, kein
  zusätzlicher Guard nötig (analog `_rpc_receive_economy_update()`). Reicht
  nur durch an das neue Signal `broadcast_event_received(kind, payload)` —
  kind-spezifische Anwendung ist Sache der jeweiligen Konsumenten-Services,
  genau wie bei `economy_state_received`.

## Optionen (verworfen)

- **Eigener neuer RPC pro Broadcast-Typ** (statt generischem
  `kind`/`payload`-Umschlag) — verworfen: hätte für jeden künftigen
  Broadcast-Konsumenten (Auktionshaus, PvP-Events, Achievements, …) einen
  eigenen `@rpc`-Handler in `NetworkBridge` verlangt, obwohl der Transport-
  und Guard-Code identisch wäre. Der generische Umschlag ist exakt das
  Muster, das `_rpc_receive_economy_update()`/`economy_state_received` für
  die 1:1-Adressierung bereits erfolgreich etabliert hat.
- **`multiplayer.get_peers()` statt `get_all_joined_peer_ids()`** —
  verworfen wegen der oben beschriebenen Boot-Race (RPC an einen Peer ohne
  gebootete Session).

## Verhältnis zu ADR-041 (Wetter)

`WeatherService`/`WorldService` bleiben **unverändert** bei ihrem
deterministischen Wurf aus `world_seed + day_count` (kein Netzwerk-Traffic).
ADR-041 hatte diesen Broadcast-Mechanismus bereits als mögliche künftige
Option genannt, falls er "für andere Zwecke gebaut wird" — das ist mit
diesem ADR jetzt der Fall. Eine Umstellung von Wetter auf
`broadcast_to_all_peers()` ist bewusst NICHT Teil dieser Runde: der
deterministische Wurf hat keinen der Nachteile, die dieser Mechanismus löst
(kein Sync-Bedarf für spät joinende Clients, siehe unten), ein Wechsel wäre
reiner Mehraufwand ohne Nutzen für dieses konkrete Feature.

## Konsequenzen

### Positiv
- Erste generische Infrastruktur für "an alle Spieler gleichzeitig" —
  künftige Features (Auktionshaus-Live-Updates aus ADR-035, PvP-/
  Achievement-Events aus dem TODO-Punkt) brauchen keinen eigenen
  Transport-Code mehr, nur einen `kind`-String + `payload`-Dictionary und
  einen `broadcast_event_received`-Listener.
- Kein neuer Netzwerk-Angriffsvektor: `_rpc_receive_broadcast_event` ist
  reiner Empfang (`@rpc("authority", …)`), kein `any_peer`-Handler, kein
  neuer client-fälschbarer State.
- Folgt exakt etablierten Konventionen (`send_*()`-Guard-Reihenfolge,
  `_rpc_receive_*()`-Authority-Guard) — kein neues Muster zu lernen für
  jemanden, der `send_economy_update_for_player()` bereits kennt.

### Negativ / Risiken
- **Kein Sync-Pfad für spät joinende Clients.** Ein Client, der nach einem
  Broadcast verbindet, sieht den aktuellen Stand erst beim nächsten
  Broadcast — jeder Konsument, der das braucht, muss seinen Zustand
  zusätzlich in den initialen State-Snapshot einhängen
  (`_rpc_client_requests_initial_state()`/`SaveSystem.get_full_state()`),
  analog zum bereits bestehenden Einzel-Sync-Pfad. Bewusst nicht Teil dieser
  Runde (siehe unten) — reine Infrastruktur, kein konkretes Feature, das
  diesen Bedarf schon hätte.
- Kein Delivery-Garantie-Unterschied zu Einzel-RPCs: bei N verbundenen
  Peers sind das N einzelne `rpc_id()`-Aufrufe, kein echtes
  Multicast-Primitive auf ENet-Ebene — für die aktuelle Spielergröße
  (`MAX_CLIENTS = 8`) unproblematisch, könnte bei sehr viel größeren
  Spielerzahlen relevant werden.

## Bewusst nicht Teil dieser Runde

- Kein konkreter Konsument (Auktionshaus-Live-Broadcast, PvP-/Achievement-
  Events) — reine Infrastruktur, siehe Kontext oben.
  **Update Round 97:** der Auktionshaus-Konsument ist jetzt umgesetzt, siehe
  [ADR-035 „Umsetzungsstand (Round 97)"](035-trading.md). Dort auch die
  Klärung, warum der Late-Join-Sync-Punkt (nächster Absatz) für diesen
  konkreten Konsumenten bereits durch den bestehenden Pull-Pfad
  (`request_listings_snapshot()`) abgedeckt ist, statt einen neuen
  Sync-Baustein zu brauchen. **Update Round 98:** PvP-Kill-Feed
  (`player_killed_by_player`) ebenfalls umgesetzt, siehe
  [ADR-036 „Umsetzungsstand (Round 98)"](036-pvp-death-loss.md).
  Achievement-Events bleiben offen — es gibt im Projekt noch kein
  Achievement-System überhaupt (keine Definitionen, keine Trigger, keine
  Persistenz), ein Broadcast-Konsument dafür wäre verfrüht, solange das
  fehlt. **Update Round 99:** der globale Kanal von `ChatService` (ADR-043)
  nutzt `broadcast_to_all_peers()` ebenfalls — der Whisper-Kanal dagegen
  bewusst NICHT (siehe ADR-043 „Optionen (verworfen)" — private Nachrichten
  gehören nicht in einen an-alle-Peers-Broadcast).
- Kein Sync-Pfad für spät joinende Clients (siehe "Negativ / Risiken").
- Keine Umstellung von Wetter auf diesen Mechanismus (siehe "Verhältnis zu
  ADR-041").
- Kein `unreliable`-Modus — jeder bisherige nicht-Bewegungs-RPC im Projekt
  ist `reliable`, keine Anforderung, davon hier abzuweichen.

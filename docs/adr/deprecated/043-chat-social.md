> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-043: Chat/Social — globaler + Whisper-Kanal

**Status:** Angenommen — umgesetzt (Round 99)
**Datum:** 2026-07
**Kontext:** Seit ADR-018 (Round 53) als fehlende Funktionalität dokumentiert
("Chat/Social-Features zwischen Spielern (0 Treffer im Code)"), zuletzt in
Round 98 erneut als offener Punkt festgehalten. Erste Umsetzung, ermöglicht
durch die in ADR-042 (Round 96) gebaute
`NetworkBridge.broadcast_to_all_peers()`-Infrastruktur für den globalen
Kanal.

## Entscheidung

Neuer `ChatService` (`scripts/social/chat/ChatService.gd`, `extends Service`,
kein eigener Save-Key — Chat ist bewusst rein transient) mit zwei Kanälen:

- **`global`** — an alle aktuell verbundenen Spieler, über
  `NetworkBridge.broadcast_to_all_peers("chat", entry)` (ADR-042).
- **`whisper`** — an genau einen Ziel-Spieler + Echo an den Absender, über
  ein neues dediziertes RPC-Paar
  `NetworkBridge.send_chat_message_for_player()`/`_rpc_receive_chat_message()`
  + Signal `chat_message_received`.

**Bewusst ein eigenes dediziertes RPC-Paar für Whisper, kein Recycling
eines bestehenden Kanals.** Es gäbe zwei Kandidaten, beide verworfen:

- `send_economy_update_for_player()` — mechanisch identisch, aber der
  `kind`-Name "economy" wäre für Chat irreführend, und jeder bestehende
  Konsument dieses Kanals (`AuctionHouseService`) müsste den `kind`-Filter
  in seinem Handler dann noch strenger prüfen, um fremde `kind`-Werte
  zuverlässig zu ignorieren.
- `report_domain_event()`/`domain_event_received()` — dieser Kanal ist im
  Code explizit als **Single-Consumer-Kanal für `QuestService`**
  dokumentiert (Client→Autorität-Richtung, `peer_id`-basiert statt
  `player_id`-basiert). Ihn für einen zweiten, fachlich unabhängigen
  Konsumenten zu öffnen, widerspräche dieser eigenen Dokumentation und wäre
  zudem die falsche Richtung (Autorität→Client, nicht umgekehrt).

Stattdessen: ein neues, dediziertes Paar — exakt das Muster, das das
Projekt bereits für jeden anderen Domain-Kanal einsetzt (`send_zone_update_
for_peer()`, `send_economy_update_for_player()`,
`send_pickpocket_notification_for_player()`). Konsistenz mit der
bestehenden Konvention wiegt hier stärker als das (kleine) Einsparen eines
weiteren RPC-Paars.

**Client→Autorität-Anfrage:** `ChatService.request_send_message()` prüft
`_network.has_peer() and not _network.is_server()` — exakt derselbe Guard
wie `AuctionHouseService.request_list_item()` — und routet entweder über
`NetworkBridge.send_chat_message()` (neues `@rpc("any_peer")`-Paar,
`_rpc_chat_send_message()`) zur Autorität, oder ruft bei bereits-Autorität
`on_send_message_confirmed()` direkt auf. Absender-Identität kommt auf der
Autorität NIE vom Client, sondern aus `_sender_as_player_uuid()`
(RPC-Sender-Auflösung) — dieselbe Sicherheitsanforderung wie bei jedem
anderen `any_peer`-RPC hier (ADR-021).

**Autoritäts-lokale Emission (ADR-042-Konvention, kein RPC-Rundweg zu sich
selbst):**
- `global`: `message_received` feuert auf der Autorität IMMER zusätzlich
  zum Broadcast — der Host ist per Definition immer Teil des globalen
  Kanals.
- `whisper`: `message_received` feuert auf der Autorität NUR, wenn der
  lokale Peer (`NetworkBridge.get_local_player_id()`) selbst Absender oder
  Ziel ist. Sonst würde ein Host, der an einem fremden Flüstern gar nicht
  beteiligt ist, es trotzdem in seiner eigenen Chat-UI sehen — ein
  Privatsphäre-Leck, das der reine "lokal immer emittieren"-Reflex aus dem
  globalen Fall hier bewusst NICHT übernimmt.

**Validierung:** leere/reine Whitespace-Nachrichten werden verworfen (kein
Broadcast, kein Signal, `message_rejected`). Nachrichten werden auf
`MAX_MESSAGE_LENGTH` (240 Zeichen) gekappt statt hart abgelehnt — dasselbe
Clamping-statt-Reject-Prinzip wie bei anderen Mengen-/Größenbegrenzungen im
Projekt (z. B. Inventar-Stacks). Einfaches Spam-Rate-Limit
(`MIN_INTERVAL_SEC` pro Absender-`player_id`, service-intern) zusätzlich
zum bereits bestehenden RPC-Rate-Limit auf `_rpc_chat_send_message`
(`NetworkBridge.RATE_LIMITS`, Netzwerk-Missbrauchsschutz-Ebene) — zwei
unabhängige Schichten mit unterschiedlichem Zweck, analog wie andere
Services (z. B. `PickpocketService`) sowohl einen RPC-Rate-Limit als auch
eine eigene Cooldown-Logik haben.

## Optionen (verworfen)

- **Whisper auch über `broadcast_to_all_peers()`** (Broadcast an alle,
  Filterung erst client-seitig auf Empfängerseite) — verworfen: ein
  Whisper würde dann im Klartext an JEDEN verbundenen Peer gehen, nur die
  UI würde ihn ausblenden — ein Server, der auf einem fremden Rechner läuft
  oder ein modifizierter Client könnte private Nachrichten mitlesen. Die
  gezielte `rpc_id()`-Zustellung ist hier kein Komfort-, sondern ein
  Sicherheits-/Privatsphäre-Entscheid.
- **Ein einziger `send_chat_message_for_player()`-Aufruf für global UND
  whisper** (statt `broadcast_to_all_peers()` für global zu nutzen) —
  verworfen: das wäre N Einzel-RPCs statt der bereits vorhandenen
  Broadcast-Fassade, exakt der Fall, für den ADR-042 gebaut wurde.

## Konsequenzen

### Positiv
- Schließt eine seit Round 53 offene funktionale Lücke, mit vollständiger
  Validierung/Rate-Limiting von Anfang an statt eines unsicheren
  Minimal-Entwurfs.
- Folgt konsequent etablierten Konventionen (Guard-Reihenfolge,
  RPC-Namensgebung, `_require_authority()`, Autoritäts-lokale-Emission-
  ohne-RPC-Rundweg) — kein neues Muster für zukünftige Wartung.
- Kein neuer Save-Key, keine Persistenz-Komplexität — Chat ist absichtlich
  ephemer.

### Negativ / Risiken
- Kein Chat-Verlauf: ein spät beigetretener Client sieht frühere
  Nachrichten nicht (weder global noch whisper) — reines Live-Feed, kein
  Scrollback. Für einen ersten Entwurf akzeptabel, siehe "Bewusst nicht
  Teil dieser Runde".
- Kein Server-seitiges Wortfilter/Moderationssystem — reine
  Struktur-/Rate-Validierung, keine Inhalts-Validierung.

## Bewusst nicht Teil dieser Runde

- Kein Chat-Verlauf/Scrollback, keine Persistenz (siehe oben).
- Keine Moderation/Wortfilter/Reporting — siehe TODO-Punkt "Reporting/
  Moderation", ein eigenständiges, größeres Thema.
- Keine Gruppen-/Party-/Gilden-Kanäle — nur `global` und `whisper` in
  dieser Runde.
- Kein UI-Panel (Chat-Fenster, Eingabezeile, Whisper-Auswahl) — dieses ADR
  liefert nur die Service-/Netzwerk-Infrastruktur, analog wie
  `weather_changed`/`player_killed_by_player` zunächst auch nur als Signal
  existierten, bevor eine UI sie konsumierte. Entsprechend auch KEIN
  `UIContext`-Eintrag in dieser Runde — es gibt noch keine UI, die ihn
  bräuchte, analog `PvPDeathLossService`/`PickpocketService`, die ebenfalls
  ohne UIContext-Eintrag auskommen.
- Keine Emote-/Formatierungs-Unterstützung (Farben, Links, @-Mentions).

**Ehrlich offen:** wie in jeder Runde seit 89 — kein Godot-Editor/
Headless-Runner in dieser Entwicklungsumgebung verfügbar, nur strukturell
geprüft (Guard-Reihenfolge, Signaturen, RPC-Annotation gegen die
bestehenden `send_*()`/`_rpc_receive_*()`-Paare abgeglichen), nicht gegen
eine echte Zwei-Peer-Verbindung gelaufen.

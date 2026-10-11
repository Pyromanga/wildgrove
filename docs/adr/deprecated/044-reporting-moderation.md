> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-044: Reporting/Moderation — Meldungen + lokales Stummschalten

**Status:** Angenommen — umgesetzt (Round 100)
**Datum:** 2026-07
**Kontext:** Seit ADR-018 (Round 53) als fehlende Funktionalität dokumentiert
("Reporting-/Moderationswerkzeug für Multiplayer-Verhalten"), jetzt mit
Chat (ADR-043, Round 99) als erstem konkreten Zielsystem sinnvoll umsetzbar.

## Entscheidung

**Zwei bewusst getrennte, unabhängige Bausteine:**

1. **`ReportService`** (`scripts/social/moderation/ReportService.gd`) —
   ein Spieler meldet einen anderen Spieler an die Autorität. Persistiert
   (`SAVE_KEY = "reports"`, `savesystem`-optional-dep) — anders als Chat
   müssen Meldungen eine Sitzung überdauern, um überhaupt später durchsehbar
   zu sein. Rein Client→Autorität-Richtung: neues `@rpc("any_peer")`-Paar
   `NetworkBridge.send_report_submit()`/`_rpc_report_submit()`. Bewusst
   **kein Gegenstück für eine Zustellung an andere Spieler** — eine Meldung
   ist nie für andere Spieler sichtbar, nur für die Autorität. `context` ist
   ein opakes `Dictionary` (z. B. `{"chat_message_id": ..., "chat_text":
   ...}` beim Melden einer Chat-Nachricht) — `ReportService` kennt
   `ChatService` nicht, keine Kopplung zwischen den beiden Services.

2. **Lokales Stummschalten** (`ChatService.mute_player()`/
   `unmute_player()`/`is_muted()`) — lebt bewusst **in `ChatService`
   selbst**, nicht in `ReportService` oder einem eigenen Service. Ein Mute
   ist eine rein lokale Anzeige-Präferenz des jeweiligen Clients, kein
   autoritatives Moderations-Urteil — braucht weder Netzwerk-Traffic (wer
   wen stummschaltet, geht niemanden sonst etwas an) noch Persistenz (setzt
   bei jedem Sitzungsstart zurück, konsistent mit dem "Chat ist
   transient"-Prinzip aus ADR-043). Gefilterte Nachrichten werden nirgends
   aufgezeichnet — reine Anzeige-Unterdrückung in `ChatService.
   _emit_if_not_muted()`, dem einzigen Ort, an dem `message_received`
   tatsächlich feuert.

**Warum getrennt, statt eines gemeinsamen "Moderations"-Service?** Ein
Mute ist client-lokal und augenblicklich wirksam, eine Meldung ist
autoritativ und für spätere Durchsicht gedacht — fachlich zwei
verschiedene Dinge mit unterschiedlicher Reichweite (lokal vs. persistent)
und unterschiedlichem Netzwerkbedarf (keiner vs. ein RPC). Ein gemeinsamer
Service hätte diese beiden Dinge künstlich zusammengezwungen, ohne einen
echten Vorteil (kein gemeinsamer State, keine gemeinsame Logik).

## Validierung (`ReportService`)

- `reason` muss aus einer festen Liste stammen (`harassment`, `spam`,
  `cheating`, `inappropriate_name`, `other`) — kein Freitext-Grund, macht
  spätere Auswertung/Filterung durch ein künftiges Review-Tool sinnvoll
  möglich.
- `details` wird auf `MAX_DETAILS_LENGTH` (500 Zeichen) gekappt statt hart
  abgelehnt — dasselbe Clamp-statt-Reject-Prinzip wie bei `ChatService`.
- Selbst-Meldung (`reported_player_id == reporter_player_id`) wird
  abgelehnt.
- Rate-Limit pro Melder (`MIN_INTERVAL_SEC` = 30s) — deutlich großzügiger
  als Chat (1s), weil eine legitime Meldung selten ist, Report-Spam aber
  selbst ein Missbrauchsvektor gegen das Review-System wäre.
- `MAX_STORED_REPORTS` (500) begrenzt die gespeicherte Liste — älteste
  zuerst verworfen, kein unbegrenztes Wachstum des Saves.

## Optionen (verworfen)

- **Automatische Konsequenzen bei X Meldungen** (Auto-Kick/-Ban ab einer
  Schwelle) — verworfen: false-positive-anfällig (koordinierter
  Falsch-Melde-Missbrauch), keine menschliche Prüfung. Ein erstes
  Reporting-Werkzeug sollte erst Daten sammeln, bevor automatisierte
  Konsequenzen überhaupt sinnvoll kalibrierbar wären.
- **Mute serverseitig/global** (Autorität unterdrückt Nachrichten eines
  gemuteten Spielers für alle) — verworfen für diese Runde: das wäre
  faktisch eine Moderations-Aktion (Konsequenz), nicht mehr eine reine
  Anzeige-Präferenz, und bräuchte eine Autorisierungsfrage ("wer darf wen
  wie global stummschalten?"), die dieses ADR bewusst nicht beantwortet.
  Lokales Mute ist die risikoärmere erste Stufe.
- **Reports über `broadcast_to_all_peers()`** — verworfen, offensichtlich
  falsch: eine Meldung ist strukturell privat (Melder→Autorität), kein
  an-alle-Peers-Fall.

## Konsequenzen

### Positiv
- Erstes konkretes Werkzeug gegen Missbrauch, mit sofort nutzbarem
  lokalem Mute (kein Warten auf Autoritäts-Handeln) UND einer
  persistenten Meldungs-Spur für spätere manuelle Durchsicht.
- Klare Trennung lokal/autoritativ vermeidet, dass ein Mute fälschlich als
  "Beweis" für irgendetwas missverstanden wird — es ist nur eine
  Sichtbarkeits-Einstellung.
- `context`-Dictionary macht `ReportService` wiederverwendbar für jedes
  künftige meldbare System (nicht nur Chat), ohne Anpassung an
  `ReportService` selbst.

### Negativ / Risiken
- Kein Review-Tooling — Meldungen werden gespeichert, aber nichts wertet
  sie aus oder zeigt sie an. Ohne ein künftiges Admin-Werkzeug bleiben sie
  nur im Save-Zustand liegen.
- Kein serverseitiger Mute — ein besonders hartnäckiger Störenfried kann
  weiterhin an ALLE senden, jeder einzelne Empfänger muss selbst muten.

## Bewusst nicht Teil dieser Runde

- Kein Review-/Admin-UI (analog Chat/PvP-Kill-Feed — reine
  Service-/Speicher-Infrastruktur zuerst, UI später), kein
  `UIContext`-Eintrag.
- Keine automatischen Konsequenzen (Bans/Kicks/serverseitige Mutes) — siehe
  "Optionen (verworfen)".
- Kein Mute-Persistenz über Sitzungen hinweg (siehe "Entscheidung" oben).
- Kein Wortfilter/automatische Inhalts-Moderation — nur strukturelle
  Validierung (Grund muss aus fester Liste stammen, Längen-Caps), keine
  Inhalts-Analyse der `details`/gemeldeten Chat-Texte.
- Keine Melde-Historie-Ansicht für den Melder selbst ("meine eingereichten
  Meldungen").

**Ehrlich offen:** wie in jeder Runde seit 89 — kein Godot-Editor/
Headless-Runner in dieser Entwicklungsumgebung verfügbar, nur strukturell
geprüft, nicht gegen eine echte Zwei-Peer-Verbindung gelaufen.

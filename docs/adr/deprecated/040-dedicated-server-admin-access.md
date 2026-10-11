> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-040: Tier-3-Admin-Zugang — SSH-basierte Konsole mit Mehrkonten-Auth

**Status:** Vorgeschlagen
**Datum:** 2026-07
**Kontext:** Schließt die in [ADR-031](031-permission-role-system.md) offen
gelassene Lücke ("Tier-3-Root-Konto mit Pflicht-Passwort-Rotation existiert
nicht — braucht eine eigene Auth-Schicht"). Betrifft `SessionManager`
(`is_dedicated_server()`), `PermissionService` (Rollenzuweisung/-widerruf) und
den Server-Betrieb selbst (Deployment-Pattern für Tier 3).

## Problem

Ein dedizierter Server (Tier 3) hat aktuell kein Login-Konzept für
menschliche Administratoren — nur TOFU-Secrets über `PlayerCredentialStore`
(ADR-029), die beweisen "dieser Peer ist dieselbe `player_uuid` wie beim
letzten Mal", aber kein Username/Passwort für Menschen mit
Admin-Absicht. ADR-031 hat das Rollenmodell (`Role`, `PermissionService`)
bereits gebaut, aber den Zugang zu diesem Modell auf Tier 3 bewusst
ausgeklammert. Zusätzliche Anforderung aus der Diskussion: der Zugriff soll
über SSH auf die Servermaschine laufen (SSH übernimmt Transport-Verschlüsselung
und Maschinen-Authentifizierung bereits vollständig), und mehrere
Administratoren sollen einzeln zurechenbar sein — kein gemeinsames
Root-Passwort.

## Optionen

### Option A: tmux/screen-Wrapper um die bestehende stdin-Konsole
Der Serverprozess läuft in einer `tmux`/`screen`-Session; Admin macht
`ssh server` → `tmux attach`, tippt in dieselbe stdin-Konsole, die auch lokal
liefe.
- ✅ Kein zusätzlicher Godot-Netzwerkcode — reines Deployment-Pattern
- ✅ SSH-Key-Auth ist die einzige Hürde
- ❌ Nur eine geteilte Terminal-Session — mehrere Admins gleichzeitig ohne
  Einzel-Zurechenbarkeit (keiner sieht, wer was getippt hat), widerspricht
  damit direkt der Anforderung aus der Diskussion

### Option B: Eigener localhost-Admin-Socket + SSH-Port-Forward (gewählt)
Godot öffnet zusätzlich zum ENet-Spielport einen zweiten `TCPServer`, aber
ausschließlich auf `127.0.0.1` gebunden — von außen technisch nicht
erreichbar. Admin macht `ssh -L 7778:localhost:7778 server` und verbindet
lokal (eigener kleiner Client oder `nc`/`telnet`) auf `localhost:7778`.
- ✅ Mehrere Admins gleichzeitig, jeder mit eigener Verbindung und eigenem
  Login → Einzel-Zurechenbarkeit möglich
- ✅ Erweiterbar (später eigenes Admin-Client-Tool statt Rohprotokoll)
- ❌ Echter neuer Code: zweiter Listener parallel zum ENet-Peer, bewusst
  außerhalb von `SessionManager`s Spiel-Handshake

## Entscheidung

Option B, kombiniert mit einem Mehrkonten-Modell statt eines einzelnen
Root-Passworts (Konsequenz aus der Einzel-Zurechenbarkeits-Anforderung — ändert
den in ADR-031 skizzierten Umfang von "ein Root-Konto" auf "mehrere benannte
Admin-Konten").

### Komponenten

**`AdminAccountStore`** (neu, eigenes Datei-I/O, analog
`PlayerCredentialStore`-Muster, atomic write)
- `user://admin_accounts.json`: `username → {password_hash (gesalzen),
  must_rotate: bool}`
- Bewusst getrennt von `PermissionService`: Account-Store beantwortet "ist das
  wirklich Alice", `PermissionService` weiterhin "darf Alice das" — dieselbe
  Trennung wie zwischen `PlayerCredentialStore` und `PermissionService`.
- Erststart: Bootstrap-Konto `root` wird automatisch angelegt, Zufallspasswort
  einmalig geloggt, `must_rotate = true`. Solange `must_rotate` steht, nimmt
  die Konsole für dieses Konto ausschließlich den Passwort-Ändern-Befehl an —
  kein anderer Befehl geht durch. `root` kann danach weitere benannte Konten
  anlegen (`admin create alice` → Temp-Passwort, ebenfalls `must_rotate` bei
  Erstlogin).

**`AdminConsole`** — Kernlogik (Befehle, Auth-Prüfung), transportunabhängig
- Wie `SessionManager._handle_join_handshake()` bewusst von der
  Transport-Hülle getrennt (Testbarkeit ohne echten Socket/echtes stdin).
- Zwei Front-Ends:
  - stdin-Reader (Thread + `OS.read_string_from_stdin()`) für direkten
    Terminalzugriff (z. B. via `tmux attach`)
  - TCP-Listener auf `127.0.0.1` (fester, per Cmdline-Argument
    konfigurierbarer Port), erreichbar nur via SSH-Port-Forward; mehrere
    gleichzeitige Verbindungen = mehrere Admins gleichzeitig
- Beide Wege verlangen dasselbe Login (Username + Passwort), auch stdin —
  sonst wäre stdin die Hintertür ohne Zurechenbarkeit, die den Sinn des
  Mehrkonten-Modells unterläuft
- Nur aktiv, wenn `SessionManager.is_dedicated_server()` — Tier 1/2 bekommen
  ihren Admin-Status bereits automatisch (ADR-031, Round 82)

**Befehlsoberfläche (erste, bewusst minimale Version)**
- `passwd` (eigenes Passwort ändern — einzige erlaubte Aktion während
  `must_rotate`)
- `admin create <username>` / `admin list` / `admin revoke <username>`
- `role assign <player_uuid> <role_id>` / `role revoke <player_uuid>` — ruft
  `PermissionService` direkt im selben Prozess auf, kein Netzwerk-Umweg
- `players` — aktuell verbundene `peer_id → player_uuid`
  (`SessionManager.get_all_slots()`)
- `kick <player_uuid>` — erster echter Aufrufer für die seit ADR-031
  bestehende `kick_player`-Capability (bisher nur Stub)

## Konsequenzen

### Positiv
- Löst die in ADR-031 offen gelassene Tier-3-Lücke, ohne ein eigenes
  Netzwerkprotokoll für Verschlüsselung/Authentifizierung bauen zu müssen —
  SSH übernimmt beides bereits
- Einzel-Zurechenbarkeit bei mehreren Admins (kein geteiltes Root-Passwort im
  Normalbetrieb)
- `AdminConsole`-Kernlogik ist transportunabhängig testbar, analog zum
  bewährten Handshake-Muster aus ADR-029

### Negativ / Risiken
- Zusätzlicher Netzwerk-Listener im Serverprozess (neue Angriffsfläche, auch
  wenn `127.0.0.1`-only) — Rate-Limiting auf Login-Versuche daher von Anfang
  an mit rein (billig, `localhost`-only schützt nicht vor einem
  kompromittierten Mitnutzer derselben Maschine)
- Mehrkonten-Modell ist mehr Umfang als das ursprünglich in ADR-031 skizzierte
  einzelne Root-Konto — bewusst in Kauf genommen wegen der
  Zurechenbarkeits-Anforderung

### Mitigationen
- Rate-Limiting auf Login-Versuche (siehe oben)
- `must_rotate`-Sperre erzwingt Passwortwechsel vor jeder anderen Aktion,
  sowohl für `root` beim Erststart als auch für neu angelegte Konten

## Bewusst NICHT Teil dieser Runde (Scope-Schnitt)

- Der unsichtbare/noclip-fähige Admin-Charakter in der Welt aus dem
  ADR-031-Text — auf einem headless Server gibt es kein Rendering, "spectate"
  bräuchte eine eigene State-Streaming-Lösung zurück zur Konsole. Eigenständiges,
  größeres Thema.
- Passwort-Maskierung im rohen TCP-Protokoll (kein Echo beim Tippen) — reine
  Client-Tool-UX-Verbesserung, ändert nichts an der Server-Architektur, kommt
  später.

## Ablösung

Ersetzt den in [ADR-031](031-permission-role-system.md) unter "Tier 3" noch
offen gelassenen Punkt zum Root-Konto (einzelnes Konto → Mehrkonten-Modell mit
SSH-erreichbarem Admin-Socket, wie oben entschieden).

## Umsetzungsstand (Round 86)

**Umgesetzt:**
- `AdminAccountStore` (`scripts/networking/AdminAccountStore.gd`) — Mehrkonten-
  Auth mit gesalzenen Passwort-Hashes, `must_rotate`-Flag, Bootstrap-`root`.
- `AdminConsole` (`scripts/networking/AdminConsole.gd`) — transportunabhängige
  Kernlogik + `AdminConsoleSession`-Inner-Class für unabhängigen Login-Zustand
  pro Verbindung. Login-Rate-Limiting (pro Username, `MAX_LOGIN_ATTEMPTS`/
  `LOCKOUT_SECONDS`) direkt mit rein statt als Folgearbeit. Befehle: `passwd`,
  `admin create/list/revoke`, `role assign/revoke`, `players`, `kick`, `help`,
  `logout`.
- `SessionManager.kick_player(player_id)` ergänzt — im ADR-Text noch nicht
  erwähnter Baustein, erster echter Aufrufer der seit ADR-031 bestehenden
  `kick_player`-Capability.
- `AdminConsoleTcpServer` (`127.0.0.1`-only, gepollt in `_process()`, kein
  eigener Thread nötig) und `AdminConsoleStdinReader` (Thread +
  `call_deferred()`-Übergabe an den Main-Thread — siehe dortigen
  Klassenkommentar für die Begründung, warum das kein Workaround, sondern der
  von Godot vorgesehene Marshalling-Mechanismus ist) als die beiden
  Transport-Frontends. Beide als Kind-Nodes von `DedicatedServerBootstrap`
  verdrahtet, gestartet erst NACH erfolgreichem `create_server()`.
  `--admin-port=` analog zu `--dedicated-port=`.
- Tests: `tests/unit/test_admin_account_store.gd`,
  `tests/unit/test_admin_console.gd`. Für `AdminConsoleTcpServer`/
  `AdminConsoleStdinReader` selbst existieren bewusst keine Unit-Tests (echte
  Sockets/Threads/Godot-Runtime nötig, headless-GUT bildet das nicht sinnvoll
  ab — gleiches Muster wie SM-04 für `create_server()`).

**Bewusst offen gelassen (siehe TODO-offene-probleme.md für Details):**
- Ob Godot beim harten Prozess-Exit für einen noch laufenden, nicht
  gejointen `AdminConsoleStdinReader`-Thread eine Fehlermeldung ausgibt, ist
  ungeprüft (keine echte Godot-Runtime in der Entwicklungssandbox
  verfügbar). `stop()` wartet bewusst nicht auf den Thread — ein
  `wait_to_finish()` würde den Shutdown-Pfad aufhängen, solange
  `OS.read_string_from_stdin()` noch blockiert und niemand tippt.
- Verhalten von `OS.read_string_from_stdin()` ohne echtes TTY (z.B. Prozess
  unter systemd ohne PTY) ist nur angenommen (sofortiges EOF), nicht gegen
  eine echte Headless-Umgebung verifiziert.
- Passwort-Maskierung im rohen TCP-Protokoll weiterhin nicht Teil dieser
  Runde (reine Client-UX, siehe oben).
- Ein manueller End-to-End-Testlauf (`godot --headless -- --dedicated-server`,
  dann `ssh -L 7778:localhost:7778` + `nc`/`telnet`) steht noch aus.


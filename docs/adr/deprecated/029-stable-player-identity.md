> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-029: Stabile Spieler-Identität — `player_uuid` statt `peer_id` als State-/Save-Schlüssel

**Status:** Vorgeschlagen — Phase 1 (dieses ADR) noch nicht umgesetzt
**Datum:** 2026-07
**Kontext:** Root-Cause-Fund während der Vorbereitung von "Reconnect-Recovery" (🟠, TODO). Betrifft `SessionManager`, `ServiceOrchestrator._on_client_connected()`, `SaveSystem`, `NetworkBridge`, sowie jeden multi-tenanten Session-Service: `InventorySystem`, `QuestService`, `SkillSystem`, `EquipmentService`. Grenzt sich ab von [ADR-015](015-local-player-identity.md) (siehe "Abgrenzung zu ADR-015" unten) und ergänzt [ADR-010](010-multiplayer-authority-tiers.md)/[MIGRATION-010](../MIGRATION-010.md).

---

## Problem

Root-Cause-Recherche (gleiche Tiefe wie bei R-4/ADR-020) ergab: der komplette multi-tenante Session-State ist per ENet-`peer_id: int` verschachtelt, nicht per stabiler Spieler-Identität.

Verifiziert im Code:
- `InventorySystem._ensure_player(player_id: int)`, `QuestService._ensure_player(player_id: int)`, analog `SkillSystem`/`EquipmentService` — Dictionary-Key ist `peer_id`.
- `InventorySystem.get_save_data()` serialisiert wörtlich `{ "1": {...}, "2": {...} }` — der Save-Schlüssel jedes Spielers in einer Coop-Session ist seine ENet-`peer_id`.
- `ServiceOrchestrator._on_client_connected()` vergibt die **Save-Identität eines Clients selbst** als `"client_%d" % local_peer` — direkt aus der Verbindungs-`peer_id` abgeleitet.

Zwei konkrete Konsequenzen, unabhängig vom "Reconnect"-Thema, mit dem das gefunden wurde:

1. **Reconnect ist strukturell nicht sauber lösbar.** ENet vergibt bei jeder neuen Verbindung eine neue `peer_id`. Ein Client, der die Verbindung verliert und neu verbindet, bekommt eine neue Save-Datei (`"client_N".json` mit neuem N) statt seiner alten — sein Inventar-/Quest-Fortschritt liegt unter der alten `peer_id` tot im Save der Session.
2. **Identitäts-Kollision zwischen verschiedenen Menschen.** Die `peer_id` ist ein Verbindungs-Slot, kein Personenmerkmal. Zwei unterschiedliche Freunde, die in zwei unterschiedlichen Sessions jeweils als zweite Person verbinden, werden beide als `peer_id 2` geführt — der zweite Freund sieht (im geteilten Save der Coop-Welt) den Inventar-/Quest-Stand, den der erste Freund als "Peer 2" hinterlassen hat, nicht seinen eigenen. Das ist kein Rand- sondern ein Kernfall von Hosted Coop mit wechselnden Mitspielern.

Punkt 2 ist eigenständig kritisch — nicht nur eine Voraussetzung für Reconnect, sondern eine bestehende Dateninkorrektheit im aktuell produktiven Tier-2-Pfad.

---

## Abgrenzung zu ADR-015

ADR-015 hat `peer_id` bewusst und korrekt als "lokale Spieler-Identität" für **Routing-Zwecke** etabliert: "welcher lokale Spieler löst gerade diese Interaktion aus, an wen geht dieses UI-Signal". Dafür ist `peer_id` das richtige Werkzeug — für die Dauer einer Verbindung eindeutig, von der `MultiplayerAPI` selbst vergeben, kein zusätzlicher Auflösungsschritt nötig.

Das hier beschriebene Problem ist ein anderes: `peer_id` wurde zusätzlich, unreflektiert, als **Persistenz-Schlüssel** wiederverwendet (Save-Daten, multi-tenante Dictionaries) — für diesen Zweck ist sie strukturell ungeeignet, weil sie nicht über eine Verbindung hinaus lebt. ADR-015 bleibt für den Routing-Fall vollständig gültig und wird durch dieses ADR nicht ersetzt, nur um den Persistenz-Fall ergänzt, den ADR-015 nie behandelt hat.

---

## Optionen

### Option A: Punktuelle Reconnect-Logik ohne Identitäts-Fix

Ein Retry-Fenster auf ENet-Ebene, das versucht, denselben Client innerhalb kurzer Zeit wieder anzubinden, ohne die zugrundeliegende `peer_id`-als-Schlüssel-Struktur anzufassen.

Verworfen: löst nur den Zufallsfall "Peer bekommt beim Reconnect dieselbe ID" (nicht garantiert, hängt von ENets interner Vergabe ab) und behebt Punkt 2 (Identitäts-Kollision) gar nicht. Genau der Workaround-Charakter, den dieses Projekt an dieser Stelle ausdrücklich nicht will.

### Option B: Stabile Spieler-Identität einführen (gewählt)

`player_uuid` lebt im Save selbst statt am Verbindungsslot. Details siehe "Entscheidung".

### Option C: Accounts/Login-System

Ein serverseitiges Accountsystem mit Login/Passwort, das Identität über mehr als nur "dasselbe Gerät" hinweg garantiert (z. B. für einen dedizierten Server, den mehrere Personen von unterschiedlichen Geräten aus nutzen).

Zurückgestellt, nicht verworfen: eine echte Account-Schicht ist ein eigenständiges, großes Thema (Registrierung, Auth, Datenschutz) und für Tier 2 (Freunde im selben Freundeskreis, informelles Vertrauen laut ADR-010) nicht notwendig. Für Tier 3 könnte das später relevant werden — siehe "Ablösung".

---

## Entscheidung

Option B — `peer_id` vollständig aus dem Persistenz-/State-Modell entfernen, nur noch für Netzwerk-Routing verwenden (dort bleibt sie, siehe Abgrenzung zu ADR-015).

**Geplante Umsetzung (mehrere Runden, hier nur die Entscheidung dokumentiert — kein Code in diesem ADR):**

1. **`player_uuid` im Save.** `SaveSystem` vergibt beim ersten Anlegen eines Charakter-Saves eine echte, zufällige UUID (`Marshalls`/`_generate_uuid()` o. ä.), persistiert im Save selbst. Unabhängig von Tier 1/2/3 — dieselbe Identitäts-Art überall.

2. **Join-Handshake statt Auto-Name.** `ServiceOrchestrator._on_client_connected()` erzeugt keine `"client_%d"`-IDs mehr. Der Client wählt beim Verbinden (analog zur Solo-Charakterauswahl) einen lokalen Charakter, schickt dessen `player_uuid` über eine Handshake-RPC. Die tatsächliche Zuordnung `sender_peer_id → player_uuid` liest der Server aus dem RPC-Absender selbst (ENet-garantiert fälschungssicher), nie aus einem vom Client mitgeschickten Argument — sonst könnte ein modifizierter Client fremde `player_uuid`s beanspruchen.

3. **`SessionManager._peer_slots` wird die kanonische `peer_id → player_uuid`-Übersetzung.** Struktur existiert bereits (`register_player_slot()`/`get_player_id_for_peer()`), bekommt echten Inhalt statt eines synthetischen Strings.

3a. **`player_uuid` allein ist keine Authentifizierung.** Sie ist ein öffentlicher Bezeichner, kein Geheimnis — liegt offen in der lokalen Save-Datei, geht unverschlüsselt über ENet mit. Ein modifizierter Client könnte eine fremde `player_uuid` im Handshake behaupten und damit fremdes Inventar/Quest-Fortschritt beanspruchen. Das ist eine eigenständige Lücke, kein reines Routing-Problem — "Server liest die peer_id aus dem RPC-Absender" beweist nur, *welcher Peer* spricht, nicht, dass die behauptete `player_uuid` ihm wirklich gehört.

  Lösung: **Trust-on-First-Use, analog SSH-Host-Keys.** Jede lokale Charakter-Save bekommt neben der `player_uuid` ein zweites, ebenfalls zufälliges `player_secret` (nie angezeigt, nie geloggt). Der Handshake schickt beide. Die Welt-Save (die des Servers/Hosts, nicht die des Clients) merkt sich pro `player_uuid`, mit welchem `player_secret` sie zuerst gesehen wurde. Verbindet sich dieselbe `player_uuid` später erneut — Reconnect oder neue Session auf demselben Server — muss sie dasselbe Secret vorzeigen, sonst wird sie abgelehnt bzw. bekommt einen neuen, unbelegten Charakter zugewiesen statt fremden State zu übernehmen.

  Diese Prüfung wird hinter einer eigenen Abstraktion gekapselt (`PlayerCredential`-Konzept: "beweise, dass diese `player_uuid` zu diesem Peer gehört"), nicht direkt im `NetworkBridge`-Handshake verdrahtet — TOFU-Secret ist eine Implementierung davon, austauschbar gegen die in "Ablösung" skizzierte Account-Token-Prüfung, ohne den Handshake-Ablauf selbst neu zu bauen.

  Bewusst bleibendes Restrisiko, hier nicht mitgelöst: das Secret geht unverschlüsselt über ENet, außer Godots DTLS wird aktiviert — ein Mitschnitt des ersten Handshakes erlaubt Identitätsdiebstahl danach. Transportverschlüsselung ist ein eigenständiges Thema, kein Teil dieses ADR.

4. **Rekeying der Session-Services.** `InventorySystem`, `QuestService`, `SkillSystem`, `EquipmentService`: überall wo heute `player_id: int` (= `peer_id`) als Dictionary-Key dient, wird daraus `player_id: String` (= `player_uuid`). `NetworkBridge` löst bei jedem eingehenden `any_peer`-RPC `sender_peer_id → player_uuid` über `SessionManager` auf, bevor sie in die Services reinruft — die Services selbst sehen nie wieder eine rohe `peer_id`.

5. **Save-Migration.** Bestehende Saves mit `peer_id`-Schlüsseln (`"1"`, `"2"`, …) müssen über `SaveMigrationService` auf das neue Format gehoben werden — mangels stabiler Alt-Identität nur mit Bestbemühen (z. B. `"1"` bleibt der Save-Inhaber selbst, alles andere kann nicht mehr eindeutig einer echten Person zugeordnet werden und wird als Verlustwarnung geloggt statt stillschweigend verworfen oder geraten).

Reconnect selbst (der ursprüngliche TODO-Punkt) wird durch diese Struktur beiläufig gelöst, nicht als eigener Mechanismus: verbindet sich dieselbe `player_uuid` neu, während der Serverprozess noch läuft, hängt sie sich an ihren bereits im Speicher liegenden State — kein Sonderfall. Kommt der Prozess selbst neu hoch, lädt alles regulär vom Save.

---

## Konsequenzen

### Positiv
- Behebt Punkt 2 (Identitäts-Kollision) — nicht nur eine Voraussetzung für Reconnect, sondern ein eigenständiger Korrektheits-Fix für den bereits produktiven Tier-2-Pfad.
- Reconnect fällt strukturell heraus, statt als Sonderfall-Logik (Gnadenfrist-Timer, Peer-Remapping-Heuristik) nachgerüstet zu werden.
- Löst denselben Persistenz-Unterbau, den auch "Save-Konflikt-Handling fehlt" (🟠, TODO) letztlich braucht — eine stabile Identität ist Voraussetzung dafür, überhaupt zu definieren, *wessen* Konflikt es ist.
- `SessionManager._peer_slots` und `register_player_slot()`/`get_player_id_for_peer()` existieren bereits genau für diesen Zweck — kein neuer Registrierungsmechanismus, nur echter Inhalt statt Platzhalter.

### Negativ / Risiken
- Größerer, mehrere Services übergreifender Umbau (Signaturänderung `int` → `String` in mind. vier Session-Services + `NetworkBridge`-Dispatch) — kein inkrementeller Bugfix.
- Save-Migration für bestehende Multiplayer-Saves ist verlustbehaftet für alle Spieler außer dem Save-Inhaber selbst (siehe Punkt 5) — es gibt keine rückwirkend rekonstruierbare Zuordnung, welche `peer_id` welchem Menschen gehörte.
- Join-Handshake ist neue Netzwerkfläche (`any_peer`-RPC mit `player_uuid`-Payload) — braucht denselben Rate-Limiting-/Validierungs-Sorgfalt wie die bestehenden `_rpc_*`-Methoden (siehe ADR-020, Round 48 Rate-Limiting).

### Mitigationen
- Die Save-Migration wird als expliziter, geloggter Verlustfall behandelt (nicht stillschweigend), konsistent mit dem bestehenden `SaveMigrationService`-Muster (Downgrade-Backups, siehe `SaveSystem._create_downgrade_backup()`).
- Der Join-Handshake wird nach demselben Absicht-statt-Wert-Muster gebaut wie `send_entity_interaction()` (ADR-020/023) — die `player_uuid` ist eine Absichtserklärung ("ich bin dieser Charakter"), die Autorität validiert sie gegen die tatsächliche `sender_peer_id`, nie umgekehrt.

---

## Ablösung

Falls das Projekt je ein echtes Accountsystem (Option C) braucht — z. B. für einen öffentlichen Tier-3-Server mit Fremden statt Freunden, oder weil Spieler ihr Secret verlieren (Gerätewechsel, Neuinstallation) und es ohne E-Mail-Wiederherstellung keinen Weg zurück zu ihrem alten Charakter gibt —, ist hier der grobe Plan, damit Phase 1 dem nicht im Weg steht:

**Was neu dazukäme:** ein eigenständiger Account-Service, getrennt vom Spiel-Server (ENet/`SessionManager`) — eine schlanke HTTP(S)-API mit eigener Datenhaltung (E-Mail, Passwort-Hash, `account_id`). Kein Teil des Godot-Prozesses; der dedizierte Server *fragt* diesen Service, er *ist* ihn nicht.

**Ablauf:**
1. Registrierung: E-Mail + Passwort → Account-Service vergibt `account_id`, verknüpft sie mit der lokal bereits existierenden `player_uuid` (kein Bruch mit Phase 1 — die UUID bleibt bestehen, bekommt nur einen Wiederherstellungsweg).
2. Login: Account-Service prüft Passwort, stellt ein kurzlebiges, signiertes Session-Token aus (z. B. JWT) — signiert, damit der Spiel-Server es **lokal** verifizieren kann, ohne bei jedem Verbindungsaufbau live beim Account-Service nachzufragen.
3. Passwort-Reset: Standard-E-Mail-Verifizierungslink ändert den Passwort-Hash beim Account-Service. Berührt das Spielprotokoll überhaupt nicht — reines Web-Flow, komplett getrennt von `NetworkBridge`/ENet.
4. Handshake (Phase 1 → Phase C): der Client schickt statt `player_secret` das Account-Token. Der Spiel-Server verifiziert die Signatur (lokal, offline-fähig) statt das `PlayerCredential`-TOFU-Secret zu prüfen — **derselbe `PlayerCredential`-Abstraktionspunkt aus 3a, andere Implementierung.** Handshake-Ablauf, `_peer_slots`-Übersetzung, String-Keying in den Services bleiben unverändert.

**Warum das nicht jetzt gebaut wird:** eine E-Mail-Infrastruktur (Versand, Verifizierungslinks, Passwort-Hashing/-Storage, DSGVO-Fragen bei Klarnamen-E-Mails) ist ein komplett anderes Projekt-Standbein als ein Godot-Multiplayer-Spiel — Hosting, Betrieb, Sicherheitsverantwortung für Nutzerdaten, die heute nirgendwo im Projekt existiert. Für Tier 2 (Freunde, informelles Vertrauen laut ADR-010) ist das TOFU-Secret aus Phase 1 ausreichend und braucht keinen Server-Betrieb. Erst wenn Tier 3 tatsächlich für Fremde geöffnet wird (nicht Teil der aktuellen Roadmap), wird der Aufwand gerechtfertigt.

---

## Implementierungsnotizen (Round 58 — Vorarbeit, noch kein Code)

Root-Cause-Recherche vor dem eigentlichen Coden ergab drei Architektur-Fakten, die Phase 1 konkret einschränken bzw. den Umfang vergrößern — hier festgehalten, bevor sie in Code gegossen werden, damit die Umsetzung nicht mittendrin auf sie stößt:

**1. `NetworkBridge` ist session-/charakterscoped, nicht app-scoped.** Wird über `boot_character()` Phase C7 in der Charakter-`ServiceRegistry` instanziiert und bei jedem `teardown_character()` mit zerstört — anders als z. B. `SessionManager` (app-scoped, lebt über die ganze App-Laufzeit). Konsequenz: ein neuer `PlayerCredentialStore` darf seinen Zustand nicht im Node selbst halten (ginge bei jedem Session-Neustart verloren), sondern muss über `SaveSystem`s Pull-Provider-Konvention (`ISaveProvider`) persistiert werden — `SaveSystem` selbst ist zwar auch app-scoped registriert, sein `_loaded_state` wird aber pro `begin_session()`/`end_session()` neu geladen/verworfen, das trägt den Neustart korrekt.

**2. Der Beweis für die Handshake-Notwendigkeit liegt bereits im Code, nicht nur in der Theorie.** `BootPipeline.boot_character()` Phase C9 registriert bereits `SessionManager.register_player_slot(local_peer, player_id)` — sieht auf den ersten Blick aus wie genau die `peer_id → player_id`-Übersetzung, die ADR-029 fordert. Ist es aber nicht: das läuft in **jedem Prozess für sich selbst** (Host registriert sich selbst, jeder Client registriert sich selbst, in seiner **eigenen, lokalen** `SessionManager`-Instanz). Der Server erfährt dadurch nie, welche Identität ein *remote* Client gewählt hat — dafür gibt es schlicht noch keinen Übertragungsweg. Das ist die konkrete Lücke, die der Join-Handshake (Schritt 2 im Plan oben) schließt; Phase C9 selbst muss dafür nicht angetastet werden, sie bleibt für die *eigene* Registrierung korrekt.

**3. Der Join-Flow überspringt Charakterauswahl komplett — größer als ursprünglich verbal skizziert.** `MainMenuController`s Client-Flow geht direkt von IP:Port-Eingabe zu `PLAYING` (`joined_as_client` → `ServiceOrchestrator._on_client_connected()` bootet sofort mit der synthetischen `"client_%d"`-ID). Damit Schritt 2 ("Client wählt beim Verbinden einen lokalen Charakter") überhaupt Sinn ergibt, braucht es einen neuen UI-Zwischenschritt nach dem Verbinden — Charakterauswahl wie beim Host/Solo-Flow, bevor der Handshake gesendet wird. `_on_client_connected()`s Auto-Boot mit `"client_%d"` entfällt komplett, nicht nur die ID-Generierung darin.

**Konkrete Umsetzungs-Checkliste für Phase 1** (siehe TODO-Liste für den Tracking-Eintrag):
- [x] `SaveSystem`: `player_uuid`/`player_secret` generieren (bei erster `begin_session()` ohne vorhandene UUID) + in `save_game()` persistieren + Getter. **Erledigt Round 59.** Dabei mitgefunden und -gefixt: `get_full_state()` hätte das `player_secret` sonst per Sprint-D-Snapshot an jeden Joiner verschickt — siehe `SaveSystem.begin_session()`-Kommentar.
- [ ] `PlayerCredentialStore` (neu, `extends ISaveProvider`) — TOFU-Verifikation (Punkt 3a), gehashtes Secret. **Klasse geschrieben (Round 59), Verdrahtung noch offen — siehe Korrektur unten.**
- [ ] `_rpc_join_handshake(player_uuid, player_secret)` — `any_peer`, Rate-Limit-Eintrag, nutzt `PlayerCredentialStore`, ruft bei Erfolg `SessionManager.register_player_slot(sender_peer_id, player_uuid)` serverseitig auf, sendet Bestätigung/Ablehnung zurück an den anfragenden Peer.
- [x] `MainMenuController`: neuer View-Zustand nach `joined_as_client` — Charakterauswahl statt Auto-Boot, sendet danach den Handshake, bootet erst nach Bestätigung. **Erledigt Round 62.**
- [x] `ServiceOrchestrator._on_client_connected()`: `"client_%d"`-Auto-Boot entfernen, ersetzt durch UI-getriebenen Boot nach Handshake-Bestätigung. **Erledigt Round 62.**
- [x] Tests für alle fünf Punkte, inkl. TOFU-Ablehnungsfall (falsches Secret für bekannte `player_uuid`). **Erledigt Round 61 (TOFU/Handshake) + Round 62 (MainMenuController-Join-Flow, SaveSystem-Idempotenz-Guard).**

### Korrektur (Round 59): Handshake gehört zu `SessionManager`, nicht zu `NetworkBridge`

Beim Verdrahten von `PlayerCredentialStore` zeigte sich ein Sequenzierungsproblem, das die ursprüngliche Skizze ("gehalten von `NetworkBridge`") nicht berücksichtigt hatte:

`NetworkBridge` existiert erst **innerhalb** einer gebooteten `CharacterScope` (`BootPipeline.boot_character()` Phase C7) — sie wird für jede Session neu erzeugt und beim Teardown wieder zerstört. Der Join-Handshake muss aber **vor** der Charakterauswahl laufen (der Client entscheidet ja über das Handshake-Ergebnis hinweg, welchen Charakter er überhaupt bootet) — zu diesem Zeitpunkt existiert noch keine `CharacterScope`, also auch kein `NetworkBridge`, also keine Stelle, an der `@rpc`-Methoden für den Handshake liegen könnten. `@rpc` braucht einen `Node` in der Multiplayer-Root, `NetworkBridge` ist zu diesem Zeitpunkt schlicht noch nicht gebaut.

Korrektur: `SessionManager` (`extends ServiceNode`, app-scoped, lebt für die gesamte App-Laufzeit) ist der richtige Ort — er ist bereits die App-weite Quelle der Wahrheit für Verbindungs-Lifecycle (`_peer_slots`), existiert bereits vor jeder Charakterauswahl, und ist bereits ein `Node`.

**Damit noch offen, bewusst nicht in Round 59 gelöst:** auf einem Tier-2-Host kann ein Client verbinden und seinen Handshake senden, **bevor der Host selbst einen Charakter gewählt hat** (`create_server()` → `HOST_ACTIVE`-Zustand, in dem der Host noch klicken muss — siehe `MainMenuController`-Flow-Dokumentation). Zu diesem Zeitpunkt hat `SaveSystem` noch keine aktive Session (`begin_session()` wurde für den Host selbst noch nicht aufgerufen) — `PlayerCredentialStore` könnte also noch nirgendwo persistieren, selbst wenn es (korrekt) an `SessionManager` hängt. Für Tier 3 (dedizierter Server) besteht dieses Problem nicht — dort bootet `DedicatedServerBootstrap` die Welt-Session automatisch direkt nach `create_server()`, ohne auf eine UI-Interaktion zu warten (Round 55). Zwei Optionen, noch nicht entschieden: (a) `PlayerCredentialStore` puffert im Speicher bis eine Session aktiv ist und flusht dann nach, oder (b) Handshakes werden serverseitig zurückgestellt (nicht abgelehnt, nicht sofort beantwortet) bis der Host seinen eigenen Charakter gewählt hat. Wird in der nächsten Runde entschieden, bevor der Handshake selbst gebaut wird.

### Entscheidung (Round 60): eigene Datei statt Kopplung an die Charakter-Save

Die eigentliche Ursache des Timing-Problems aus Round 59 war ein Kategorienfehler, nicht nur eine Reihenfolgefrage: `PlayerCredentialStore` war über die `ISaveProvider`-Pull-Konvention an die **Charakter**-Save gekoppelt — TOFU-Secrets gehören aber inhaltlich nicht zu einem Charakter, sondern zur **Server-Installation** (wer hat sich auf dieser Welt/diesem Rechner schon mal als welche `player_uuid` verbunden). Ein Host, der zwischen zwei eigenen Charakteren wechselt, dürfte dadurch nicht plötzlich alle Vertrauensbeziehungen zu seinen Mitspielern verlieren.

Lösung: `PlayerCredentialStore` bekommt eine eigene, von `SaveSystem`/`ISaveProvider` komplett unabhängige Datei (`user://server_credentials.json`), geladen einmalig beim Boot von `SessionManager` (app-scoped, existiert bevor überhaupt ein Client verbinden kann) — nicht an `begin_session()`/`end_session()` gekoppelt. Das löst die Tier-2-Race aus Round 59 vollständig auf, statt sie durch Pufferung/Zurückstellen zu umgehen: die Datei ist immer schon geladen, unabhängig davon, ob oder welcher Charakter gerade aktiv ist. Damit entfällt auch die `extends ISaveProvider`-Vererbung — `PlayerCredentialStore` macht eigenes, einfaches Datei-I/O statt über `SaveSystem`s Pull-Konvention zu laufen.

## Implementierungsnotizen (Round 62)

Schritte 4+5 der Phase-1-Checkliste (siehe oben) umgesetzt: `MainMenuController`
bekommt einen neuen View-Zustand `JOIN_CHARACTER_SELECT`, `ServiceOrchestrator`s
Auto-Boot auf `joined_as_client` entfällt.

**Neuer Flow:** `[Beitreten]` → `NET_SETUP` → `joined_as_client` →
`JOIN_CHARACTER_SELECT` (Charakter-Liste, kein Auto-Boot mehr) → Charakter
klicken → `SaveSystem.begin_session(player_id)` (lädt/erzeugt `player_uuid`/
`player_secret`) → `SessionManager.send_join_handshake(uuid, secret)` →
`join_handshake_result`: akzeptiert → `session_requested` → `PLAYING`;
abgelehnt → `SaveSystem.end_session()`, zurück zu `JOIN_CHARACTER_SELECT` mit
Fehlertext.

**`ServiceOrchestrator`-Umbau war nicht optional trennbar von Schritt 4.** Der
alte `_on_client_connected()`-Auto-Boot (`"client_%d"`-ID direkt auf
`joined_as_client`) hätte den neuen `JOIN_CHARACTER_SELECT`-Zustand sofort
überholt — beide Listener hätten auf dasselbe Signal reagiert, der alte hätte
gewonnen (Registrierungsreihenfolge), der neue View-Zustand wäre nie sichtbar
geworden. Der Entfernung des Auto-Boots macht `SessionManager` zusätzlich zu
`SaveSystem` zu einer Pflicht-Injektion ins Hauptmenü (`inject_session_manager()`,
analog `inject_save_system()`, gepusht von `ServiceOrchestrator._on_menu_initializer_ready()`)
— ohne sie könnte `_start_join_handshake()` nie senden.

**Bei der Umsetzung entdeckter Bug, mitgefixt statt nur notiert:**
`SaveSystem.begin_session()` wird durch diesen Flow jetzt zwangsläufig zweimal
für dieselbe `player_id` aufgerufen — einmal vom `MainMenuController` vor dem
Handshake (um die Identität zu lesen, die verschickt wird), einmal danach
regulär von `BootPipeline.boot_character()` Phase C1. Ohne einen
Idempotenz-Guard hätte der zweite Aufruf für einen frisch angelegten Charakter
(noch kein `save_game()` dazwischen, also weiterhin kein Save auf Disk) den
"Neustart"-Pfad genommen und eine zweite, eigene Zufalls-Identität erzeugt —
der Client wäre mit einer Identität gebootet, die der Server im Handshake nie
gesehen hat, und die Verbindung wäre inkonsistent geworden, ohne dass irgendein
Fehler sichtbar geloggt worden wäre. Guard in `SaveSystem.begin_session()`:
ein zweiter Aufruf für dieselbe `player_id`, während bereits eine Session für
sie aktiv ist, ist ein No-Op (überspringt Disk-Reload und Identitätserzeugung
komplett) statt erneut zu laden.

**Beim Schreiben der Tests einen zweiten, unabhängigen Bug gefunden:**
`_on_join_handshake_result()` im Ablehnungsfall rief `_set_status(<Ablehnungsgrund>)`
auf, bevor es `_show_view(JOIN_CHARACTER_SELECT)` aufrief — `_show_view()`
setzt für diesen Zustand aber selbst einen generischen Status-Text
(`"Verbunden — wähle einen Charakter zum Beitreten."`), der den Ablehnungsgrund
sofort wieder überschrieben hätte, bevor der Spieler ihn lesen kann. Reihenfolge
getauscht: erst View wechseln, dann den spezifischeren Fehlertext setzen.

**Tests:** `test_main_menu_controller.gd` bekommt einen `SessionManagerDouble`
(Spy für `send_join_handshake()`, extends `SessionManager` statt echtem
ENet-Peer) neben dem bestehenden `SaveSystemDouble` — Letzterer zusätzlich um
Tracking für `begin_session()`/`end_session()`-Aufrufe sowie feste
Uuid/Secret-Getter erweitert. Neun neue Fälle decken Handshake-Auslösung
(Charakter- und `[Neues Spiel]`-Pfad), akzeptierten/abgelehnten Handshake,
ein verspätetes Ergebnis ohne laufenden Handshake (Ignorieren statt
versehentlichem Boot), fehlende `SessionManager`-Injektion (Guard-Reihenfolge
vor `begin_session()`) und Verbindungsabbruch während eines laufenden
Handshakes ab. `test_save_system.gd` bekommt fünf neue Fälle für den
`begin_session()`-Guard, inkl. der beiden Abgrenzungen (Guard darf nicht über
unterschiedliche `player_id`s hinweg greifen, und nicht mehr nach einem
zwischenzeitlichen `end_session()`).

## Implementierungsnotizen (Round 63) — Plan-Schritt 4 begonnen: InventorySystem

Phase 1 (Checkliste oben) war mit Round 62 vollständig abgeschlossen. Round 63
beginnt den größeren, numerierten Schritt 4 aus dem Entscheidungs-Fließtext
oben ("Rekeying der Session-Services") — als ersten vollständigen
Vertikalschnitt an `InventorySystem`, dem kleinsten der vier Services.

**Vorab-Recherche vor dem Coden ergab zwei Kopplungsstellen, die der
Fließtext oben nicht erwähnt** (derselbe Grund, warum Round 58 schon einmal
vor dem Coden recherchiert hat, statt der ersten verbalen Skizze zu folgen):

1. **`NetworkBridge._sender_as_player_id()` ist kein Inventory-exklusiver
   Helfer.** Er wird von sechs `_rpc_*`-Handlern genutzt, die alle in noch
   nicht migrierte Services (`QuestService`, `PlayerStateService`,
   `EquipmentService`, `WorldService`) reichen. `InventorySystem` selbst hat
   seit Round 45 gar keinen `_rpc_*`-Handler mehr (Item-Grants laufen
   ausschließlich autoritätsseitig über `RewardDispatcher`/
   `InteractionResolver`/`EnemyNPC._die()`). Eine Umstellung von
   `_sender_as_player_id()` auf `String` jetzt hätte die fünf anderen Handler
   sofort gebrochen, für einen Rückgabewert, den `InventorySystem` nicht
   konsumiert. Lösung: `_sender_as_player_id()` bleibt unverändert (`int`,
   Routing, ADR-015). Neuer, separater Helfer `_sender_as_player_uuid()`
   (String) — noch von niemandem in `NetworkBridge` selbst genutzt, wird erst
   relevant, sobald einer der sechs Handler seinen Ziel-Service migriert.
   Jeder künftige Handler wechselt einzeln; sobald alle sechs umgestellt sind,
   wird `_sender_as_player_id()` selbst überflüssig.

2. **`InventorySystem` hat zwei Aufrufer, die selbst noch nicht migriert
   sind.** `RewardDispatcher.dispatch()` ruft im selben Aufruf sowohl
   `_inventory.request_add_item()` als auch `_skill_system.request_add_xp()`
   und `_stat_modifiers.add_modifier()` mit demselben `player_id: int` auf.
   `EquipmentService.on_equip_confirmed()` ruft `_inventory.has_item()` mit
   seinem eigenen, noch int-basierten `player_id`. Beide brauchen die
   Übersetzung `peer_id → player_id` an genau der einen Stelle, an der sie in
   den migrierten Service rufen, während sie selbst (bzw. ihre anderen
   Aufrufe) int-basiert bleiben.

**Lösung, konsistent mit dem bereits etablierten NetworkBridge-Muster:** beide
Aufrufer fragen `NetworkBridge.get_player_id_for_peer()` (die selbst nur an
`SessionManager` delegiert) an genau der einen Aufrufgrenze — keine neue
Abstraktion, nur ein zusätzlicher Aufrufer desselben kanonischen Getters, den
`NetworkBridge` bereits für sich selbst nutzt. Das ist Übergangs-Verkabelung,
kein Dauerzustand: sobald `SkillSystem`/`EquipmentService` selbst migriert
sind, bekommen `RewardDispatcher`/`EquipmentService` ihre `player_id` bereits
als `String` von ihrem eigenen Aufrufer — die Übersetzungszeile wird dann
ersatzlos gestrichen. Jede der verbleibenden drei Service-Runden verkleinert
die Übergangsstellen um genau die, die dabei migriert wird; am Ende bleibt
exakt eine reale Auflösungsstelle übrig (`NetworkBridge`/`SessionManager`
selbst) — dieselbe Form, die ADR-015 für `peer_id` bereits etabliert hat, nur
für `player_uuid` wiederholt.

**Dabei gefundener und mitgefixter Zirkulär-Dep-Fehler:** `RewardDispatcher`
sollte `NetworkBridge` zunächst als normalen `configure()`-Dep bekommen —
wäre ein Zyklus gewesen: `network_bridge` deklariert `quest` als Dep, `quest`
deklariert `reward_dispatcher` als Dep, macht also
`network_bridge → quest → reward_dispatcher → network_bridge`. Gefunden vor
dem Testen, beim Abgleich gegen `BootstrapConfig.tres` (derselbe Grund, aus
dem `WorldService`/`EquipmentService` `NetworkBridge` schon nicht als
`configure()`-Dep bekommen, siehe Kommentar dort). Fix: `RewardDispatcher`
bekommt `inject_network_bridge()` und kommt über denselben
Phase-C8-Late-Inject-Mechanismus wie Inventory/Quest/SkillSystem/Equipment/
World (`BootPipeline.gd`-Loop um `ServiceKeys.REWARD_DISPATCHER` ergänzt).

**Parameter-Reihenfolge geändert, nicht nur Typ.** `player_id` ist jetzt auf
allen öffentlichen `InventorySystem`-Methoden ein Pflichtparameter ohne
Default (es gibt keine sinnvolle String-Entsprechung zum früheren
`player_id: int = 1`; ein vergessener Aufrufer soll laut fehlschlagen statt
still einen falschen Bucket zu befüllen). Da GDScript keinen Pflichtparameter
nach einem Parameter mit Default erlaubt, mussten `has_item()`/`remove_item()`/
`request_add_item()` umsortiert werden: `player_id` steht jetzt vor dem
optionalen `quantity`. `get_all_items()`/`get_weight_status()`/
`get_free_slots()`/`on_item_add_confirmed()` waren davon nicht betroffen
(`player_id` war dort bereits der einzige bzw. letzte nicht-defaultete
Parameter).

**Save-Migration (Plan-Schritt 5) entfällt für diesen Umbau.** Auf
Bestätigung: keine nennenswerten Bestandsdaten in existierenden Coop-Saves —
sauberer Schnitt (`_restore_from_save()` erwartet jetzt direkt
`player_id`-Strings als Keys, keine `int()`-Konvertierung, keine
Übergangslogik für alte `"1"`/`"2"`-peer_id-Saves).

**Geändert:**
- `scripts/session/SessionManager.gd` — `get_local_player_id()`,
  `get_peer_id_for_player()` (Rückwärts-Auflösung).
- `scripts/networking/NetworkBridge.gd` — String-Fassaden
  (`get_local_player_id()`, `get_player_id_for_peer()`,
  `get_peer_id_for_player()`), `_sender_as_player_uuid()` (vorbereitet, noch
  ungenutzt), `send_economy_update_for_player()`.
- `scripts/economy/inventory/InventorySystem.gd` — vollständig auf
  `player_id: String` migriert.
- `scripts/economy/rewards/RewardDispatcher.gd` — `inject_network_bridge()`,
  Übersetzung am Inventory-Call.
- `scripts/economy/equipment/EquipmentService.gd` — Übersetzung am
  `has_item()`-Call.
- `scripts/platform/BootPipeline.gd` — `REWARD_DISPATCHER` in die
  Phase-C8-Late-Inject-Liste aufgenommen.
- `scripts/platform/interfaces/IUIContext.gd` / `UIContext.gd` —
  `get_local_player_id()`.
- `scripts/economy/inventory/ui/InventoryUIController.gd` /
  `scripts/economy/equipment/ui/EquipmentUIController.gd` — nutzen
  `get_local_player_id()` für Inventory-Calls, `get_local_peer_id()`
  unverändert für die noch nicht migrierten Equipment-Calls.
- `tests/unit/test_inventory_system.gd`, `test_inventory_ui_signal.gd`,
  `test_equipment_service_r4.gd` (+ `SessionManager`/`NetworkBridge`-Wiring für
  die Cross-Service-Übersetzung), `test_network_bridge.gd`,
  `test_entity_context.gd` (Mock-Signatur-Fix), `test_ui_context.gd` (+4
  Fälle für `get_local_player_id()`), `test_session_manager.gd` (+5 Fälle
  SM-13/SM-14).
- `tests/unit/test_player_identity_access_boundary.gd` (neu) — Spiegel von
  `test_identity_access_boundary.gd`, verhindert direkten Zugriff auf
  `SessionManager._peer_slots` außerhalb der Klasse.
- `TODO-offene-probleme.md` — neuer Checklisten-Block "Plan-Schritt 4"
  synchronisiert.

**Noch offen:** `QuestService`/`SkillSystem`/`EquipmentService` (eigener
State) folgen nach demselben Muster — vermutlich schneller, weil das Muster
jetzt steht. Die neuen/angepassten Tests sind in diesem Coding-Environment nur
statisch geprüft, noch nicht gegen die echte Godot/GUT-Runtime gelaufen.

## Implementierungsnotizen (Round 64) — Plan-Schritt 4 fortgesetzt: QuestService

Zweiter Vertikalschnitt nach `InventorySystem` (Round 63), nach demselben
Muster: `player_id` Pflichtparameter ohne Default auf allen öffentlichen
Methoden, Übersetzung an den verbleibenden Cross-Service-Grenzen über
`NetworkBridge.get_player_id_for_peer()`/`get_peer_id_for_player()`.

**Kein Parameter-Reordering nötig** (anders als bei `InventorySystem`s
`has_item()`/`remove_item()`/`request_add_item()`): `player_id` war bei jeder
öffentlichen `QuestService`-Methode bereits der letzte Parameter, kein
optionaler Parameter stand danach.

**Vorab-Recherche vor dem Coden ergab eine dritte Kopplungsstelle, die weder
der ADR-Fließtext noch die Round-63-Notizen erwähnen** — eine
Boot-Reihenfolge-Falle, keine reine Aufrufer-Übersetzung wie in Round 63:

`QuestService.on_ready()` startete früher Auto-Start-Quests
(`_data_service.get_auto_start_quests()`) direkt inline. Mit `player_id:
String` bräuchte das die lokale `player_id` — aber `on_ready()` läuft in
Phase C6, lange bevor `NetworkBridge` überhaupt injiziert ist (Phase C8).
Naheliegender Fix wäre gewesen, die Auto-Start-Logik nach
`inject_network_bridge()` zu verschieben — aber ein Abgleich gegen
`BootPipeline.boot_character()` zeigt: `SessionManager.register_player_slot()`
(der Slot-Eintrag, den `NetworkBridge.get_local_player_id()` überhaupt erst
braucht) läuft in **Phase C9**, also NACH Phase C8. `inject_network_bridge()`
hätte `_local_player_id()` also ebenfalls strukturell immer leer gesehen —
Auto-Start-Quests wären beim Boot nie gestartet. Kein bestehender Hook lag
zeitlich nach C9.

**Lösung:** neue **Phase C9.5** in `BootPipeline.boot_character()`, direkt
nach dem `register_player_slot()`-Aufruf. Ruft — duck-typed wie der
bestehende Phase-C8-Loop für `inject_network_bridge()` — `on_local_identity_
ready()` auf jedem Service auf, der die Methode implementiert. Bislang
einziger Konsument: `QuestService`. Kein neuer Interface-Zwang für die
übrigen Services (`has_method()`-Check, kein `implements`).

**Zweite, kleinere Kopplungsstelle:** die parameterlosen `active_quests`/
`completed_quests`/`available_quests`-Properties (`var x: T : get = _get_x`)
konnten keinen `player_id`-Parameter aufnehmen — eine Godot-`get =`-Property
ist immer nullstellig. Umgewandelt in echte Methoden `get_active_quests
(player_id)`/`get_completed_quests(player_id)`/`get_available_quests
(player_id)`. Einziger betroffener Aufrufer außerhalb der Tests:
`QuestPanelController`, der jetzt durchgängig `_ctx.get_local_player_id()`
übergibt.

**Dieselbe Zwei-Klassen-Übersetzung wie in Round 63, nur an anderer Stelle:**
- Eingehend: `loot_collected`/`xp_gained`/`enemy_killed`/
  `domain_event_received` liefern weiterhin `peer_id: int` (`WorldService`/
  `SkillSystem` noch nicht migriert) — `_resolve_player_uuid()` übersetzt an
  der Empfangsgrenze in allen vier `_on_*()`-Handlern.
- Ausgehend: `RewardDispatcher.dispatch()` erwartet weiterhin `peer_id: int`
  — `_resolve_peer_id()` übersetzt zurück in `on_quest_complete_confirmed()`,
  exakt an der einen Stelle, an der `QuestService` in `RewardDispatcher`
  ruft.
Beide Helfer verschwinden ersatzlos, sobald `SkillSystem`/`EquipmentService`
selbst migriert sind — dieselbe Übergangs-Argumentation wie Round 63.
**Korrektur (Round 67):** gilt nur für den `loot_collected`/`xp_gained`/
`enemy_killed`-Zweig (interne EventBus-Signale aus `WorldService`/
`SkillSystem`). Der `domain_event_received`-Zweig bleibt dauerhaft
`peer_id: int` — siehe "Implementierungsnotizen (Round 67)" unten, dieser
Handler wird bewusst nicht migriert. `_resolve_player_uuid()` in
`QuestService` verschwindet also nicht vollständig, nur teilweise.

**Erste tatsächliche Nutzung von `_sender_as_player_uuid()`:**
`_rpc_start_quest()`/`_rpc_complete_quest()` sind die ersten zwei der sechs
`_rpc_*`-Handler, die von `_sender_as_player_id()` (int, nur noch fürs
Rate-Limiting verwendet) auf `_sender_as_player_uuid()` (String, für den
`QuestService`-Aufruf) umgestellt sind — der Helfer war seit Round 63
vorbereitet, aber bis jetzt ungenutzt.

**Bekannte, nicht in dieser Runde behobene Einschränkung:**
`RewardDispatcher.dispatch()` emittiert `quest_unlock_requested` für
Folge-Quest-Unlocks — das Signal trägt (wie `quest_start_requested`) keine
`player_id`, der neue `_on_quest_unlock_requested()`-Wrapper löst deshalb "der
lokale Prozess" auf, nicht zwingend den Spieler, dessen Quest den Reward
ausgelöst hat. Verhält sich identisch zum Vorzustand (der hatte denselben
festen Tier-1-Default) — kein Verhaltens-Downgrade durch diese Runde, aber
weiterhin offen für eine künftige Runde, sobald `quest_unlock_requested`
selbst eine `player_id` trägt.

**Separat gefunden, nicht durch diese Runde verursacht:** sechs Tests in der
alten `test_quest_service.gd` griffen auf `_svc._on_npc_talked_to`/
`_bus.quest().npc_talked_to` zu — Methoden/Signale, die seit ADR-021
(Option C, vorherige Runde) in `QuestService` nicht mehr existieren
(`on_ready()`-Kommentar dort). Die Datei war dadurch bereits vor dieser
Migration nicht lauffähig, unabhängig vom `player_id`-Typ. Beim ohnehin
nötigen Umschreiben mitgefixt: ersetzt durch Tests gegen den tatsächlichen
aktuellen Pfad (`NetworkBridge.domain_event_received` →
`QuestService._on_domain_event_received()`).

**Save-Migration entfällt**, aus demselben Grund wie Round 63 — sauberer
Schnitt, `_restore_from_save()` erwartet direkt `player_id`-Strings als Keys.

**Geändert:**
- `scripts/progression/quests/QuestService.gd` — vollständig auf
  `player_id: String` migriert; neue Helfer `_local_player_id()`,
  `_resolve_player_uuid()`, `_resolve_peer_id()`; neuer Hook
  `on_local_identity_ready()`; `active_quests`/`completed_quests`/
  `available_quests` → `get_active_quests()`/`get_completed_quests()`/
  `get_available_quests()`.
- `scripts/networking/NetworkBridge.gd` — `send_start_quest()`/
  `send_complete_quest()` nutzen `get_local_player_id()` statt hartcodierter
  `1`; `_rpc_start_quest()`/`_rpc_complete_quest()` nutzen
  `_sender_as_player_uuid()` für den `QuestService`-Aufruf (Rate-Limiting
  bleibt an `_sender_as_player_id()`, peer-basiert, ADR-015).
- `scripts/platform/BootPipeline.gd` — neue Phase C9.5
  (`on_local_identity_ready()`-Hook, duck-typed).
- `scripts/progression/quests/ui/QuestPanelController.gd` — nutzt
  `_ctx.get_local_player_id()` für alle `QuestService`-Aufrufe.
- `tests/unit/test_quest_service.gd`, `test_quest_service_signals.gd` —
  vollständig neu geschrieben (Pflichtparameter, SessionManager/
  NetworkBridge-Wiring für die Signal-Pfad-Tests, TALK/CUSTOM-Tests auf den
  aktuellen `domain_event_received`-Pfad umgestellt).
- `TODO-offene-probleme.md` — Checklisten-Block "Plan-Schritt 4"
  synchronisiert.

**Noch offen:** `SkillSystem`/`EquipmentService` (eigener State) folgen nach
demselben Muster. Sobald beide migriert sind, entfallen
`_resolve_player_uuid()`/`_resolve_peer_id()` in `QuestService` UND
`RewardDispatcher` ersatzlos, und die restlichen vier `_rpc_*`-Handler können
auf `_sender_as_player_uuid()` umgestellt werden — danach wird
`_sender_as_player_id()` selbst überflüssig. Wie in Round 63: Tests nur
statisch geprüft, kein Godot-Runtime im Coding-Environment verfügbar.

## Implementierungsnotizen (Round 67) — Korrektur: `_sender_as_player_id()` bleibt

`SkillSystem` (Round 65) und `EquipmentService` (Round 66) sind seither
migriert. Damit war laut obigem Absatz und der analogen Notiz in Round 64
(Zeile "Beide Helfer verschwinden ersatzlos, sobald ... selbst migriert
sind") der Moment erreicht, die restlichen vier `_rpc_*`-Handler in
`NetworkBridge` gegenzuprüfen. Ergebnis: **die Annahme war falsch.**

Alle vier verbleibenden Handler (`_rpc_set_state`, `_rpc_report_domain_event`,
`_rpc_request_entity_interaction`, `_rpc_submit_movement_input`) wurden
einzeln gegen ihren Ziel-Service geprüft:

- `_rpc_set_state` → `PlayerStateService._current`: ein nicht-persistierter
  In-Memory-Dictionary für Mikro-UI-State (FREE/BUSY/MENU), kein Save-Feld.
  Es gibt keinen Korrektheitsbug, den die Migration lösen würde — der
  State ist ohnehin nur für die Dauer der Verbindung gültig.
- `_rpc_request_entity_interaction`/`_rpc_submit_movement_input` →
  `WorldService.resolve_and_dispatch_interaction()`/`route_movement_input()`
  → `EntityOrchestrator.resolve_for_player()`/`find_player_by_id()`: beide
  lösen ausschließlich über das Entity-Meta `owner_peer_id` auf (gesetzt in
  `spawn_entity()`, siehe auch der gelöste `multiplayer_authority`-Blocker
  weiter unten in `TODO-offene-probleme.md`). Die adressierte Player-Node ist
  strukturell an die laufende Verbindung gebunden, nicht an die stabile
  Identität — sie wird bei jedem Reconnect ohnehin neu gespawnt. Eine
  Umstellung auf `player_id: String` würde hier keinen Bug lösen, sondern nur
  einen zusätzlichen `player_id → owner_peer_id`-Rücklauf einführen, um exakt
  wieder bei der `peer_id` zu landen, mit der man begonnen hat.
- `_rpc_report_domain_event` → Signal `domain_event_received`: einziger
  Konsument ist `QuestService._on_domain_event_received()`, das
  `peer_id → player_id` bereits an seiner eigenen Empfangsgrenze übersetzt
  (`_resolve_player_uuid()`, siehe Round 64 oben). Eine Übersetzung schon in
  `NetworkBridge` wäre eine zweite Übersetzung für denselben Zweck.

**Korrektur der Zählung:** die ursprüngliche Formulierung "sechs
`_rpc_*`-Handler insgesamt" (Round 58/59) war zu niedrig angesetzt — der
Sender-Kontext wird tatsächlich von mindestens acht Handlern über
`_sender_as_player_id()` angefragt, wenn man `_rpc_start_quest`/
`_rpc_complete_quest`/`_rpc_equip_item`/`_rpc_unequip_item` (jetzt beide
Helfer nutzend) mitzählt.

**Fazit:** `_sender_as_player_id()` ist kein Übergangs-Code, der mit
Abschluss von Plan-Schritt 4 verschwindet, sondern der dauerhaft richtige
Helfer für die vier peer-/verbindungsscoped Handler. Die Unterscheidung, die
Plan-Schritt 4 eigentlich trifft, ist nicht "Handler A bis F migrieren", wie
die ursprüngliche Skizze nahelegte, sondern "adressiert der Handler
Save-Daten (→ `player_id: String`) oder Laufzeit-/Verbindungs-Zustand (→
`peer_id: int`)". Vier Handler fallen in die erste Kategorie und sind
migriert; vier in die zweite und bleiben unverändert. Plan-Schritt 4 ist
damit inhaltlich, nicht nur zahlenmäßig, abgeschlossen.

**Geändert:**
- `scripts/networking/NetworkBridge.gd` — Doku-Kommentar über
  `_sender_as_player_uuid()`/`_sender_as_player_id()` korrigiert (verwies
  bisher fälschlich auf eine bevorstehende Vollmigration).
- `TODO-offene-probleme.md` — offenen Untersuchungspunkt geschlossen.
- Kein Verhaltens-/Produktivcode in den vier geprüften Handlern geändert —
  ihr bisheriges Verhalten war bereits korrekt, nur die Planungsannahme
  darüber war es nicht.

**Noch offen (unverändert):** Tests einmal gegen die echte Godot/GUT-Runtime
laufen lassen, sobald verfügbar.

## Implementierungsnotizen (Round 68) — Naming-Bereinigung + Reconnect-Recovery verifiziert

**Naming-Bereinigung.** Während der Round-67-Untersuchung fiel auf, dass
`_sender_as_player_id()` (und ca. 30 weitere Stellen quer durchs Projekt:
`PlayerStateService`, `InteractionExecutor`, `WorldService`,
`EntityOrchestrator`, `CombatSystem`, `EnemyNPC`, `RewardDispatcher`,
`StatModifierService` u. a.) einen `int`-Wert (die Verbindungs-ID) `player_id`
nannten — exakt denselben Namen, den ADR-029 für die stabile `String`-Identität
reserviert. Durchgängig umbenannt auf `peer_id`, überall wo es sich tatsächlich
um die Verbindungs-ID handelte; `player_id` bleibt ab jetzt ausschließlich für
die stabile `String`-Identität reserviert. `_sender_as_player_id()` heißt jetzt
`_sender_as_peer_id()` — alle Vorkommen des alten Namens weiter oben in diesem
Dokument sind historische Beschreibung des damaligen Codes, keine aktuelle
API-Referenz mehr. Dabei ein echter Typkonflikt gefunden und behoben (kein
reines Naming-Problem): `QuestObjectiveHandler.resolve_xp()` war als
`player_id: int` deklariert und reichte den Wert direkt an
`SkillSystem.get_level()` durch — die aber seit Round 65 `player_id: String`
verlangt. `QuestService._on_xp_gained()` übergab bis dahin den rohen
`peer_id` statt der bereits an seiner eigenen Empfangsgrenze übersetzten
`player_id`. Nie aufgefallen, weil dieser Pfad nur gegen ein Test-Double mit
derselben (ebenfalls veralteten) `int`-Signatur lief, nie gegen die echte
Godot-Runtime.

**Reconnect-Recovery verifiziert, kein Code nötig.** Der TODO-Punkt "Kein
Reconnect-Recovery" ist geschlossen — nicht durch neuen Code, sondern durch
Nachvollziehen des bestehenden Codepfads gegen die in diesem ADR (Abschnitt
oben) getroffene Vorhersage: `SessionManager._on_peer_disconnected()` löscht
ausschließlich `_peer_slots`/`_handshake_done` (die `peer_id ↔ player_id`-
Routing-Zuordnung), nie die `player_id`-verschachtelten `_players`-
Dictionaries der vier Session-Services. `WorldService._on_peer_cleanup_requested()`
räumt ebenfalls nur peer-scoped Laufzeit-Zustand ab (Chunk-Tracking,
Player-Node-Meta), nie `player_id`-Daten. Verbindet sich derselbe `player_uuid`
erneut und besteht den TOFU-Handshake, hängt `register_player_slot()` die neue
Verbindung einfach an den bereits im Speicher liegenden Save-State — exakt wie
oben vorhergesagt, kein Sonderfall nötig. Bewusst zurückgestellt: ein echter
Zwei-Prozess-Integrationstest (Server hochfahren, Client verbinden/trennen/neu
verbinden, Session-Fortbestand end-to-end beweisen) — kommt mit dem großen
Multiplayer-Integrationstest am Ende dieser TODO-Serie, statt hier isoliert
vorgezogen zu werden.

**Geändert:** ca. 30 Dateien (Produktivcode + Tests) umbenannt, siehe
`TODO-offene-probleme.md` für die volle Liste. `QuestObjectiveHandler.gd` +
`QuestService.gd` (Bug-Fix) + zugehöriges Test-Double in
`test_quest_objective_handler.gd`. `TODO-offene-probleme.md`:
"Kein Reconnect-Recovery" geschlossen, "Save-Konflikt-Handling fehlt"
entblockt (Identitäts-Voraussetzung erfüllt, Mechanismus selbst weiterhin
offen).

## Implementierungsnotizen (Round 70) — Korrektur: `get_player_by_id()`/`get_player_visuals()` bleiben `peer_id: int`

Round 69 migrierte `StatModifierService` (letzter verbliebener Session-Service
mit Save-Bucket-Semantik) und hielt in seiner Übergabenotiz
`WorldService.get_player_visuals()`/`get_player_by_id()` für den noch offenen
Rest der ADR-029-Familie. Round 70 hat das geprüft: **die Annahme war
falsch**, aus demselben strukturellen Grund wie schon einmal in Round 67.

Beide Methoden sind Fassaden auf `EntityOrchestrator.find_player_by_id()`,
das ausschließlich über das Entity-Meta `owner_peer_id` auflöst — denselben
Mechanismus, den Round 67 für `_rpc_request_entity_interaction`/
`_rpc_submit_movement_input` bereits geprüft und bewusst bei `peer_id: int`
belassen hat (Player-Node ist verbindungsgebunden, nicht identitätsgebunden,
und wird nach einem Reconnect ohnehin neu erzeugt). Der einzige produktive
Aufrufer, `EquipmentService._resolve_peer_id()`, übersetzt `player_id` über
`NetworkBridge.get_peer_id_for_player()` — eine Live-Routing-Abfrage über
aktuell verbundene Peers, keine Save-Bucket-Übersetzung. Eine
Signaturmigration hätte diese Übersetzung nicht eliminiert, sondern nur eine
Ebene tiefer verschoben und dabei `WorldService` unnötig von `NetworkBridge`
abhängig gemacht.

**Ergebnis: die ADR-029-Familie ist mit Round 69 vollständig abgeschlossen.**
Migriert: `InventorySystem` (63), `QuestService` (64), `SkillSystem` (65),
`EquipmentService` (66), `StatModifierService` (69). Bewusst und geprüft bei
`peer_id: int` belassen: die vier `_rpc_*`-Handler in `NetworkBridge` (67),
`EntityOrchestrator.find_player_by_id()`/`resolve_for_player()` (67, 70),
`WorldService.get_player_by_id()`/`get_player_visuals()` (70). Kein Code
geändert — nur `TODO-offene-probleme.md` korrigiert, siehe dort für die
volle Herleitung inkl. der Korrektur der Round-69-Aufrufer-Liste
(`InventoryUIController`/`EquipmentUIController` rufen `get_player_visuals()`
entgegen der damaligen Notiz gar nicht auf, nur ein Kommentar erwähnt es).

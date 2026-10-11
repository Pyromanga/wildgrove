> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-025: Server-autoritatives Movement — Input statt Position als Übertragungseinheit

**Status:** Umgesetzt (Round 47) — siehe Umsetzungsstand unten
**Datum:** 2026-07
**Kontext:** `Player.gd`, `PlayerMover.gd`, `TouchInput.gd`, `PlayerCamera.gd`,
`EntityOrchestrator`, `NetworkBridge`, `NetworkContract`. Löst
[ADR-024](024-server-side-movement-validation.md) ab — bewusste
Entscheidung, das dort beschriebene Sicherheitsniveau ("Plausibilitätsfilter,
kein Anti-Cheat") nicht als Zielzustand zu akzeptieren, sondern auf
kompetitives Shooter-Niveau zu heben, obwohl WildGrove kein Shooter ist.

## Problem

Heute ist Player-Movement **client-autoritativ**: `Player.gd._setup_multiplayer_sync()`
setzt einen `MultiplayerSynchronizer` auf `position`/`rotation`/`velocity`, dessen
Authority beim besitzenden Client liegt (`EntityOrchestrator.spawn_entity()` setzt
`set_multiplayer_authority()` auf `peer_id`, nicht auf `1`). Der Client simuliert
seine eigene Physik lokal (`_loop_free()` → `PlayerMover.calculate_velocity()` →
`move_and_slide()`) und repliziert das *Ergebnis* an Server und andere Clients.
Der Server hat dabei keine eigene Simulation — er übernimmt die client-berechnete
Position unverändert.

ADR-024 hatte das akzeptiert und nur einen nachträglichen Plausibilitätsfilter
(Speed-Cap gegen die replizierte Position) vorgeschlagen — ausdrücklich *kein*
Anti-Cheat, weil die geprüfte Position selbst vom potenziell manipulierten Client
stammt. Diese Entscheidung wird hier revidiert: das Zielniveau ist explizit höher.

**Root Cause für "kein echtes Anti-Cheat möglich":** Die Autorität hat keine eigene
Simulation, gegen die sie prüfen könnte — sie hat nur eine Behauptung. Ein
Plausibilitätsfilter auf eine Behauptung bleibt ein Filter auf eine Behauptung,
unabhängig davon, wie eng man ihn zieht. Die einzige Lösung, die das grundsätzlich
ändert, ist eine zweite, unabhängige Simulation auf der Autorität selbst.

## Optionen

### Option A: ADR-024 beibehalten (Plausibilitätsfilter auf replizierte Position)
- ✅ Kein Umbau nötig
- ❌ Löst das eigentliche Problem nicht — bleibt eine Prüfung auf eine Client-Aussage,
  keine unabhängige Wahrheit. Vom Auftraggeber explizit als nicht ausreichend
  zurückgewiesen für das angestrebte Sicherheitsniveau.

### Option B: Server simuliert autoritativ aus übertragenem Input (gewählt)
Der Client sendet nicht mehr seine berechnete Position, sondern **Eingabe-Rohdaten**
pro Tick: `move_vec: Vector2` (aus `TouchInput.js_vec`), `camera_yaw: float` (weil
`MathHelper.calculate_move_direction()` kamera-relativ rechnet — ohne Yaw kann der
Server die Bewegungsrichtung nicht reproduzieren), `jump_requested: bool`, plus eine
monoton steigende `input_seq: int` (Grundlage für ADR-026s Reconciliation).

Die **Server**-Instanz der `Player`-Node (existiert bereits — jede `Player`-Entity
wird über `EntityOrchestrator.spawn_entity("player", …)` auf **allen** Peers
inklusive Server gespawnt) führt denselben `PlayerMover.calculate_velocity()` +
`move_and_slide()`-Code mit dem empfangenen Input aus — nicht eine Kopie des Codes,
derselbe Code, denselben Regeln wie der Client, nur mit der Autorität als Ausführungsort.

**Tier-Kollaps, analog zu den bestehenden `send_*()`-Methoden in `NetworkBridge`:**
Die Input-Übertragung bekommt eine eigene Methode `submit_movement_input(input_snapshot)`,
die exakt demselben Muster folgt wie `send_add_xp()`/`send_add_item()`/etc.:

```
func submit_movement_input(input_snapshot: Dictionary) -> void:
    if _has_peer() and not multiplayer.is_server():
        rpc_id(1, "_rpc_submit_movement_input", input_snapshot)  # unreliable, s. u.
    else:
        _simulate_authoritative_movement(input_snapshot, get_local_peer_id())
```

Das ist kein Sonderfall für Tier 1 — es ist derselbe Kollaps, den jedes andere
`send_*()` in `NetworkBridge` schon hat. Konsequenz pro Tier:
- **Tier 1 (Solo):** kein Peer → immer der `else`-Zweig, Direktaufruf im selben
  Frame. Kein RPC, keine Latenz, keine Prediction-Divergenz möglich (Vorhersage
  und Autorität laufen im selben Aufruf) — ADR-026s Reconciliation trifft hier
  immer "0 Abweichung", ohne dass ein Tier-1-spezifischer Sonderpfad im
  Prediction-Code selbst nötig wäre.
- **Tier 2 (Hosted Coop):** Für den **Host selbst** gilt exakt derselbe
  Direktaufruf-Zweig wie Tier 1 (`multiplayer.is_server()` ist für den Host wahr)
  — seine eigene Bewegung hat also nie wahrnehmbare Prediction-Korrekturen. Für
  die **Mitspieler** beim Host greift der `rpc_id(1, …)`-Zweig mit echter Latenz
  und echter Reconciliation.
- **Tier 3 (Dedizierter Server):** Alle Spieler nehmen den `rpc_id(1, …)`-Zweig,
  kein lokaler Spieler auf dem Server selbst — der reine, ursprünglich intendierte
  Fall.

`_setup_multiplayer_sync()`s `MultiplayerSynchronizer`-Authority dreht sich um: für
Player-Nodes gilt jetzt dieselbe Regel wie für `EnemyNPC`/Bäume (Autorität = Server),
nicht mehr "Autorität = besitzender Client". `position`/`rotation`/`velocity`
fließen von 1 (Server) zu allen Clients — auch zum eigenen Client des Spielers
(Grundlage für ADR-026: der eigene Client braucht die autoritative Antwort, um zu
reconcilen).

- ✅ Der Server hat jetzt eine **eigene, unabhängige** Simulation — keine Prüfung
  einer Behauptung mehr, sondern die Behauptung existiert gar nicht mehr als
  Wahrheitsquelle
- ✅ Löst ADR-024s Grundproblem strukturell statt es enger zu filtern
- ✅ `resolve_for_player()` (ADR-023) bekommt dieselbe Position, die auch für Rendering
  bei allen anderen Clients gilt — eine Wahrheit, nicht zwei (client-simuliert +
  server-gefiltert)
- ❌ Ohne Gegenmaßnahme fühlt sich Bewegung für den lokalen Spieler jetzt nach
  Server-Roundtrip-Latenz an — Regression gegenüber heute. Wird in
  [ADR-026](026-client-side-prediction-reconciliation.md) gelöst, nicht hier
  mitgelöst (eigenständiges Problem, eigener ADR, um beide Entscheidungen einzeln
  nachvollziehbar zu halten)
- ❌ Input-Übertragung braucht eine neue, hochfrequente Kommunikationsart
  (`unreliable_ordered` statt `reliable`, da 20+ Hz Input-Rate — bei `reliable`
  würde ein verlorenes Paket die Warteschlange stauen). Bisher nutzt `NetworkBridge`
  ausschließlich `reliable` RPCs — dies ist die erste `unreliable`-Nutzung im Projekt
  und braucht eigene Sorgfalt (Paketverlust ist normal, kein Fehlerfall)

### Option C: Server simuliert autoritativ, aber nur als nachträgliche Korrektur (Lockstep-light)
Client bewegt sich weiter client-autoritativ wie heute, Server simuliert *zusätzlich*
parallel aus periodisch übertragenem Input und überschreibt die Client-Position nur
bei großer Abweichung (ähnlich Option C aus ADR-024, aber mit echter Server-Simulation
statt nur Speed-Cap).
- ✅ Kleinerer gefühlter Sprung von heute aus
- ❌ Zwei parallele Simulationen (Client-Physik + Server-Physik) ohne klaren
  Zeitpunkt, wann welche gilt, ist strukturell fehleranfälliger als eine klare
  Umkehr der Autorität — genau die Art von Zwischenzustand, der bei AUDIT-05 als
  "Mutations-Zwiebel" beschrieben wurde (zwei Wahrheiten für dieselbe Frage)
- ❌ Löst das eigentliche Sicherheitsziel nur teilweise: der Client bewegt sich
  weiterhin autoritativ, bis der Server eingreift — ein cleverer Cheat, der knapp
  unter der Korrektur-Schwelle bleibt, ist strukturell unentdeckbar, exakt derselbe
  Rest-Trade-off wie bei ADR-024, nur aufwändiger gebaut

## Entscheidung

**Option B.** Server simuliert autoritativ aus übertragenem Input, keine
Zwischenlösung (Option C) und keine Beibehaltung des reinen Filters (Option A,
ADR-024). Latenzverdeckung für den lokalen Spieler ist bewusst ausgelagert nach
ADR-026.

## Konsequenzen

### Positiv
- Bewegung erreicht dasselbe Sicherheitsniveau wie die übrigen server-autoritativen
  Systeme (Inventar, XP, Combat — vgl. `NetworkContract.gd`) — kein struktureller
  Sonderfall mehr, in dem "Autorität" nur ein Wort für "Server nimmt Client-Aussage
  entgegen" ist.
- `resolve_for_player()` (ADR-023) prüft ab sofort gegen eine echte, unabhängige
  Server-Position — ADR-024 kann als abgelöst markiert werden, nicht nur als
  "vorerst ausreichend" stehen bleiben.
- Kamera-relative Bewegungsrichtung (`camera_yaw`) wird als explizit übertragener
  Wert sichtbar, statt implizit nur im Client-Rendering zu existieren — macht eine
  bisher unausgesprochene Abhängigkeit (`MathHelper.calculate_move_direction()`
  braucht die Kamera) explizit im Netzwerk-Kontrakt.

### Negativ / Risiken
- Ohne ADR-026 ist dieser Schritt für sich genommen eine UX-Verschlechterung
  (spürbare Latenz für den lokalen Spieler) — dieser ADR wird bewusst nicht
  isoliert ausgerollt, sondern nur zusammen mit ADR-026.
- Erste `unreliable`-RPC-Nutzung im Projekt — `NetworkContract.gd` muss um diese
  Kategorie erweitert werden (aktuell nur `reliable` dokumentiert), inklusive der
  Regel, dass Paketverlust hier normal ist und nicht wie bei den bestehenden
  `reliable`-RPCs behandelt werden darf (kein Retry-Timer wie beim
  Snapshot-Request in `NetworkBridge` — verlorene Inputs werden einfach durch den
  nächsten Tick überholt).
- Server-Rechenlast steigt: die Autorität simuliert jetzt Physik für **jeden**
  angeschlossenen Spieler pro Tick, nicht nur für sich selbst. Das betrifft
  **Tier 2 stärker als zunächst vermutet**: laut `project.godot`
  (`config/tags = mobile`) und `export_presets.cfg` (Android-Export) ist das
  primäre Zielgerät ein Mobiltelefon — der Host in einer Hosted-Coop-Session
  simuliert damit nicht nur seine eigene Physik (wie heute), sondern zusätzlich
  die aller Mitspieler, auf demselben Gerät, das auch noch rendert. Für Tier 3
  (dediziertes Hosting, eigene Hardware) ist das ein reines Skalierungsthema;
  für Tier 2 ist es eine echte Geräte-Grenze, die vor dem Rollout an mobilen
  Referenzgeräten gemessen werden muss, nicht nur angenommen.

### Mitigationen
- Kein isolierter Merge dieses ADRs ohne ADR-026 — beide werden als ein
  zusammenhängender Umsetzungsschritt behandelt, auch wenn sie als zwei ADRs
  dokumentiert sind (Nachvollziehbarkeit der einzelnen Entscheidungen).
- `NetworkContract.gd` bekommt einen neuen Abschnitt „UNRELIABLE (Input-Streams)"
  neben den bestehenden Kategorien, mit derselben Sorgfalt wie die bisherigen drei
  Kategorien (server-autoritativ / client-autoritativ / shared-read-only).
- Server-Tick-Kosten werden nicht in diesem ADR gelöst (kein Interest-Management,
  kein Culling) — das ist ein separates, späteres Skalierungsthema, explizit nicht
  Teil dieses ADRs, um Scope-Creep zu vermeiden.
- Die Tier-2-Geräte-Grenze (Host-Handy simuliert für alle Mitspieler) wird vor
  Rollout an einem realistischen Referenzgerät mit der für Tier 2 vorgesehenen
  Ziel-Spielerzahl gemessen — kein geschätzter "sollte reichen"-Wert. Sollte sich
  eine Grenze zeigen, ist eine niedrigere maximale Mitspielerzahl in Tier 2 die
  ehrliche Antwort, kein Zurückschrauben der Simulationsgenauigkeit nur für Tier 2
  (das wäre wieder ein Tier-spezifischer Sonderpfad, den ADR-010 ausschließt).

## Ablösung

[Leer lassen bis dieser ADR durch einen neuen abgelöst wird]

## Umsetzungsstand (Round 47)

Implementiert: Authority-Flip (`EntityOrchestrator` setzt Player-Authority nicht
mehr auf `peer_id`, `Player._ready()` setzt `set_multiplayer_authority(1)` wie
jede andere Entity), `submit_movement_input()`/`_rpc_submit_movement_input()`
(unreliable_ordered), `WorldService.route_movement_input()`,
`Player._loop_free_authoritative()` (simuliert für den Host selbst UND für jeden
verbundenen Mitspieler aus dessen zuletzt empfangenem Input),
`MathHelper.calculate_move_direction_from_yaw()` (Ersatz für den kamera-basierten
Pfad, wenn kein lokal rotierter Kamera-Node existiert).

**Nicht in dieser Runde geprüft/gemessen:**
- Die Tier-2-Geräte-Grenze (siehe Mitigation oben) — braucht echte Hardware,
  nicht simulierbar in der Entwicklungs-Sandbox.
- Server-Tick-Kosten bei vielen Spielern — bewusst außerhalb des Scopes (s.o.).
- Ein echter Zwei-Prozess-Netzwerktest (zwei tatsächliche `ENetMultiplayerPeer`-
  Instanzen über echte Latenz) konnte in der Sandbox, in der dieser Code
  entstanden ist, nicht ausgeführt werden (kein Netzwerkzugriff, kein
  Godot-Binary verfügbar). Es existiert ein Testgerüst
  (`tests/integration/test_movement_two_peer.gd`), das zwei lokale
  ENetMultiplayerPeer-Instanzen (127.0.0.1) aufbaut — das ist eine reale
  Zwei-Peer-Verbindung, aber ohne die Latenz/Paketverlust-Bedingungen eines
  echten Internet-Coop-Spiels. Muss vor einem Produktions-Rollout mit echter
  Godot-Umgebung (Editor oder Headless-Export) UND idealerweise künstlich
  injizierter Latenz (z. B. via `ENetMultiplayerPeer` + Netzwerk-Throttling-Tool
  oder zwei physisch getrennten Geräten) verifiziert werden. Bis dahin gilt
  dieser Umbau als "nach bestem Wissen korrekt konstruiert und durch Code-Review
  + Unit-Tests abgesichert", NICHT als "unter realer Netzwerkbedingung verifiziert".

**Update (Round 50):** ein echter Zwei-*Prozess*-Test (nicht nur Zwei-Peer im
selben Prozess) existiert jetzt — siehe ADR-026 "Update (Round 50)" für
Details (`scripts/testing/IT03Harness.gd`). Latenz/Paketverlust/Tier-2-Geräte-
Grenze bleiben davon unberührt weiterhin offen, siehe dort.

**Update (Round 51):** Latenz/Paketverlust sind jetzt ebenfalls simuliert
(`scripts/ci/udp_latency_proxy.py`, siehe ADR-026 "Update (Round 51)").
Verbleibend offen: nur noch die Tier-2-Geräte-Grenzmessung — eine
Hardware-Leistungsfrage, kein Netzwerk-Problem mehr.

**Update (Round 52):** die Mess-*Infrastruktur* für genau diese Grenze
existiert jetzt — `Player._loop_free_authoritative()` misst sich selbst
(`Time.get_ticks_usec()`, aggregiert pro Physik-Frame über alle gleichzeitig
authoritativ simulierten Spieler), abrufbar über die Debug-Konsolen-Befehle
`tier2stats`/`tier2reset`. Volles Protokoll:
[docs/tier2-device-verification.md](../tier2-device-verification.md).
**Ausdrücklich NICHT Teil dieses Updates:** die Messung selbst — die braucht
ein physisches Referenzgerät und eine echte Ziel-Spielerzahl, beides in
dieser Sandbox nicht verfügbar. Dieser Punkt bleibt bis zur tatsächlichen
Durchführung durch den Project Owner offen, mit den Messwerten als
Ergänzung an dieser Stelle.

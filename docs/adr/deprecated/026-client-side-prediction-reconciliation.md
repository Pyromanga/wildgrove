> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-026: Client-Side Prediction & Server-Reconciliation für Movement

**Status:** Umgesetzt (Round 47) — siehe Umsetzungsstand unten
**Datum:** 2026-07
**Kontext:** `Player.gd`, `PlayerMover.gd`, `RemotePlayerInterpolator.gd`,
`NetworkBridge`. Setzt [ADR-025](025-server-authoritative-movement.md) voraus —
löst die dort bewusst ausgelagerte Latenz-Regression für den lokalen Spieler.

## Problem

Mit ADR-025 simuliert nur noch die Autorität die tatsächliche Bewegung. Der lokale
Client wartet ohne Gegenmaßnahme auf die replizierte Server-Antwort, bevor sich sein
Charakter sichtbar bewegt — ein voller Roundtrip pro Eingabe. Bei den heute
üblichen Coop-Sessions (nicht LAN, echtes Internet) ist das spürbar und ein reiner
Rückschritt gegenüber dem heutigen (client-autoritativen) Gefühl.

Das gewünschte Ergebnis: **Sicherheit auf Server-autoritativem Niveau (ADR-025),
Bewegungsgefühl weiterhin ohne wahrnehmbare Latenz** — genau das Muster, das
kompetitive Shooter nutzen, um beides gleichzeitig zu erreichen.

## Optionen

### Option A: Keine Prediction, Latenz wird akzeptiert
- ✅ Kein zusätzlicher Code
- ❌ Widerspricht dem explizit gewünschten Zielniveau — nicht weiter verfolgt

### Option B: Dead Reckoning (Extrapolation ohne Prediction-Historie)
Client extrapoliert aus der letzten bekannten Server-Velocity, bis die nächste
Server-Antwort eintrifft — ähnlich wie `RemotePlayerInterpolator` heute schon für
*fremde* Spieler zwischen Snapshots interpoliert, nur vorwärts statt zwischen zwei
bekannten Punkten.
- ✅ Einfacher als volle Prediction — keine Input-Historie nötig
- ❌ Extrapolation ist nur eine Vermutung ohne Kenntnis der tatsächlichen neuen
  Eingabe — bei Richtungswechseln (der Normalfall bei aktiver Steuerung) sichtbar
  falsch, korrigiert sich erst nach der nächsten Server-Antwort. Für den *lokalen*,
  aktiv gesteuerten Spieler ungeeignet (im Unterschied zu Remote-Spielern, wo
  Extrapolation zwischen fremden, bereits vergangenen Eingaben durchaus passt)

### Option C: Volle Client-Side Prediction + Reconciliation (gewählt)
Der Client führt **denselben** `PlayerMover.calculate_velocity()` + `move_and_slide()`-
Code, den ADR-025 auf den Server verlagert hat, weiterhin **zusätzlich lokal** aus —
sofort bei Eingabe, ohne auf den Server zu warten. Jeder lokal simulierte Zustand
wird mit der `input_seq` aus ADR-025 in einem kleinen Ringpuffer
(`_predicted_states: Array[{seq, position, rotation, velocity}]`, Größe an
erwarteter Round-Trip-Time orientiert, nicht unbegrenzt) zwischengespeichert.

Wenn die autoritative Antwort vom Server eintrifft (repliziert über den in
ADR-025 umgedrehten `MultiplayerSynchronizer`, jetzt mit `input_seq` als
zusätzlichem replizierten Feld statt implizit): Client sucht im Ringpuffer den
lokal vorhergesagten Zustand zu genau dieser `input_seq`. Weicht er von der
Server-Antwort um mehr als eine dokumentierte Toleranz ab → **Reconciliation**:
Client setzt sich auf die Server-Position zurück und **re-simuliert** alle seither
lokal ausgeführten, noch unbestätigten Inputs erneut von dort aus (nicht nur ein
hartes Snap — das würde bei jeder kleinen Server-Korrektur sichtbar ruckeln).
Liegt die Abweichung innerhalb der Toleranz → verworfen, keine Korrektur nötig
(Normalfall, keine Divergenz).

- ✅ Lokaler Spieler bewegt sich weiterhin ohne wahrnehmbare Latenz — dieselbe
  Erfahrung wie heute (client-autoritativ), aber auf einer Simulation, die nur
  eine *Vorhersage* ist, keine Wahrheit
- ✅ Serverautorität aus ADR-025 bleibt vollständig erhalten — Reconciliation
  korrigiert den Client, niemals umgekehrt
- ✅ Etabliertes, gut verstandenes Muster (kein Neuentwurf, sondern Standard-Netcode)
- ❌ Deutlich mehr Zustand und Komplexität als heute: Ringpuffer, Re-Simulation,
  Toleranz-Tuning — der teuerste der drei ADR-020-026 in Aufwand
- ❌ `PlayerMover.calculate_velocity()` muss garantiert **deterministisch** und
  **reentrant** sein (gleicher Input + gleicher Vorzustand → exakt gleiches
  Ergebnis, egal ob einmalig oder als Teil einer Re-Simulation aufgerufen) —
  aktuell nicht geprüft, siehe Risiken

## Entscheidung

**Option C.** Volle Client-Side Prediction mit Re-Simulation bei Reconciliation.
Kein Dead Reckoning (Option B) für den lokalen Spieler — das bleibt weiterhin das
richtige, bereits vorhandene Muster für *fremde* Spieler in
`RemotePlayerInterpolator`, wird davon nicht ersetzt, nur nicht auf den lokalen
Fall übertragen.

## Konsequenzen

### Positiv
- Gleichzeitig Server-Sicherheit (ADR-025) und Client-Responsivität — das
  eigentliche Ziel, das ADR-024 allein nicht erreichen konnte.
- `RemotePlayerInterpolator` bleibt unverändert zuständig für fremde Spieler —
  klare Trennung: Prediction für "ich", Interpolation für "die anderen", keine
  Vermischung der beiden bestehenden/neuen Mechanismen.
- Kein Tier-1-Sonderfall im Reconciliation-Code nötig: für Solo und für den Host
  in Tier 2 (siehe ADR-025s Tier-Kollaps) laufen Vorhersage und autoritative
  Simulation im selben Aufruf — Reconciliation findet dort strukturell immer
  "0 Abweichung", ohne dass ein `if is_tier_1` irgendwo im Prediction-Code stehen
  müsste. Das ist eine Konsequenz des Kollaps-Musters aus ADR-025, kein separat
  zu bauender Fall.

### Negativ / Risiken
- **Determinismus-Annahme ungeprüft:** `PlayerMover.calculate_velocity()` nutzt
  `StatModifierService.get_effective_stat()` — falls sich Stat-Modifier zwischen
  der ursprünglichen Simulation und einer späteren Re-Simulation desselben Ticks
  ändern könnten (z. B. ein Buff läuft mitten im Re-Simulations-Fenster ab), wäre
  das Ergebnis nicht reproduzierbar. Muss vor Implementierung verifiziert werden,
  nicht angenommen.
- Toleranzwert für "Divergenz signifikant genug für Reconciliation" ist ein neuer
  Balance-Parameter — wie in ADR-024 bereits vermerkt: kein geschätzter
  Platzhalter, sondern explizit herzuleiten (aus Sync-Rate + normaler
  Physik-Ungenauigkeit float-basierter Berechnung).
- Größerer Test-Aufwand: Reconciliation ist nur unter echter Netzwerk-Latenz
  beobachtbar — der offene TODO-Punkt „Kein echter Zwei-Peer-Integrationstest"
  wird durch dieses ADR von "wäre gut" zu "notwendig", weil sich Prediction-Bugs
  in einem rein gemockten Test nicht zeigen.

### Mitigationen
- Determinismus wird vor Implementierung durch einen gezielten Test verifiziert
  (gleicher Input + gleicher Vorzustand zweimal hintereinander simuliert → exakt
  gleiches Ergebnis), nicht durch Code-Lektüre angenommen.
- Re-Simulation ist auf den Ringpuffer-Horizont begrenzt (nicht "seit Spielbeginn"),
  Größe explizit an eine erwartete Round-Trip-Time gebunden und dokumentiert.
- Der offene Zwei-Peer-Integrationstest-Punkt wird als Voraussetzung *vor*
  Umsetzung dieses ADRs behandelt, nicht als parallele Nebenarbeit — ohne ihn ist
  Reconciliation nicht verifizierbar, nur "sieht im Einzelspieler-Test gut aus".

## Ablösung

[Leer lassen bis dieser ADR durch einen neuen abgelöst wird]

## Umsetzungsstand (Round 47)

Implementiert: reines `PlayerMover.calculate_velocity()` (effective_speed als
Parameter, kein Live-Stat-Query/Logging-Seiteneffekt mehr), Determinismus-Test
`PM-07` in `test_player_gd.gd`, Prediction-Ringpuffer
(`Player._predicted_states`, 180 Einträge = 3s bei 60Hz), Reconciliation
(`_reconcile_if_needed()`/`_resimulate_from()`), repliziertes
`_last_processed_input_seq`-Feld.

**Determinismus-Voraussetzung:** durch `PM-07` als Unit-Test verifiziert (nicht
nur durch Code-Lektüre angenommen) — aber dieser Test lief in der
Entwicklungs-Sandbox nicht tatsächlich (kein Godot-Binary verfügbar dort). Vor
Rollout mit `gut` oder dem Godot-Editor tatsächlich ausführen.

**Zwei-Peer-Integrationstest:** Die von diesem ADR als Voraussetzung
verlangte Verifikation unter echter Latenz ist NICHT erfüllt — nur ein
lokales Zwei-Peer-Testgerüst (`tests/integration/test_movement_two_peer.gd`,
zwei ENetMultiplayerPeer auf 127.0.0.1, keine künstliche Latenz/kein
Paketverlust). Das ist ehrlich gesagt eine Lücke gegenüber dem, was dieses
ADR ursprünglich als Bedingung *vor* Umsetzung verlangt hat — die Umsetzung
wurde trotzdem vorgenommen (auf expliziten Wunsch, siehe Round-47-Auftrag),
weil ein echter Zwei-Prozess-Test mit injizierter Latenz in dieser Sandbox
technisch nicht herstellbar war (kein Netzwerkzugriff für die Sandbox selbst).
Das ist damit der verbleibende, offene Punkt vor einem Produktions-Rollout —
nicht stillschweigend als erledigt markiert.

### Update (Round 50)

`scripts/testing/IT03Harness.gd` + CI-Job "IT-03 — Two-Process Movement Round
Trip" (build-apk.yml) schließen die zuvor offene Lücke **teilweise**: zwei
echte, getrennte `godot --headless`-Prozesse (Host + Client) mit vollem
App-Boot (ServiceOrchestrator, WorldService, NetworkBridge, Player — keine
Mocks) verbinden sich über einen echten Port, der Client sendet organischen
Input über `Player._loop_free_predicted()`, der Test wartet auf
`Player.get_last_processed_input_seq()` (neuer öffentlicher Getter, vorher
fehlte er — der Grund, warum eine frühere Fassung dieses Harness-Entwurfs nie
grün laufen konnte) ≥ Schwellwert als Beleg für einen echten Round-Trip.
**Weiterhin NICHT abgedeckt:** beide Prozesse laufen auf demselben CI-Runner
über 127.0.0.1 — keine künstliche Latenz, kein Paketverlust, keine reale
Internet-Verbindung, keine Tier-2-Geräte-Grenzmessung. Das ist ein echter
Zwei-Prozess-Test, aber kein Latenz-Test.

### Update (Round 51)

`scripts/ci/udp_latency_proxy.py` schließt den zuletzt offenen Netzwerk-Teil
der obigen Lücke: ein reines UDP-Relay (Python-stdlib/asyncio, kein
Extra-Dependency im CI-Runner) sitzt zwischen Host- und Client-Prozess,
verzögert jedes Paket künstlich (Default 80ms ± 20ms Jitter) und verwirft es
mit einer konfigurierbaren Wahrscheinlichkeit (Default 2% pro Richtung —
compoundet auf ~4% Verlust über den vollen Round-Trip), unabhängig für beide
Richtungen. Der Client verbindet sich gegen den Proxy-Port, nicht direkt
gegen den Host — aus Sicht von `NetworkBridge`/ENet ist das ein Netzwerk mit
echter Latenz, ohne dass GDScript-Seitig irgendetwas angepasst werden musste.
**Weiterhin NICHT abgedeckt:** die Tier-2-Geräte-Grenzmessung (Hardware-, keine
Netzwerkfrage) und Verifikation unter einer echten Internet-Verbindung
zwischen zwei physisch getrennten Geräten (der Proxy simuliert die
*Bedingungen* einer solchen Verbindung, ist aber kein Ersatz für einen Test
auf tatsächlich getrennter Hardware/Infrastruktur).

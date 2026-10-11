# Tier-2-Geräte-Grenzmessung — manuelles Protokoll

**Zugehörig zu:** [ADR-025](adr/025-server-authoritative-movement.md), Abschnitt
„Mitigationen" — der letzte noch offene Punkt aus
`TODO-offene-probleme.md`.

## Warum das nicht in CI automatisierbar ist

ADR-025 verlangt für diesen Punkt explizit **keinen geschätzten
"sollte reichen"-Wert**, sondern eine echte Messung auf einem realistischen
Referenzgerät mit der für Tier 2 vorgesehenen Ziel-Spielerzahl. Das ist eine
bewusste Entscheidung im ADR, keine Lücke, die sich durch mehr Tooling
schließen lässt: ein CPU-gedrosselter CI-Runner simuliert eine geschätzte
CPU-Grenze — genau das, was das ADR ausschließt. Round 51
(`scripts/ci/udp_latency_proxy.py`) hat den *Netzwerk*-Teil der
Zwei-Peer-Lücke geschlossen (Latenz/Paketverlust sind simulierbar, weil sie
reine Netzwerk-Eigenschaften sind); die *Geräte*-Grenze ist eine
Hardware-Frage und bleibt es.

Was Round 52 stattdessen liefert: die Mess-Infrastruktur, damit ein Mensch
mit einem echten Gerät diese Messung tatsächlich durchführen kann, statt sie
von Hand mit einer Stoppuhr zu improvisieren.

## Was gemessen wird

`Player._loop_free_authoritative()` — der Teil, der laut ADR-025 auf Tier 2
zum Problem werden kann (der Host simuliert Physik für JEDEN angeschlossenen
Spieler, auf demselben Gerät, das auch rendert) — misst sich jetzt selbst:
`Time.get_ticks_usec()` vor/nach der eigentlichen Simulation, aggregiert
**pro Physik-Frame über alle gleichzeitig simulierten Spieler** (nicht pro
Spieler einzeln — die interessante Zahl ist "wie viel CPU-Zeit kostet dieser
Tick den Host insgesamt"). Zugriff über die eingebaute Debug-Konsole
(`SimpleTerminal`, siehe `docs/services.md`):

- `tier2stats` — Sample-Anzahl (= Anzahl getrackter Physik-Frames, Ringpuffer
  über die letzten ~10s bei 60Hz), Durchschnitt/p95/Maximum in Mikrosekunden.
- `tier2reset` — Ringpuffer leeren, für einen sauberen Mess-Lauf ab einem
  definierten Startpunkt.

Reiner Lesezugriff auf bereits laufende Simulation — kein Sonderpfad, keine
Verhaltensänderung, kostet im Normalbetrieb nur zwei `Time.get_ticks_usec()`-
Aufrufe pro Tick und Spieler.

## Referenzgerät

Kein geschätzter Wert, aber ein konkreter Anhaltspunkt: `export_presets.cfg`
setzt bereits `min_sdk=24` (Android 7.0, 2016) und baut ausschließlich für
`arm64-v8a` — das ist die vom Projekt selbst bereits committete untere
Grenze. Ein Referenzgerät nahe an dieser Grenze (mehrere Jahre altes
Mittelklasse-Gerät, nicht das aktuelle Entwickler-Handy) ist der ehrliche
Test — ein aktuelles Flagship-Telefon würde diese Frage nicht beantworten.

## Protokoll

1. **Ziel-Spielerzahl festlegen.** Wie viele gleichzeitige Mitspieler soll
   Tier 2 (Hosted Coop) unterstützen? Das ist eine Produktentscheidung, kein
   technischer Wert — dieses Dokument setzt keine Zahl voraus.
2. **Debug-Build auf dem Referenzgerät installieren.** Normaler
   Android-Export-Flow, kein Sonderbuild — `SimpleTerminal` ist bereits Teil
   des Spiels (kein `--it03-*`-Cmdline-Trick nötig, der auf Android ohnehin
   nicht praktikabel wäre).
3. **Session hosten** auf dem Referenzgerät (normaler UI-Flow:
   „Host starten"). Sobald alle Ziel-Mitspieler beigetreten sind und sich
   eingependelt haben (kein Verbindungsaufbau-Rauschen mehr in den
   Werten): `tier2reset` in der Debug-Konsole ausführen.
4. **Realistische Last erzeugen.** Alle Mitspieler bewegen sich gleichzeitig
   für mindestens 2 Minuten — nicht still stehen (das misst den Leerlauf,
   nicht die Grenze). Idealerweise inklusive typischer Begleitlast
   (Interaktionen, Kämpfe, Rendering-Last durch mehrere sichtbare Spieler),
   nicht nur reine Bewegung — Movement-Simulation konkurriert mit allem
   anderen um dieselbe Frame-Zeit.
5. **`tier2stats` auslesen** auf dem Referenzgerät. Ergebnis (Sample-Anzahl,
   avg/p95/max in Mikrosekunden), Gerätemodell, tatsächliche Spielerzahl und
   Datum notieren.
6. **Einordnen.** Bei 60Hz Physik-Tickrate steht pro Tick ein Budget von
   ~16667µs zur Verfügung — geteilt zwischen Rendering, dieser Movement-
   Simulation, jeder anderen Physik/Gameplay-Logik und OS-Overhead.
   Movement-Simulation ist nur EIN Verbraucher davon, kein Alleinstellungs-
   Budget. Wo genau die Grenze liegt (welcher Anteil noch akzeptabel ist),
   ist eine Produktentscheidung des Project Owners, keine, die dieses
   Dokument vorwegnimmt.
7. **Ergebnis eintragen.** Die gemessenen Werte (nicht nur "getestet, war ok")
   gehören in ADR-025 „Umsetzungsstand" als neuer, datierter Absatz —
   Gerätemodell, Spielerzahl, avg/p95/max, Entscheidung (Ziel-Spielerzahl
   bestätigt oder nach unten korrigiert). Siehe ADR-025 „Mitigationen": eine
   niedrigere Tier-2-Spielerzahl ist die ehrliche Antwort bei einer
   gefundenen Grenze, keine tierspezifische Reduktion der Simulationsgenauigkeit.

## Optional: mehrere entfernte Mitspieler ohne N physische Testgeräte

Nur das HOSTENDE Gerät muss das Referenzgerät sein (es simuliert die
gesamte Physik). Die Mitspieler-Clients können auf beliebiger anderer
Hardware laufen (PC-Debug-Builds, andere Test-Handys) — für diese Messung
zählt nur, dass ihr Input echt und gleichzeitig eintrifft, nicht auf welchem
Gerät er erzeugt wird. Das hält den Aufwand überschaubar: ein Referenzgerät
als Host, beliebig viele günstigere Client-Quellen für die Ziel-Spielerzahl.

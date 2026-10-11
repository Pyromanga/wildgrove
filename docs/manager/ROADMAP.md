# ROADMAP.md — Zielbild, vom Manager selbst gepflegt

Diese Datei gehört dem Manager, nicht dem Menschen — sie wird bei jedem
größeren Entscheidungs-Batch aktualisiert (normalerweise durch
`metrik-master` im Meta-Review, siehe MEMORY_PROTOCOL.md). Der Mensch kann
jederzeit reingrätschen, aber Standardfall ist: der Manager pflegt sie
selbst.

## Phase 0 — Infrastruktur (Round 110, aktuell)
Manager-Protokoll, Rollen, Decision-/Metrik-Logging, `make brief` als
Einstiegspunkt für jede neue Session. **Kein** Architektur-Abriss in dieser
Phase — explizite Entscheidung des Menschen (siehe Decision 0001/0002).

## Phase 1 — Architektur-Assessment (nächster echter Manager-Lauf)
Bestandsaufnahme: welche der 49 ADRs haben ein zugehöriges Build-/Check-
Script (→ real), welche nicht (→ unverifizierte Behauptung, Abriss-
Kandidat)? Ergebnis ist eine Liste mit Empfehlung pro ADR
(behalten/verscripten/verwerfen), keine Ausführung in dieser Phase.

## Phase 2 — Determinismus schrittweise erzwingen
Ziel aus §8 MANAGER.md: irgendwann läuft der Manager voll autonom, jede
Änderung geht über ein Makefile-Target. Weg dahin: pro Änderungsklasse
(nicht pro Datei) entscheiden, ob sich ein Codemod lohnt — Muster aus
Round 109 (`eventbus-direct`) ist der Präzedenzfall. Kein Big-Bang-Zwang.

## Phase 3 — Test-Runner-Lücke schließen

**GATE (Decision 0009, Round 110): nicht anfangen, bevor der Mensch explizit
sagt, dass das Grundprojekt steht.** Das ist keine Priorisierungs-Empfehlung,
sondern eine harte Sequenz-Vorgabe — auch wenn ein künftiger Manager-Lauf
Kapazität dafür hätte. Erst fragen/warten, dann bauen.

Aktuell: `.gd`-Tests existieren, kein Runner (siehe Decision 0005 /
`roles/code-tester.md`). Braucht eine Entscheidung GUT vs. gdUnit4
(Netzwerk/Download nötig — kann nicht in dieser Sandbox passieren, das ist
eine der wenigen Stellen, wo der Manager den Menschen aktiv braucht, siehe
MANAGER.md §7).

## Phase 4 — Spielkonzept-Architektur (Interaction-RPG / Bio-Content)
Erst NACH Phase 1–3, weil eine Content-Schicht (Tiere/Pflanzen/Ökosysteme
als Spieldaten) auf einer sauberen Service-Architektur aufsetzen sollte,
nicht auf einer, die gerade noch abgerissen wird. Genre-Mix
(Animal Crossing / Pokémon / Age of Empires / Minecraft-Terraria / RuneScape)
braucht eine eigene Grundsatzentscheidung mit dem Menschen (Genre-Priorität,
Lern-vs-Spiel-Balance) — kein Punkt, den der Manager allein durchentscheiden
sollte (MANAGER.md §7).

## Nicht-Ziele dieser Roadmap
Kein festes Datum pro Phase. Fortschritt wird an Decisions/Metriken
gemessen, nicht an Kalenderzeit — aus demselben Grund wie die
Meta-Review-Kadenz in MEMORY_PROTOCOL.md.

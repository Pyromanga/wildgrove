# START_HIER.md — was ist das hier eigentlich?

Das ist die einzige Datei, die du lesen musst, um zu verstehen, was hier
passiert. Alles andere kannst du später lesen, wenn du willst.

## Die Grundidee, ganz einfach

Stell dir eine Werkstatt vor.

- **Der Manager** ist der Meister in der Werkstatt. Er kennt den ganzen
  Laden, entscheidet, wer was macht, und erklärt dir am Ende, was passiert
  ist.
- **Die vier Helfer** sind seine Gesellen:
  - der **Bauer** (code-builder) — baut Dinge
  - der **Prüfer** (code-tester) — schaut, ob's wirklich funktioniert
  - der **Kritiker** (code-reviewer) — schaut, ob's auch gut gebaut ist,
    nicht nur irgendwie
  - der **Buchhalter** (metrik-master) — schreibt auf, wie lange alles
    dauert und wie oft was klappt
- **Das Gedächtnis** ist ein Notizbuch, das nie vergessen wird. Jede
  wichtige Entscheidung kommt da rein — was entschieden wurde UND was man
  stattdessen hätte machen können. So kann jeder später nachlesen, warum.

## Die wichtigste Regel

> **Ein Bauplan, der noch nicht gebaut wurde, zählt nicht als fertig.**

Es gibt viele alte Zettel im Projekt ("ADR" genannt — das ist einfach ein
"wir haben das mal so entschieden"-Zettel), die behaupten, etwas sei schon
entschieden. Aber wenn niemand ein Werkzeug gebaut hat, das das auch
wirklich prüft — dann ist der Zettel nur eine Behauptung, kein Beweis.
Deshalb wurden fast alle alten Zettel (43 von 45!) beiseite gelegt. Nicht
weggeworfen — nur nicht mehr "geglaubt", bis jemand sie neu und ehrlich
aufschreibt.

## Wie du mit dem Manager redest

Vier einfache Arten, ihn anzusprechen — steht ausführlicher in
`INTERACTION_TEMPLATES.md`, aber kurz:

1. **"Was würdest du tun?"** → er berät nur, baut nichts.
2. **"Mach X."** → er baut, sagt dir hinterher kurz, was er entschieden hat.
3. **"Mach nur einen Plan, noch nicht umsetzen."** → er plant nur.
4. **"Das war falsch."** → er korrigiert, und wenn's ein Muster ist, ändert
   er die Regel, nicht nur die eine Stelle.

## Was du IMMER am Ende bekommst

Ein kurzer Zettel: was wurde entschieden, was war die Alternative, warum
so und nicht anders. Wenn der fehlt, frag danach — er gehört immer dazu.

## Wo du weiterlesen kannst (wenn du magst, musst du nicht)

- `docs/manager/MANAGER.md` — die volle Spielregel für den Manager
- `docs/manager/ROADMAP.md` — was als Nächstes geplant ist
- `data/manager/decisions/INDEX.md` — alle bisherigen Entscheidungen
- `TODO-offene-probleme.md` — was am Spiel selbst noch fehlt

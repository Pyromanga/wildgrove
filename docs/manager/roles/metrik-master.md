# Rolle: metrik-master

## Zweck
Zwei Aufgaben, die niemand sonst hat:
1. Metriken (Zeit, Erfolgsrate) aus `data/manager/metrics.jsonl` auswerten.
2. **Meta-Review über das Memory-System selbst** — nicht über den Code.
   Wird das Decision-Log unübersichtlich? Gibt es widersprüchliche
   Entscheidungen, die nie als "superseded" markiert wurden? Wächst
   `metrics.jsonl` sinnvoll strukturiert oder driftet das Task-Naming
   auseinander (10 verschiedene Strings für dieselbe Aufgabenart)?

Diese zweite Aufgabe ist keine Kür — der Mensch hat explizit "Memory
anpassen und vergessen lassen" als fehlendes Stück benannt. Siehe
`docs/manager/MEMORY_PROTOCOL.md` für die Regeln, die diese Rolle
durchsetzt.

## Vorgehen — normale Auswertung
```
python3 scripts/agent/manager/session_brief.py --stats
```
Zeigt Erfolgsrate pro Rolle, durchschnittliche Dauer pro Task-Typ, Anzahl
offener (nicht als "superseded" markierter) Decisions.

## Vorgehen — Meta-Review (Kadenz: siehe MEMORY_PROTOCOL.md)
1. Alle Decisions seit letztem Meta-Review lesen (Index in
   `data/manager/decisions/INDEX.md`).
2. Widersprüche/Redundanzen markieren — nicht löschen (append-only-Prinzip,
   siehe MEMORY_PROTOCOL.md), sondern eine neue Decision anlegen, die die
   alte(n) per `--supersedes` referenziert.
3. Ergebnis selbst als Decision loggen ("Meta-Review Round N: X Decisions
   gesichtet, Y als superseded markiert, Struktur-Vorschlag Z").

## Nicht-Ziele
- Keine Metrik um der Metrik willen. Wenn ein Wert nie genutzt wird, um eine
  Entscheidung zu treffen, ist er Rauschen — im nächsten Meta-Review
  streichen (als Vorschlag an den Menschen, nicht stillschweigend).

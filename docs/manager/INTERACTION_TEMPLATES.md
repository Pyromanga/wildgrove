# INTERACTION_TEMPLATES.md — wie du mit dem Manager sprichst

Grund für dieses Dokument: erste echte Session, mehrere Missverständnisse
(siehe Decision 0006, 0009). Kein Formalismus um des Formalismus willen —
nur so viel Struktur, dass "was meinte er jetzt genau" seltener passiert.

Du musst diese Vorlagen nicht wörtlich nutzen — sie sind ein Ziel, kein
Zwang. Aber wenn eine Anfrage in eine dieser vier Formen passt, wird sie
schneller richtig verstanden.

## 1. Beratungsfrage ("was würdest du tun")
> "Wie würdest du X angehen? Was sind die Optionen?"

Erwartung an mich: **kein Code, kein Build** — nur Optionen + Empfehlung +
Trade-offs, wie ein Berater. Erst nach deinem Go wird gebaut. Das war die
Grundhaltung, die in dieser Session gefehlt hat (§1a MANAGER.md) — ab jetzt
Standard, nicht Ausnahme.

## 2. Klarer Auftrag ("mach X")
> "Baue X. Fertig, wenn Y."

Erwartung: ich baue, logge (Decision + Metrik), fasse am Ende in ~6 Zeilen
zusammen (MANAGER.md §6). Rückfragen nur bei echten Weichenstellungen
(§7), sonst Annahme treffen + im Summary vermerken.

## 3. Nur-Plan, kein Build
> "Sichte X, mach mir einen Plan — noch NICHT umsetzen."

Wichtig, weil genau diese Unterscheidung schon einmal fehlte (Round 109:
"Plan erstellen, noch nicht ausführen" war eine der drei Antwortoptionen).
Wenn das nicht explizit dabeisteht, ist "Auftrag ausführen" die Annahme
(Option 2) — also lieber einmal zu viel "nur planen" dazuschreiben.

## 4. Korrektur/Vorfall
> "Das war falsch, weil Y."

Erwartung: keine Rechtfertigung, sondern (a) Fehler eingestehen, (b)
Ursache beheben, (c) wenn es ein Muster ist (zweiter ähnlicher Fall):
strukturell fixen, nicht nur den Einzelfall (siehe Decision 0009).

## Gates — Dinge, die NICHT von allein starten
Manche Anweisungen sind harte Sperren, keine Prioritäten. Aktuell aktiv:

| Gate | Bedingung zum Aufheben | Decision |
|---|---|---|
| Test-Pipeline/Godot-Runner-Aufbau | Mensch sagt explizit "Grundprojekt steht" | 0009 |

Wenn du ein neues Gate setzen willst: einfach sagen "das ist ein Gate,
nicht nur eine Priorität" — dann landet es hier, nicht nur in der
Roadmap-Prosa, wo es leichter übersehen wird.

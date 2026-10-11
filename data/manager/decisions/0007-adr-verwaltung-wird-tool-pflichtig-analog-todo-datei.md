# 0007 — ADR-Verwaltung wird Tool-pflichtig, analog TODO-Datei

Zeit: 2026-08-02 11:31 UTC
Rolle: manager

## Gewählt
adr_tool.py (list/show/audit/deprecate) als einziger vorgesehener Weg, ADR-Status zu pruefen oder ADRs zu deprecaten. Status wird live aus Repo-Zustand berechnet, nicht in einer separaten State-Datei gepflegt (vermeidet Drift).

## Verworfene Alternativen
- ADR-Status manuell in einer Tracking-Tabelle pflegen
- ADRs weiter nur als Freitext-Markdown ohne jedes Tooling behandeln

## Begründung
Mensch: 'ADRs muessen genauso wie TODOs sauber ueber Scripte laufen, alles andere ist legacy.' Live-Berechnung statt gepflegtem State vermeidet, dass der Status selbst wieder veraltet.

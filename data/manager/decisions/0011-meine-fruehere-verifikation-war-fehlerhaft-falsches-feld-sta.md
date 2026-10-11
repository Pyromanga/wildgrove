# 0011 — Meine fruehere Verifikation war fehlerhaft: falsches Feld statt ERROR_KINDS geprueft

Zeit: 2026-08-02 19:17 UTC
Rolle: code-tester

## Gewählt
Alle bisherigen 'X ERROR-Findings'-Aussagen in dieser Session waren mit einem Check gegen ein nicht existierendes Feld 'severity' erstellt -- immer 0, unabhaengig vom echten Zustand. Korrigiert: echte Klassifikation ist f['kind'] in ERROR_KINDS/WARN_KINDS. Realer Zustand: 7 ECHTE ERROR-Findings vorhanden (6 nach Fix unten).

## Verworfene Alternativen
- Fehler stillschweigend weiterlaufen lassen, da 'wahrscheinlich eh ok'

## Begründung
Vertrauen in die eigenen Tool-Aufrufe ist die Grundlage des ganzen Manager-Systems -- eine falsch-positive Gruen-Meldung ist schlimmer als gar keine Pruefung, weil sie Sicherheit vortaeuscht.

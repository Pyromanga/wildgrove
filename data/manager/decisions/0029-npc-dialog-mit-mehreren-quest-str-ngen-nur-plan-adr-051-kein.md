# 0029 — NPC-Dialog mit mehreren Quest-Strängen: nur Plan (ADR-051), keine Umsetzung

Zeit: 2026-09-26 10:45 UTC
Rolle: manager

## Gewählt
ADR-051 geschrieben (3 gestaffelte Ausbaustufen: mehrere Quest-Slots pro NPC -> Auswahlliste -> volles verzweigendes Dialogsystem), TODO-Eintrag ergaenzt, Index aktualisiert. Kein Code geaendert.

## Verworfene Alternativen
- Sofort Stufe 1 (mehrere Quest-Slots) umsetzen
- Sofort Stufe 2 (+ Auswahl-UI) umsetzen
- Sofort volles Runescape-artiges Dialogsystem (Stufe 3) bauen

## Begründung
Nutzer hat bei explizit gestellter Auswahl (klein/mittel/gross/nur Plan) 'nur Plan/ADR schreiben, Umsetzung spaeter' gewaehlt -- Kontext-Budget der Session war laut Nutzer ohnehin fast am Limit. Architekturentscheidung dieser Groessenordnung verdient laut MANAGER.md §3/§7 ohnehin eine bewusste, eigene Session statt nebenbei in einer Quest-Content-Runde entschieden zu werden.

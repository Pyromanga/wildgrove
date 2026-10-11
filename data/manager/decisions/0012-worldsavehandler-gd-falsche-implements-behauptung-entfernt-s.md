# 0012 — WorldSaveHandler.gd: falsche ## implements-Behauptung entfernt statt Code ergaenzt

Zeit: 2026-08-02 19:17 UTC
Rolle: code-builder

## Gewählt
Kommentar '## implements ISaveProvider' aus WorldSaveHandler.gd entfernt -- die Klasse ist nie ueber register_save_provider() registriert, WorldService ist der echte Provider und delegiert nur intern. Kein fehlender Code (get_save_key() haette nichts Sinnvolles zurueckgeben koennen -- die Klasse hat keinen eigenen Save-Key-Begriff).

## Verworfene Alternativen
- Kuenstliches get_save_key() ergaenzen, nur um den Checker zufriedenzustellen

## Begründung
Der Kommentar war schlicht falsch, kein Lueckenfall -- ein erfundener Rueckgabewert haette eine Behauptung ueber etwas gemacht, das WorldSaveHandler gar nicht tut. TODO-offene-probleme.md Punkt 1 selbst vermutete das bereits ('unauffaellig nur weil WorldSaveHandler nirgends registriert wird').

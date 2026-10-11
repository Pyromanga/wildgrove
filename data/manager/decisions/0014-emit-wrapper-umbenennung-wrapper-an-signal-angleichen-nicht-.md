# 0014 — Emit-Wrapper-Umbenennung: Wrapper an Signal angleichen, nicht umgekehrt

Zeit: 2026-08-02 19:35 UTC
Rolle: code-builder

## Gewählt
Alle 7 emit_<wrapper>() auf emit_<signal_name>() umbenannt -- per-Fall verifiziert dass Wrapper-Rename die kleinere Aenderung ist (Signal-Name erscheint an Deklaration+allen .connect()-Stellen+eigenem .emit(); Wrapper-Name nur an Definition+Call-Sites). Codemod gebaut (fix_emit_wrapper_names.py), Dry-Run vor Apply.

## Verworfene Alternativen
- Stattdessen die 7 Signale umbenennen (mehr Connect-Stellen betroffen, groesserer Blast-Radius)
- Von Hand ohne Codemod aendern

## Begründung
TODO-Punkt 5 verlangte explizit Einzelfall-Entscheidung, keine Pauschale -- Blast-Radius-Analyse pro Fall (grep auf Wrapper-Calls vs Signal-Connects) ergab durchgaengig: Wrapper-Rename ist die kleinere, sichere Aenderung. Als Codemod gebaut (nicht /tmp), damit die Analyse nachvollziehbar/wiederholbar bleibt.

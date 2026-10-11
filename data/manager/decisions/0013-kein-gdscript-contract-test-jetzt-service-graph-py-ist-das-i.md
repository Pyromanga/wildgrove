# 0013 — Kein GDScript-Contract-Test jetzt -- service_graph.py ist das Interims-Aequivalent

Zeit: 2026-08-02 19:17 UTC
Rolle: manager

## Gewählt
TODO-Punkt 2/3 (Contract-Test fuer ISaveProvider-Konformitaet) bleibt fachlich offen bis Phase 3 (Test-Runner, Decision-0009-Gate). service_graph.py's UNVERIFIED_INTERFACE_CLAIM (ERROR) + MISSING_OVERRIDE (WARN) sind ab jetzt offiziell das Interims-Contract-Test-Aequivalent: strenger als noetig (verlangt extends ODER echten Testlauf), aber ehrlich -- kein Kommentar zaehlt als Beweis.

## Verworfene Alternativen
- GDScript-Testdatei jetzt schreiben, obwohl sie in dieser Sandbox nicht ausfuehrbar/verifizierbar ist
- UNVERIFIED_INTERFACE_CLAIM-Schwelle abschwaechen, damit die 6 verbleibenden Faelle nicht mehr als ERROR zaehlen

## Begründung
Ungeprueften GDScript-Code zu schreiben waere wieder 'raten' (Nutzer-Kritik von vorhin) -- Syntax-/API-Fehler koennte ich hier nicht erkennen. Die Schwelle abschwaechen waere Schoenrechnen. Ehrlich 'ERROR, bis ein echter Test das beweist' ist die einzige Option, die weder raet noch beschoenigt.

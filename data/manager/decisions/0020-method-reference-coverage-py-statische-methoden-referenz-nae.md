# 0020 — method_reference_coverage.py: statische Methoden-Referenz-Naeherung statt echter Line-Coverage (Phase-3-Gate respektiert)

Zeit: 2026-08-30 19:58 UTC
Rolle: manager

## Gewählt
Neues Tool scripts/agent/method_reference_coverage.py -- prueft pro Service-Methode statisch, ob sie in der zugeordneten Testdatei (per bestehender 'Tests fuer <ClassName>'-Header-Konvention) ueberhaupt als .methodenname( aufgerufen wird. Explizit als Naeherung gekennzeichnet, nicht als Coverage-Ersatz. Modi: Default (nur Luecken), --service <name> (Detail), --full (alle Methoden), --json. Makefile-Target 'method-coverage' ergaenzt.

## Verworfene Alternativen
- Echten Coverage-Runner (GUT/gdUnit4 + Coverage-Addon) installieren und ausfuehren -- verworfen: kein Godot-Binary in der Sandbox, kein Netzwerk fuer Addon-Download, UND explizit per Decision 0009/ROADMAP.md Phase 3 gesperrt ('nicht anfangen, bevor der Mensch explizit sagt, dass das Grundprojekt steht'). Dieses Gate wurde nicht umgangen -- das Tool installiert/startet nichts, es liest nur Textdateien.

## Begründung
Der Mensch wollte 'genaue Test Coverage welche Zeilen wie getestet sind' -- das ist ehrlich nicht lieferbar ohne echte Codeausfuehrung, und Codeausfuehrung ist hier doppelt blockiert (Sandbox-Limitierung + Projekt-Gate). Statt entweder zu verweigern oder das Gate zu umgehen: die bestmoegliche statische Naeherung liefern, unmissverstaendlich als Naeherung beschriftet (Kopfkommentar + Ausgabe-Header), mit klarer Nennung was fuer die echte Variante fehlt (Godot + GUT/gdUnit4, Freigabe Phase 3).

# 0005 — Test-Runner-Lücke: kein GUT/gdUnit4, kein Godot-Binary in Sandbox

Zeit: 2026-08-02 11:25 UTC
Rolle: code-tester

## Gewählt
Lücke offen dokumentieren (roles/code-tester.md, ROADMAP.md Phase 3) statt so zu tun als seien .gd-Tests verifiziert

## Verworfene Alternativen
- Ignorieren / stillschweigend als 'getestet' behandeln
- Sofort einen Runner bauen/simulieren ohne echtes Godot

## Begründung
Ehrlichkeit über Testabdeckung ist wichtiger als grüner Anschein — Sandbox hat kein Netzwerk, ein Runner-Addon kann hier nicht nachgeladen werden, das braucht den Menschen lokal.

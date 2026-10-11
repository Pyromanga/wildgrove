# 0008 — ADR-Audit-Befund: 2 von 45 ADRs sind script-enforced, 43 unverifiziert

Zeit: 2026-08-02 11:31 UTC
Rolle: code-reviewer

## Gewählt
43 unverifizierte ADRs NICHT sofort massenhaft loeschen/deprecaten. Nächster Schritt (Roadmap Phase 1, Fortsetzung): pro ADR einzeln entscheiden -- Check-Script bauen (wenn die Regel noch gilt und pruefbar ist) oder explizit deprecaten (adr_tool.py deprecate) -- nicht pauschal.

## Verworfene Alternativen
- Alle 43 unverifizierten ADRs sofort deprecaten, weil unbewiesen
- Status quo belassen, nur dokumentieren

## Begründung
Unverifiziert heisst nicht automatisch falsch -- manche (z.B. ADR-029 player_uuid statt peer_id) sind laut TODO-Datei bereits umgesetzt, nur nicht durch ein Script geprueft. Pauschal-Loeschen wuerde echtes Wissen vernichten; pauschal-Behalten waere das alte Problem. Einzelfall-Entscheidung ist der einzige ehrliche Weg.

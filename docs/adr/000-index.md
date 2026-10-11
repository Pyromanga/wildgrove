# Architecture Decision Records — WildGrove

**Neustart (Round 110, Decision 0010).** 43 der ehemals 45 ADRs waren reine
Behauptung ohne zugehöriges Build-/Check-Script (siehe `adr_tool.py audit`)
— nach `docs/adr/deprecated/` verschoben, nicht gelöscht (Historie bleibt
nachvollziehbar, ist aber nicht mehr bindend).

**Regel ab jetzt (siehe `docs/manager/MANAGER.md` §3):** ein ADR heißt "es
gibt noch kein Build-Script dafür". Ein neuer ADR wird nur angelegt, wenn er
aus einem bekannten, aktuell offenen Punkt entsteht (`TODO-offene-probleme.md`,
Checkbox-Items) — nicht rekonstruiert aus Altbestand.

Werkzeug: `python3 scripts/agent/adr_tool.py list` / `show <nnn>` / `audit`
/ `deprecate <nnn> --reason "..."`. Nie von Hand in dieser Tabelle editieren
außerhalb dieses Tools — sonst driftet sie wieder auseinander wie vorher.

## Aktiv (script-enforced)

| Nr. | Titel | Enforced durch |
|-----|-------|-----------------|
| [012](012-ui-eventbus-injection.md) | UI-EventBus-Injection | `service_graph.py` |
| [017](017-cross-scope-service-access.md) | Cross-Scope Service Access | `service_graph.py` |

## Proposed (Konzept, noch nicht code-enforced — siehe eigener Status im ADR)

| Nr. | Titel | Grund |
|-----|-------|-----------------|
| [050](050-native-signal-domain-event-migration.md) | Native-Signal → Domain-Event-Migration | Konzept/Plan vor Code (TODO Punkt 5) — Phase 3 macht es ENFORCED |
| [051](051-npc-dialogue-multi-quest.md) | NPC-Dialog: mehrere gleichzeitige Quest-Stränge & Gesprächsoptionen | Stufe 1+2+3 umgesetzt (nur GUT-Tests, kein eigenes Check-Script → bleibt unverified) |

## Deprecated (43, siehe `docs/adr/deprecated/`)

Historie, nicht bindend. `adr_tool.py list` zeigt nur den aktiven Bestand.

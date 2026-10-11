# 0016 — ADR-050: Migrationskonzept fuer Native-Signal-Cross-Layer-Faelle, EventBus wiederverwenden statt neuer Mechanismus

Zeit: 2026-08-02 21:01 UTC
Rolle: manager

## Gewählt
ADR-050 geschrieben (Status: Proposed, bewusst nicht ENFORCED bevor Phase 3/Codemod existiert). Zielarchitektur: CROSS_LAYER-Signale (52) wandern in die bestehende EventBus/*Events.gd-Indirektion (Path B, ADR-012/017) statt einen neuen Domain-Event-Mechanismus zu erfinden. 4-Phasen-Plan: (1) 18 NEEDS_HUMAN-Faelle einzeln klaeren, (2) 52 CROSS_LAYER-Faelle in Domain-Batches migrieren, (3) Codemod bauen, (4) Regressions-Finding in service_graph.py. Keine Migration in diesem Round durchgefuehrt -- nur das Konzept, wie von TODO Punkt 5 gefordert.

## Verworfene Alternativen
- Neue eigene DomainEvent-Klassenhierarchie statt EventBus wiederzuverwenden -- verworfen, verdoppelt exakt das Problem (zwei Kanaele fuer eine Tatsache) eine Ebene hoeher.
- Alle 52 CROSS_LAYER-Faelle in einem Round migrieren -- verworfen, TODO Punkt 5 nennt dies selbst die riskanteste Migration der Liste.
- NEEDS_HUMAN-Faelle automatisch nach bestem Wissen aufloesen -- verworfen, waere das gleiche stille Raten, das der bereits behobene EMIT_WRAPPER_UNRESOLVED-Bug als Praezedenzfall zeigt.

## Begründung
TODO Punkt 5 verlangt explizit ein Konzept/ADR VOR jedem Code-Schritt, weil es die groesste und riskanteste Migration der Liste ist. ADR-050 liefert genau das: Zielmechanismus + Sequenzierung, ohne vorzeitig ENFORCED zu behaupten (Decision 0010) oder die 18 unklaren Faelle zu erraten statt sie offen als naechsten Schritt zu benennen.

# 0018 — architecture_overview.py: Architektur-Abriss als Script statt Gedaechtnisleistung/manuell gepflegter Doku

Zeit: 2026-08-29 01:13 UTC
Rolle: manager

## Gewählt
Neues Tool scripts/agent/architecture_overview.py -- leitet Services (config/BootstrapConfig.tres), EventBus-Namespaces (scripts/eventbus/EventBus.gd), Domains/Dateizahlen, ADR-Status (docs/adr/), und Test-Abdeckung (tests/unit/) bei jedem Lauf frisch aus den Quelldateien ab, kein Cache/Snapshot. Modi: Kurzabriss (Default), --full (+ EventBus-Namespaces + ADRs), --domain <name> (eine Domain vertiefen), --json (maschinenlesbar), --write-report (docs/manager/reports/architecture-overview.md). Makefile-Targets 'overview'/'overview-full' ergaenzt, analog zu graph/signal-categorize.

## Verworfene Alternativen
- Eine von Hand gepflegte ARCHITECTURE.md schreiben -- verworfen, veraltet erfahrungsgemaess sofort (siehe den stale-WIP-Fund in Round 113: eine Zusammenfassung, die den echten Dateizustand nicht widerspiegelte, hat den letzten Round fast falsch fortgesetzt). Ein Script, das direkt aus BootstrapConfig.tres/EventBus.gd liest, kann per Definition nicht staler werden als die Quelle selbst. | In session_brief.py integrieren statt eigenes Tool -- verworfen, session_brief.py beantwortet 'wo stehen wir' (Decisions/Metriken/Roadmap-Phase), dieses Tool beantwortet eine andere Frage ('was existiert strukturell') -- getrennte Concerns, getrennte Tools, wie es der Rest von scripts/agent/ bereits vorlebt (service_graph.py vs. analyze_native_signals.py).

## Begründung
Direkter Anlass: in diesem Round hat sich gezeigt, dass ein reiner Text-Abriss in einer frueheren Session-Zusammenfassung nicht mit dem tatsaechlichen Repo-Zustand uebereinstimmte -- Vertrauen in eine Behauptung statt in eine ausfuehrbare Quelle war der Fehler. Ein Script, das bei jedem Aufruf frisch parst, macht diese Fehlerklasse strukturell unmoeglich: es kann nicht veralten, weil es keinen Zwischenspeicher hat, nur Ableitung. Passt zum bestehenden Werkzeug-Muster (service_graph.py, analyze_native_signals.py) statt einen neuen Stil einzufuehren.

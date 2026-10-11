# 0001 — Manager-Runtime: in-repo Protokoll statt Subagents/Orchestrator

Zeit: 2026-08-02 11:25 UTC
Rolle: manager

## Gewählt
Reines Protokoll+Scripts im Repo (docs/manager/, scripts/agent/manager/) — jede Claude-Session, auch Chat, kann Manager sein

## Verworfene Alternativen
- Claude Code Subagents (.claude/agents/*.md) — echte Parallelität, aber erfordert lokales Claude-Code-Setup, läuft nicht im Chat
- Eigener Python-API-Orchestrator (manager.py mit eigenen Claude-API-Calls) — headless-fähig, aber doppelte Tokenkosten + eigenes API-Key-Handling, für den Menschen intransparent

## Begründung
Memory/Self-Healing/Meta-Review muss laut Anforderung IM Projekt leben und für jede Session (auch Mobile-Chat mit Kontextlimits) sofort nutzbar sein, ohne Zusatz-Setup.

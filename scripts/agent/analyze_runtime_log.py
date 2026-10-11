#!/usr/bin/env python3
# scripts/agent/analyze_runtime_log.py
#
# DEBUG-COMMAND für Agents — Runtime-Log-Analyse (Godot-Logdateien aus
# Spielsessions). Gegenstück zu service_graph.py (das den STATISCHEN Code
# prüft) — dieses Modul prüft, was TATSÄCHLICH zur Laufzeit passiert ist.
# Liest ausschließlich die übergebene(n) Logdatei(en), führt KEINE Änderungen
# am Code durch (read-only, wie service_graph.py).
#
# WARUM DIESES MODUL EXISTIERT (2026-09-13, Solo-Playtest-Session):
# Log-Analyse per Ad-hoc-grep im Chat ist nicht reproduzierbar und nicht
# wiederholbar, sobald der nächste Log reinkommt — jedes Mal wieder von Hand
# grep-Pattern bauen, Zeilen zählen, Backtraces von Hand zuordnen. Dieses
# Modul kodiert die bereits bekannten Fehlerklassen (siehe KNOWN_PATTERNS
# unten) als wiederholbare Regeln — neue Logs laufen automatisch durch
# dieselbe Klassifikation, und neue Fehlerklassen werden hier als neue
# Pattern-Einträge ergänzt statt als Einmal-grep im Chat zu verpuffen.
#
# Jedes KNOWN_PATTERN kennt optional eine `fix_hint`, die auf das passende
# Modul in scripts/agent/build/ verweist (z.B. fix_known_runtime_bugs.py) —
# damit "Analyse" und "Fix" durchgängig scriptbar bleiben (kein manuelles
# Nachschlagen "welcher Fix gehört zu diesem Fehler").
#
# Usage:
#   python3 scripts/agent/analyze_runtime_log.py <logfile> [<logfile> ...]
#   python3 scripts/agent/analyze_runtime_log.py --json <logfile>

from __future__ import annotations

import json
import re
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

LOG_LINE_RE = re.compile(
    r"^\[(?P<ts>[\d\- :]+)\]\s*\[(?P<level>DEBUG|INFO|WARN|ERROR)\]\s*(?:\[(?P<cat>[^\]]+)\])?\s*(?P<msg>.*)$"
)


@dataclass
class KnownPattern:
    id: str
    level: str  # "ERROR" oder "WARN" — nur zur Doku, matching läuft über regex
    regex: re.Pattern
    description: str
    fix_hint: str = ""  # Pfad zum passenden Fix-Modul, falls vorhanden


# ─────────────────────────────────────────────────────────────────────────
# Bekannte Fehlerklassen — bei jedem neu diagnostizierten Bug hier ergänzen,
# NICHT als Einmal-grep im Chat lösen (siehe Modul-Kommentar oben).
# ─────────────────────────────────────────────────────────────────────────
KNOWN_PATTERNS: list[KnownPattern] = [
    KnownPattern(
        id="XP_SIGNAL_ARITY_MISMATCH",
        level="ERROR",
        regex=re.compile(
            r"Error calling from signal '(?P<signal>xp_gained|level_up)' to callable: "
            r"'RefCounted\(FloatingTextController\.gd\)::(?P<method>_on_\w+)': "
            r"Method expected (?P<expected>\d+) argument\(s\), but called with (?P<got>\d+)"
        ),
        description=(
            "FloatingTextController._on_xp_gained()/_on_level_up() fehlt der "
            "peer_id-Parameter — Signal liefert 3 Argumente, Handler nimmt nur 2. "
            "Feuert bei JEDEM XP-Gain/Level-Up (XP-Floating-Text komplett kaputt)."
        ),
        fix_hint="scripts/agent/build/fix_known_runtime_bugs.py --fix xp_signal_arity",
    ),
    KnownPattern(
        id="OBJECT_FREED_DURING_OWN_SIGNAL",
        level="ERROR",
        regex=re.compile(
            r"Object '<Object#\d+>' was freed or unreferenced while a signal is being emitted from it"
        ),
        description=(
            "Ein Node wird per .free() (statt .queue_free()) zerstört, während "
            "eines seiner eigenen Signale noch verarbeitet wird — typischerweise "
            "eine Liste, die sich selbst während eines Button-Click-Handlers neu "
            "aufbaut und dabei den geklickten Button synchron freigibt."
        ),
        fix_hint="scripts/agent/build/fix_known_runtime_bugs.py --fix immediate_free_in_ui_clear",
    ),
    KnownPattern(
        id="LAMBDA_CAPTURE_FREED",
        level="ERROR",
        regex=re.compile(r'Lambda capture at index 0 was freed\. Passed "null" instead'),
        description=(
            "Ein Lambda mit erfasstem Objekt (Node oder self) wird aufgerufen, "
            "nachdem das erfasste Objekt bereits freigegeben wurde — meist ein "
            "verwaister get_tree().create_timer(...).timeout, dessen Ziel-Node "
            "vorher schon durch einen anderen Pfad (z.B. neues Popup ersetzt "
            "altes) zerstört wurde. Mit is_instance_valid()-Guard im Lambda-Body "
            "meist harmlos (kein Crash), aber Log-Spam und Symptom einer "
            "fehlenden Timer/Node-Kopplung."
        ),
        fix_hint="scripts/agent/build/fix_known_runtime_bugs.py --fix orphaned_ui_timers",
    ),
    KnownPattern(
        id="ENET_HOST_CREATE_FAILED",
        level="ERROR",
        regex=re.compile(r"Couldn't create an ENet host"),
        description=(
            "create_server() konnte keinen ENet-Host binden — meist Port bereits "
            "belegt (alter/verwaister Prozess, TIME_WAIT nach vorherigem Host-Lauf, "
            "oder ein zweiter Host-Versuch nach einem fehlgeschlagenen Join auf "
            "denselben Port). SessionManager gibt aktuell nur eine generische "
            "Fehlermeldung zurück, ohne Retry auf einen alternativen Port."
        ),
        fix_hint="scripts/agent/build/fix_known_runtime_bugs.py --fix session_manager_port_retry",
    ),
    KnownPattern(
        id="MULTIPLAYER_SPAWNER_INVALID_DESPAWN_FUNCTION",
        level="ERROR",
        regex=re.compile(
            r"Invalid assignment of property or key 'despawn_function'.*MultiplayerSpawner"
        ),
        description=(
            "'despawn_function' ist keine gültige Property auf MultiplayerSpawner "
            "(Godot 4) — WorldService._setup_multiplayer_spawner() versucht sie "
            "trotzdem zuzuweisen. Feuert bei JEDEM Welt-Boot in Multiplayer-"
            "Sessions. MultiplayerSpawner despawnt automatisch beim Freigeben "
            "auf dem Server; für Client-seitige Zusatzlogik gibt es stattdessen "
            "das Signal 'despawned(node)'."
        ),
        fix_hint="scripts/agent/build/fix_known_runtime_bugs.py --fix multiplayer_spawner_invalid_despawn_function",
    ),
    KnownPattern(
        id="CHUNK_MANAGER_FREED_TRANSFORM_ACCESS",
        level="ERROR",
        regex=re.compile(
            r'Condition "!is_inside_tree\(\)" is true\. Returning: Transform3D\(\)'
        ),
        description=(
            "ChunkManager.on_tick() liest player.global_position, obwohl der "
            "Player-Node zwar noch is_instance_valid() ist, aber schon aus dem "
            "SceneTree entfernt wurde (typisch beim Szenenwechsel, z.B. "
            "'Zurück zum Hauptmenü'). is_instance_valid() allein reicht hier "
            "nicht — zusätzlich is_inside_tree() prüfen."
        ),
        fix_hint="scripts/agent/build/fix_known_runtime_bugs.py --fix chunk_manager_freed_transform_access",
    ),
    KnownPattern(
        id="JOIN_TIMEOUT",
        level="WARN",
        regex=re.compile(r"Verbindungs-Timeout nach \d+ Sekunden"),
        description=(
            "Join-Versuch lief in den 10s-Timeout — kein Host unter der Zieladresse "
            "erreichbar. Kein Code-Bug an sich, aber relevantes Kontext-Signal für "
            "nachfolgende ENET_HOST_CREATE_FAILED-Funde (gleiche Adresse/Port?)."
        ),
    ),
    KnownPattern(
        id="ANOTHER_PLAYER_FALLBACK_SPAM",
        level="DEBUG",
        regex=re.compile(r"Belohnungstext: 'Ein anderer Spieler\.'"),
        description=(
            "InteractionSensor löst wiederholt auf 'sich selbst' auf statt auf "
            "das echte Ziel (siehe InteractionSensor.get_closest() Self-Exclusion-"
            "Fix, Round 2026-09-13). Falls dieses Muster erneut auftaucht: Fix "
            "wurde vermutlich zurückgerollt oder nicht deployed."
        ),
    ),
    KnownPattern(
        id="DESPAWNED_ENTITY_INTERACTION",
        level="WARN",
        regex=re.compile(
            r"resolve_and_dispatch_interaction\('[^']+'\): unbekannte/bereits despawnte Entity"
        ),
        description=(
            "Eine Interaktion wurde für eine UUID aufgelöst, die im "
            "EntityOrchestrator nicht mehr aktiv ist — Race zwischen "
            "Despawn (z.B. Tier gefangen/Baum gefällt) und noch laufender "
            "Interaktions-Auflösung auf Client-Seite."
        ),
    ),
]


@dataclass
class Finding:
    pattern_id: str
    level: str
    description: str
    fix_hint: str
    count: int = 0
    first_ts: str = ""
    last_ts: str = ""
    sample_lines: list[str] = field(default_factory=list)


_HOSTING_STARTED_RE = re.compile(r"\[SessionManager\] Server gestartet auf Port \d+")
_HOST_REQUESTED_RE = re.compile(r"\[MainMenuController\] Host angefordert auf Port \d+")
_JOIN_REQUESTED_RE = re.compile(r"\[MainMenuController\] Join angefordert: ")
_PEER_CLOSED_RE = re.compile(
    r"Multiplayer-Peer geschlossen|Server-Verbindung verloren|Verbindungs-Timeout"
)


def _detect_reentrant_host_while_active(raw_line: str, peer_active: list[bool]) -> str | None:
    """Stateful (nicht pro Zeile isoliert) Regel: erkennt einen zweiten
    Host-/Join-Klick, während laut Log bereits ein Peer aktiv ist (siehe
    MainMenuController — '[Multiplayer]'-Button bleibt in HOST_ACTIVE
    sichtbar/erreichbar, siehe fix_known_runtime_bugs.py --fix
    mainmenu_hide_multiplayer_button_while_active).
    peer_active ist eine 1-elementige Liste als Pass-by-Reference-Ersatz."""
    if _HOSTING_STARTED_RE.search(raw_line):
        peer_active[0] = True
        return None
    if _PEER_CLOSED_RE.search(raw_line):
        peer_active[0] = False
        return None
    if peer_active[0] and (_HOST_REQUESTED_RE.search(raw_line) or _JOIN_REQUESTED_RE.search(raw_line)):
        return "REENTRANT_HOST_OR_JOIN_WHILE_PEER_ACTIVE"
    return None


_REENTRANT_DESCRIPTION = (
    "Host/Join wurde erneut angefordert, während laut Log bereits ein Peer "
    "aktiv war (vorheriges 'Server gestartet' ohne dazwischenliegendes "
    "Schließen). Typische Ursache: MainMenuController versteckt den "
    "'[Multiplayer]'-Button in HOST_ACTIVE nicht, der Spieler gelangt zurück "
    "zu NET_SETUP und startet Host/Join ein zweites Mal auf denselben Port "
    "-> 'Couldn't create an ENet host', weil der erste (noch laufende) Peer "
    "den Port bereits hält."
)
_REENTRANT_FIX_HINT = (
    "scripts/agent/build/fix_known_runtime_bugs.py --fix session_manager_reentry_guard "
    "und --fix mainmenu_hide_multiplayer_button_while_active"
)


def analyze(paths: list[Path]) -> list[Finding]:
    findings: dict[str, Finding] = {}
    for path in paths:
        text = path.read_text(encoding="utf-8", errors="replace")
        peer_active = [False]  # State für _detect_reentrant_host_while_active, pro Datei zurückgesetzt
        for raw_line in text.splitlines():
            m = LOG_LINE_RE.match(raw_line)
            ts = m.group("ts") if m else ""
            for kp in KNOWN_PATTERNS:
                if kp.regex.search(raw_line):
                    f = findings.setdefault(
                        kp.id,
                        Finding(
                            pattern_id=kp.id,
                            level=kp.level,
                            description=kp.description,
                            fix_hint=kp.fix_hint,
                        ),
                    )
                    f.count += 1
                    if not f.first_ts:
                        f.first_ts = ts
                    f.last_ts = ts
                    if len(f.sample_lines) < 3:
                        f.sample_lines.append(raw_line.strip())

            reentrant_id = _detect_reentrant_host_while_active(raw_line, peer_active)
            if reentrant_id:
                f = findings.setdefault(
                    reentrant_id,
                    Finding(
                        pattern_id=reentrant_id,
                        level="ERROR",
                        description=_REENTRANT_DESCRIPTION,
                        fix_hint=_REENTRANT_FIX_HINT,
                    ),
                )
                f.count += 1
                if not f.first_ts:
                    f.first_ts = ts
                f.last_ts = ts
                if len(f.sample_lines) < 3:
                    f.sample_lines.append(raw_line.strip())
    return sorted(findings.values(), key=lambda f: (-f.count))


def print_report(findings: list[Finding]) -> None:
    if not findings:
        print("Keine bekannten Fehlermuster gefunden.")
        return
    print("=" * 78)
    print(f"RUNTIME-LOG-ANALYSE — {len(findings)} bekannte Fehlermuster gefunden")
    print("=" * 78)
    for f in findings:
        print(f"\n[{f.level}] {f.pattern_id}  (x{f.count}, {f.first_ts} … {f.last_ts})")
        print(f"  {f.description}")
        if f.fix_hint:
            print(f"  → Fix: {f.fix_hint}")
        for s in f.sample_lines:
            print(f"    | {s[:160]}")
    print("\n" + "=" * 78)
    unmatched_hint = (
        "Neue/unbekannte ERROR-Zeilen? Prüfen und als neues KNOWN_PATTERN in "
        "diesem Skript ergänzen statt erneut per Ad-hoc-grep zu analysieren."
    )
    print(unmatched_hint)


def main(argv: list[str]) -> int:
    as_json = "--json" in argv
    args = [a for a in argv if a != "--json"]
    if not args:
        print("Usage: analyze_runtime_log.py [--json] <logfile> [<logfile> ...]", file=sys.stderr)
        return 2
    paths = [Path(a) for a in args]
    for p in paths:
        if not p.exists():
            print(f"FEHLER: Datei nicht gefunden: {p}", file=sys.stderr)
            return 2
    findings = analyze(paths)
    if as_json:
        print(json.dumps([f.__dict__ for f in findings], indent=2, ensure_ascii=False))
    else:
        print_report(findings)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

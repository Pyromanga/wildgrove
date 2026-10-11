#!/usr/bin/env python3
# scripts/agent/architecture_overview.py
#
# "Was haben wir implementiert" als Script statt als Gedächtnisleistung.
# Liest NICHTS aus einem Cache/Snapshot — jede Ausgabe wird bei jedem Lauf
# frisch aus den Quelldateien abgeleitet (BootstrapConfig.tres, EventBus.gd,
# class_name-Deklarationen, docs/adr/*.md, tests/unit/). Dadurch veraltet
# der Abriss nie stillschweigend, im Gegensatz zu einer von Hand gepflegten
# Übersicht in einer Markdown-Datei.
#
# Selbstheilend wie die übrigen scripts/agent/-Tools (MEMORY_PROTOCOL.md):
# eine kaputte/unlesbare Datei bricht den Lauf nicht ab, sondern wird als
# Warnung gemeldet.
#
# Verwendung:
#   python3 scripts/agent/architecture_overview.py                 # Kurzabriss (Domains + Services)
#   python3 scripts/agent/architecture_overview.py --full           # + EventBus-Namespaces, Entities, ADRs, Test-Abdeckung
#   python3 scripts/agent/architecture_overview.py --domain economy # nur eine Domain, alle Details
#   python3 scripts/agent/architecture_overview.py --json           # maschinenlesbar (für weitere Tools)
#   python3 scripts/agent/architecture_overview.py --write-report   # schreibt docs/manager/reports/architecture-overview.md
#
# Einstiegspunkt für zukünftige Sessions: dieses Script ausführen statt
# Services/Entities einzeln über view() durchzulesen. Bei Bedarf mit
# --domain <name> gezielt eine Domain vertiefen.

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any

_REPO_ROOT = Path(__file__).resolve().parents[2]
_SCRIPTS_DIR = _REPO_ROOT / "scripts"
_BOOTSTRAP_CONFIG = _REPO_ROOT / "config" / "BootstrapConfig.tres"
_EVENTBUS_GD = _REPO_ROOT / "scripts" / "eventbus" / "EventBus.gd"
_ADR_DIR = _REPO_ROOT / "docs" / "adr"
_TESTS_DIR = _REPO_ROOT / "tests" / "unit"
_REPORT_PATH = _REPO_ROOT / "docs" / "manager" / "reports" / "architecture-overview.md"


def _domain_of(path_str: str) -> str:
    """res://scripts/economy/shop/ShopService.gd -> 'economy'"""
    m = re.search(r"scripts/([^/]+)/", path_str)
    return m.group(1) if m else "(root)"


# ---------------------------------------------------------------------------
# Services (config/BootstrapConfig.tres — die Quelle der Wahrheit für DI)
# ---------------------------------------------------------------------------

def _parse_services() -> tuple[list[dict], list[str]]:
    warnings: list[str] = []
    if not _BOOTSTRAP_CONFIG.exists():
        return [], [f"⚠ {_BOOTSTRAP_CONFIG} nicht gefunden"]

    services: list[dict] = []
    current: dict[str, Any] | None = None
    try:
        text = _BOOTSTRAP_CONFIG.read_text(encoding="utf-8")
    except Exception as e:  # noqa: BLE001
        return [], [f"⚠ konnte BootstrapConfig.tres nicht lesen: {e}"]

    for line in text.splitlines():
        if line.startswith("[sub_resource"):
            if current and "service_name" in current:
                services.append(current)
            current = {"required_deps": [], "optional_deps": []}
            continue
        if current is None:
            continue
        m = re.match(r'(\w+)\s*=\s*(.+)', line.strip())
        if not m:
            continue
        key, val = m.groups()
        if key == "service_name":
            current["service_name"] = val.strip('"')
        elif key == "path":
            current["path"] = val.strip('"')
        elif key in ("required_deps", "optional_deps"):
            current[key] = re.findall(r'"([^"]+)"', val)
    if current and "service_name" in current:
        services.append(current)

    for s in services:
        s["domain"] = _domain_of(s.get("path", ""))
        if "path" not in s:
            warnings.append(f"⚠ Service '{s.get('service_name')}' hat keinen path-Eintrag")
    return services, warnings


# ---------------------------------------------------------------------------
# EventBus-Namespaces (scripts/eventbus/EventBus.gd — die einzige Registry)
# ---------------------------------------------------------------------------

def _parse_eventbus_namespaces() -> tuple[list[dict], list[str]]:
    warnings: list[str] = []
    if not _EVENTBUS_GD.exists():
        return [], [f"⚠ {_EVENTBUS_GD} nicht gefunden"]
    try:
        text = _EVENTBUS_GD.read_text(encoding="utf-8")
    except Exception as e:  # noqa: BLE001
        return [], [f"⚠ konnte EventBus.gd nicht lesen: {e}"]

    namespaces = []
    for m in re.finditer(r'^var (\w+): (\w+)$', text, re.MULTILINE):
        namespaces.append({"namespace": m.group(1), "class_name": m.group(2)})

    # Zugehörige *Events.gd-Datei über class_name-Suche auflösen (Datei kann
    # in jeder Domain liegen, kein fester Pfad).
    class_to_file = _find_class_declarations()
    for ns in namespaces:
        f = class_to_file.get(ns["class_name"])
        if f:
            ns["file"] = str(f.relative_to(_REPO_ROOT))
            ns["domain"] = _domain_of(str(f))
        else:
            ns["file"] = None
            ns["domain"] = None
            warnings.append(f"⚠ Namespace '{ns['namespace']}': Klasse {ns['class_name']} nirgends als class_name gefunden")
    return namespaces, warnings


# ---------------------------------------------------------------------------
# class_name-Inventar (Entities, Services-Implementierungen, alles) — einmal
# über das ganze scripts/-Verzeichnis, danach von allen Funktionen genutzt.
# ---------------------------------------------------------------------------

def _find_class_declarations() -> dict[str, Path]:
    result: dict[str, Path] = {}
    for f in _SCRIPTS_DIR.rglob("*.gd"):
        if f.suffix == ".bak" or f.name.endswith(".gd.bak"):
            continue
        try:
            head = f.read_text(encoding="utf-8", errors="replace")[:400]
        except Exception:  # noqa: BLE001
            continue
        m = re.search(r'^class_name (\w+)', head, re.MULTILINE)
        if m:
            result[m.group(1)] = f
    return result


def _gd_files_by_domain() -> dict[str, list[Path]]:
    by_domain: dict[str, list[Path]] = defaultdict(list)
    for f in _SCRIPTS_DIR.rglob("*.gd"):
        if f.suffix == ".bak" or f.name.endswith(".gd.bak"):
            continue
        by_domain[_domain_of(str(f))].append(f)
    return by_domain


# ---------------------------------------------------------------------------
# ADRs
# ---------------------------------------------------------------------------

def _parse_adrs() -> tuple[list[dict], list[str]]:
    warnings: list[str] = []
    adrs: list[dict] = []
    if not _ADR_DIR.exists():
        return [], [f"⚠ {_ADR_DIR} nicht gefunden"]
    for f in sorted(_ADR_DIR.glob("*.md")):
        try:
            text = f.read_text(encoding="utf-8")
        except Exception as e:  # noqa: BLE001
            warnings.append(f"⚠ konnte ADR nicht lesen: {f.name} ({e})")
            continue
        title_m = re.search(r'^# (.+)', text, re.MULTILINE)
        status_m = re.search(r'^\*\*Status:\*\*\s*(.+)', text, re.MULTILINE)
        adrs.append({
            "file": f.name,
            "title": title_m.group(1).strip() if title_m else f.name,
            "status": status_m.group(1).strip() if status_m else "(kein Status-Feld)",
        })
    return adrs, warnings


# ---------------------------------------------------------------------------
# Test-Abdeckung — welcher Service hat (nach Namenskonvention) eine Testdatei?
# ---------------------------------------------------------------------------

def _service_class_name(service_path: str) -> str | None:
    """Liest den class_name direkt aus der Service-Datei (verlässlicher als
    Namenskonvention-Raten am Dateinamen — ADR-050-Fund im selben Round zeigt,
    wie leicht Namenskonventionen auseinanderlaufen, z.B. 'playerstates' vs.
    'test_player_state_service.gd')."""
    rel = service_path.removeprefix("res://")
    f = _REPO_ROOT / rel
    if not f.exists():
        return None
    try:
        head = f.read_text(encoding="utf-8", errors="replace")[:400]
    except Exception:  # noqa: BLE001
        return None
    m = re.search(r'^class_name (\w+)', head, re.MULTILINE)
    return m.group(1) if m else None


def _test_coverage(services: list[dict]) -> dict[str, bool]:
    """Prüft für jeden Service, ob eine Testdatei die etablierte Header-
    Konvention 'Tests für <ClassName>' / 'Unit-Tests für <ClassName>' trägt
    (119 von 133 Testdateien folgen das, siehe Projekt-Konvention). Zuverlässiger
    als Dateinamen-Raten (ADR-050-Fund: 'playerstates' vs.
    'test_player_state_service.gd' passt bei keiner simplen Namensregel) und
    als reine class_name-Textsuche (die matcht auch auf Mock/Fake-Nutzung in
    fremden Testdateien, z.B. 'FakeDataService extends DataService' in einem
    Test für einen ANDEREN Service — false positive)."""
    test_files: list[tuple[Path, str]] = []
    if _TESTS_DIR.exists():
        for f in _TESTS_DIR.glob("test_*.gd"):
            try:
                test_files.append((f, f.read_text(encoding="utf-8", errors="replace")))
            except Exception:  # noqa: BLE001
                continue

    coverage = {}
    for s in services:
        cls = _service_class_name(s.get("path", ""))
        found = False
        if cls:
            for _, t in test_files:
                header_lines = t.splitlines()[:40]
                for line in header_lines:
                    cleaned = re.sub(r'\([^)]*\)', '', line)
                    m = re.search(r'Tests für [^.\n]*', cleaned)
                    if m and cls in m.group(0):
                        found = True
                        break
                if found:
                    break
        coverage[s["service_name"]] = found
    return coverage


# ---------------------------------------------------------------------------
# Aufbau der Gesamt-Übersicht
# ---------------------------------------------------------------------------

def build_overview() -> dict:
    services, sw = _parse_services()
    namespaces, nw = _parse_eventbus_namespaces()
    adrs, aw = _parse_adrs()
    by_domain = _gd_files_by_domain()
    coverage = _test_coverage(services)

    services_by_domain: dict[str, list[dict]] = defaultdict(list)
    for s in services:
        services_by_domain[s["domain"]].append(s)

    domains = []
    all_domain_names = sorted(set(by_domain) | set(services_by_domain))
    for d in all_domain_names:
        domains.append({
            "domain": d,
            "gd_file_count": len(by_domain.get(d, [])),
            "services": sorted(s["service_name"] for s in services_by_domain.get(d, [])),
        })

    return {
        "services": services,
        "services_by_domain": {k: v for k, v in services_by_domain.items()},
        "eventbus_namespaces": namespaces,
        "domains": domains,
        "adrs": adrs,
        "test_coverage": coverage,
        "warnings": sw + nw + aw,
    }


# ---------------------------------------------------------------------------
# Ausgabe
# ---------------------------------------------------------------------------

def _fmt_deps(deps: list[str]) -> str:
    return ", ".join(deps) if deps else "—"


def render_markdown(data: dict, full: bool, domain_filter: str | None) -> str:
    lines: list[str] = []
    lines.append("# Architektur-Abriss (automatisch generiert)")
    lines.append("")
    lines.append("Quelle: `config/BootstrapConfig.tres`, `scripts/eventbus/EventBus.gd`, "
                  "`class_name`-Deklarationen unter `scripts/`, `docs/adr/`, `tests/unit/`. "
                  "Kein manueller Cache — bei jedem Lauf frisch abgeleitet.")
    lines.append("")

    domains = data["domains"]
    if domain_filter:
        domains = [d for d in domains if d["domain"] == domain_filter]
        if not domains:
            lines.append(f"⚠ Domain '{domain_filter}' nicht gefunden.")
            return "\n".join(lines)

    lines.append(f"## Domains ({len(domains)})")
    lines.append("")
    lines.append("| Domain | .gd-Dateien | Services (DI) |")
    lines.append("|---|---|---|")
    for d in domains:
        svc = ", ".join(d["services"]) if d["services"] else "—"
        lines.append(f"| `{d['domain']}` | {d['gd_file_count']} | {svc} |")
    lines.append("")

    services = data["services"]
    if domain_filter:
        services = [s for s in services if s["domain"] == domain_filter]

    lines.append(f"## Services ({len(services)}) — registriert in BootstrapConfig.tres")
    lines.append("")
    lines.append("| Service | Domain | Pfad | required_deps | optional_deps | Test? |")
    lines.append("|---|---|---|---|---|---|")
    for s in sorted(services, key=lambda s: (s["domain"], s["service_name"])):
        has_test = "✓" if data["test_coverage"].get(s["service_name"]) else "✗"
        lines.append(
            f"| `{s['service_name']}` | {s['domain']} | `{s.get('path', '?')}` "
            f"| {_fmt_deps(s['required_deps'])} | {_fmt_deps(s['optional_deps'])} | {has_test} |"
        )
    lines.append("")

    if full or domain_filter:
        namespaces = data["eventbus_namespaces"]
        if domain_filter:
            namespaces = [n for n in namespaces if n.get("domain") == domain_filter]
        lines.append(f"## EventBus-Namespaces ({len(namespaces)})")
        lines.append("")
        lines.append("| Namespace | Klasse | Datei |")
        lines.append("|---|---|---|")
        for n in namespaces:
            lines.append(f"| `EventBus.{n['namespace']}` | `{n['class_name']}` | `{n.get('file') or '⚠ nicht gefunden'}` |")
        lines.append("")

    if full and not domain_filter:
        lines.append(f"## ADRs ({len(data['adrs'])})")
        lines.append("")
        lines.append("| Datei | Titel | Status |")
        lines.append("|---|---|---|")
        for a in data["adrs"]:
            lines.append(f"| `{a['file']}` | {a['title']} | {a['status']} |")
        lines.append("")

    if data["warnings"]:
        lines.append("## Warnungen")
        lines.append("")
        for w in data["warnings"]:
            lines.append(f"- {w}")
        lines.append("")

    return "\n".join(lines)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--full", action="store_true", help="Auch EventBus-Namespaces + ADRs anzeigen")
    ap.add_argument("--domain", help="Nur eine Domain vertiefen (z.B. 'economy')")
    ap.add_argument("--json", action="store_true", help="Maschinenlesbare JSON-Ausgabe statt Markdown")
    ap.add_argument("--write-report", action="store_true", help=f"Zusätzlich nach {_REPORT_PATH.relative_to(_REPO_ROOT)} schreiben")
    args = ap.parse_args()

    data = build_overview()

    if args.json:
        print(json.dumps(data, indent=2, ensure_ascii=False))
        return

    out = render_markdown(data, full=args.full, domain_filter=args.domain)
    print(out)

    if args.write_report:
        _REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
        _REPORT_PATH.write_text(render_markdown(data, full=True, domain_filter=None), encoding="utf-8")
        print(f"\n(Report geschrieben: {_REPORT_PATH.relative_to(_REPO_ROOT)})", file=sys.stderr)


if __name__ == "__main__":
    main()

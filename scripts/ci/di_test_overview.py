#!/usr/bin/env python3
# scripts/ci/di_test_overview.py
#
# CI-Job "DI-Überblick & Testabdeckung" in build-apk.yml ruft dies auf als:
#   python3 project/scripts/ci/di_test_overview.py \
#     --project project --out di-overview.json --markdown-out di-overview.md
#
# Diese Datei fehlte im Projekt-ZIP (der Workflow referenzierte sie, aber sie
# existierte nirgends) — hier neu gebaut, damit der bereits verdrahtete Job
# tatsächlich lauffähig wird.
#
# WAS ES TUT: Reines Python/stdlib, statische Analyse — kein Godot-Import
# nötig, läuft unabhängig vom test-logic-Job.
#   1. Liest config/BootstrapConfig.tres (ServiceDefinition/ResourceDefinition
#      Sub-Resources) — das ist laut ServiceDefinition.gd-Kommentar ("eine
#      Config, ein Blick, keine Code-Analyse nötig") die kanonische Quelle
#      für den DI-Graphen, kein Parsen von configure()-Methoden nötig.
#   2. Baut den Dependency-Graphen (required_deps + optional_deps je Service),
#      prüft auf unauflösbare Deps und Zyklen (Kahn's Algorithmus — dieselbe
#      Methode, die laut ServiceDefinition.gd-Kommentar ServiceDependencyResolver
#      zur Laufzeit für die Boot-Reihenfolge nutzt; hier statisch vorab geprüft).
#   3. Ordnet jeden Service seiner erwarteten Unit-Test-Datei zu (Namenskonvention
#      bestätigt gegen tests/unit/: test_<snake_case(Skript-Dateiname)>.gd,
#      NICHT snake_case(service_name) — z.B. Service "scenemanager" mit Skript
#      SceneManager.gd → test_scene_manager.gd, nicht test_scenemanager.gd)
#      und meldet fehlende Testdateien.
#   4. check_boot_flow_scene_causality() (Round 113 Nachtrag): validiert die
#      GameManager↔SceneManager-Kausalität statisch — der State, den
#      _on_session_ready() setzt, MUSS in SceneManager.STATE_SCENE_MAP auf
#      eine World-Szene zeigen (siehe Funktionskommentar für den konkreten
#      Bug, den das gefangen hätte).
#
# WAS ES NICHT TUT (bewusst, laut CI-Job-Kommentar "gated nichts"):
#   Kein exit 1 bei fehlender Testabdeckung — reines Reporting. Ein
#   Graph-Fehler (unauflösbare Dep, Zyklus) IST dagegen ein struktureller Bug,
#   der das Spiel beim Boot tatsächlich crashen lassen würde — dafür exit 1,
#   siehe --strict weiter unten. Der CI-Job ruft --strict inzwischen IMMER
#   auf (Round 113 Nachtrag) — genau wegen dieser Kategorie von Fund (siehe
#   check_boot_flow_scene_causality()). Per Governance-Note in docs/ci-pipeline.md:
#   ob das zum Gate werden soll, ist eine Entscheidung des Project Owners,
#   nicht dieses Tools — deshalb ist --strict ein Opt-in-Flag, nicht Default.
#
# Bekannte Grenze: EXTERNALLY_PROVIDED_KEYS unten ist eine Allowlist für Keys,
# die NICHT über BootstrapConfig.tres bereitgestellt werden, sondern manuell
# im Code (aktuell nur "event_bus", siehe ServiceOrchestrator._ready():
# _app_scope.register_event_bus(...) läuft VOR boot_app()). Ein neuer
# ähnlicher Fall müsste hier von Hand nachgetragen werden — dieses Tool kann
# nicht wissen, dass ein Key auf diesem Weg bereitgestellt wird, ohne dass
# jemand es ihm sagt.

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

# Siehe Kopfkommentar: einzige bekannte Ausnahme, manuell registriert statt
# über BootstrapConfig.tres deklariert.
EXTERNALLY_PROVIDED_KEYS = {"event_bus"}


@dataclass
class ServiceDef:
    id: str  # sub_resource id im .tres, z.B. "Resource_ticker"
    service_name: str
    path: str
    required_deps: list[str]
    optional_deps: list[str]
    scope: str = ""  # "global" | "session", nach dem zweiten Parse-Durchlauf gesetzt


@dataclass
class ResourceDef:
    id: str
    registry_key: str
    path: str
    scope: str = ""


@dataclass
class Finding:
    severity: str  # ERROR | WARN | INFO
    kind: str
    message: str


_SUB_RESOURCE_RE = re.compile(
    r'\[sub_resource type="Resource" id="([^"]+)"\]\n(.*?)(?=\n\[|\Z)', re.DOTALL)
_EXT_RESOURCE_RE = re.compile(
    r'\[ext_resource type="Script" path="([^"]+)" id="([^"]+)"\]')
_STR_FIELD_RE = lambda name: re.compile(rf'^{name}\s*=\s*"([^"]*)"', re.MULTILINE)
_ARR_FIELD_RE = lambda name: re.compile(rf'^{name}\s*=\s*Array\[String\]\(\[(.*?)\]\)', re.MULTILINE)


def _parse_str_list(inner: str) -> list[str]:
    return re.findall(r'"([^"]*)"', inner)


def parse_bootstrap_config(path: Path) -> tuple[dict[str, ServiceDef], dict[str, ResourceDef], list[Finding]]:
    findings: list[Finding] = []
    text = path.read_text(encoding="utf-8")

    ext_id_to_path = {eid: epath for epath, eid in _EXT_RESOURCE_RE.findall(text)}

    services: dict[str, ServiceDef] = {}
    resources: dict[str, ResourceDef] = {}

    for sub_id, body in _SUB_RESOURCE_RE.findall(text):
        script_m = re.search(r'script\s*=\s*ExtResource\("([^"]+)"\)', body)
        if not script_m:
            continue
        script_path = ext_id_to_path.get(script_m.group(1), "")
        if script_path.endswith("ServiceDefinition.gd"):
            name_m = _STR_FIELD_RE("service_name").search(body)
            path_m = _STR_FIELD_RE("path").search(body)
            if not name_m or not path_m:
                findings.append(Finding("ERROR", "MALFORMED_SERVICE_DEF",
                                         f"sub_resource '{sub_id}': ServiceDefinition ohne service_name/path"))
                continue
            req_m = _ARR_FIELD_RE("required_deps").search(body)
            opt_m = _ARR_FIELD_RE("optional_deps").search(body)
            services[sub_id] = ServiceDef(
                id=sub_id, service_name=name_m.group(1), path=path_m.group(1),
                required_deps=_parse_str_list(req_m.group(1)) if req_m else [],
                optional_deps=_parse_str_list(opt_m.group(1)) if opt_m else [],
            )
        elif script_path.endswith("ResourceDefinition.gd"):
            key_m = _STR_FIELD_RE("registry_key").search(body)
            path_m = _STR_FIELD_RE("path").search(body)
            if not key_m or not path_m:
                findings.append(Finding("ERROR", "MALFORMED_RESOURCE_DEF",
                                         f"sub_resource '{sub_id}': ResourceDefinition ohne registry_key/path"))
                continue
            resources[sub_id] = ResourceDef(id=sub_id, registry_key=key_m.group(1), path=path_m.group(1))

    # [resource]-Block: welche sub_resource-IDs stehen in global_services /
    # session_services / global_resources / session_resources? Das legt den
    # "scope" jedes Eintrags fest (wichtig für Boot-Reihenfolge/Cross-Scope-
    # Regeln weiter unten).
    resource_block_m = re.search(r'\[resource\]\n(.*)\Z', text, re.DOTALL)
    resource_block = resource_block_m.group(1) if resource_block_m else ""

    for array_name, scope in (("global_services", "global"), ("session_services", "session"),
                               ("global_resources", "global"), ("session_resources", "session")):
        m = re.search(rf'^{array_name}\s*=\s*Array\[\w+\]\(\[(.*?)\]\)', resource_block, re.DOTALL | re.MULTILINE)
        if not m:
            continue
        for sub_id in re.findall(r'SubResource\("([^"]+)"\)', m.group(1)):
            if sub_id in services:
                services[sub_id].scope = scope
            elif sub_id in resources:
                resources[sub_id].scope = scope
            else:
                findings.append(Finding("ERROR", "DANGLING_REFERENCE",
                                         f"{array_name} referenziert SubResource '{sub_id}', "
                                         f"die nicht als ServiceDefinition/ResourceDefinition gefunden wurde"))

    for sid, sd in services.items():
        if not sd.scope:
            findings.append(Finding("WARN", "UNSCOPED_SERVICE",
                                     f"Service '{sd.service_name}' ({sid}) steht in keinem der vier Arrays "
                                     f"(global_services/session_services) — wird nie gebootet"))

    return services, resources, findings


def build_provider_map(services: dict[str, ServiceDef], resources: dict[str, ResourceDef]) -> dict[str, str]:
    """key -> scope ('global'/'session'), für alle statisch deklarierten Provider."""
    out: dict[str, str] = {}
    for sd in services.values():
        out[sd.service_name] = sd.scope
    for rd in resources.values():
        out[rd.registry_key] = rd.scope
    for k in EXTERNALLY_PROVIDED_KEYS:
        out[k] = "global"  # event_bus ist vor boot_app() da, also faktisch global verfügbar
    return out


def check_dependencies(services: dict[str, ServiceDef], provider_scope: dict[str, str]) -> list[Finding]:
    findings: list[Finding] = []
    for sd in services.values():
        for dep in sd.required_deps + sd.optional_deps:
            kind = "required_deps" if dep in sd.required_deps else "optional_deps"
            if dep not in provider_scope:
                sev = "ERROR" if kind == "required_deps" else "WARN"
                findings.append(Finding(
                    sev, "UNRESOLVED_DEPENDENCY",
                    f"Service '{sd.service_name}' ({kind}) verlangt '{dep}', aber kein Service/Resource "
                    f"deklariert diesen Key (auch nicht in EXTERNALLY_PROVIDED_KEYS) — "
                    f"{'Boot würde crashen (AppLogger.fatal in ServiceDeps.require)' if kind == 'required_deps' else 'get_optional() liefert still null'}."
                ))
                continue
            dep_scope = provider_scope[dep]
            if sd.scope == "global" and dep_scope == "session":
                findings.append(Finding(
                    "ERROR", "SCOPE_VIOLATION",
                    f"Service '{sd.service_name}' (global) hängt von '{dep}' (session) ab — "
                    f"global-Services booten VOR jedem Charakter, session-Keys existieren zu dem "
                    f"Zeitpunkt noch nicht (siehe AppScope/CharacterScope-Boot-Reihenfolge)."
                ))
    return findings


def topo_sort(services: dict[str, ServiceDef], provider_scope: dict[str, str], scope: str) -> tuple[list[str], list[Finding]]:
    """Kahn's Algorithmus, pro Scope getrennt (global zuerst, dann session —
    session darf auf bereits gebootete global-Keys zeigen, das zählt hier
    nicht als Kante INNERHALB des session-Graphen)."""
    findings: list[Finding] = []
    nodes = {sid: sd for sid, sd in services.items() if sd.scope == scope}
    name_to_id = {sd.service_name: sid for sid, sd in nodes.items()}
    indegree = {sid: 0 for sid in nodes}
    edges: dict[str, list[str]] = {sid: [] for sid in nodes}

    for sid, sd in nodes.items():
        deps = list(dict.fromkeys(sd.required_deps + sd.optional_deps))  # dedupe, stabile Reihenfolge
        for dep in deps:
            dep_id = name_to_id.get(dep)
            if dep_id is None:
                continue  # Cross-Scope oder external — kein Zyklus-Kandidat innerhalb dieses Scopes
            edges[dep_id].append(sid)
            indegree[sid] += 1

    queue = sorted([sid for sid, d in indegree.items() if d == 0], key=lambda i: nodes[i].service_name)
    order: list[str] = []
    while queue:
        queue.sort(key=lambda i: nodes[i].service_name)
        cur = queue.pop(0)
        order.append(nodes[cur].service_name)
        for nxt in edges[cur]:
            indegree[nxt] -= 1
            if indegree[nxt] == 0:
                queue.append(nxt)

    if len(order) != len(nodes):
        stuck = sorted(nodes[sid].service_name for sid, d in indegree.items() if d > 0)
        findings.append(Finding("ERROR", "DEPENDENCY_CYCLE",
                                 f"Zyklus im {scope}-Scope erkannt — betroffene Services (kommen in keiner "
                                 f"gültigen Boot-Reihenfolge vor): {', '.join(stuck)}"))
        order.extend(sorted(s for s in (nodes[sid].service_name for sid in nodes) if s not in order))
    return order, findings


def snake_case(name: str) -> str:
    # Bekannte Akronym-artige Tokens, die eine generische CamelCase→snake_case-
    # Regel nicht korrekt trennen kann (z.B. "PvP" würde zu "pv_p" statt "pvp").
    # Muss von Hand nachgetragen werden, wenn ein neuer Service so einen Fall
    # einführt — kein Algorithmus kann "PvP" zuverlässig von einem echten
    # CamelCase-Wortübergang unterscheiden.
    for token, repl in (("PvP", "Pvp"),):
        name = name.replace(token, repl)
    s1 = re.sub(r'(.)([A-Z][a-z]+)', r'\1_\2', name)
    s2 = re.sub(r'([a-z0-9])([A-Z])', r'\1_\2', s1)
    return s2.lower()


def expected_test_file(script_path: str, unit_dir_files: set[str]) -> str:
    """Liefert den Dateinamen, gegen den geprüft wird. Probiert zuerst die
    mechanische Konvention (test_<snake_case(Klassenname)>.gd), dann — falls
    das nicht existiert — dieselbe ohne trailing '_service' (z.B.
    StatModifierService.gd wird tatsächlich von test_stat_modifier.gd
    getestet, nicht test_stat_modifier_service.gd; eine von Hand getroffene
    Namenswahl, keine Regel). Gibt den ERSTEN existierenden Kandidaten zurück,
    sonst den mechanischen Namen (für die Fehlermeldung)."""
    basename = Path(script_path).stem
    primary = f"test_{snake_case(basename)}.gd"
    if primary in unit_dir_files:
        return primary
    if primary.endswith("_service.gd"):
        fallback = primary[: -len("_service.gd")] + ".gd"
        if fallback in unit_dir_files:
            return fallback
    return primary


def check_test_coverage(services: dict[str, ServiceDef], project_root: Path) -> tuple[list[dict], list[Finding]]:
    unit_dir = project_root / "tests" / "unit"
    existing = {p.name for p in unit_dir.glob("test_*.gd")} if unit_dir.exists() else set()
    rows = []
    findings = []
    for sd in sorted(services.values(), key=lambda s: s.service_name):
        expected = expected_test_file(sd.path, existing)
        covered = expected in existing
        rows.append({"service_name": sd.service_name, "script": sd.path,
                     "expected_test": f"tests/unit/{expected}", "covered": covered})
        if not covered:
            findings.append(Finding("INFO", "MISSING_UNIT_TEST",
                                     f"Service '{sd.service_name}' ({sd.path}) — erwartete Testdatei "
                                     f"tests/unit/{expected} nicht gefunden (mechanische Namenskonvention "
                                     f"+ '_service'-Suffix-Fallback geprüft; bei falsch-positiv Datei "
                                     f"manuell suchen, nicht blind als ungetestet werten)."))
    return rows, findings


_GAME_MANAGER_PATH = Path("scripts/platform/GameManager.gd")
_SCENE_MANAGER_PATH = Path("scripts/session/SceneManager.gd")

_CHANGE_STATE_RE = re.compile(r"change_state\(GameEnums\.State\.(\w+)\)")
_STATE_SCENE_ENTRY_RE = re.compile(
    r"GameEnums\.State\.(\w+)\s*:\s*\"(res://scenes/[^\"]+)\""
)


def check_boot_flow_scene_causality(project: Path) -> list[Finding]:
    """Round 113 Regressions-Check, generisch statt hartcodiert 'LOADING'/'PLAYING':
    GameManager._on_session_ready() setzt einen State (Y), BEVOR die Welt-Szene
    geladen ist — genau in diesem State muss laut SceneManager.STATE_SCENE_MAP
    der Szenenwechsel zu einer *World*-Szene passieren. GameManager.
    _on_world_scene_ready() setzt einen Folgestate (Z), der per Definition
    NACH dem Laden erreicht wird — Z braucht keinen eigenen Map-Eintrag
    (redundanter zweiter Szenenwechsel mitten im laufenden Spiel wäre ein Bug
    für sich).

    Konkreter, real aufgetretener Bug: STATE_SCENE_MAP mappte Z (PLAYING)
    statt Y (LOADING) auf World.tscn — ein Henne-Ei-Deadlock (Z wird erst
    über world_scene_ready erreicht, world_scene_ready braucht aber World.tscn
    bereits geladen). Ergebnis: "Neues Spiel" blieb im Hauptmenü hängen, ohne
    Crash, ohne Fehler-Log. Kein GUT-Test hätte das gefangen (siehe
    tests/unit/test_game_manager.gd und tests/integration/
    test_new_game_boot_flow.gd Kopfkommentare für die Details) — dieser
    Check läuft dagegen bei JEDEM CI-Lauf, unabhängig von GUT, rein aus dem
    Quelltext abgeleitet, kann also nicht durch einen Testfall-Bypass
    umgangen werden.
    """
    findings: list[Finding] = []
    gm_path = project / _GAME_MANAGER_PATH
    sm_path = project / _SCENE_MANAGER_PATH
    if not gm_path.exists() or not sm_path.exists():
        findings.append(Finding("WARN", "BOOT_FLOW_CHECK_SKIPPED",
                                 f"{_GAME_MANAGER_PATH} oder {_SCENE_MANAGER_PATH} nicht gefunden — "
                                 f"Boot-Flow-Kausalitäts-Check übersprungen."))
        return findings

    gm_src = gm_path.read_text(encoding="utf-8")
    sm_src = sm_path.read_text(encoding="utf-8")

    def _state_in_handler(handler_name: str) -> str | None:
        m = re.search(rf"func {handler_name}\([^)]*\)[^:]*:\n((?:\t.*\n)*)", gm_src)
        if not m:
            return None
        body = m.group(1)
        cm = _CHANGE_STATE_RE.search(body)
        return cm.group(1) if cm else None

    pre_world_state = _state_in_handler(r"_on_session_ready")
    post_world_state = _state_in_handler(r"_on_world_scene_ready")

    if not pre_world_state or not post_world_state:
        findings.append(Finding(
            "WARN", "BOOT_FLOW_CHECK_INCONCLUSIVE",
            f"_on_session_ready()/_on_world_scene_ready() in {_GAME_MANAGER_PATH} nicht wie erwartet "
            f"gefunden (pre={pre_world_state}, post={post_world_state}) — Check übersprungen. "
            f"Falls die Methoden umbenannt/umstrukturiert wurden, dieses Script nachziehen."
        ))
        return findings

    scene_map = dict(_STATE_SCENE_ENTRY_RE.findall(sm_src))

    if pre_world_state not in scene_map:
        findings.append(Finding(
            "ERROR", "WORLD_SCENE_NEVER_LOADED",
            f"GameManager._on_session_ready() setzt State '{pre_world_state}', aber "
            f"SceneManager.STATE_SCENE_MAP hat dafür keinen Eintrag — World.tscn wird beim "
            f"Session-Boot NIE geladen (Henne-Ei-Deadlock: '{post_world_state}' braucht "
            f"world_scene_ready, world_scene_ready braucht World.tscn bereits geladen). "
            f"Sichtbares Symptom: 'Neues Spiel' bleibt ohne Crash/Fehler im Hauptmenü hängen."
        ))
    elif "World" not in scene_map[pre_world_state]:
        findings.append(Finding(
            "ERROR", "WORLD_SCENE_MAPPING_SUSPICIOUS",
            f"State '{pre_world_state}' (gesetzt in _on_session_ready()) mapt auf "
            f"'{scene_map[pre_world_state]}' — enthält nicht 'World', wirkt falsch für den "
            f"Zustand, der laut Kommentar 'Welt wird gebootet' bedeutet."
        ))

    if post_world_state in scene_map:
        findings.append(Finding(
            "WARN", "REDUNDANT_SCENE_RELOAD_ON_PLAYING",
            f"State '{post_world_state}' (gesetzt in _on_world_scene_ready(), also NACHDEM "
            f"die Welt-Szene bereits geladen ist) hat einen eigenen STATE_SCENE_MAP-Eintrag "
            f"('{scene_map[post_world_state]}') — das löst einen redundanten zweiten "
            f"Szenenwechsel mitten im laufenden Spiel aus (Terrain/Entities würden neu geladen)."
        ))

    return findings


def run(project: Path) -> dict:
    config_path = project / "config" / "BootstrapConfig.tres"
    if not config_path.exists():
        return {"ok": False, "error": f"BootstrapConfig.tres nicht gefunden unter {config_path}"}

    services, resources, parse_findings = parse_bootstrap_config(config_path)
    provider_scope = build_provider_map(services, resources)
    dep_findings = check_dependencies(services, provider_scope)
    global_order, go_findings = topo_sort(services, provider_scope, "global")
    session_order, so_findings = topo_sort(services, provider_scope, "session")
    coverage_rows, coverage_findings = check_test_coverage(services, project)
    boot_flow_findings = check_boot_flow_scene_causality(project)

    all_findings = parse_findings + dep_findings + go_findings + so_findings + coverage_findings + boot_flow_findings
    errors = [f for f in all_findings if f.severity == "ERROR"]
    warns = [f for f in all_findings if f.severity == "WARN"]
    infos = [f for f in all_findings if f.severity == "INFO"]

    covered_count = sum(1 for r in coverage_rows if r["covered"])
    total = len(coverage_rows)

    return {
        "ok": not errors,
        "summary": {
            "services": total,
            "resources": len(resources),
            "unit_test_coverage": f"{covered_count}/{total}",
            "unit_test_coverage_pct": round(100 * covered_count / total, 1) if total else 0.0,
            "errors": len(errors), "warnings": len(warns), "info": len(infos),
        },
        "boot_order": {"global": global_order, "session": session_order},
        "services": [
            {"service_name": sd.service_name, "path": sd.path, "scope": sd.scope,
             "required_deps": sd.required_deps, "optional_deps": sd.optional_deps}
            for sd in sorted(services.values(), key=lambda s: s.service_name)
        ],
        "resources": [
            {"registry_key": rd.registry_key, "path": rd.path, "scope": rd.scope}
            for rd in sorted(resources.values(), key=lambda r: r.registry_key)
        ],
        "test_coverage": coverage_rows,
        "findings": {
            "errors": [f.__dict__ for f in errors],
            "warnings": [f.__dict__ for f in warns],
            "info": [f.__dict__ for f in infos],
        },
    }


def to_markdown(result: dict) -> str:
    if not result.get("summary"):
        return f"## DI-Überblick\n\n❌ {result.get('error', 'unbekannter Fehler')}\n"
    s = result["summary"]
    lines = [
        "## DI-Überblick & Testabdeckung",
        "",
        f"- Services: **{s['services']}** · Injectable Resources: **{s['resources']}**",
        f"- Unit-Test-Abdeckung: **{s['unit_test_coverage']}** ({s['unit_test_coverage_pct']}%)",
        f"- Findings: {s['errors']} Error(s), {s['warnings']} Warning(s), {s['info']} Info",
        "",
    ]
    if result["findings"]["errors"]:
        lines.append("### ❌ Errors (struktureller DI-Bug — würde den Boot crashen)")
        for f in result["findings"]["errors"]:
            lines.append(f"- **{f['kind']}**: {f['message']}")
        lines.append("")
    if result["findings"]["warnings"]:
        lines.append("### ⚠️ Warnings")
        for f in result["findings"]["warnings"]:
            lines.append(f"- **{f['kind']}**: {f['message']}")
        lines.append("")
    missing = [r for r in result["test_coverage"] if not r["covered"]]
    if missing:
        lines.append(f"### 🧪 Services ohne Unit-Test ({len(missing)})")
        for r in missing:
            lines.append(f"- `{r['service_name']}` — erwartet `{r['expected_test']}`")
        lines.append("")
    lines.append("### Boot-Reihenfolge (global → session)")
    lines.append("```")
    lines.append("global:  " + " → ".join(result["boot_order"]["global"]))
    lines.append("session: " + " → ".join(result["boot_order"]["session"]))
    lines.append("```")
    return "\n".join(lines) + "\n"


def main() -> None:
    p = argparse.ArgumentParser(description="DI-Graph + Test-Coverage-Überblick aus BootstrapConfig.tres.")
    p.add_argument("--project", required=True, help="Pfad zum Godot-Projektroot")
    p.add_argument("--out", required=True, help="JSON-Output-Pfad")
    p.add_argument("--markdown-out", help="Markdown-Output-Pfad (für Job-Summary)")
    p.add_argument("--strict", action="store_true",
                   help="exit 1 bei ERROR-Findings (Default: reines Reporting, exit 0 — "
                        "siehe Kopfkommentar zur Governance-Entscheidung)")
    args = p.parse_args()

    project = Path(args.project)
    result = run(project)

    Path(args.out).write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    if args.markdown_out:
        Path(args.markdown_out).write_text(to_markdown(result), encoding="utf-8")

    print(f"DI-Überblick geschrieben: {args.out}" + (f", {args.markdown_out}" if args.markdown_out else ""))
    if not result.get("ok", True):
        print(f"Errors: {result.get('summary', {}).get('errors', '?')} — siehe {args.out}", file=sys.stderr)
        if args.strict:
            sys.exit(1)


if __name__ == "__main__":
    main()

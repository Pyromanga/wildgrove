#!/usr/bin/env python3
# scripts/agent/method_reference_coverage.py
#
# WICHTIG — was das hier NICHT ist:
# Das ist KEINE echte Line-Coverage. Echte Line-Coverage braucht instrumentierte
# Codeausführung (GUT/gdUnit4 + Coverage-Addon, laufend in echtem Godot) — das
# ist in dieser Sandbox nicht möglich (kein Godot-Binary, kein Netzwerk für den
# Addon-Download) UND ist über Decision 0009 / ROADMAP.md Phase 3 explizit
# gesperrt, bis der Mensch das Grundprojekt für fertig erklärt und Phase 3
# freigibt. Dieses Script umgeht dieses Gate nicht — es installiert nichts,
# führt nichts aus, startet keinen Runner.
#
# Was es STATT dessen liefert: eine statische Näherung auf Methodenebene, mit
# einem INTRA-KLASSEN-CALL-GRAPH. Für jeden Service wird geprüft, ob sein
# Methodenname in der zugeordneten Testdatei als Methodenaufruf auftaucht
# (DIREKT getestet) — UND zusätzlich, ob eine andere Methode DERSELBEN Klasse
# sie aufruft, die ihrerseits direkt getestet ist (INDIREKT getestet, z.B.
# request_X() ruft synchron on_X_confirmed() auf; ein Test von request_X()
# durchläuft dann denselben Code, ohne dass die Testdatei .on_X_confirmed(
# wörtlich enthält).
#
# AST-Modus (Round 113 Nachtrag) vs. Regex-Fallback:
#   Standardmäßig wird `gdtoolkit.parser` (echte Lark-Grammatik für GDScript,
#   siehe scripts/agent/requirements.txt) genutzt, um Methodendefinitionen und
#   Methodenaufrufe aus einem echten Parse-Tree zu extrahieren — keine
#   Regex-Textsuche mehr, die z.B. durch Namen in Kommentaren/Strings oder
#   Teilstring-Kollisionen getäuscht werden könnte.
#   Ist gdtoolkit NICHT installiert (oder scheitert der Parser an einer
#   einzelnen Datei — z.B. exotische Syntax), fällt das Tool AUTOMATISCH auf
#   die alte `\bname\(`-Regex-Heuristik zurück, pro betroffener Datei einzeln,
#   mit einer expliziten Warnung in der Ausgabe. Kein stiller Qualitätsverlust.
#
# Verbleibende Grenzen, ehrlich benannt (auch im AST-Modus):
#   - Nur INNERHALB derselben .gd-Datei/Klasse — keine Cross-File-Auflösung,
#     keine Vererbungs-/Interface-Auflösung, kein dynamischer Dispatch über
#     Callables/Signals (ein `.connect(callback)` wird NICHT als Aufruf erkannt).
#   - Kein Typechecker — `self.foo()` wird als Aufruf von `foo` erkannt, aber
#     `other_object.foo()` auf einem GLEICHNAMIGEN `foo` einer FREMDEN Klasse
#     würde in Testdateien (dort wird bewusst nicht typaufgelöst, siehe
#     _referenced_names_in_test_file_ast()) fälschlich mitgezählt.
#   - Ein "indirekt getestet" ist schwächer als "direkt getestet": es zeigt nur,
#     dass der Code-Pfad potenziell mitläuft, wenn die aufrufende Methode
#     läuft — nicht, dass der Test auch die spezifischen Effekte DIESER
#     Methode geprüft hat.
# Immer noch kein Ersatz für echte Line-Coverage — nur eine bessere Näherung
# als reine Direkt-Referenz-Textsuche.
#
# Verwendung:
#   python3 scripts/agent/method_reference_coverage.py                    # Kurzfassung: nur echte Lücken (weder direkt noch indirekt)
#   python3 scripts/agent/method_reference_coverage.py --service shop     # eine Domain/Service vertiefen
#   python3 scripts/agent/method_reference_coverage.py --full             # jede Methode jedes Service, mit Status
#   python3 scripts/agent/method_reference_coverage.py --json             # maschinenlesbar

from __future__ import annotations

import argparse
import json
import re
from collections import deque
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
_BOOTSTRAP_CONFIG = _REPO_ROOT / "config" / "BootstrapConfig.tres"
_TESTS_DIR = _REPO_ROOT / "tests" / "unit"

# Diese Methoden zählen nicht als "eigene Testbarkeit" — Lifecycle-Hooks, die
# jeder Service hat und die implizit über configure() in jedem Test laufen.
_LIFECYCLE_METHOD_NAMES = {"configure", "on_ready", "on_cleanup", "_ready", "_process", "_physics_process"}

try:
    from gdtoolkit.parser import parser as _gd_parser
    from lark import Tree as _LarkTree
    from lark import Token as _LarkToken
    _GDTOOLKIT_AVAILABLE = True
except ImportError:
    _GDTOOLKIT_AVAILABLE = False

_parse_warnings: list[str] = []


def _parse_services() -> list[dict]:
    services: list[dict] = []
    current: dict | None = None
    if not _BOOTSTRAP_CONFIG.exists():
        return []
    for line in _BOOTSTRAP_CONFIG.read_text(encoding="utf-8").splitlines():
        if line.startswith("[sub_resource"):
            if current and "service_name" in current:
                services.append(current)
            current = {}
            continue
        if current is None:
            continue
        m = re.match(r'(\w+)\s*=\s*(.+)', line.strip())
        if m and m.group(1) in ("service_name", "path"):
            current[m.group(1)] = m.group(2).strip('"')
    if current and "service_name" in current:
        services.append(current)
    return services


def _class_name_of(path: str) -> str | None:
    f = _REPO_ROOT / path.removeprefix("res://")
    if not f.exists():
        return None
    m = re.search(r'^class_name (\w+)', f.read_text(encoding="utf-8", errors="replace")[:400], re.MULTILINE)
    return m.group(1) if m else None


# ─────────────────────────────────────────────────────────────────────────────
# AST-Extraktion (gdtoolkit) — bevorzugter Pfad
# ─────────────────────────────────────────────────────────────────────────────

def _collect_top_level_func_defs(tree: "_LarkTree") -> list["_LarkTree"]:
    """func_def-Knoten der HAUPTKLASSE — steigt NICHT in verschachtelte
    class_def-Knoten ab (z.B. innere Spy/Mock-Klassen in Testdateien), damit
    deren Methodennamen nicht mit denen der Hauptklasse kollidieren."""
    out = []
    def walk(node):
        if not isinstance(node, _LarkTree):
            return
        if node.data == "func_def":
            out.append(node)
            return  # Methodenkörper kann keine weiteren top-level func_def enthalten
        if node.data == "class_def":
            return  # bewusst NICHT abtauchen — andere Klasse
        for c in node.children:
            walk(c)
    walk(tree)
    return out


def _collect_called_names(node, out: set[str]) -> None:
    """Sammelt Methodennamen aus `standalone_call`- (bare Aufrufe, z.B.
    `_connect_economy_sync()`) und `getattr_call`-Knoten (`empfaenger.name(...)`,
    z.B. `_svc.request_buy_item(...)` oder `self.foo()`) — unabhängig vom
    Empfänger-Objekt, da kein Typechecker verfügbar ist (siehe Skript-Kopf)."""
    if isinstance(node, _LarkTree):
        if node.data == "standalone_call" and node.children:
            first = node.children[0]
            if isinstance(first, _LarkToken):
                out.add(str(first))
        elif node.data == "getattr_call" and node.children:
            ga = node.children[0]
            if isinstance(ga, _LarkTree) and ga.data == "getattr" and ga.children:
                last = ga.children[-1]
                if isinstance(last, _LarkToken):
                    out.add(str(last))
        for c in node.children:
            _collect_called_names(c, out)


def _all_methods_of_ast(path: str) -> dict[str, dict] | None:
    """AST-basiert via gdtoolkit. Gibt None zurück (statt zu werfen), wenn
    gdtoolkit fehlt oder die Datei nicht parsbar ist — Aufrufer fällt dann
    automatisch auf _all_methods_of_regex() zurück."""
    if not _GDTOOLKIT_AVAILABLE:
        return None
    f = _REPO_ROOT / path.removeprefix("res://")
    if not f.exists():
        return None
    try:
        code = f.read_text(encoding="utf-8", errors="replace")
        tree = _gd_parser.parse(code, gather_metadata=True)
    except Exception as e:  # noqa: BLE001 — Parser kann diverse Fehlerklassen werfen
        _parse_warnings.append(f"⚠ AST-Parse fehlgeschlagen für {path} ({type(e).__name__}) — Fallback auf Regex-Heuristik für diese Datei.")
        return None

    out: dict[str, dict] = {}
    for fd in _collect_top_level_func_defs(tree):
        header = fd.children[0]
        if not header.children or not isinstance(header.children[0], _LarkToken):
            continue
        name = str(header.children[0])
        calls: set[str] = set()
        _collect_called_names(fd, calls)
        calls.discard(name)  # Selbstrekursion ist kein Call-Graph-Kante von Interesse
        line = getattr(fd.meta, "line", None) or 0
        out[name] = {"line": line, "calls": calls}
    return out or None


def _referenced_names_in_test_file_ast(path: Path) -> set[str] | None:
    if not _GDTOOLKIT_AVAILABLE:
        return None
    try:
        code = path.read_text(encoding="utf-8", errors="replace")
        tree = _gd_parser.parse(code, gather_metadata=True)
    except Exception as e:  # noqa: BLE001
        _parse_warnings.append(f"⚠ AST-Parse fehlgeschlagen für {path.relative_to(_REPO_ROOT)} ({type(e).__name__}) — Fallback auf Regex-Heuristik für diese Datei.")
        return None
    names: set[str] = set()
    _collect_called_names(tree, names)
    return names


# ─────────────────────────────────────────────────────────────────────────────
# Regex-Fallback (nur wenn AST nicht verfügbar/gescheitert)
# ─────────────────────────────────────────────────────────────────────────────

def _all_methods_of_regex(path: str) -> dict[str, dict]:
    f = _REPO_ROOT / path.removeprefix("res://")
    if not f.exists():
        return {}
    lines = f.read_text(encoding="utf-8", errors="replace").splitlines()
    starts = []
    for i, line in enumerate(lines):
        m = re.match(r'^(?:static )?func (\w+)\(', line)
        if m:
            starts.append((i, m.group(1)))
    out: dict[str, dict] = {}
    for idx, (start, name) in enumerate(starts):
        end = starts[idx + 1][0] if idx + 1 < len(starts) else len(lines)
        body = "\n".join(lines[start:end])
        calls = {other for other in [s[1] for s in starts] if other != name and re.search(r'\b' + re.escape(other) + r'\(', body)}
        out[name] = {"line": start + 1, "calls": calls}
    return out


def _referenced_names_in_test_file_regex(path: Path, known_names: set[str]) -> set[str]:
    text = path.read_text(encoding="utf-8", errors="replace")
    return {name for name in known_names if re.search(r'\.' + re.escape(name) + r'\(', text)}


# ─────────────────────────────────────────────────────────────────────────────
# Gemeinsame Logik (unabhängig vom Extraktions-Backend)
# ─────────────────────────────────────────────────────────────────────────────

def _methods_of(path: str) -> tuple[dict[str, dict], bool]:
    """(methods, used_ast) — methods hat IMMER 'calls' bereits aufgelöst
    (AST-Callgraph-Kanten fehlen im Regex-Fallback NICHT, werden dort separat
    aus demselben Body-Text nachgebaut)."""
    ast_result = _all_methods_of_ast(path)
    if ast_result is not None:
        return ast_result, True
    return _all_methods_of_regex(path), False


def _referenced_names_in_test_file(path: Path, known_names: set[str]) -> set[str]:
    ast_result = _referenced_names_in_test_file_ast(path)
    if ast_result is not None:
        return ast_result & known_names
    return _referenced_names_in_test_file_regex(path, known_names)


def _transitively_covered(graph: dict[str, set[str]], directly_tested: set[str]) -> dict[str, str]:
    """BFS von jeder direkt getesteten Methode aus über den Call-Graph.
    Rückgabe: {methodenname: naechster_direkt_getesteter_aufrufer} für jede
    Methode, die NICHT selbst direkt getestet ist, aber von einer direkt
    getesteten Methode aus erreichbar ist."""
    reached_via: dict[str, str] = {}
    for start in directly_tested:
        seen = {start}
        queue = deque([(start, start)])  # (aktueller_knoten, urspruenglicher_direkt_getesteter_aufrufer)
        while queue:
            node, origin = queue.popleft()
            for callee in graph.get(node, ()):
                if callee in seen:
                    continue
                seen.add(callee)
                if callee not in directly_tested and callee not in reached_via:
                    reached_via[callee] = origin
                queue.append((callee, origin))
    return reached_via


def _matching_test_files(class_name: str) -> list[Path]:
    if not _TESTS_DIR.exists() or not class_name:
        return []
    matches = []
    for f in _TESTS_DIR.glob("test_*.gd"):
        try:
            header = f.read_text(encoding="utf-8", errors="replace").splitlines()[:40]
        except Exception:  # noqa: BLE001
            continue
        # class_name muss im direkten Subjekt-Teil von "Tests für X" stehen,
        # nicht nur beiläufig irgendwo in der Zeile — sonst matcht z.B.
        # "Tests für WorldSaveHandler (E-02 — WorldService save/load)"
        # fälschlich auf WorldService. Klammerinhalte werden vor der Suche
        # entfernt (nicht: bei der ersten Klammer abgeschnitten), damit
        # legitime Mehrfach-Subjekt-Header wie "Tests für StatModifier
        # (Daten) und StatModifierService (Logik)" trotzdem beide Namen
        # finden — der Unterschied ist der Fließtext AUSSERHALB der Klammern,
        # nicht die Klammer selbst.
        for line in header:
            cleaned = re.sub(r'\([^)]*\)', '', line)
            m = re.search(r'Tests für [^.\n]*', cleaned)
            if m and class_name in m.group(0):
                matches.append(f)
                break

    # Ergänzungs-Testdateien folgen im Projekt der Konvention
    # 'test_<basisname>_<suffix>.gd' (z.B. test_equipment_service_r4.gd,
    # test_player_state_service_signals.gd) — deren Header sagt oft NICHT
    # wörtlich "Tests für <ClassName>" (z.B. "Regressionstests für ADR-027"),
    # würde also vom obigen Check allein übersehen. Für jede über den
    # Header-Match gefundene Basisdatei zusätzlich alle test_<stem>_*.gd
    # mitnehmen.
    extra = []
    for f in matches:
        for sibling in _TESTS_DIR.glob(f"{f.stem}_*.gd"):
            if sibling not in matches and sibling not in extra:
                extra.append(sibling)
    matches.extend(extra)
    return matches


def build_report() -> list[dict]:
    services = _parse_services()
    out = []
    for s in services:
        cls = _class_name_of(s.get("path", ""))
        all_methods, used_ast = _methods_of(s.get("path", "")) if cls else ({}, False)
        test_files = _matching_test_files(cls) if cls else []

        known_names = set(all_methods.keys())
        directly_tested: set[str] = set()
        for tf in test_files:
            directly_tested |= _referenced_names_in_test_file(tf, known_names)

        graph = {name: info["calls"] for name, info in all_methods.items()}
        indirectly_tested = _transitively_covered(graph, directly_tested)

        # Bericht bleibt auf öffentliche, nicht-Lifecycle-Methoden beschränkt
        # (Aufrufer-Interesse), aber private Helfer zählen als gültige
        # Zwischenknoten im Call-Graph (z.B. request_X() -> _validate() ->
        # on_X_confirmed()).
        method_results = []
        for name, info in all_methods.items():
            if name in _LIFECYCLE_METHOD_NAMES or name.startswith("_"):
                continue
            if name in directly_tested:
                status = "direct"
                via = None
            elif name in indirectly_tested:
                status = "indirect"
                via = indirectly_tested[name]
            else:
                status = "none"
                via = None
            method_results.append({"method": name, "line": info["line"], "status": status, "via": via, "referenced": status != "none"})

        method_results.sort(key=lambda m: m["line"])
        referenced_count = sum(1 for m in method_results if m["referenced"])
        direct_count = sum(1 for m in method_results if m["status"] == "direct")
        out.append({
            "service_name": s["service_name"],
            "class_name": cls,
            "path": s.get("path"),
            "test_files": [str(f.relative_to(_REPO_ROOT)) for f in test_files],
            "used_ast": used_ast,
            "methods": method_results,
            "method_count": len(method_results),
            "referenced_count": referenced_count,
            "direct_count": direct_count,
            "coverage_pct": round(100 * referenced_count / len(method_results), 1) if method_results else None,
        })
    return out


def render(data: list[dict], full: bool, service_filter: str | None) -> str:
    lines = []
    lines.append("# Methoden-Referenz-Näherung mit Intra-Klassen-Call-Graph (KEINE echte Line-Coverage — siehe Skript-Kopf)")
    lines.append("")
    if _GDTOOLKIT_AVAILABLE:
        lines.append("Extraktion: echter GDScript-AST via gdtoolkit.")
    else:
        lines.append("⚠ gdtoolkit nicht installiert — komplett auf Regex-Heuristik zurückgefallen.")
        lines.append("  Für echten AST: pip install -r scripts/agent/requirements.txt --break-system-packages")
    lines.append("✓ = Testdatei ruft `.methodenname(` direkt auf. ~ = nicht direkt, aber von einer")
    lines.append("direkt getesteten Methode DERSELBEN Klasse aus erreichbar (z.B. request_X() ruft")
    lines.append("synchron on_X_confirmed() auf). ✗ = weder noch — echte Lücke. Kein Beweis für")
    lines.append("Assertions, keine Branch-/Zeilen-Abdeckung. Echte Coverage braucht Godot +")
    lines.append("GUT/gdUnit4 — gesperrt bis Phase 3 (Decision 0009).")
    lines.append("")
    ast_fallback_services = [r["service_name"] for r in data if not r.get("used_ast", True)]
    if _GDTOOLKIT_AVAILABLE and ast_fallback_services:
        lines.append(f"⚠ Datei-Parse-Fallback auf Regex für: {', '.join(ast_fallback_services)} (siehe Warnungen unten)")
        lines.append("")
    if _parse_warnings:
        lines.append("## Warnungen")
        lines.append("")
        for w in sorted(set(_parse_warnings)):
            lines.append(f"- {w}")
        lines.append("")

    rows = data
    if service_filter:
        rows = [r for r in rows if r["service_name"] == service_filter]
        if not rows:
            return "\n".join(lines) + f"\n⚠ Service '{service_filter}' nicht gefunden."

    if not full and not service_filter:
        lines.append("## Services mit echten Lücken (weder direkt noch indirekt getestet)")
        lines.append("")
        any_gap = False
        for r in sorted(rows, key=lambda r: r["service_name"]):
            gaps = [m for m in r["methods"] if m["status"] == "none"]
            if not gaps:
                continue
            any_gap = True
            lines.append(f"### `{r['service_name']}` ({r['class_name']}) — {r['referenced_count']}/{r['method_count']} referenziert ({r['coverage_pct']}%, davon {r['direct_count']} direkt)")
            for m in gaps:
                lines.append(f"- `{m['method']}()` — Zeile {m['line']}, {r['path']}")
            lines.append("")
        if not any_gap:
            lines.append("Keine echten Lücken gefunden (jede öffentliche Methode wird mindestens einmal direkt oder indirekt über eine getestete Aufruferin erreicht).")
        lines.append("")
        lines.append("(`--full` für die komplette Tabelle inkl. bereits abgedeckter Methoden.)")
        return "\n".join(lines)

    lines.append(f"## Services ({len(rows)})")
    lines.append("")
    for r in sorted(rows, key=lambda r: r["service_name"]):
        pct = f"{r['coverage_pct']}%" if r["coverage_pct"] is not None else "—"
        lines.append(f"### `{r['service_name']}` ({r['class_name']}) — {r['referenced_count']}/{r['method_count']} referenziert ({pct}, davon {r['direct_count']} direkt)")
        if not r["test_files"]:
            lines.append("⚠ keine zugeordnete Testdatei gefunden")
        for m in r["methods"]:
            mark = {"direct": "✓", "indirect": "~", "none": "✗"}[m["status"]]
            suffix = f" — indirekt über `{m['via']}()`" if m["status"] == "indirect" else ""
            lines.append(f"- {mark} `{m['method']}()` — Zeile {m['line']}{suffix}")
        lines.append("")
    return "\n".join(lines)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--service", help="Nur einen Service (service_name aus BootstrapConfig) anzeigen, mit voller Methodenliste")
    ap.add_argument("--full", action="store_true", help="Alle Methoden aller Services zeigen, nicht nur echte Lücken")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    data = build_report()
    if args.json:
        print(json.dumps(data, indent=2, ensure_ascii=False))
        return
    print(render(data, full=args.full, service_filter=args.service))


if __name__ == "__main__":
    main()


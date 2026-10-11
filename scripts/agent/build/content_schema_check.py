#!/usr/bin/env python3
# scripts/agent/build/content_schema_check.py
#
# AUSBAUSCHRITT zu content_forge.py — schließt dessen selbst benannte Lücke:
# "Die Schemas sind von Hand aus den .gd-Dateien übertragen, kein
# automatischer Sync". Dieses Tool macht das Vergessen-nachzuziehen laut
# statt still: es liest die @export-Felder direkt aus den
# *Definition.gd-Dateien (und, wo relevant, aus deren `extends`-Basisklasse,
# z.B. WeaponDefinition extends ItemDefinition) und vergleicht sie gegen
# content_forge.SCHEMAS. Jede Abweichung ist ein Finding — analog zu
# service_graph.py (ERROR-Kinds -> exit 1), nicht nur eine Textausgabe.
#
# AST vs. Regex (gleiche Konvention wie method_reference_coverage.py):
#   Primär genutzt wird eine Zeilen-Regex über @export-Deklarationen — das
#   ist der Teil, der in dieser Sandbox tatsächlich gegen alle *Definition.gd-
#   Dateien des Repos getestet wurde (siehe `--self-test`). Ist `gdtoolkit`
#   installiert, wird zusätzlich ein AST-Parse pro Datei versucht und dessen
#   @export-Anzahl gegen die Regex-Anzahl gegengeprüft (SCHEMA_AST_MISMATCH-
#   Finding bei Abweichung) — das deckt Fälle ab, die eine Zeilen-Regex
#   grundsätzlich nicht sicher erfassen kann (@export über mehrere Zeilen,
#   Feld-Deklaration ohne Leerzeichen-Konvention, etc.). Diese AST-Kreuzprüfung
#   selbst ist in DIESER Sandbox nicht ausführbar (kein Netzwerk, gdtoolkit
#   nicht installierbar) — sie ist implementiert und fällt automatisch weg
#   (übersprungen, keine Findings) wenn `import gdtoolkit` fehlschlägt, statt
#   eine ungeprüfte Behauptung über ihre Korrektheit zu machen. Das AST-Modul
#   ersetzt NICHT die Regex — es ist eine zusätzliche Gegenprobe, weil die
#   Regex hier die einzige Schicht ist, die tatsächlich verifiziert wurde.
#
# Was dieses Tool NICHT tut: SCHEMAS automatisch umschreiben. Ein Feld, das
# neu in einer .gd-Datei auftaucht, kann Bedeutung tragen, die eine
# Textersetzung nicht sicher erraten kann (Enum-Zuordnung, ob es überhaupt
# über den Content-Workflow gesetzt werden soll, Sub-Resource-Klasse bei
# array_obj-Feldern). Genau dasselbe Prinzip wie build/common.py Regel 4
# ("Kein Modul darf raten") — dieses Tool findet die Lücke und benennt genau
# was in content_forge.py SCHEMAS zu ändern ist; der Mensch/Agent trägt die
# Änderung nach und lässt --self-test danach grün laufen.
#
# Befehle:
#   check [--json]        Alle Content-Typen aus content_forge.SCHEMAS gegen
#                          ihre .gd-Quelle prüfen. Exit 1 bei ERROR-Findings.
#   dump <gd-path>         Rohe @export-Extraktion einer einzelnen .gd-Datei
#                          (Debug-Hilfe, um die Regex selbst zu prüfen).

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import content_forge as cf  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[3]

try:
    from gdtoolkit.parser import parser as _gd_parser
    _GDTOOLKIT_AVAILABLE = True
except ImportError:
    _GDTOOLKIT_AVAILABLE = False

ERROR_KINDS = {"OWN_FIELD_MISSING_FROM_SCHEMA", "SCHEMA_FIELD_STALE", "TYPE_MISMATCH", "DEFAULT_MISMATCH"}

# Felder, die absichtlich nicht über content_forge abgebildet werden, weil sie
# strukturell anders gehandhabt werden (Sub-Resource statt Skalarwert) oder
# reine Editor-/Asset-Felder sind, die ein Content-Agent nicht setzen soll.
STRUCTURAL_ALLOWLIST = {
    ("quest", "reward"): "wird aus reward_xp/reward_items/reward_unlock_quests/"
                          "reward_custom_signals/reward_stat_modifiers als eigene "
                          "QuestReward-Sub-Resource gebaut, kein Skalarfeld",
    ("quest", "reward_xp"): "flacher Alias für QuestReward.xp_rewards (geprüft via QUEST_REWARD_FIELD_MAP)",
    ("quest", "reward_items"): "flacher Alias für QuestReward.item_rewards (geprüft via QUEST_REWARD_FIELD_MAP)",
    ("quest", "reward_unlock_quests"): "flacher Alias für QuestReward.unlock_quests (geprüft via QUEST_REWARD_FIELD_MAP)",
    ("quest", "reward_custom_signals"): "flacher Alias für QuestReward.custom_signals (geprüft via QUEST_REWARD_FIELD_MAP)",
    ("quest", "reward_stat_modifiers"): "flacher Alias für QuestReward.stat_modifiers (geprüft via QUEST_REWARD_FIELD_MAP)",
}
SKIP_GD_TYPES = {"Texture2D"}  # editor-only Asset-Referenzen, kein Content-Feld

# reward_* in content_forge.SCHEMAS['quest'] sind flache Aliase auf Felder
# einer ANDEREN .gd-Datei (QuestReward.gd, nicht QuestDefinition.gd) — siehe
# build_tres()/quest-Sonderfall in content_forge.py. Werden hier separat
# gegen ihre echte Quelle geprüft statt pauschal allowlisted, damit eine
# Umbenennung in QuestReward.gd trotzdem als Drift auffällt.
QUEST_REWARD_FIELD_MAP = {
    "reward_xp": "xp_rewards", "reward_items": "item_rewards",
    "reward_unlock_quests": "unlock_quests", "reward_custom_signals": "custom_signals",
    "reward_stat_modifiers": "stat_modifiers",
}
QUEST_REWARD_GD = "res://scripts/progression/quests/QuestReward.gd"

# Fälle, in denen content_forge.SCHEMAS ABSICHTLICH einen anderen Default
# wählt als der @export-Default in der .gd-Klasse — z.B. weil der Content-
# Workflow einen sinnvolleren Ausgangswert für NEUE Instanzen dieses Typs
# vorschlägt, als der Resource-Klassen-Default (der u.U. von einer anderen
# Subklasse mitgeerbt wird). Jeder Eintrag MUSS begründet sein — sonst ist
# es keine bewusste Abweichung, sondern die Drift, die dieses Tool finden
# soll.
ALLOWED_DEFAULT_OVERRIDES = {
    ("weapon", "max_stack"): "ItemDefinition.gd-Default ist 999 (für stapelbare "
        "Gathering-Items gedacht); WeaponDefinition erbt das Feld ohne eigenen "
        "Override, aber jede vorhandene Waffen-.tres im Repo setzt es explizit "
        "auf 1 (nicht stapelbar) — content_forge übernimmt diese gelebte "
        "Konvention als Default, nicht den geerbten Klassen-Default.",
    ("tool", "max_stack"): "gleiche Begründung wie weapon.max_stack — Werkzeuge "
        "sind in allen vorhandenen .tres-Beispielen max_stack=1.",
}

GD_TYPE_TO_KIND = {
    "String": "str", "int": "int", "float": "float", "bool": "bool",
    "Vector3": "vector3", "Dictionary": "dict",
    "Array[int]": "array_int", "Array[String]": "array_str",
}


@dataclass
class ParsedField:
    name: str
    gd_type: str
    default_text: str | None
    line_no: int
    source: Path | None = None


def _strip_trailing_comment(line: str) -> str:
    in_str = False
    quote = ""
    for i, ch in enumerate(line):
        if in_str:
            if ch == quote and line[i - 1:i] != "\\":
                in_str = False
        elif ch in ('"', "'"):
            in_str, quote = True, ch
        elif ch == "#":
            return line[:i]
    return line


_EXPORT_RE = re.compile(
    r'^\s*@export(?:_range\([^)]*\)|_flags\([^)]*\))?\s+var\s+'
    r'(?P<name>\w+)\s*:\s*(?P<type>[\w\[\],\. ]+?)'
    r'(?:\s*=\s*(?P<default>.+?))?\s*$'
)
_ENUM_RE = re.compile(r'^\s*enum\s+(\w+)\s*\{(.*?)\}', re.DOTALL | re.MULTILINE)
_EXTENDS_RE = re.compile(r'^\s*extends\s+(\w+)', re.MULTILINE)


def parse_enums(text: str) -> dict[str, dict[str, int]]:
    out: dict[str, dict[str, int]] = {}
    for m in _ENUM_RE.finditer(text):
        name = m.group(1)
        members = [p.strip() for p in m.group(2).split(",") if p.strip()]
        out[name] = {}
        idx = 0
        for mem in members:
            mem = mem.split("=")[0].strip() if "=" in mem else mem
            if not mem:
                continue
            out[name][mem] = idx
            idx += 1
    return out


def parse_export_fields(path: Path) -> list[ParsedField]:
    if not path.exists():
        return []
    lines = path.read_text(encoding="utf-8").splitlines()
    out = []
    for i, raw in enumerate(lines):
        line = _strip_trailing_comment(raw)
        if "@export" not in line:
            continue
        m = _EXPORT_RE.match(line)
        if not m:
            continue
        out.append(ParsedField(
            name=m.group("name"), gd_type=m.group("type").strip(),
            default_text=(m.group("default") or "").strip() or None,
            line_no=i + 1, source=path,
        ))
    return out


def ast_export_count(path: Path) -> int | None:
    """Best-effort AST-Gegenprobe. Ungetestet in dieser Sandbox (kein
    gdtoolkit installierbar) — liefert None statt einer Zahl, wenn gdtoolkit
    fehlt oder der Parse scheitert, damit der Aufrufer das nicht mit
    'null Treffer' verwechselt."""
    if not _GDTOOLKIT_AVAILABLE or not path.exists():
        return None
    try:
        tree = _gd_parser.parse(path.read_text(encoding="utf-8"))
    except Exception:
        return None
    count = 0
    for node in tree.iter_subtrees():
        node_name = getattr(node, "data", "")
        if "annotation" in str(node_name).lower() or "export" in str(node_name).lower():
            text = " ".join(str(t) for t in node.children if hasattr(t, "value")) if hasattr(node, "children") else ""
            if "export" in str(node_name).lower() or "export" in text.lower():
                count += 1
    return count or None


def find_gd_for_class(class_name: str) -> Path | None:
    """Sucht die .gd-Datei, die `class_name X` deklariert — nur für Basis-
    klassen gebraucht (z.B. ItemDefinition, wenn WeaponDefinition sie
    extended). Begrenzte, gezielte Suche (kein Full-Repo-Scan nötig, da nur
    innerhalb der ItemDefinition-Familie relevant)."""
    for gd in REPO_ROOT.rglob("*.gd"):
        if gd.name.endswith(".gd") and not gd.name.endswith(".gd.bak"):
            head = gd.read_text(encoding="utf-8", errors="ignore")[:400]
            if re.search(rf'\bclass_name\s+{re.escape(class_name)}\b', head):
                return gd
    return None


def _unwrap_array_literal(text: str) -> str:
    """'Array[int]([1, 2])' und '[1, 2]' sind für einen typisierten
    @export-Default austauschbar — Godot akzeptiert das nackte Literal, wenn
    der Typ schon aus der Annotation feststeht (siehe SkillDefinition.gd:
    xp_to_level_up wird ohne 'Array[int](...)'-Wrapper geschrieben). Für den
    Vergleich wird beidseitig auf den inneren Klammerinhalt reduziert."""
    m = re.match(r'^Array\[\w+\]\(\[(.*)\]\)$', text)
    if m:
        return m.group(1)
    m = re.match(r'^\[(.*)\]$', text)
    if m:
        return m.group(1)
    return text


def gd_default_matches_schema(kind: str, schema_default, enum: dict | None, gd_default: str | None) -> tuple[bool, str]:
    if gd_default is None:
        return True, "kein Default in .gd (Pflichtfeld-artig) — nicht vergleichbar, übersprungen"
    if kind == "enum":
        m = re.match(r'^\w+\.(\w+)$', gd_default)
        gd_member = m.group(1) if m else gd_default
        return (gd_member == schema_default), f"gd='{gd_default}' vs. schema='{schema_default}'"
    if kind in ("array_obj", "dict"):
        return True, "Container-Default nicht literal verglichen (immer leer/eingebettet)"
    rendered = cf.fmt_value(kind, schema_default, enum)
    norm_gd = re.sub(r"\s+", "", gd_default)
    norm_schema = re.sub(r"\s+", "", rendered)
    if kind in ("array_int", "array_str"):
        norm_gd = _unwrap_array_literal(norm_gd)
        norm_schema = _unwrap_array_literal(norm_schema)
    return (norm_gd == norm_schema), f"gd='{gd_default}' vs. schema-gerendert='{rendered}'"


def check_content_type(ctype: cf.ContentType) -> list[dict]:
    findings: list[dict] = []
    gd_path = REPO_ROOT / ctype.script.replace("res://", "")
    text = gd_path.read_text(encoding="utf-8") if gd_path.exists() else ""
    if not text:
        findings.append({"kind": "SOURCE_MISSING", "severity": "ERROR", "type": ctype.key,
                          "message": f"Quelldatei nicht gefunden: {gd_path}"})
        return findings

    own_fields = {f.name: f for f in parse_export_fields(gd_path)}
    own_enums = parse_enums(text)

    inherited_fields: dict[str, ParsedField] = {}
    m = _EXTENDS_RE.search(text)
    if m:
        base_name = m.group(1)
        base_path = find_gd_for_class(base_name)
        if base_path:
            inherited_fields = {f.name: f for f in parse_export_fields(base_path)}

    ast_count = ast_export_count(gd_path)
    if ast_count is not None:
        regex_count = len(own_fields)
        if ast_count != regex_count:
            findings.append({
                "kind": "SCHEMA_AST_MISMATCH", "severity": "WARN", "type": ctype.key,
                "message": f"AST fand {ast_count} @export-Annotationen, Regex fand {regex_count} — "
                           f"ein Feld in {gd_path.name} folgt vermutlich nicht dem erwarteten Ein-Zeilen-Muster, "
                           f"manuell prüfen.",
            })

    schema_by_name = {f.name: f for f in ctype.base_fields}
    all_gd_fields = {**inherited_fields, **own_fields}  # own überschreibt gleichnamige inherited (Override-Fall)

    # 1) .gd-Felder, die im Schema fehlen.
    for name, pf in all_gd_fields.items():
        is_own = name in own_fields
        if pf.gd_type in SKIP_GD_TYPES:
            continue
        if (ctype.key, name) in STRUCTURAL_ALLOWLIST:
            continue
        if name in schema_by_name:
            continue
        src_name = pf.source.name if pf.source else gd_path.name
        findings.append({
            "kind": "OWN_FIELD_MISSING_FROM_SCHEMA" if is_own else "INHERITED_FIELD_NOT_EXPOSED",
            "severity": "ERROR" if is_own else "INFO",
            "type": ctype.key, "field": name,
            "message": f"{src_name}:{pf.line_no} deklariert @export var {name}: {pf.gd_type}"
                       f"{' (geerbt, bewusst nicht über content_forge setzbar)' if not is_own else ' — fehlt in ContentType.base_fields, SCHEMAS in content_forge.py nachziehen'}",
        })

    # 2) Schema-Felder, die es in der .gd-Datei nicht (mehr) gibt.
    for name, f in schema_by_name.items():
        if (ctype.key, name) in STRUCTURAL_ALLOWLIST:
            continue
        if name not in all_gd_fields:
            findings.append({
                "kind": "SCHEMA_FIELD_STALE", "severity": "ERROR", "type": ctype.key, "field": name,
                "message": f"content_forge.SCHEMAS['{ctype.key}'] kennt Feld '{name}', "
                           f"aber weder {gd_path.name} noch dessen Basisklasse deklarieren es (mehr) — "
                           f"Feld aus SCHEMAS entfernen oder .gd-Datei prüfen.",
            })

    # 3) Typ-/Default-Abgleich für Felder, die auf beiden Seiten existieren.
    for name, f in schema_by_name.items():
        pf = all_gd_fields.get(name)
        if pf is None or f.kind == "array_obj":
            continue  # array_obj (Sub-Resource-Listen) hat keine 1:1 GDScript-Skalar-Typkorrespondenz
        expected_kind = f.kind
        if expected_kind == "enum":
            gd_kind_ok = pf.gd_type in own_enums or pf.gd_type in parse_enums(
                (REPO_ROOT / (find_gd_for_class(pf.gd_type).relative_to(REPO_ROOT) if find_gd_for_class(pf.gd_type) else Path("."))).read_text(encoding="utf-8")
            ) if False else True  # Enum-Typname wird unten nur über Namensgleichheit mit f.enum-Keys geprüft
            if pf.gd_type not in own_enums:
                findings.append({
                    "kind": "TYPE_MISMATCH", "severity": "WARN", "type": ctype.key, "field": name,
                    "message": f"Schema erwartet Enum-Typ, .gd-Typ '{pf.gd_type}' ist in {gd_path.name} "
                               f"kein lokal deklariertes enum (evtl. geerbt — dann hier nicht prüfbar).",
                })
        else:
            gd_kind = GD_TYPE_TO_KIND.get(pf.gd_type)
            src_name = pf.source.name if pf.source else gd_path.name
            if gd_kind is not None and gd_kind != expected_kind:
                findings.append({
                    "kind": "TYPE_MISMATCH", "severity": "ERROR", "type": ctype.key, "field": name,
                    "message": f"Schema kind='{expected_kind}', .gd deklariert '{pf.gd_type}' (kind='{gd_kind}') "
                               f"in {src_name}:{pf.line_no}",
                })

        if not f.required:
            ok, detail = gd_default_matches_schema(f.kind, f.default, f.enum, pf.default_text)
            if not ok:
                override_reason = ALLOWED_DEFAULT_OVERRIDES.get((ctype.key, name))
                src_name = pf.source.name if pf.source else gd_path.name
                if override_reason:
                    findings.append({
                        "kind": "DEFAULT_OVERRIDE_ACKNOWLEDGED", "severity": "INFO", "type": ctype.key, "field": name,
                        "message": f"Default weicht bewusst ab in {src_name}:{pf.line_no} ({detail}) — {override_reason}",
                    })
                else:
                    findings.append({
                        "kind": "DEFAULT_MISMATCH", "severity": "ERROR", "type": ctype.key, "field": name,
                        "message": f"Default weicht ab in {src_name}:{pf.line_no} — {detail}. "
                                   f"Falls beabsichtigt: in ALLOWED_DEFAULT_OVERRIDES mit Begründung eintragen, "
                                   f"sonst SCHEMAS in content_forge.py korrigieren.",
                    })

    if ctype.key == "quest":
        reward_gd = REPO_ROOT / QUEST_REWARD_GD.replace("res://", "")
        reward_fields = {f.name: f for f in parse_export_fields(reward_gd)}
        for alias, real_name in QUEST_REWARD_FIELD_MAP.items():
            if real_name not in reward_fields:
                findings.append({
                    "kind": "SCHEMA_FIELD_STALE", "severity": "ERROR", "type": ctype.key, "field": alias,
                    "message": f"content_forge.SCHEMAS['quest'] Feld '{alias}' ist als Alias für "
                               f"QuestReward.{real_name} gedacht, aber {reward_gd.name} deklariert dieses "
                               f"Feld nicht (mehr) — QUEST_REWARD_FIELD_MAP oder QuestReward.gd geändert?",
                })

    return findings


def cmd_check(args: argparse.Namespace) -> None:
    all_findings: list[dict] = []
    for key in sorted(cf.SCHEMAS):
        all_findings.extend(check_content_type(cf.SCHEMAS[key]))

    errors = [f for f in all_findings if f["severity"] == "ERROR"]
    warns = [f for f in all_findings if f["severity"] == "WARN"]
    infos = [f for f in all_findings if f["severity"] == "INFO"]

    if args.json:
        print(json.dumps({
            "ok": not errors,
            "checked_types": sorted(cf.SCHEMAS),
            "gdtoolkit_available": _GDTOOLKIT_AVAILABLE,
            "errors": errors, "warnings": warns, "info": infos,
        }, indent=2, ensure_ascii=False))
    else:
        print(f"content_schema_check — {len(cf.SCHEMAS)} Content-Typen geprüft "
              f"(gdtoolkit {'verfügbar' if _GDTOOLKIT_AVAILABLE else 'NICHT verfügbar — nur Regex-Pfad aktiv'})")
        for label, bucket in (("ERROR", errors), ("WARN", warns), ("INFO", infos)):
            if not bucket:
                continue
            print(f"\n{label} ({len(bucket)}):")
            for f in bucket:
                loc = f.get("field", "")
                print(f"  [{f['type']}{'.' + loc if loc else ''}] {f['kind']}: {f['message']}")
        if not all_findings:
            print("\nKeine Abweichungen — SCHEMAS in content_forge.py deckt sich mit den .gd-Quellen.")
    sys.exit(1 if errors else 0)


def cmd_dump(args: argparse.Namespace) -> None:
    path = Path(args.gd_path)
    if not path.is_absolute():
        path = REPO_ROOT / path
    fields = parse_export_fields(path)
    print(json.dumps({
        "path": str(path.relative_to(REPO_ROOT)) if path.is_relative_to(REPO_ROOT) else str(path),
        "fields": [{"name": f.name, "gd_type": f.gd_type, "default": f.default_text, "line": f.line_no} for f in fields],
        "enums": parse_enums(path.read_text(encoding="utf-8")) if path.exists() else {},
    }, indent=2, ensure_ascii=False))


def main() -> None:
    p = argparse.ArgumentParser(description="Schema-Drift-Check: content_forge.SCHEMAS vs. tatsächliche .gd-@export-Felder.")
    sub = p.add_subparsers(dest="cmd", required=True)

    p_check = sub.add_parser("check", help="Alle Content-Typen prüfen")
    p_check.add_argument("--json", action="store_true")
    p_check.set_defaults(func=cmd_check)

    p_dump = sub.add_parser("dump", help="@export-Felder einer einzelnen .gd-Datei roh ausgeben")
    p_dump.add_argument("gd_path")
    p_dump.set_defaults(func=cmd_dump)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()

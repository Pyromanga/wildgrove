#!/usr/bin/env python3
# scripts/ci/di_query.py
#
# Navigator für die JSON-Datei, die di_test_overview.py schreibt (Default:
# di-overview.json). Zweck: ein Agent, der z.B. "was hängt alles an
# 'savesystem'?" oder "welche Services haben keinen Unit-Test?" wissen will,
# soll das nicht durch erneutes Parsen von BootstrapConfig.tres herausfinden
# müssen — einmal in di_test_overview.py gebaut, hier nur noch gelesen.
#
# Befehle:
#   service <name>          Volles Profil eines Service (Deps, Scope, Test)
#   deps <name>              Direkte Abhängigkeiten (required + optional)
#   dependents <name>        Wer hängt (direkt) von <name> ab? (Reverse-Lookup)
#   missing-tests            Alle Services ohne gefundene Unit-Test-Datei
#   boot-order [global|session]   Die berechnete Boot-Reihenfolge
#   errors                   Alle ERROR-Findings (struktureller DI-Bug)
#
# Alle Befehle: --file <pfad zu di-overview.json>, Default "di-overview.json".

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def load(path: str) -> dict:
    p = Path(path)
    if not p.exists():
        print(json.dumps({"error": f"'{path}' nicht gefunden — erst di_test_overview.py laufen lassen."}),
              file=sys.stderr)
        sys.exit(1)
    return json.loads(p.read_text(encoding="utf-8"))


def find_service(data: dict, name: str) -> dict | None:
    for s in data.get("services", []):
        if s["service_name"] == name:
            return s
    return None


def cmd_service(args, data: dict) -> None:
    s = find_service(data, args.name)
    if not s:
        print(json.dumps({"error": f"Service '{args.name}' nicht gefunden"}, ensure_ascii=False))
        sys.exit(1)
    coverage = next((r for r in data.get("test_coverage", []) if r["service_name"] == args.name), None)
    print(json.dumps({**s, "test_coverage": coverage}, indent=2, ensure_ascii=False))


def cmd_deps(args, data: dict) -> None:
    s = find_service(data, args.name)
    if not s:
        print(json.dumps({"error": f"Service '{args.name}' nicht gefunden"}, ensure_ascii=False))
        sys.exit(1)
    print(json.dumps({
        "service_name": args.name,
        "required": s["required_deps"],
        "optional": s["optional_deps"],
    }, indent=2, ensure_ascii=False))


def cmd_dependents(args, data: dict) -> None:
    out = []
    for s in data.get("services", []):
        if args.name in s["required_deps"]:
            out.append({"service_name": s["service_name"], "kind": "required"})
        elif args.name in s["optional_deps"]:
            out.append({"service_name": s["service_name"], "kind": "optional"})
    print(json.dumps({"depended_on_by": out, "count": len(out)}, indent=2, ensure_ascii=False))


def cmd_missing_tests(args, data: dict) -> None:
    missing = [r for r in data.get("test_coverage", []) if not r["covered"]]
    print(json.dumps({"missing": missing, "count": len(missing)}, indent=2, ensure_ascii=False))


def cmd_boot_order(args, data: dict) -> None:
    order = data.get("boot_order", {})
    if args.scope:
        print(json.dumps({args.scope: order.get(args.scope, [])}, indent=2, ensure_ascii=False))
    else:
        print(json.dumps(order, indent=2, ensure_ascii=False))


def cmd_errors(args, data: dict) -> None:
    print(json.dumps(data.get("findings", {}).get("errors", []), indent=2, ensure_ascii=False))


def main() -> None:
    p = argparse.ArgumentParser(description="Navigator für di-overview.json (siehe di_test_overview.py).")
    p.add_argument("--file", default="di-overview.json")
    sub = p.add_subparsers(dest="cmd", required=True)

    sp = sub.add_parser("service"); sp.add_argument("name"); sp.set_defaults(func=cmd_service)
    sp = sub.add_parser("deps"); sp.add_argument("name"); sp.set_defaults(func=cmd_deps)
    sp = sub.add_parser("dependents"); sp.add_argument("name"); sp.set_defaults(func=cmd_dependents)
    sp = sub.add_parser("missing-tests"); sp.set_defaults(func=cmd_missing_tests)
    sp = sub.add_parser("boot-order"); sp.add_argument("scope", nargs="?", choices=["global", "session"]); sp.set_defaults(func=cmd_boot_order)
    sp = sub.add_parser("errors"); sp.set_defaults(func=cmd_errors)

    args = p.parse_args()
    data = load(args.file)
    args.func(args, data)


if __name__ == "__main__":
    main()

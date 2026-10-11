#!/usr/bin/env python3
# scripts/agent/manager/log_metric.py
#
# Loggt eine abgeschlossene Sub-Agent-Aufgabe als JSON-Zeile in
# data/manager/metrics.jsonl (append-only, ein Objekt pro Zeile — bewusst
# keine DB, damit es ohne Tooling lesbar/diffbar bleibt).
#
# Verwendung:
#   python3 scripts/agent/manager/log_metric.py \
#     --agent code-builder --task "eventbus-direct migration" \
#     --duration 340 --success [--notes "optional"]

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[3]
_METRICS_PATH = _REPO_ROOT / "data" / "manager" / "metrics.jsonl"

_VALID_AGENTS = {"manager", "code-builder", "code-tester", "code-reviewer", "metrik-master"}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--agent", required=True, choices=sorted(_VALID_AGENTS))
    ap.add_argument("--task", required=True)
    ap.add_argument("--duration", type=float, required=True, help="Sekunden")
    outcome = ap.add_mutually_exclusive_group(required=True)
    outcome.add_argument("--success", action="store_true")
    outcome.add_argument("--fail", action="store_true")
    ap.add_argument("--notes", default="")
    args = ap.parse_args()

    entry = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "agent": args.agent,
        "task": args.task,
        "duration_seconds": args.duration,
        "success": bool(args.success),
        "notes": args.notes,
    }

    _METRICS_PATH.parent.mkdir(parents=True, exist_ok=True)
    with _METRICS_PATH.open("a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")

    print(f"Metrik geloggt: {args.agent} / {args.task} / "
          f"{'success' if args.success else 'fail'} ({args.duration:.0f}s)")


if __name__ == "__main__":
    sys.exit(main())

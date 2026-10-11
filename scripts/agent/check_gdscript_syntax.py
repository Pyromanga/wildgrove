#!/usr/bin/env python3
# scripts/agent/check_gdscript_syntax.py
#
# Read-only Sanity-Checker für .gd-Dateien — KEIN vollständiger Parser (wir
# haben keinen Godot-Binary in dieser Umgebung, siehe TODO-offene-probleme.md),
# sondern ein gezielter Satz heuristischer Regeln für Fehlerklassen, die ein
# reiner String-Diff (wie ihn BuildSession.apply_change() zeigt) NICHT sieht,
# weil der Diff pro Zeile "sauber" aussieht, das Ergebnis aber trotzdem nicht
# kompiliert.
#
# ENTSTANDEN AUS EINEM ECHTEN VORFALL (2026-09-14):
# fix_known_runtime_bugs.py --fix session_manager_reentry_guard hat zwei
# String-Literale wie in Python nebeneinandergeschrieben:
#     "teil eins "
#     "teil zwei"
#         % [...]
# GDScript konkateniert adjazente String-Literale NICHT automatisch (anders
# als Python) — das Ergebnis war ein Parse-Fehler in SessionManager.gd, der
# die GESAMTE Boot-Pipeline lahmgelegt hat (0 registrierte Services). Der
# Diff selbst sah unauffällig aus; nur ein tatsächlicher Godot-Start oder
# dieser Checker hätte es vor dem Ausliefern gefangen.
#
# Deshalb: JEDES Build-Modul soll (via common.py, automatisch bei --apply)
# seine geänderten Dateien hier durchlaufen lassen, BEVOR das fertige Ergebnis
# als "angewendet" gilt. Neue Vorfälle dieser Art -> neue Regel hier, nicht
# nur einmalig von Hand nachgezogen.
#
# Usage:
#   python3 scripts/agent/check_gdscript_syntax.py <file.gd> [<file.gd> ...]
#   (exit code 1 wenn mind. ein Fund, sonst 0 — für CI/Codemod-Gating geeignet)

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

_STRING_ONLY_LINE_RE = re.compile(r'^\s*"([^"\\]|\\.)*"\s*(\+\s*)?$')
_STRING_START_LINE_RE = re.compile(r'^\s*"([^"\\]|\\.)*"')
_OPERATOR_TAIL_RE = re.compile(r'[+,(\[{]\s*$')


@dataclass
class Issue:
    line_no: int
    rule: str
    detail: str


def _check_adjacent_string_literals(lines: list[str]) -> list[Issue]:
    """Erkennt zwei aufeinanderfolgende Zeilen, die je nur aus einem
    String-Literal bestehen, OHNE ein '+' am Ende der ersten Zeile — das
    einzige, was GDScript zum Verketten akzeptiert (kein Python-Style
    Adjazenz-Concat)."""
    issues: list[Issue] = []
    for i in range(len(lines) - 1):
        a, b = lines[i], lines[i + 1]
        a_stripped = a.rstrip()
        if not _STRING_START_LINE_RE.match(a.strip()):
            continue
        if not _STRING_ONLY_LINE_RE.match(a.strip()):
            continue  # Zeile hat noch mehr Inhalt nach dem String -> anderer Fall
        if a_stripped.endswith("+"):
            continue  # explizit korrekt verkettet
        if not _STRING_START_LINE_RE.match(b.strip()):
            continue
        issues.append(Issue(
            line_no=i + 1,
            rule="ADJACENT_STRING_LITERALS_WITHOUT_PLUS",
            detail=(
                "Zwei String-Literale direkt untereinander ohne '+' — GDScript "
                "konkateniert (anders als Python) NICHT automatisch. "
                f"Zeile {i+1}: {a.strip()[:60]!r} / Zeile {i+2}: {b.strip()[:60]!r}"
            ),
        ))
    return issues


def _strip_strings_and_comments(text: str) -> str:
    """Grobe Näherung: ersetzt Inhalte von '...'/"..." und #-Kommentaren durch
    Leerzeichen, damit Klammer-Zählung nicht durch Klammern IN Strings/
    Kommentaren verfälscht wird. Kein vollständiger Lexer (keine
    Multiline-Strings/""\"..\"\"\" o.ä.), aber ausreichend für die Bracket-
    Balance-Heuristik unten."""
    out = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c == "#":
            j = text.find("\n", i)
            if j == -1:
                j = n
            out.append(" " * (j - i))
            i = j
        elif c in ("'", '"'):
            quote = c
            j = i + 1
            while j < n and text[j] != quote:
                if text[j] == "\\":
                    j += 1
                j += 1
            j = min(j + 1, n)
            out.append(" " * (j - i))
            i = j
        else:
            out.append(c)
            i += 1
    return "".join(out)


def _check_bracket_balance(text: str) -> list[Issue]:
    cleaned = _strip_strings_and_comments(text)
    pairs = {")": "(", "]": "[", "}": "{"}
    stack: list[tuple[str, int]] = []
    line_no = 1
    issues: list[Issue] = []
    for ch in cleaned:
        if ch == "\n":
            line_no += 1
            continue
        if ch in "([{":
            stack.append((ch, line_no))
        elif ch in ")]}":
            if not stack or stack[-1][0] != pairs[ch]:
                issues.append(Issue(
                    line_no=line_no,
                    rule="UNBALANCED_BRACKETS",
                    detail=f"Unerwartetes '{ch}' in Zeile {line_no} (Stack: {stack[-3:]}).",
                ))
                return issues  # ein Fund reicht, weitere wären Folgefehler
            stack.pop()
    if stack:
        ch, ln = stack[-1]
        issues.append(Issue(
            line_no=ln,
            rule="UNBALANCED_BRACKETS",
            detail=f"'{ch}' aus Zeile {ln} wurde nie geschlossen.",
        ))
    return issues


def check_file(path: Path) -> list[Issue]:
    text = path.read_text(encoding="utf-8")
    lines = text.split("\n")
    issues = []
    issues += _check_adjacent_string_literals(lines)
    issues += _check_bracket_balance(text)
    return issues


def main(argv: list[str]) -> int:
    if not argv:
        print("Usage: check_gdscript_syntax.py <file.gd> [<file.gd> ...]", file=sys.stderr)
        return 2
    any_issue = False
    for arg in argv:
        path = Path(arg)
        if not path.exists():
            print(f"FEHLER: Datei nicht gefunden: {path}", file=sys.stderr)
            any_issue = True
            continue
        issues = check_file(path)
        if issues:
            any_issue = True
            print(f"\n{path}:")
            for iss in issues:
                print(f"  Zeile {iss.line_no} [{iss.rule}]: {iss.detail}")
        else:
            print(f"{path}: OK")
    return 1 if any_issue else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

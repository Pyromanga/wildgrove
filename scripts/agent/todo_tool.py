#!/usr/bin/env python3
# scripts/agent/todo_tool.py
#
# DEBUG-COMMAND für Agents — strukturierte Bearbeitung von
# TODO-offene-probleme.md statt Ad-hoc-Markdown-Parsing per Hand.
#
# Zweck:
#   Die TODO-Datei hat eine feste, aber nirgends kodifizierte Struktur:
#   "## "-Überschriften gliedern in Abschnitte, "- [ ] "-Zeilen starten
#   Items, Folgezeilen sind mit 6 Leerzeichen eingerückt (Fließtext,
#   width ~80 inkl. Einrückung). Manuelles Editieren (Nummern hochzählen,
#   Einrückung treffen, Item-Grenzen finden) ist genau die Fehlerklasse,
#   die zu den 52 verwaisten [x]-Blöcken in Round 109 geführt hat.
#
#   Dieses Tool kennt die Struktur, das manuelle Editieren nicht mehr.
#
# Befehle:
#   list                                   Alle Items mit ID + Abschnitt + Vorschau
#   show <id>                              Volltext eines Items
#   add --after <id> --text "..."          Neues Item nach <id> einfügen
#   add --section "<text>" --text "..."    Neues Item ans Ende eines Abschnitts
#   remove <id>                            Item löschen
#   edit <id> --text "..."                 Item-Body komplett ersetzen (neu gewrappt)
#   renumber --section "<text>"            "**N. "-Nummerierung in einem Abschnitt neu vergeben
#
# IDs sind NICHT persistent — sie sind die 1-basierte Position im aktuellen
# Dateizustand. Immer erst `list`, dann sofort mit der angezeigten ID
# arbeiten (nicht über mehrere Aufrufe hinweg cachen).
#
# Schreibt niemals ohne Backup: <file>.bak wird vor jeder Änderung angelegt
# (überschrieben, kein Verlauf — Konvention aus scripts/platform/*.gd.bak).

from __future__ import annotations

import argparse
import re
import shutil
import sys
import textwrap
from dataclasses import dataclass, field
from pathlib import Path

DEFAULT_FILE = "TODO-offene-probleme.md"
WRAP_WIDTH = 80
CONT_INDENT = "      "  # 6 Spaces, deckt sich mit "- [ ] " Länge
ITEM_PREFIX = "- [ ] "
HEADING_RE = re.compile(r"^#{1,6}\s")
ITEM_RE = re.compile(r"^- \[ \] ")
NUMBER_RE = re.compile(r"^\*\*(\d+)\.\s")


@dataclass
class Item:
    id: int
    section: str
    start: int  # Zeilenindex (0-basiert) in lines, inklusiv
    end: int  # Zeilenindex, exklusiv
    lines: list[str] = field(default_factory=list)

    def preview(self, max_len: int = 68) -> str:
        first = self.lines[0][len(ITEM_PREFIX):].strip()
        first = re.sub(r"\*\*", "", first)
        return (first[:max_len] + "…") if len(first) > max_len else first

    def body_text(self) -> str:
        """Body ohne '- [ ] '-Prefix und ohne Zeilenumbrüche, für Re-Wrap."""
        raw = " ".join(
            line[len(ITEM_PREFIX):] if i == 0 else line.strip()
            for i, line in enumerate(self.lines)
        )
        return re.sub(r"\s+", " ", raw).strip()


def load_lines(path: Path) -> list[str]:
    return path.read_text(encoding="utf-8").split("\n")


def parse_items(lines: list[str]) -> list[Item]:
    items: list[Item] = []
    current_section = "(vor erster Überschrift)"
    i = 0
    n = len(lines)
    item_id = 0
    while i < n:
        line = lines[i]
        if HEADING_RE.match(line):
            current_section = line.lstrip("#").strip()
            i += 1
            continue
        if ITEM_RE.match(line):
            start = i
            i += 1
            while i < n and not ITEM_RE.match(lines[i]) and not HEADING_RE.match(lines[i]) and lines[i].strip() != "":
                i += 1
            item_id += 1
            items.append(Item(id=item_id, section=current_section, start=start, end=i, lines=lines[start:i]))
            continue
        i += 1
    return items


def wrap_body(body_text: str) -> list[str]:
    wrapped = textwrap.wrap(
        body_text,
        width=WRAP_WIDTH,
        initial_indent=ITEM_PREFIX,
        subsequent_indent=CONT_INDENT,
        break_long_words=False,
        break_on_hyphens=False,
    )
    return wrapped if wrapped else [ITEM_PREFIX.rstrip()]


def backup(path: Path) -> None:
    shutil.copyfile(path, path.with_suffix(path.suffix + ".bak"))


def write_lines(path: Path, lines: list[str]) -> None:
    backup(path)
    path.write_text("\n".join(lines), encoding="utf-8")


# ─────────────────────────────────────────────
# Commands
# ─────────────────────────────────────────────

def cmd_list(args, lines: list[str]) -> None:
    items = parse_items(lines)
    last_section = None
    for it in items:
        if it.section != last_section:
            print(f"\n## {it.section}")
            last_section = it.section
        print(f"  [{it.id:>2}] {it.preview()}")


def cmd_show(args, lines: list[str]) -> None:
    items = parse_items(lines)
    it = _find(items, args.id)
    print(f"# Abschnitt: {it.section}")
    print(f"# Zeilen {it.start + 1}-{it.end} (Datei ist 1-indiziert)\n")
    print("\n".join(it.lines))


def cmd_remove(args, lines: list[str], path: Path) -> None:
    items = parse_items(lines)
    it = _find(items, args.id)
    new_lines = lines[: it.start] + lines[it.end :]
    # Doppelte Leerzeile vermeiden, falls Item direkt vor einer Überschrift stand
    write_lines(path, new_lines)
    print(f"Entfernt: [{it.id}] {it.preview()}")
    print(f"Backup: {path}.bak")


def cmd_edit(args, lines: list[str], path: Path) -> None:
    items = parse_items(lines)
    it = _find(items, args.id)
    new_block = wrap_body(args.text.strip())
    new_lines = lines[: it.start] + new_block + lines[it.end :]
    write_lines(path, new_lines)
    print(f"Bearbeitet: [{it.id}]")
    print("\n".join(new_block))
    print(f"Backup: {path}.bak")


def cmd_add(args, lines: list[str], path: Path) -> None:
    items = parse_items(lines)
    new_block = wrap_body(args.text.strip())

    if args.after is not None:
        it = _find(items, args.after)
        insert_at = it.end
    elif args.section is not None:
        matches = [i for i in items if args.section.lower() in i.section.lower()]
        if not matches:
            sys.exit(f"Kein Abschnitt gefunden, der '{args.section}' enthält.")
        insert_at = matches[-1].end
    else:
        sys.exit("add braucht --after <id> oder --section \"<text>\"")

    new_lines = lines[:insert_at] + new_block + lines[insert_at:]
    write_lines(path, new_lines)
    print("Eingefügt:")
    print("\n".join(new_block))
    print(f"Backup: {path}.bak")
    print("Hinweis: falls das Item eine '**N.'-Nummer trägt, jetzt `renumber --section \"...\"` laufen lassen.")


def cmd_renumber(args, lines: list[str], path: Path) -> None:
    items = parse_items(lines)
    matches = [i for i in items if args.section.lower() in i.section.lower()]
    if not matches:
        sys.exit(f"Kein Abschnitt gefunden, der '{args.section}' enthält.")

    numbered = [i for i in matches if NUMBER_RE.match(i.lines[0][len(ITEM_PREFIX):])]
    if not numbered:
        sys.exit("Keine nummerierten Items ('**N. ...') in diesem Abschnitt gefunden.")

    new_lines = list(lines)
    # Von hinten nach vorne ersetzen, damit Zeilenindizes der anderen Items stabil bleiben
    for new_num, it in enumerate(numbered, start=1):
        old_first = new_lines[it.start]
        rest_after_prefix = old_first[len(ITEM_PREFIX):]
        replaced = NUMBER_RE.sub(f"**{new_num}. ", rest_after_prefix, count=1)
        new_lines[it.start] = ITEM_PREFIX + replaced

    write_lines(path, new_lines)
    print(f"Renummeriert: {len(numbered)} Items in Abschnitt '{matches[0].section}' → 1..{len(numbered)}")
    print(f"Backup: {path}.bak")


def _find(items: list[Item], item_id: int) -> Item:
    for it in items:
        if it.id == item_id:
            return it
    sys.exit(f"Keine Item-ID {item_id}. `list` zeigt aktuell gültige IDs.")


# ─────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────

def main() -> None:
    p = argparse.ArgumentParser(description="Strukturierte Bearbeitung von TODO-offene-probleme.md")
    p.add_argument("--file", default=DEFAULT_FILE, help=f"Pfad zur TODO-Datei (default: {DEFAULT_FILE})")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list", help="Alle Items mit ID + Abschnitt + Vorschau")

    sp = sub.add_parser("show", help="Volltext eines Items")
    sp.add_argument("id", type=int)

    sp = sub.add_parser("remove", help="Item löschen")
    sp.add_argument("id", type=int)

    sp = sub.add_parser("edit", help="Item-Body ersetzen (wird neu gewrappt)")
    sp.add_argument("id", type=int)
    sp.add_argument("--text", required=True, help="Neuer Volltext, z.B. '**3. Titel.** Beschreibung...'")

    sp = sub.add_parser("add", help="Neues Item einfügen")
    grp = sp.add_mutually_exclusive_group(required=True)
    grp.add_argument("--after", type=int, help="Item-ID, nach der eingefügt wird")
    grp.add_argument("--section", help="Abschnitts-Substring; Einfügen ans Ende des Abschnitts")
    sp.add_argument("--text", required=True, help="Volltext des neuen Items")

    sp = sub.add_parser("renumber", help="'**N. '-Nummerierung in einem Abschnitt neu vergeben")
    sp.add_argument("--section", required=True, help="Abschnitts-Substring")

    args = p.parse_args()
    path = Path(args.file)
    if not path.exists():
        sys.exit(f"Datei nicht gefunden: {path}")
    lines = load_lines(path)

    if args.cmd == "list":
        cmd_list(args, lines)
    elif args.cmd == "show":
        cmd_show(args, lines)
    elif args.cmd == "remove":
        cmd_remove(args, lines, path)
    elif args.cmd == "edit":
        cmd_edit(args, lines, path)
    elif args.cmd == "add":
        cmd_add(args, lines, path)
    elif args.cmd == "renumber":
        cmd_renumber(args, lines, path)


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        # z.B. wenn `list | head` die Pipe früh schließt — kein echter Fehler.
        sys.stderr.close()

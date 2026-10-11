#!/usr/bin/env python3
# scripts/agent/build/quest_npc_scaffold.py
#
# WERKZEUG für Agents — erzeugt einen KOMPLETTEN Quest-Geber-NPC (eine oder
# zwei Quest-.tres-Dateien + die zugehörige NPC-.gd-Datei im ADR-051-Stufe-3-
# Dialogbaum-Format) aus EINER kompakten JSON-Spezifikation, statt beides von
# Hand nacheinander zu bauen (vorher: content_forge.py für die Quest(s), dann
# manuell eine .gd-Datei mit DialogueTreeController.build_quest_giver()
# schreiben — siehe Git-Historie von MinerNPC.gd/HerbalistNPC.gd/etc. für das
# Muster, das dieses Tool automatisiert).
#
# WARUM EIN EIGENES TOOL STATT CONTENT_FORGE.PY ZU ERWEITERN:
#   content_forge.py erzeugt genau EINEN Resource-Typ pro Spec-Eintrag
#   (Item ODER Quest ODER ...) nach einem generischen @export-Feld-Schema.
#   Eine NPC-.gd-Datei ist aber KEINE Daten-Resource, sondern Code mit einer
#   festen, sich wiederholenden STRUKTUR (siehe alle 6 konvertierten
#   NPC-Klassen: _init() + _build_dialogue_tree() + optional
#   _get_body_color()) — das passt nicht ins content_forge-Feld-Schema-Modell,
#   verdient aber dieselbe Determinismus-Garantie ("zwei identische Specs
#   erzeugen byte-identischen Output", siehe content_forge.py-Kommentar).
#   Dieses Tool importiert content_forge als Modul und ruft dessen
#   run_create() für den Quest-Teil direkt auf — keine Logik doppelt gepflegt.
#
# WAS DIESES TOOL BEWUSST NICHT AUTOMATISIERT:
#   Die Registrierung in WorldEntityRegistry.gd (orchestrator.register_definition)
#   und den Spawn-Aufruf in WorldSpawner.gd. Beide Dateien haben keinen
#   stabilen, projektweit gültigen Textanker (siehe die wiederholt
#   unterschiedlichen Einfügestellen in der Git-Historie dieser beiden
#   Dateien durch parallele Terrain-/Pet-/Smithing-Arbeit) — ein Tool, das
#   dort blind nach der "letzten register_definition-Zeile" sucht, würde
#   irgendwann an der FALSCHEN Stelle einfügen und das stillschweigend falsch
#   machen, statt ehrlich zu sagen "unsicher". Siehe common.py Regel 4: "Kein
#   Modul darf raten." Stattdessen druckt dieses Tool die exakt einzufügenden
#   zwei Zeilen am Ende aus (siehe _print_manual_wiring_steps()) — ein
#   bewusster, sichtbarer letzter Handarbeits-Schritt statt eines unsichtbar
#   falschen automatischen.
#
# Sicherheitsregeln (identisch zu content_forge.py/common.py):
#   1. Default = --dry-run: zeigt was geschrieben würde (inkl. voller
#      .gd-Dateitext + Quest-Diffs), schreibt nichts.
#   2. --apply schreibt die .gd-Datei über BuildSession (also mit .bak) UND
#      die Quest(s) über content_forge.run_create(apply=True).
#   3. Lehnt eine Spec ab, die auf eine bereits existierende .gd-Datei oder
#      Quest-ID zeigt, ohne --force (identisches Verhalten zu content_forge.py).

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402
import content_forge  # noqa: E402

REPO_ROOT = content_forge.REPO_ROOT
NPC_DIR = REPO_ROOT / "scripts" / "progression" / "quests"

# Feld-Namen in einer "stage"-Spec, die NICHT an content_forge.py
# durchgereicht werden — reine Dialog-Texte fürs generierte .gd.
_DIALOG_ONLY_KEYS = {"tracked_obj_id", "tracked_required", "offer_text", "encourage_format", "completed_text"}


def _fail(msg: str) -> None:
    print(f"FEHLER: {msg}", file=sys.stderr)
    sys.exit(2)


def _gd_string(s: str) -> str:
    """Ein GDScript-String-LITERAL (eine physische Zeile im generierten Code)
    aus einem Python-String. GDScript erlaubt in normalen "..."-Strings
    KEINEN rohen Zeilenumbruch (Parse-Fehler) — ein echtes Newline-Zeichen
    (aus dem JSON-"\\n" der Spec) muss deshalb als zwei Zeichen \\n
    zurück-escaped werden, exakt wie bei allen 6 von Hand geschriebenen
    NPCs ("Zeile1\\nZeile2" auf einer Codezeile, nicht echt mehrzeilig)."""
    escaped = s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    return f'"{escaped}"'


def _quest_fields_from_stage(stage: dict, prerequisites: list[str]) -> dict:
    fields = {k: v for k, v in stage.items() if k not in _DIALOG_ONLY_KEYS}
    fields.setdefault("category", "side")
    fields.setdefault("reward_xp", {})
    fields.setdefault("reward_items", {})
    fields.setdefault("prerequisites", prerequisites)
    fields.setdefault("auto_start", False)
    fields.setdefault("repeatable", False)
    return fields


def _build_quest_batch(spec: dict) -> list[dict]:
    batch = []
    stage1 = spec["stage1"]
    batch.append({"type": "quest", "fields": _quest_fields_from_stage(stage1, [])})
    stage2 = spec.get("stage2")
    if stage2 is not None:
        batch.append({
            "type": "quest",
            "fields": _quest_fields_from_stage(stage2, [stage1["id"]]),
        })
    return batch


def _render_npc_gd(spec: dict) -> str:
    npc_class = spec["npc_class_name"]
    npc_id = spec["npc_id"]
    npc_display_name = spec["npc_display_name"]
    body_color = spec.get("body_color")
    culture_note = spec.get("culture_note", "").strip()
    stage1 = spec["stage1"]
    stage2 = spec.get("stage2")

    header_note = f"\n## {culture_note}\n" if culture_note else "\n"

    args = [
        _gd_string(stage1["id"]), _gd_string(stage1["tracked_obj_id"]), str(stage1["tracked_required"]),
        _gd_string(stage1["offer_text"]), _gd_string(stage1["encourage_format"]), _gd_string(stage1["completed_text"]),
    ]
    if stage2 is not None:
        args += [
            _gd_string(stage2["id"]), _gd_string(stage2["tracked_obj_id"]), str(stage2["tracked_required"]),
            _gd_string(stage2["offer_text"]), _gd_string(stage2["encourage_format"]), _gd_string(stage2["completed_text"]),
        ]
    args_block = ",\n\t\t".join(args)

    body_color_method = ""
    if body_color is not None:
        r, g, b = body_color
        body_color_method = (
            "\nfunc _get_body_color() -> Color:\n"
            f"\treturn Color({r}, {g}, {b})\n"
        )

    return f'''extends QuestNPC
class_name {npc_class}

## {npc_class} — "{npc_display_name}". Generiert von
## scripts/agent/build/quest_npc_scaffold.py (ADR-051 Stufe 3 —
## DialogueTreeController.build_quest_giver(), siehe dortiger
## Klassenkommentar für die generelle Begründung dieses Musters).
{header_note}
func _init() -> void:
\tquest_id         = ""  # kein Slot-System — dieser NPC nutzt ausschließlich den Dialogbaum.
\tnpc_display_name = "{npc_display_name}"
\tnpc_id            = "{npc_id}"

func _build_dialogue_tree(
\ttree_label: Label3D, tree: SceneTree, tree_bus: IEventBus, quest_service: QuestService
) -> DialogueTreeController:
\treturn DialogueTreeController.build_quest_giver(
\t\ttree_label, tree, tree_bus, quest_service,
\t\t{args_block}
\t)
{body_color_method}'''


def _print_manual_wiring_steps(spec: dict) -> None:
    npc_id = spec["npc_id"]
    npc_class = spec["npc_class_name"]
    entity_type = spec.get("entity_type_id", npc_id)
    print("\n" + "=" * 70)
    print("MANUELLER LETZTER SCHRITT (siehe Modulkommentar: kein stabiler Textanker)")
    print("=" * 70)
    print("In scripts/world/core/WorldEntityRegistry.gd ergänzen:")
    print(f'  orchestrator.register_definition("{entity_type}", "res://scripts/progression/quests/{npc_class}.gd", "npcs")')
    spawn = spec.get("spawn")
    if spawn:
        print("\nIn scripts/world/core/WorldSpawner.gd ergänzen (Höhe + Spawn-Aufruf):")
        print(f'  var {npc_id}_h: float = 0.0')
        print(f'  if is_instance_valid(_terrain):')
        print(f'      {npc_id}_h = _terrain.get_height_at({spawn["x"]}, {spawn["z"]})')
        print(f'  _entity_orchestrator.spawn_entity("{entity_type}", Vector3({spawn["x"]}, {npc_id}_h, {spawn["z"]}))')
    else:
        print("\nKein \"spawn\" in der Spec angegeben — WorldSpawner.gd-Eintrag selbst ergänzen.")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--spec", required=True, help="Pfad zur JSON-Spec-Datei")
    ap.add_argument("--apply", action="store_true", help="Tatsächlich schreiben (Default: Dry-Run)")
    ap.add_argument("--force", action="store_true", help="Existierende Dateien/IDs überschreiben")
    args = ap.parse_args()

    spec_path = Path(args.spec)
    if not spec_path.exists():
        _fail(f"Spec-Datei nicht gefunden: {spec_path}")
    spec = json.loads(spec_path.read_text(encoding="utf-8"))

    for required_key in ("npc_id", "npc_class_name", "npc_display_name", "stage1"):
        if required_key not in spec:
            _fail(f"Spec fehlt Pflichtfeld '{required_key}'.")
    for stage_key in ("id", "tracked_obj_id", "tracked_required", "offer_text", "encourage_format", "completed_text"):
        if stage_key not in spec["stage1"]:
            _fail(f"stage1 fehlt Pflichtfeld '{stage_key}'.")
    if "stage2" in spec:
        for stage_key in ("id", "tracked_obj_id", "tracked_required", "offer_text", "encourage_format", "completed_text"):
            if stage_key not in spec["stage2"]:
                _fail(f"stage2 fehlt Pflichtfeld '{stage_key}'.")

    gd_path = NPC_DIR / f"{spec['npc_class_name']}.gd"
    if gd_path.exists() and not args.force:
        _fail(f"{gd_path} existiert bereits — mit --force überschreiben.")

    # 1) Quest(s) — über dieselbe Schema-Validierung wie content_forge.py,
    #    kein eigener Validierungscode hier (siehe Moduldoc oben).
    batch = _build_quest_batch(spec)
    quest_result = content_forge.run_create(batch, apply=args.apply, force=args.force)
    if not quest_result["ok"]:
        print(json.dumps({"ok": False, "stage": "quest", "errors": quest_result["errors"]}, indent=2, ensure_ascii=False))
        sys.exit(1)

    # 2) NPC-.gd-Datei — über dieselbe BuildSession wie andere build/-Module
    #    (Backup/Dry-Run/Syntax-Check einheitlich, siehe common.py).
    session = common.BuildSession(apply=args.apply)
    new_text = _render_npc_gd(spec)
    original = gd_path.read_text(encoding="utf-8") if gd_path.exists() else ""
    session.apply_change(gd_path, original, new_text, count=1)

    print(json.dumps({
        "ok": True,
        "apply": args.apply,
        "quest_written": quest_result["written"],
        "npc_gd_path": str(gd_path.relative_to(REPO_ROOT)),
    }, indent=2, ensure_ascii=False))

    if not args.apply:
        print("\n--- Quest-Diffs (Dry-Run) ---")
        for d in (quest_result.get("diffs") or []):
            print(d)
        print("\n--- Generierte NPC-Datei (Dry-Run, nicht geschrieben) ---")
        print(new_text)
    else:
        session.summary()

    _print_manual_wiring_steps(spec)


if __name__ == "__main__":
    main()

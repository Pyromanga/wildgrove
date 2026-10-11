#!/usr/bin/env python3
# scripts/agent/build/content_forge.py
#
# WERKZEUG für Agents — deterministische ERZEUGUNG von Content-Resourcen
# (.tres), nicht nur deren Analyse. Gegenstück zu service_graph.py /
# method_reference_coverage.py (die lesen und finden) und zu den übrigen
# build/-Modulen (die bestehenden .gd-Code umschreiben): content_forge.py
# schreibt NEUE Daten-Resourcen (Items, Waffen, Werkzeuge, Loot-Tabellen,
# Quests, Skills, Achievements, Kampf-Profile) aus einer JSON-Spezifikation
# und registriert sie in DataManifest.gd — die beiden Schritte, die bisher
# von Hand gemacht wurden (Godot-.tres-Syntax nachbauen, richtige
# ext_resource/sub_resource-IDs vergeben, DataManifest.gd nicht vergessen).
#
# WARUM DETERMINISTISCH STATT "TEXT GENERIEREN LASSEN":
#   Ein Agent, der freihändig .tres-Text schreibt, kann silently vom
#   Resource-Schema abweichen (Feld fehlt, falscher Typ, Vector3-Syntax
#   falsch, doppelte id) — Godot lädt das im schlimmsten Fall stillschweigend
#   mit Default-Werten statt zu crashen (siehe AGENT.md "Trust the code, not
#   the docs" — dasselbe Prinzip gilt für generierten Code: ohne Schema-
#   Validierung wird ungeprüfte Behauptung zu ungeprüfter Datei). Dieses Tool
#   kennt die Resource-Schemas (SCHEMAS unten, 1:1 aus den @export-Feldern
#   der jeweiligen *.gd-Klasse übernommen) und lehnt ungültige Specs vor dem
#   Schreiben ab, statt zu raten. Zwei identische Specs erzeugen byte-
#   identischen Output (stabile Key-Reihenfolge, keine Zeitstempel/UUIDs) —
#   das ist die Voraussetzung für Diffs, die tatsächlich etwas aussagen.
#
# Sicherheitsregeln (analog build/common.py):
#   1. Default = --dry-run: zeigt was geschrieben würde, schreibt nichts.
#   2. --apply schreibt die .tres-Datei(en) UND hängt den Pfad an das
#      passende DataManifest.gd-Array an (über BuildSession, also mit .bak).
#   3. id-Kollisionen (gegen vorhandene .tres-Dateien UND gegen das Manifest)
#      sind ein harter Fehler, kein Overwrite — außer --force.
#   4. Cross-Referenzen (item_id in Loot-Einträgen/Quest-Rewards,
#      prerequisite-/unlock-Quest-IDs) werden gegen den tatsächlichen
#      Repo-Zustand UND gegen den Rest derselben Spec-Batch geprüft, damit
#      "Item + Loot-Table die darauf verweist" in einem Lauf erzeugt werden
#      kann, ohne dass die Referenz als "unbekannt" abgelehnt wird.
#
# Befehle:
#   schema <type>                 Feldliste + Typen + Defaults für einen
#                                  Content-Typ (JSON) — was ein Agent braucht
#                                  um eine gültige Spec zu bauen, ohne die
#                                  .gd-Datei selbst lesen zu müssen.
#   list <type>                   Vorhandene IDs eines Typs (aus .tres UND
#                                  Manifest — deckt Karteileichen auf beiden
#                                  Seiten auf).
#   validate --spec <file.json>   Prüft eine Spec-Batch, schreibt nichts.
#   create --spec <file.json> [--apply] [--force]
#                                  Validiert + erzeugt. Ohne --apply: Dry-Run
#                                  (zeigt den .tres-Text + Manifest-Diff).
#
# Spec-Format (JSON, Liste von Objekten — eine Batch = ein atomarer Lauf):
#   [
#     {"type": "item", "fields": {"id": "iron_key", "display_name": "Eiserner Schlüssel"}},
#     {"type": "loot_table", "filename": "loot_goblin_boss",
#      "fields": {"entries": [{"item_id": "iron_key", "weight": 5}], "gold_min": 10, "gold_max": 20}}
#   ]
#
# Content-Typen: item, weapon, tool, armor, loot_table, quest, skill, achievement,
# combat_profile, smithing_recipe. Siehe `schema <type>` für Felder je Typ.

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import BuildSession, fail  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[3]
DATA_MANIFEST_GD = REPO_ROOT / "scripts" / "persistence" / "DataManifest.gd"


# ---------------------------------------------------------------------------
# Schema-Definition — 1:1 aus den @export-Feldern der jeweiligen *.gd-Klasse.
# Quelle je Typ steht in `script`. Bei Änderung an der .gd-Klasse muss dieser
# Block nachgezogen werden — es gibt keinen automatischen Sync (GDScript hat
# keine Introspection, die von außen ohne laufende Godot-Instanz erreichbar
# wäre; das wäre der nächste Ausbauschritt, siehe "Bekannte Grenzen" unten).
# ---------------------------------------------------------------------------


@dataclass
class Field:
    name: str
    kind: str  # str | int | float | bool | vector3 | array_str | array_int | dict | enum | array_obj
    default: Any = None
    required: bool = False
    enum: dict | None = None       # name -> int, für kind == "enum"
    obj_fields: list["Field"] | None = None  # für kind == "array_obj"
    doc: str = ""


@dataclass
class ContentType:
    key: str
    class_name: str
    script: str
    base_fields: list[Field]              # top-level [resource]-Felder
    id_field: str | None                  # Feldname der als eindeutige ID gilt, None = kein id-Feld (z.B. loot_table)
    dir_path: str                         # relativ zu data/
    manifest_const: str | None            # Name des DataManifest.gd-Arrays, None = nicht registriert
    filename_from: str                    # "id" | "explicit" — wie der Dateiname bestimmt wird
    sub_resources: list[tuple[str, str, str]] | None = None  # (field_name, class_name, script) für array_obj-Felder mit eigener Resource-Klasse
    extra_ext_resources: list[tuple[str, str]] | None = None  # weitere (class_name, script) fest verdrahtete ext_resources (z.B. QuestReward)


LOOT_ENTRY_FIELDS = [
    Field("item_id", "str", required=True, doc="Muss einer existierenden ItemDefinition.id entsprechen"),
    Field("weight", "float", default=100.0),
    Field("quantity_min", "int", default=1),
    Field("quantity_max", "int", default=1),
]

QUEST_OBJECTIVE_TYPE_ENUM = {"COLLECT": 0, "SKILL": 1, "INTERACT": 2, "KILL": 3, "TALK": 4, "CUSTOM": 5}

QUEST_OBJECTIVE_FIELDS = [
    Field("id", "str", required=True),
    Field("label", "str", required=True),
    Field("type", "enum", default="COLLECT", enum=QUEST_OBJECTIVE_TYPE_ENUM),
    Field("target_id", "str", required=True, doc="item_id / skill_name / interactable_id / enemy_id / npc_id / custom_key"),
    Field("required", "int", default=1),
    Field("optional", "bool", default=False),
]

WEAPON_TYPE_ENUM = {"DAGGER": 0, "SWORD": 1, "AXE": 2, "STAFF": 3}

# 1:1 aus ToolDefinition.ToolType — die Werte sind in .tres als Zahl gespeichert (Pickaxe.tres:
# tool_type = 1), neue Typen deshalb immer ans Ende (siehe ToolDefinition.gd).
TOOL_TYPE_ENUM = {"AXE": 0, "PICKAXE": 1, "SHOVEL": 2, "TONGS": 3, "HAMMER": 4}

# 1:1 aus ArmorDefinition.ArmorSlot.
ARMOR_SLOT_ENUM = {"HELMET": 0, "CHEST": 1, "LEGS": 2, "BOOTS": 3}

# 1:1 aus SmithingRecipe.STATIONS.
SMITHING_STATIONS = ("furnace", "anvil")

# Content-Typen, deren `id` eine Item-ID ist (für Cross-Referenz-Prüfungen und PascalCase-Dateinamen).
ITEM_TYPES = ("item", "weapon", "tool", "armor")

SCHEMAS: dict[str, ContentType] = {
    "item": ContentType(
        key="item", class_name="ItemDefinition",
        script="res://scripts/economy/inventory/ItemDefinition.gd",
        base_fields=[
            Field("id", "str", required=True),
            Field("display_name", "str", required=True),
            Field("max_stack", "int", default=999),
            Field("sell_price", "int", default=0),
            Field("xp_bonus", "dict", default={},
                  doc='Ausrüstungs-Bonus auf Aktions-XP: skill_id|"all" -> Faktor (0.10 = +10 %), siehe SkillSystem.add_action_xp()'),
            Field("grants_protection_type", "str", default="",
                  doc='ADR-038: "" | "pve" | "theft" | "pvp"'),
            Field("pickpocket_crystal_tier", "str", default="",
                  doc='ADR-039: "" | "weak" | "normal" | "strong"'),
        ],
        id_field="id", dir_path="items", manifest_const="ITEMS", filename_from="id",
    ),
    "weapon": ContentType(
        key="weapon", class_name="WeaponDefinition",
        script="res://scripts/entities/combat/WeaponDefinition.gd",
        base_fields=[
            Field("id", "str", required=True),
            Field("display_name", "str", required=True),
            Field("max_stack", "int", default=1),
            Field("sell_price", "int", default=0),
            Field("damage_bonus", "float", default=0.0),
            Field("damage_type", "int", default=0, doc="DamageRecord.DamageType — 0=PHYSICAL, 1=MAGIC, 2=TRUE"),
            Field("on_hit_effect", "int", default=-1, doc="StatusEffect.Kind, -1 = kein Effekt"),
            Field("on_hit_ticks", "int", default=4),
            Field("on_hit_damage_per_tick", "float", default=3.0),
            Field("on_hit_tick_interval", "float", default=1.0),
            Field("weapon_type", "enum", default="SWORD", enum=WEAPON_TYPE_ENUM),
            Field("visual_offset", "vector3", default=(0.0, -0.15, 0.2)),
            Field("visual_rotation", "vector3", default=(0.0, 0.0, 0.0)),
            Field("xp_bonus", "dict", default={},
                  doc='Ausrüstungs-Bonus auf Aktions-XP: skill_id|"all" -> Faktor (0.10 = +10 %), siehe SkillSystem.add_action_xp()'),
            Field("grants_protection_type", "str", default="",
                  doc='geerbt von ItemDefinition, ADR-038: "" | "pve" | "theft" | "pvp"'),
            Field("pickpocket_crystal_tier", "str", default="",
                  doc='geerbt von ItemDefinition, ADR-039: "" | "weak" | "normal" | "strong"'),
        ],
        id_field="id", dir_path="items/weapons", manifest_const="ITEMS", filename_from="id",
    ),
    "tool": ContentType(
        key="tool", class_name="ToolDefinition",
        script="res://scripts/economy/equipment/ToolDefinition.gd",
        base_fields=[
            Field("id", "str", required=True),
            Field("display_name", "str", required=True),
            Field("max_stack", "int", default=1),
            Field("sell_price", "int", default=0),
            Field("speed_stat_id", "str", default="",
                  doc='z.B. "gathering_speed_wood", "gathering_speed_ore" — muss zur HarvestableEntity-Subklasse passen. '
                      'Leer = reines Handwerkszeug ohne Gathering-Bonus (Zange/Hammer; dann speed_bonus 0.0 setzen)'),
            Field("speed_bonus", "float", default=0.5),
            Field("buy_price", "int", default=0),
            Field("tool_type", "enum", default="AXE", enum=TOOL_TYPE_ENUM,
                  doc="steuert Mesh-Form/-Farbe in WeaponVisual3D; ohne Angabe AXE (bisheriges Verhalten)"),
            Field("xp_bonus", "dict", default={},
                  doc='Ausrüstungs-Bonus auf Aktions-XP: skill_id|"all" -> Faktor (0.10 = +10 %), siehe SkillSystem.add_action_xp()'),
            Field("grants_protection_type", "str", default="",
                  doc='geerbt von ItemDefinition, ADR-038: "" | "pve" | "theft" | "pvp"'),
            Field("pickpocket_crystal_tier", "str", default="",
                  doc='geerbt von ItemDefinition, ADR-039: "" | "weak" | "normal" | "strong"'),
        ],
        id_field="id", dir_path="items/tools", manifest_const="ITEMS", filename_from="id",
    ),
    "armor": ContentType(
        key="armor", class_name="ArmorDefinition",
        script="res://scripts/economy/equipment/ArmorDefinition.gd",
        base_fields=[
            Field("id", "str", required=True),
            Field("display_name", "str", required=True),
            Field("max_stack", "int", default=1),
            Field("sell_price", "int", default=0),
            Field("armor_slot", "enum", default="CHEST", enum=ARMOR_SLOT_ENUM,
                  doc="in welchen Equipment-Slot das Teil gehört (helmet/chest/legs/boots)"),
            Field("armor_value", "float", default=0.0,
                  doc="physische Schadensminderung 0.0-1.0, additiv über alle Slots (CombatSystem clamped gesamt auf 0.85)"),
            Field("xp_bonus", "dict", default={},
                  doc='Ausrüstungs-Bonus auf Aktions-XP: skill_id|"all" -> Faktor (0.10 = +10 %), siehe SkillSystem.add_action_xp()'),
            Field("grants_protection_type", "str", default="",
                  doc='geerbt von ItemDefinition, ADR-038: "" | "pve" | "theft" | "pvp"'),
            Field("pickpocket_crystal_tier", "str", default="",
                  doc='geerbt von ItemDefinition, ADR-039: "" | "weak" | "normal" | "strong"'),
        ],
        id_field="id", dir_path="items/armor", manifest_const="ITEMS", filename_from="id",
    ),
    "loot_table": ContentType(
        key="loot_table", class_name="LootTable",
        script="res://scripts/economy/rewards/LootTable.gd",
        base_fields=[
            Field("max_rolls", "int", default=3),
            Field("entries", "array_obj", default=[], obj_fields=LOOT_ENTRY_FIELDS),
            Field("gold_min", "int", default=0),
            Field("gold_max", "int", default=0),
        ],
        id_field=None, dir_path="loot_tables", manifest_const="LOOT_TABLES", filename_from="explicit",
        sub_resources=[("entries", "LootEntry", "res://scripts/economy/rewards/LootEntry.gd")],
    ),
    "quest": ContentType(
        key="quest", class_name="QuestDefinition",
        script="res://scripts/progression/quests/QuestDefinition.gd",
        base_fields=[
            Field("id", "str", required=True),
            Field("title", "str", required=True),
            Field("description", "str", default=""),
            Field("category", "str", default="main", doc='"main" | "side" | "daily"'),
            Field("objectives", "array_obj", default=[], obj_fields=QUEST_OBJECTIVE_FIELDS),
            Field("reward_xp", "dict", default={}, doc="skill_name -> xp (int); wird zu reward.xp_rewards"),
            Field("reward_items", "dict", default={}, doc="item_id -> quantity (int); wird zu reward.item_rewards"),
            Field("reward_unlock_quests", "array_str", default=[]),
            Field("reward_custom_signals", "array_str", default=[]),
            Field("reward_stat_modifiers", "dict", default={}, doc="stat_id -> PERCENT_ADD-Wert"),
            Field("prerequisites", "array_str", default=[]),
            Field("auto_start", "bool", default=False),
            Field("repeatable", "bool", default=False),
        ],
        id_field="id", dir_path="quests", manifest_const="QUESTS", filename_from="id",
        sub_resources=[("objectives", "QuestObjective", "res://scripts/progression/quests/QuestObjective.gd")],
        extra_ext_resources=[("QuestReward", "res://scripts/progression/quests/QuestReward.gd")],
    ),
    "skill": ContentType(
        key="skill", class_name="SkillDefinition",
        script="res://scripts/progression/skills/SkillDefinition.gd",
        base_fields=[
            Field("id", "str", required=True),
            Field("display_name", "str", required=True),
            Field("description", "str", default=""),
            Field("xp_to_level_up", "array_int", default=[100, 250, 500, 900, 1400, 2000]),
            Field("xp_scaling_factor", "float", default=1.5),
            Field("max_level", "int", default=99, doc="-1 = unbegrenzt"),
        ],
        id_field="id", dir_path="skills", manifest_const="SKILLS", filename_from="id",
    ),
    "achievement": ContentType(
        key="achievement", class_name="AchievementDefinition",
        script="res://scripts/progression/achievements/AchievementDefinition.gd",
        base_fields=[
            Field("id", "str", required=True),
            Field("display_name", "str", required=True),
            Field("description", "str", required=True),
            Field("target", "float", default=1.0),
            Field("category", "str", default="general", doc='"combat" | "economy" | "social" | "stats" | ...'),
            Field("reward_gold", "int", default=0),
        ],
        id_field="id", dir_path="achievements", manifest_const="ACHIEVEMENTS", filename_from="id",
    ),
    "combat_profile": ContentType(
        key="combat_profile", class_name="CombatProfile",
        script="res://scripts/entities/combat/CombatProfile.gd",
        base_fields=[
            Field("id", "str", required=True),
            Field("display_name", "str", required=True),
            Field("armor", "float", default=0.0, doc="0.0-1.0, im CombatSystem auf 0.85 geclamped"),
            Field("magic_resist", "float", default=0.0, doc="0.0-1.0"),
        ],
        id_field="id", dir_path="combat_profiles", manifest_const="COMBAT_PROFILES", filename_from="id",
    ),
    "smithing_recipe": ContentType(
        key="smithing_recipe", class_name="SmithingRecipe",
        script="res://scripts/economy/crafting/SmithingRecipe.gd",
        base_fields=[
            Field("id", "str", required=True, doc='z.B. "smelt_iron", "forge_iron_sword" — gleichzeitig Dateiname'),
            Field("display_name", "str", required=True),
            Field("station", "str", required=True, doc='"furnace" (Hochofen) | "anvil" (Amboss)'),
            Field("inputs", "dict", required=True, doc="item_id -> Menge (int); wird beim Herstellen verbraucht"),
            Field("output_item_id", "str", required=True, doc="Muss einer existierenden ItemDefinition.id entsprechen"),
            Field("output_quantity", "int", default=1),
            Field("skill_id", "str", default="smithing",
                  doc='Verarbeitungs-Skill des Rezepts (Level-Check + XP); Default "smithing", weitere Skills (Kochen ...) nutzen denselben Service'),
            Field("min_level", "int", default=1, doc='Mindest-Level im Skill `skill_id`'),
            Field("xp", "int", default=10, doc='XP im Skill "smithing" pro Herstellung'),
            Field("required_tools", "array_str", default=[],
                  doc="Item-IDs der Werkzeuge, die vorhanden sein müssen (werden nicht verbraucht), z.B. tool_hammer"),
        ],
        id_field="id", dir_path="smithing_recipes", manifest_const="SMITHING_RECIPES", filename_from="id",
    ),
}

# item-referenzierende Felder je Typ, für Cross-Reference-Checks gegen den
# bekannten Item-Bestand (existierend + in derselben Batch neu angelegt).
ITEM_REF_PATHS = {
    "loot_table": [("entries", "item_id")],
    "quest": [("reward_items", None)],  # dict, Keys sind item_ids
    "smithing_recipe": [("inputs", None), ("required_tools", None), ("output_item_id", None)],
}
QUEST_REF_FIELDS = ["prerequisites", "reward_unlock_quests"]  # Werte sind quest_ids


# ---------------------------------------------------------------------------
# .tres-Wert-Serialisierung (Godot Resource-Text-Format, format=3)
# ---------------------------------------------------------------------------


def _esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


def _fmt_float(x: float) -> str:
    # Godot schreibt ganzzahlige Floats immer mit ".0" (siehe alle Beispiele:
    # armor = 0.1, weight = 80.0, xp_scaling_factor = 1.5).
    if float(x) == int(x):
        return f"{int(x)}.0"
    return repr(float(x))


def fmt_value(kind: str, value: Any, enum: dict | None = None) -> str:
    if kind == "str":
        return f'"{_esc(str(value))}"'
    if kind == "int":
        return str(int(value))
    if kind == "float":
        return _fmt_float(value)
    if kind == "bool":
        return "true" if value else "false"
    if kind == "enum":
        if value not in enum:
            fail(f"Ungültiger Enum-Wert '{value}' — erlaubt: {sorted(enum)}")
        return str(enum[value])
    if kind == "vector3":
        x, y, z = value
        return f"Vector3({_fmt_float(x)}, {_fmt_float(y)}, {_fmt_float(z)})"
    if kind == "array_str":
        return "[" + ", ".join(f'"{_esc(str(v))}"' for v in value) + "]"
    if kind == "array_int":
        return "Array[int]([" + ", ".join(str(int(v)) for v in value) + "])"
    if kind == "dict":
        items = ", ".join(f'"{_esc(str(k))}": {v!r}' if isinstance(v, str) else f'"{_esc(str(k))}": {v}'
                           for k, v in value.items())
        return "{" + items + "}"
    fail(f"Interner Fehler: unbekannte Feldart '{kind}'")


def build_tres(ctype: ContentType, fields: dict[str, Any]) -> str:
    """Baut den vollständigen .tres-Text deterministisch. Reihenfolge: immer
    Script-ext_resource zuerst (id '1_x'), dann evtl. extra_ext_resources,
    dann Sub-Resource-Script-ext_resources, dann Sub-Resources selbst
    (in Eingabe-Reihenfolge), dann [resource] in Schema-Feldreihenfolge —
    identisch bei jedem Aufruf mit derselben Spec."""
    ext_lines: list[str] = []
    ext_id_counter = 1
    script_ext_id = f"{ext_id_counter}_{ctype.key[:4]}"
    ext_lines.append(f'[ext_resource type="Script" path="{ctype.script}" id="{script_ext_id}"]')
    ext_id_counter += 1

    extra_ext_ids: dict[str, str] = {}
    for cls, path in (ctype.extra_ext_resources or []):
        eid = f"{ext_id_counter}_{cls[:4].lower()}"
        ext_lines.append(f'[ext_resource type="Script" path="{path}" id="{eid}"]')
        extra_ext_ids[cls] = eid
        ext_id_counter += 1

    sub_ext_ids: dict[str, str] = {}
    for field_name, cls, path in (ctype.sub_resources or []):
        eid = f"{ext_id_counter}_{cls[:4].lower()}"
        ext_lines.append(f'[ext_resource type="Script" path="{path}" id="{eid}"]')
        sub_ext_ids[field_name] = eid
        ext_id_counter += 1

    sub_blocks: list[str] = []
    sub_ref_by_field: dict[str, list[str]] = {}
    for field_name, cls, _path in (ctype.sub_resources or []):
        obj_field = next(f for f in ctype.base_fields if f.name == field_name)
        refs = []
        for i, obj in enumerate(fields.get(field_name) or []):
            sub_id = _sub_resource_id(ctype.key, field_name, obj, i)
            lines = [f'[sub_resource type="Resource" id="{sub_id}"]',
                     f'script = ExtResource("{sub_ext_ids[field_name]}")']
            for f in obj_field.obj_fields:
                val = obj.get(f.name, f.default)
                lines.append(f"{f.name} = {fmt_value(f.kind, val, f.enum)}")
            sub_blocks.append("\n".join(lines))
            refs.append(f'SubResource("{sub_id}")')
        sub_ref_by_field[field_name] = refs

    # Quest-Reward ist ein Sonderfall: eigene Sub-Resource, aber nicht aus
    # einem array_obj-Feld gebaut, sondern aus vier flachen reward_*-Feldern
    # gesammelt (weniger Verschachtelung in der Spec für den Agenten).
    reward_sub_id = None
    if ctype.key == "quest":
        reward_sub_id = "reward"
        r_lines = [f'[sub_resource type="Resource" id="{reward_sub_id}"]',
                   f'script = ExtResource("{extra_ext_ids["QuestReward"]}")']
        r_lines.append(f'xp_rewards = {fmt_value("dict", fields.get("reward_xp") or {})}')
        r_lines.append(f'item_rewards = {fmt_value("dict", fields.get("reward_items") or {})}')
        r_lines.append(f'unlock_quests = {fmt_value("array_str", fields.get("reward_unlock_quests") or [])}')
        r_lines.append(f'custom_signals = {fmt_value("array_str", fields.get("reward_custom_signals") or [])}')
        r_lines.append(f'stat_modifiers = {fmt_value("dict", fields.get("reward_stat_modifiers") or {})}')
        sub_blocks.append("\n".join(r_lines))

    res_lines = [f'script = ExtResource("{script_ext_id}")']
    for f in ctype.base_fields:
        if f.kind == "array_obj":
            res_lines.append(f"{f.name} = [{', '.join(sub_ref_by_field.get(f.name, []))}]")
            continue
        if ctype.key == "quest" and f.name.startswith("reward_"):
            continue  # in reward-Subresource gebündelt, nicht als Top-Level-Feld
        val = fields.get(f.name, f.default)
        res_lines.append(f"{f.name} = {fmt_value(f.kind, val, f.enum)}")
    if ctype.key == "quest":
        res_lines.append(f'reward = SubResource("{reward_sub_id}")')

    load_steps = len(ext_lines) + len(sub_blocks) + 1
    header = f'[gd_resource type="Resource" script_class="{ctype.class_name}" load_steps={load_steps} format=3]'
    parts = [header, ""]
    parts.extend(ext_lines)
    parts.append("")
    for b in sub_blocks:
        parts.append(b)
        parts.append("")
    parts.append("[resource]")
    parts.extend(res_lines)
    return "\n".join(parts).rstrip() + "\n"


def _sub_resource_id(ctype_key: str, field_name: str, obj: dict, index: int) -> str:
    if ctype_key == "loot_table":
        return f"entry_{obj.get('item_id', index)}"
    if ctype_key == "quest" and field_name == "objectives":
        oid = str(obj.get("id", index))
        return oid if oid.startswith("obj_") else f"obj_{oid}"
    return f"{field_name}_{index}"


# ---------------------------------------------------------------------------
# Validierung
# ---------------------------------------------------------------------------


def to_pascal(snake: str) -> str:
    return "".join(p[:1].upper() + p[1:] for p in snake.split("_") if p)


def scan_existing_ids(ctype: ContentType) -> dict[str, Path]:
    """id -> Pfad der .tres-Datei, die sie deklariert. Scannt tatsächliche
    Dateien (nicht das Manifest) — Wahrheit ist der Dateibestand, siehe
    AGENT.md 'Trust the code, not the docs'."""
    out: dict[str, Path] = {}
    base = REPO_ROOT / "data" / ctype.dir_path
    if not base.exists():
        return out
    id_re = re.compile(r'^\s*id\s*=\s*"([^"]*)"', re.MULTILINE)
    for p in base.rglob("*.tres"):
        text = p.read_text(encoding="utf-8")
        m = list(id_re.finditer(text.split("[resource]", 1)[-1]))
        if m:
            out[m[0].group(1)] = p
    return out


def scan_all_item_ids() -> set[str]:
    ids: set[str] = set()
    for key in ITEM_TYPES:
        ids |= set(scan_existing_ids(SCHEMAS[key]).keys())
    return ids


def scan_all_quest_ids() -> set[str]:
    return set(scan_existing_ids(SCHEMAS["quest"]).keys())


def scan_existing_filenames(ctype: ContentType) -> set[str]:
    base = REPO_ROOT / "data" / ctype.dir_path
    if not base.exists():
        return set()
    return {p.stem for p in base.rglob("*.tres")}


@dataclass
class Errors:
    items: list[str] = field(default_factory=list)

    def add(self, msg: str) -> None:
        self.items.append(msg)

    def ok(self) -> bool:
        return not self.items


def validate_field(f: Field, value: Any, errs: Errors, path: str) -> None:
    if f.kind in ("str",) and not isinstance(value, str):
        errs.add(f"{path}: erwartet str, bekam {type(value).__name__}")
    if f.kind in ("int",) and not isinstance(value, int):
        errs.add(f"{path}: erwartet int, bekam {type(value).__name__}")
    if f.kind in ("float",) and not isinstance(value, (int, float)):
        errs.add(f"{path}: erwartet float, bekam {type(value).__name__}")
    if f.kind == "bool" and not isinstance(value, bool):
        errs.add(f"{path}: erwartet bool, bekam {type(value).__name__}")
    if f.kind == "enum" and value not in (f.enum or {}):
        errs.add(f"{path}: ungültiger Enum-Wert '{value}', erlaubt: {sorted((f.enum or {}).keys())}")
    if f.kind == "vector3":
        if not (isinstance(value, (list, tuple)) and len(value) == 3):
            errs.add(f"{path}: erwartet [x, y, z], bekam {value!r}")
    if f.kind == "array_str" and not (isinstance(value, list) and all(isinstance(v, str) for v in value)):
        errs.add(f"{path}: erwartet Liste von Strings")
    if f.kind == "array_int" and not (isinstance(value, list) and all(isinstance(v, int) for v in value)):
        errs.add(f"{path}: erwartet Liste von Integers")
    if f.kind == "dict" and not isinstance(value, dict):
        errs.add(f"{path}: erwartet dict")


def validate_batch(batch: list[dict]) -> tuple[Errors, list[dict]]:
    """Prüft Schema-Konformität + Cross-Referenzen. Referenzen dürfen auf
    bereits existierende Content ODER auf andere Einträge derselben Batch
    zeigen (z.B. Item + Loot-Table die es droppt, in einem Lauf)."""
    errs = Errors()
    known_item_ids = scan_all_item_ids()
    known_quest_ids = scan_all_quest_ids()
    batch_item_ids: set[str] = set()
    batch_quest_ids: set[str] = set()
    resolved: list[dict] = []

    for i, entry in enumerate(batch):
        prefix = f"[{i}] {entry.get('type', '?')}"
        t = entry.get("type")
        if t not in SCHEMAS:
            errs.add(f"{prefix}: unbekannter type '{t}', erlaubt: {sorted(SCHEMAS)}")
            continue
        ctype = SCHEMAS[t]
        fields = entry.get("fields", {})
        if not isinstance(fields, dict):
            errs.add(f"{prefix}: 'fields' muss ein Objekt sein")
            continue

        unknown = set(fields) - {f.name for f in ctype.base_fields}
        for u in unknown:
            errs.add(f"{prefix}: unbekanntes Feld '{u}' (siehe `schema {t}`)")

        for f in ctype.base_fields:
            if f.name not in fields:
                if f.required:
                    errs.add(f"{prefix}.{f.name}: Pflichtfeld fehlt")
                continue
            val = fields[f.name]
            if f.kind == "array_obj":
                if not isinstance(val, list):
                    errs.add(f"{prefix}.{f.name}: erwartet Liste")
                    continue
                for j, obj in enumerate(val):
                    if not isinstance(obj, dict):
                        errs.add(f"{prefix}.{f.name}[{j}]: erwartet Objekt")
                        continue
                    obj_unknown = set(obj) - {of.name for of in f.obj_fields}
                    for u in obj_unknown:
                        errs.add(f"{prefix}.{f.name}[{j}]: unbekanntes Feld '{u}'")
                    for of in f.obj_fields:
                        if of.name not in obj:
                            if of.required:
                                errs.add(f"{prefix}.{f.name}[{j}].{of.name}: Pflichtfeld fehlt")
                            continue
                        validate_field(of, obj[of.name], errs, f"{prefix}.{f.name}[{j}].{of.name}")
            else:
                validate_field(f, val, errs, f"{prefix}.{f.name}")

        # id-Kollisionen: gegen Dateibestand UND gegen den Rest der Batch.
        if ctype.id_field and ctype.id_field in fields:
            new_id = fields[ctype.id_field]
            existing = scan_existing_ids(ctype)
            if new_id in existing:
                errs.add(f"{prefix}: id '{new_id}' existiert bereits in {existing[new_id]} — --force zum Überschreiben nötig")
            if t in ITEM_TYPES:
                if new_id in batch_item_ids:
                    errs.add(f"{prefix}: id '{new_id}' doppelt innerhalb dieser Batch")
                batch_item_ids.add(new_id)
            if t == "quest":
                if new_id in batch_quest_ids:
                    errs.add(f"{prefix}: id '{new_id}' doppelt innerhalb dieser Batch")
                batch_quest_ids.add(new_id)

        # Dateiname-Kollision (loot_table hat keine id, aber einen Dateinamen).
        fname = entry.get("filename")
        if ctype.filename_from == "explicit":
            if not fname:
                errs.add(f"{prefix}: 'filename' ist für type={t} Pflicht (keine id-basierte Ableitung möglich)")
            elif fname in scan_existing_filenames(ctype):
                errs.add(f"{prefix}: Datei '{fname}.tres' existiert bereits unter data/{ctype.dir_path}/")

        resolved.append(entry)

    # Zweiter Durchlauf für Cross-Referenzen — erst NACHDEM alle neuen IDs
    # dieser Batch bekannt sind (Reihenfolge in der Batch darf beliebig sein:
    # Loot-Table VOR dem Item, das sie referenziert, ist gültig).
    all_item_ids = known_item_ids | batch_item_ids
    all_quest_ids = known_quest_ids | batch_quest_ids
    for i, entry in enumerate(resolved):
        t = entry["type"]
        fields = entry.get("fields", {})
        prefix = f"[{i}] {t}"
        if t == "loot_table":
            for obj in fields.get("entries") or []:
                iid = obj.get("item_id")
                if iid and iid not in all_item_ids:
                    errs.add(f"{prefix}.entries: item_id '{iid}' ist keine bekannte Item-ID (weder Repo noch Batch)")
        if t == "smithing_recipe":
            if fields.get("station") not in SMITHING_STATIONS:
                errs.add(f"{prefix}.station: '{fields.get('station')}' ungültig, erlaubt: {list(SMITHING_STATIONS)}")
            for iid, qty in (fields.get("inputs") or {}).items():
                if iid not in all_item_ids:
                    errs.add(f"{prefix}.inputs: item_id '{iid}' ist keine bekannte Item-ID (weder Repo noch Batch)")
                if not isinstance(qty, int) or qty <= 0:
                    errs.add(f"{prefix}.inputs['{iid}']: Menge muss ein positiver int sein, bekam {qty!r}")
            for iid in fields.get("required_tools") or []:
                if iid not in all_item_ids:
                    errs.add(f"{prefix}.required_tools: item_id '{iid}' ist keine bekannte Item-ID")
            out_id = fields.get("output_item_id")
            if out_id and out_id not in all_item_ids:
                errs.add(f"{prefix}.output_item_id: '{out_id}' ist keine bekannte Item-ID")
            if int(fields.get("output_quantity", 1)) <= 0:
                errs.add(f"{prefix}.output_quantity: muss > 0 sein")
            if int(fields.get("min_level", 1)) < 1:
                errs.add(f"{prefix}.min_level: muss >= 1 sein")
        if t == "quest":
            for iid in (fields.get("reward_items") or {}):
                if iid not in all_item_ids:
                    errs.add(f"{prefix}.reward_items: item_id '{iid}' ist keine bekannte Item-ID")
            for qid in fields.get("prerequisites") or []:
                if qid not in all_quest_ids:
                    errs.add(f"{prefix}.prerequisites: quest-id '{qid}' ist keine bekannte Quest-ID")
            for qid in fields.get("reward_unlock_quests") or []:
                if qid not in all_quest_ids:
                    errs.add(f"{prefix}.reward_unlock_quests: quest-id '{qid}' ist keine bekannte Quest-ID")

    return errs, resolved


# ---------------------------------------------------------------------------
# DataManifest.gd — Pfad-Registrierung
# ---------------------------------------------------------------------------


def add_to_manifest(session: BuildSession, const_name: str, res_path: str) -> None:
    text = DATA_MANIFEST_GD.read_text(encoding="utf-8")
    block_re = re.compile(
        rf"(const {const_name}: Array\[String\] = \[\n)(.*?)(\n?\])", re.DOTALL)
    m = block_re.search(text)
    if not m:
        fail(f"DataManifest.gd: Array '{const_name}' nicht gefunden — Datei-Format geändert?")
    if f'"{res_path}"' in m.group(0):
        return  # bereits registriert, nichts zu tun
    body = m.group(2)
    insertion = f'\t"{res_path}",'
    new_body = body + ("\n" if not body.endswith("\n") and body.strip() else "") + insertion
    if not body.strip():
        new_body = insertion
    new_block = m.group(1) + new_body + m.group(3)
    new_text = text[:m.start()] + new_block + text[m.end():]
    session.apply_change(DATA_MANIFEST_GD, text, new_text, count=1)


# ---------------------------------------------------------------------------
# create — Orchestrierung
# ---------------------------------------------------------------------------


def target_path(ctype: ContentType, entry: dict) -> Path:
    fields = entry.get("fields", {})
    if ctype.filename_from == "id":
        base = to_pascal(fields[ctype.id_field]) if ctype.key in ITEM_TYPES else fields[ctype.id_field]
    else:
        base = entry["filename"]
    return REPO_ROOT / "data" / ctype.dir_path / f"{base}.tres"


def run_create(batch: list[dict], apply: bool, force: bool) -> dict:
    errs, resolved = validate_batch(batch)
    if not force:
        collision_errs = [e for e in errs.items if "existiert bereits" in e and "--force" in e]
    else:
        collision_errs = []
        errs.items = [e for e in errs.items if "--force" not in e]

    if errs.items:
        return {"ok": False, "errors": errs.items, "written": []}

    session = BuildSession(apply=apply)
    written = []
    for entry in resolved:
        ctype = SCHEMAS[entry["type"]]
        fields = entry.get("fields", {})
        text = build_tres(ctype, fields)
        path = target_path(ctype, entry)
        rel = path.relative_to(REPO_ROOT)
        res_path = f"res://{rel.as_posix()}"

        existed_before = path.exists()
        original = path.read_text(encoding="utf-8") if existed_before else ""
        session.apply_change(path, original, text, count=1)

        if ctype.manifest_const:
            add_to_manifest(session, ctype.manifest_const, res_path)

        written.append({
            "type": entry["type"],
            "path": str(rel),
            "res_path": res_path,
            "overwritten": existed_before,
            "manifest_const": ctype.manifest_const,
        })

    return {
        "ok": True,
        "apply": apply,
        "written": written,
        "diffs": [c.diff for c in session.changes] if not apply else None,
        "changed_files": [str(c.path.relative_to(REPO_ROOT)) for c in session.changes],
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def field_to_schema_dict(f: Field) -> dict:
    d = {"name": f.name, "kind": f.kind, "required": f.required}
    if not f.required:
        d["default"] = f.default
    if f.enum:
        d["enum"] = f.enum
    if f.doc:
        d["doc"] = f.doc
    if f.kind == "array_obj":
        d["object_fields"] = [field_to_schema_dict(of) for of in f.obj_fields]
    return d


def cmd_schema(args: argparse.Namespace) -> None:
    if args.type not in SCHEMAS:
        print(json.dumps({"error": f"unbekannter type '{args.type}'", "available": sorted(SCHEMAS)},
                          indent=2, ensure_ascii=False))
        sys.exit(1)
    ctype = SCHEMAS[args.type]
    out = {
        "type": ctype.key,
        "class_name": ctype.class_name,
        "script": ctype.script,
        "id_field": ctype.id_field,
        "filename": ("derived from id (PascalCase)" if ctype.filename_from == "id" and ctype.key in ITEM_TYPES
                     else "= id" if ctype.filename_from == "id"
                     else "explicit 'filename' field required"),
        "target_dir": f"data/{ctype.dir_path}/",
        "registered_in": f"DataManifest.gd::{ctype.manifest_const}" if ctype.manifest_const else None,
        "fields": [field_to_schema_dict(f) for f in ctype.base_fields],
    }
    print(json.dumps(out, indent=2, ensure_ascii=False))


def cmd_list(args: argparse.Namespace) -> None:
    if args.type not in SCHEMAS:
        print(json.dumps({"error": f"unbekannter type '{args.type}'", "available": sorted(SCHEMAS)},
                          indent=2, ensure_ascii=False))
        sys.exit(1)
    ctype = SCHEMAS[args.type]
    by_file = scan_existing_ids(ctype)
    manifest_paths: list[str] = []
    if ctype.manifest_const:
        text = DATA_MANIFEST_GD.read_text(encoding="utf-8")
        m = re.search(rf"const {ctype.manifest_const}: Array\[String\] = \[(.*?)\]", text, re.DOTALL)
        if m:
            manifest_paths = re.findall(r'"([^"]+)"', m.group(1))
    registered_res_paths = set(manifest_paths)
    out = []
    for id_, path in sorted(by_file.items()):
        rel = path.relative_to(REPO_ROOT)
        res_path = f"res://{rel.as_posix()}"
        out.append({"id": id_, "path": str(rel), "registered_in_manifest": res_path in registered_res_paths})
    orphan_manifest = [p for p in manifest_paths if not any(o["path"] == p.replace("res://", "") for o in out)]
    print(json.dumps({
        "type": args.type,
        "count": len(out),
        "entries": out,
        "manifest_entries_without_matching_file": orphan_manifest,
    }, indent=2, ensure_ascii=False))


def load_batch(spec_path: str) -> list[dict]:
    raw = Path(spec_path).read_text(encoding="utf-8")
    data = json.loads(raw)
    if isinstance(data, dict):
        data = [data]
    if not isinstance(data, list):
        fail("Spec muss ein JSON-Objekt oder eine Liste von Objekten sein")
    return data


def cmd_validate(args: argparse.Namespace) -> None:
    batch = load_batch(args.spec)
    errs, resolved = validate_batch(batch)
    print(json.dumps({"ok": errs.ok(), "errors": errs.items, "entries_checked": len(batch)},
                      indent=2, ensure_ascii=False))
    sys.exit(0 if errs.ok() else 1)


def cmd_create(args: argparse.Namespace) -> None:
    batch = load_batch(args.spec)
    result = run_create(batch, apply=args.apply, force=args.force)
    print(json.dumps(result, indent=2, ensure_ascii=False))
    if not args.apply and result["ok"]:
        print("\n--- DRY-RUN: nichts geschrieben. Mit --apply wirklich anlegen. ---", file=sys.stderr)
    sys.exit(0 if result["ok"] else 1)


def main() -> None:
    p = argparse.ArgumentParser(description="Deterministische Content-Erzeugung (.tres) für Agents.")
    sub = p.add_subparsers(dest="cmd", required=True)

    p_schema = sub.add_parser("schema", help="Feldschema eines Content-Typs")
    p_schema.add_argument("type", choices=sorted(SCHEMAS))
    p_schema.set_defaults(func=cmd_schema)

    p_list = sub.add_parser("list", help="Vorhandene IDs eines Content-Typs")
    p_list.add_argument("type", choices=sorted(SCHEMAS))
    p_list.set_defaults(func=cmd_list)

    p_val = sub.add_parser("validate", help="Spec-Batch prüfen, nichts schreiben")
    p_val.add_argument("--spec", required=True)
    p_val.set_defaults(func=cmd_validate)

    p_create = sub.add_parser("create", help="Spec-Batch validieren + erzeugen")
    p_create.add_argument("--spec", required=True)
    p_create.add_argument("--apply", action="store_true", help="tatsächlich schreiben (sonst Dry-Run)")
    p_create.add_argument("--force", action="store_true", help="id-Kollisionen als Overwrite erlauben")
    p_create.set_defaults(func=cmd_create)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()

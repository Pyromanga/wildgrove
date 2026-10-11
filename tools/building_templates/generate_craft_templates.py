#!/usr/bin/env python3
"""Erzeugt + validiert die Berufs-Gebäude (HouseTemplateDefinition) unter data/building/houses/.

Warum ein Generator: ein Haus besteht aus 20-70 Einträgen {piece_id, kind, axis, dx, dz}. Von Hand
getippt passieren Fehler, die erst im Spiel auffallen (Dach ohne Wand = "unsupported", zwei Teile
auf demselben Schlüssel = "occupied", Requisite vor der Tür). Dieses Skript baut die Vorlagen aus
Räumen/Zäunen/Requisiten und prüft sie gegen dieselben Schlüsselräume wie BuildGrid.

Konventionen (siehe HouseTemplateDefinition.gd / BuildGrid.gd):
  Zelle (cx,cz); Kanten: N=(axis0,cx,cz) S=(axis0,cx,cz+1) W=(axis1,cx,cz) E=(axis1,cx+1,cz).
  Requisiten-Blickrichtung axis: 0 = +Z (Süden), 1 = +X (Osten), 2 = -Z (Norden), 3 = -X (Westen).

Aufruf:  python3 tools/building_templates/generate_craft_templates.py [--check]
  --check  nur validieren, nichts schreiben (Exit 1 bei Fehlern)
Schreibt nur data/building/houses/<Name>.tres der hier erzeugten Vorlagen (Smithy.tres gehört dem Schmiede-System).
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HOUSES = ROOT / "data" / "building" / "houses"
BUILD_DIR = ROOT / "data" / "building"

FLOOR, WALL, ROOF, DOOR, WINDOW, STAIRS, TARGET = range(7)
REACH = 10.0          # WorldBuildHandler.REACH (m), je Teil gemessen vom Spieler
CELL = 2.0            # BuildGrid.CELL (m)
ROOF_OVERHANG_REACH = 3   # BuildPlacementRules.ROOF_OVERHANG_REACH


def load_piece_kinds() -> dict[str, int]:
    kinds: dict[str, int] = {}
    for p in BUILD_DIR.glob("*.tres"):
        t = p.read_text(encoding="utf-8")
        m_id = re.search(r'^id = "([^"]+)"', t, re.M)
        m_kind = re.search(r"^kind = (\d+)", t, re.M)
        if m_id:
            kinds[m_id.group(1)] = int(m_kind.group(1)) if m_kind else 0
    return kinds


class Template:
    """Eine Vorlage als Menge von Einträgen. Schlüssel = (Raum, x, z, ebene) bzw. ("W", achse, x, z, ebene)
    — dieselben Schlüsselräume wie BuildGrid (F_/R_/T_/P_ je Zelle, W<achse> je Kante für Wand/Tür/Fenster),
    getrennt je Ebene (`storey` = Ebenen-OFFSET zur Ebene des Hauses, Default 0)."""

    def __init__(self, tid: str, filename: str, name: str, desc: str) -> None:
        self.tid, self.filename, self.name, self.desc = tid, filename, name, desc
        self.entries: dict[tuple, dict] = {}
        self.errors: list[str] = []

    @staticmethod
    def _key(kind: int, axis: int, dx: int, dz: int, storey: int) -> tuple:
        if kind in (WALL, DOOR, WINDOW):
            return ("W", axis % 2, dx, dz, storey)
        return ({FLOOR: "F", ROOF: "R", STAIRS: "T", TARGET: "P"}[kind], dx, dz, storey)

    def _add(self, piece_id: str, kind: int, axis: int, dx: int, dz: int, storey: int = 0) -> None:
        key = self._key(kind, axis, dx, dz, storey)
        if key in self.entries:
            self.errors.append(f"{self.tid}: doppelter Schlüssel {key} ({piece_id} vs {self.entries[key]['piece_id']})")
            return
        self.entries[key] = {"piece_id": piece_id, "kind": kind, "axis": axis, "dx": dx, "dz": dz, "storey": storey}

    def floor(self, piece_id: str, cells_, storey: int = 0) -> None:
        for cx, cz in cells_:
            self._add(piece_id, FLOOR, -1, cx, cz, storey)

    def wall(self, piece_id: str, kind: int, axis: int, ex: int, ez: int, storey: int = 0) -> None:
        self._add(piece_id, kind, axis, ex, ez, storey)

    def roof(self, piece_id: str, cells_, axis: int = 0, storey: int = 0) -> None:
        for cx, cz in cells_:
            self._add(piece_id, ROOF, axis, cx, cz, storey)

    def stairs(self, piece_id: str, cx: int, cz: int, facing: int, storey: int = 0) -> None:
        self._add(piece_id, STAIRS, facing, cx, cz, storey)

    def prop(self, piece_id: str, cx: int, cz: int, facing: int = 0, storey: int = 0) -> None:
        self._add(piece_id, TARGET, facing, cx, cz, storey)

    # --- Hilfen: Wandringe -------------------------------------------------------------------
    @staticmethod
    def ring_edges(x0: int, z0: int, w: int, d: int) -> dict[str, list[tuple[int, int, int]]]:
        return {
            "N": [(0, x, z0) for x in range(x0, x0 + w)],
            "S": [(0, x, z0 + d) for x in range(x0, x0 + w)],
            "W": [(1, x0, z) for z in range(z0, z0 + d)],
            "E": [(1, x0 + w, z) for z in range(z0, z0 + d)],
        }

    def walls_on(self, piece_id: str, edges, kind: int = WALL, storey: int = 0) -> None:
        for axis, ex, ez in edges:
            self.wall(piece_id, kind, axis, ex, ez, storey)

    # --- Validierung -------------------------------------------------------------------------
    @staticmethod
    def _edges_around(cx: int, cz: int) -> list[tuple[int, int, int]]:
        return [(0, cx, cz), (0, cx, cz + 1), (1, cx, cz), (1, cx + 1, cz)]

    @staticmethod
    def _cells_beside(edge: tuple[int, int, int]) -> list[tuple[int, int]]:
        axis, ex, ez = edge
        return [(ex, ez - 1), (ex, ez)] if axis == 0 else [(ex - 1, ez), (ex, ez)]

    def validate(self, known: dict[str, int]) -> list[str]:
        errs = list(self.errors)
        # Wand/Tür/Fenster-Kanten und Böden je Ebene (nur was die Vorlage SELBST mitbringt)
        walls: dict[int, set] = {}
        floors: dict[int, set] = {}
        for k in self.entries:
            if k[0] == "W":
                walls.setdefault(k[4], set()).add((k[1], k[2], k[3]))
            elif k[0] == "F":
                floors.setdefault(k[3], set()).add((k[1], k[2]))
        for k, e in self.entries.items():
            if e["piece_id"] not in known:
                errs.append(f"{self.tid}: unbekanntes Bauteil '{e['piece_id']}'")
            elif known[e["piece_id"]] != e["kind"]:
                errs.append(f"{self.tid}: '{e['piece_id']}' hat kind {known[e['piece_id']]}, Eintrag sagt {e['kind']}")
        # Dach-Regel wie BuildPlacementRules._check_roof (je Ebene): eigene Wand ODER Überhang über eine lückenlose
        # Dachkette bis ROOF_OVERHANG_REACH Zellen von einem wandgetragenen Dach.
        # roof_tier[(ebene, x, z)] = Kettenlänge (0 = eigene Wand); to_tres() sortiert danach.
        roof_cells = {(k[3], k[1], k[2]) for k in self.entries if k[0] == "R"}
        self.roof_tier = {}
        for (st, cx, cz) in roof_cells:
            if any(a in walls.get(st, set()) for a in self._edges_around(cx, cz)):
                self.roof_tier[(st, cx, cz)] = 0
        for hop in range(1, ROOF_OVERHANG_REACH + 1):
            for (st, cx, cz) in sorted(roof_cells - set(self.roof_tier)):
                if any(self.roof_tier.get((st, nx, nz)) == hop - 1 for nx, nz in ((cx - 1, cz), (cx + 1, cz), (cx, cz - 1), (cx, cz + 1))):
                    self.roof_tier[(st, cx, cz)] = hop
        for (st, cx, cz) in sorted(roof_cells - set(self.roof_tier)):
            errs.append(f"{self.tid}: Dach bei Zelle ({cx},{cz}) Ebene {st} hat keine Wand rundherum und ist weiter als "
                        f"{ROOF_OVERHANG_REACH} Zellen von einem getragenen Dach entfernt (unsupported)")
        for k, e in self.entries.items():
            # Obere Ebenen: dieselben Halteregeln wie BuildPlacementRules._check_*_upper
            if k[0] in ("F", "P", "T") and k[3] > 0:
                cx, cz, st = k[1], k[2], k[3]
                if not any(a in walls.get(st - 1, set()) for a in self._edges_around(cx, cz)):
                    errs.append(f"{self.tid}: {k[0]} bei Zelle ({cx},{cz}) Ebene {st} hat keine Wand der Ebene {st - 1} als Auflager")
            if k[0] == "W" and k[4] > 0:
                edge, st = (k[1], k[2], k[3]), k[4]
                on_wall_below = edge in walls.get(st - 1, set())
                on_floor = any(c in floors.get(st, set()) for c in self._cells_beside(edge))
                if not (on_wall_below or on_floor):
                    errs.append(f"{self.tid}: Wand {edge} Ebene {st} steht weder auf einer Wand darunter noch an einem Boden")
        props = {(k[1], k[2]) for k in self.entries if k[0] == "P" and k[3] == 0}
        for k, e in self.entries.items():
            if k[0] == "W" and e["kind"] == DOOR and k[4] == 0:
                for c in self._cells_beside((k[1], k[2], k[3])):
                    if c in props:
                        errs.append(f"{self.tid}: Requisite auf Zelle {c} blockiert die Tür {k}")
        xs = [(k[1] if k[0] != "W" else k[2]) for k in self.entries]
        zs = [(k[2] if k[0] != "W" else k[3]) for k in self.entries]
        # Reichweite: jedes Teil muss ≤ REACH von der Mitte der Grundfläche entfernt sein (waagerecht).
        cx_mid = (min(xs) + max(xs) + 1) * 0.5 * CELL
        cz_mid = (min(zs) + max(zs) + 1) * 0.5 * CELL
        worst = 0.0
        for k in self.entries:
            if k[0] == "W":
                px = (k[2] + (0.5 if k[1] == 0 else 0.0)) * CELL
                pz = (k[3] + (0.0 if k[1] == 0 else 0.5)) * CELL
            else:
                px, pz = (k[1] + 0.5) * CELL, (k[2] + 0.5) * CELL
            worst = max(worst, ((px - cx_mid) ** 2 + (pz - cz_mid) ** 2) ** 0.5)
        if worst > REACH:
            errs.append(f"{self.tid}: Teil {worst:.1f} m von der Mitte entfernt (> REACH {REACH})")
        self.reach_from_center = worst
        return errs

    def to_tres(self) -> str:
        order = {FLOOR: 0, WALL: 1, DOOR: 1, WINDOW: 1, ROOF: 2, STAIRS: 2, TARGET: 3}
        # Dächer nach Kettenlänge sortiert (0 = eigene Wand, 1.. = Überhang): WorldBuildHandler baut in Dateireihenfolge,
        # ein Überhang braucht sein tragendes Nachbardach schon im Bestand — unabhängig von der Drehung des Hauses.
        # Davor immer nach Ebene (obere Ebenen brauchen Halt von unten).
        tiers = getattr(self, "roof_tier", {})
        def tier(e: dict) -> int:
            return tiers.get((e["storey"], e["dx"], e["dz"]), 0) if e["kind"] == ROOF else 0
        rows = sorted(self.entries.values(),
                      key=lambda e: (e["storey"], order[e["kind"]], tier(e), e["dx"], e["dz"], e["axis"]))
        lines = [
            '[gd_resource type="Resource" script_class="HouseTemplateDefinition" load_steps=2 format=3]',
            "",
            '[ext_resource type="Script" path="res://scripts/world/building/HouseTemplateDefinition.gd" id="1_house"]',
            "",
            "[resource]",
            'script = ExtResource("1_house")',
            f'id = "{self.tid}"',
            f'display_name = "{self.name}"',
            f'description = "{self.desc}"',
            "pieces = Array[Dictionary]([",
        ]
        for e in rows:
            extra = ', "storey": %d' % e["storey"] if e["storey"] > 0 else ""
            lines.append('{"piece_id": "%s", "kind": %d, "axis": %d, "dx": %d, "dz": %d%s},' % (
                e["piece_id"], e["kind"], e["axis"], e["dx"], e["dz"], extra))
        lines.append("])")
        return "\n".join(lines) + "\n"


def cells(x0: int, z0: int, w: int, d: int):
    return [(x, z) for z in range(z0, z0 + d) for x in range(x0, x0 + w)]


# ───────────────────────── Bausteine: wiederverwendbar im Handwerkerviertel ─────────────────────
def build_smithy(t: Template, ox: int = 0, oz: int = 0) -> None:
    """2×2, Süden offen: Hochofen (Schmiede-Station) an der Nordwand, Löschfass, Werkbank.
    Der Amboss-Platz (ox, oz+1) bleibt wie in data/building/houses/Smithy.tres FREI: der Amboss
    braucht Eisenbarren und wird nachgerüstet, sobald der Hochofen welche geschmolzen hat."""
    t.floor("stone_floor", cells(ox, oz, 2, 2))
    r = Template.ring_edges(ox, oz, 2, 2)
    t.walls_on("stone_wall", r["N"] + r["W"] + r["E"])
    t.roof("wood_roof", cells(ox, oz, 2, 2), 0)
    t.prop("furnace", ox, oz, 0)
    t.prop("barrel", ox + 1, oz, 0)
    t.prop("workbench", ox + 1, oz + 1, 0)


def build_bakery(t: Template, ox: int = 0, oz: int = 0, door_x: int = 1, window_x: int = 2) -> None:
    """3×2 geschlossen, Tür + Fenster nach Süden: Ofen im Nordwesten, Teigtisch, Mehlfass."""
    t.floor("wood_floor", cells(ox, oz, 3, 2))
    r = Template.ring_edges(ox, oz, 3, 2)
    for kind_piece, edges in (("wood_wall", r["N"] + r["W"] + r["E"] + r["S"]),):
        for axis, ex, ez in edges:
            if (axis, ex, ez) == (0, ox + door_x, oz + 2):
                t.wall("wood_door", DOOR, axis, ex, ez)
            elif (axis, ex, ez) == (0, ox + window_x, oz + 2):
                t.wall("wood_window", WINDOW, axis, ex, ez)
            else:
                t.wall(kind_piece, WALL, axis, ex, ez)
    t.roof("wood_roof", cells(ox, oz, 3, 2), 0)
    t.prop("bake_oven", ox, oz, 0)
    t.prop("workbench", ox + 2, oz, 0)
    t.prop("barrel", ox + 2, oz + 1, 0)


def build_carpenter(t: Template, ox: int = 0, oz: int = 0, front: str = "S") -> None:
    """4×2 offene Halle mit niedrigem Tresenzaun in der Front (Eingänge an beiden Enden)."""
    t.floor("wood_floor", cells(ox, oz, 4, 2))
    r = Template.ring_edges(ox, oz, 4, 2)
    back = "N" if front == "S" else "S"
    t.walls_on("wood_wall", r[back] + r["W"] + r["E"])
    front_edges = r[front]
    t.walls_on("wood_fence", front_edges[1:3])   # mittlere zwei Kanten = Tresen, Enden = Eingang
    t.roof("wood_roof", cells(ox, oz, 4, 2), 0)
    row = oz if front == "S" else oz + 1          # Werkbänke an der Rückwand
    face = 0 if front == "S" else 2               # mit Blick zur offenen Front
    for i in range(3):
        t.prop("workbench", ox + i, row, face)
    t.prop("barrel", ox + 3, row, face)
    t.prop("barrel", ox + 3, oz + 1 if front == "S" else oz, face)


# ───────────────────────────────────────── Vorlagen ──────────────────────────────────────────────
def make_all() -> list[Template]:
    out: list[Template] = []

    t = Template("bakery", "Bakery.tres", "Bäckerei",
                 "3×2 Felder, Holz, eine Tür und ein Fenster nach Süden. Backofen im Nordwesten, Teigtisch und Mehlfass. "
                 "Davor ein roter Marktstand für das Brot und eine Laterne.")
    build_bakery(t)
    t.prop("market_stall_red", 0, 2, 0)
    t.prop("street_lamp_wood", 2, 2, 0)
    out.append(t)

    t = Template("carpenter_shop", "CarpenterShop.tres", "Zimmerei",
                 "4×2 Felder, offene Holzhalle mit Tresenzaun zur Straße (Süden) und Eingängen an beiden Enden. "
                 "Drei Werkbänke an der Rückwand, zwei Fässer.")
    build_carpenter(t)
    out.append(t)

    t = Template("market_square", "MarketSquare.tres", "Marktplatz",
                 "5×3 Felder Steinpflaster. Im Norden vier Marktstände (rot/blau) um einen Wegweiser, in der Mitte ein Brunnen, "
                 "im Süden zwei Stände mit Fässern und eine Laterne. Keine Mauern — Stände zum Platz hin geöffnet. "
                 "Mitte des Platzes anvisieren und dort stehen.")
    t.floor("stone_floor", cells(0, 0, 5, 3))
    t.prop("market_stall_red", 0, 0, 0)
    t.prop("market_stall_blue", 1, 0, 0)
    t.prop("signpost_wood", 2, 0, 0)
    t.prop("market_stall_red", 3, 0, 0)
    t.prop("market_stall_blue", 4, 0, 0)
    t.prop("well", 2, 1, 0)
    t.prop("market_stall_blue", 0, 2, 2)
    t.prop("barrel", 1, 2, 0)
    t.prop("street_lamp_wood", 2, 2, 0)
    t.prop("barrel", 3, 2, 0)
    t.prop("market_stall_red", 4, 2, 2)
    out.append(t)

    t = Template("tavern", "Tavern.tres", "Taverne",
                 "4×3 Felder, Holz, Tür und Fenster, Holzdach. Ein Tresenzaun trennt drei Fässer vom Gastraum, Fässer dienen als Tische, "
                 "an der Ostwand Ausschank und Ofen als Kamin. Draußen Wegweiser und Laterne.")
    t.floor("wood_floor", cells(0, 0, 4, 3))
    r = Template.ring_edges(0, 0, 4, 3)
    window_edges = {(0, 1, 0), (0, 2, 0), (1, 0, 1), (1, 4, 1), (0, 3, 3)}
    door_edge = (0, 1, 3)
    for edge in r["N"] + r["S"] + r["W"] + r["E"]:
        if edge == door_edge:
            t.wall("wood_door", DOOR, *edge)
        elif edge in window_edges:
            t.wall("wood_window", WINDOW, *edge)
        else:
            t.wall("wood_wall", WALL, *edge)
    # Schanktresen: niedriger Zaun trennt die Fässer (Reihe z=0) vom Gastraum. Er ist zugleich das
    # Dachauflager der zwei inneren Zellen (1,1)/(2,1) — ohne Wand ringsum wäre ihr Dach "unsupported".
    t.walls_on("wood_fence", [(0, 1, 1), (0, 2, 1)])
    t.roof("wood_roof", cells(0, 0, 4, 3), 0)
    for x in range(3):
        t.prop("barrel", x, 0, 0)
    t.prop("barrel", 0, 2, 0)
    t.prop("barrel", 2, 2, 0)
    t.prop("market_stall_blue", 3, 1, 3)
    t.prop("bake_oven", 3, 2, 3)
    t.prop("signpost_wood", 4, 3, 0)
    t.prop("street_lamp_wood", -1, 3, 0)
    out.append(t)

    t = Template("farmstead", "Farmstead.tres", "Bauernhof",
                 "5×4 Felder Hof mit Holzzaun (Tor nach Süden), kleiner Hütte in der Nordwestecke, Brunnen, Fass, Heuballen "
                 "und einem Hofladen. Kein Boden — der Hof liegt frei auf dem Gelände.")
    t.floor("wood_floor", cells(0, 0, 2, 2))
    cab = Template.ring_edges(0, 0, 2, 2)
    cabin_edges = set(cab["N"] + cab["W"] + cab["S"] + cab["E"])
    for edge in cab["N"] + cab["W"] + cab["S"] + cab["E"]:
        if edge == (0, 0, 2):
            t.wall("wood_door", DOOR, *edge)
        elif edge == (0, 1, 0) or edge == (1, 2, 1):
            t.wall("wood_window", WINDOW, *edge)
        else:
            t.wall("wood_wall", WALL, *edge)
    t.roof("wood_roof", cells(0, 0, 2, 2), 0)
    yard = Template.ring_edges(0, 0, 5, 4)
    fence = [e for e in yard["N"] + yard["W"] + yard["E"] + yard["S"] if e not in cabin_edges]
    fence = [e for e in fence if e not in {(0, 3, 4), (0, 4, 4)}]   # Tor: zwei Kanten Lücke im Süden
    t.walls_on("wood_fence", fence)
    t.prop("well", 3, 1, 0)
    t.prop("barrel", 2, 2, 0)
    t.prop("market_stall_red", 4, 1, 3)
    t.wall("hay_bale", WALL, 0, 2, 3)
    t.wall("hay_bale", WALL, 0, 3, 3)
    out.append(t)

    t = Template("craft_quarter", "CraftQuarter.tres", "Handwerkerviertel",
                 "6×5 Felder: kleine Schmiede mit Hochofen (Amboss-Platz frei zum Nachrüsten), Bäckerei mit Tür zur gepflasterten Straße und Zimmerei gegenüber, dazu zwei Marktstände, "
                 "Brunnen, Wegweiser, Laternen und Fässer. Größte Struktur — Mitte des Viertels anvisieren und dort stehen, "
                 "sonst ist ein Teil außer Reichweite.")
    build_smithy(t, 0, 0)                       # Zellen x0-1, z0-1
    build_bakery(t, 3, 0, door_x=1, window_x=2)  # Zellen x3-5, z0-1; Tür bei x=4, Fenster bei x=5
    t.floor("stone_floor", cells(0, 2, 6, 1))    # Straße z=2
    build_carpenter(t, 0, 3, front="N")          # Zellen x0-3, z3-4, Front nach Norden zur Straße
    t.prop("market_stall_blue", 4, 3, 2)
    t.prop("market_stall_red", 5, 3, 2)
    t.prop("barrel", 4, 4, 0)
    t.prop("barrel", 5, 4, 0)
    t.prop("barrel", 2, 0, 0)
    t.prop("street_lamp_wood", 2, 1, 0)
    t.prop("signpost_wood", 0, 2, 0)
    t.prop("well", 5, 2, 0)
    t.prop("street_lamp_wood", 3, 2, 0)
    out.append(t)

    # ───────── Tore und Plätze (Torbögen/Zinnenmauer/Kleinigkeiten) ─────────
    t = Template("gate_arch", "GateArch.tres", "Torbogen",
                 "5 Felder Zinnenmauer mit Rundbogen-Durchgang in der Mitte und je einer Fahne daneben. Ohne Dach, ohne Boden — "
                 "an Mauern oder Türme ansetzen und beliebig oft in Reihe stellen.")
    t.walls_on("stone_wall_crenel", [(0, 0, 0), (0, 1, 0), (0, 3, 0), (0, 4, 0)])
    t.wall("stone_gate_arch", DOOR, 0, 2, 0)
    t.prop("banner_red", 1, 0, 0)
    t.prop("banner_red", 3, 0, 0)
    out.append(t)

    t = Template("city_gate", "CityGate.tres", "Stadttor",
                 "14 m breite Torfront: zwei Rundtürme, fünf Felder Zinnenmauer mit Rundbogen-Tor in der Mitte, Pflaster durch das Tor, "
                 "Fahnen und zwei Eisenlaternen auf der Innenseite. Mitte anvisieren und dort stehen.")
    t.walls_on("stone_wall_crenel", [(0, 1, 1), (0, 2, 1), (0, 4, 1), (0, 5, 1)])
    t.wall("stone_gate_arch", DOOR, 0, 3, 1)
    t.floor("stone_floor", [(3, 0), (3, 1)])
    t.prop("tower_stone_round", 0, 0, 0)
    t.prop("tower_stone_round", 6, 0, 0)
    t.prop("banner_blue", 2, 0, 0)
    t.prop("banner_blue", 4, 0, 0)
    t.prop("street_lamp_iron", 1, 1, 0)
    t.prop("street_lamp_iron", 5, 1, 0)
    out.append(t)

    t = Template("village_square", "VillageSquare.tres", "Dorfplatz",
                 "5×5 Felder: gepflasterte Mitte mit Brunnen, vier Bänken und vier Laternen; links und rechts je zwei Marktstände, "
                 "oben Kisten, Säcke und eine Fahne, unten Handkarren, Tisch und Feuerstelle. Mitte anvisieren und dort stehen.")
    t.floor("stone_floor", cells(1, 1, 3, 3))
    t.prop("well", 2, 2, 0)
    t.prop("bench_wood", 2, 1, 0)
    t.prop("bench_wood", 2, 3, 2)
    t.prop("bench_wood", 1, 2, 1)
    t.prop("bench_wood", 3, 2, 3)
    for cx, cz in ((1, 1), (3, 1), (1, 3), (3, 3)):
        t.prop("street_lamp_wood", cx, cz, 0)
    t.prop("market_stall_red", 0, 1, 1)
    t.prop("market_stall_blue", 0, 3, 1)
    t.prop("market_stall_blue", 4, 1, 3)
    t.prop("market_stall_red", 4, 3, 3)
    t.prop("crate", 1, 0, 0)
    t.prop("banner_blue", 2, 0, 0)
    t.prop("sacks", 3, 0, 0)
    t.prop("hand_cart", 1, 4, 0)
    t.prop("firepit", 2, 4, 0)
    t.prop("table_wood", 3, 4, 0)
    out.append(t)

    # ───────── Hof und Wehr (Stall, Garten, Scheune, Eckturm, Kaserne, Wehrhof) — klein nach groß ─────────
    t = Template("herb_garden", "HerbGarden.tres", "Kräutergarten",
                 "5×3 Felder Garten mit Holzzaun (Tor nach Süden): in der Mitte ein Weg, links und rechts Kräuter- und Blumenbeete, "
                 "eine Vogelscheuche zwischen den Beeten, hinten ein Brunnen und eine Bank. Kein Boden — der Garten liegt frei auf dem Gelände.")
    yard = Template.ring_edges(0, 0, 5, 3)
    fence = [e for e in yard["N"] + yard["W"] + yard["E"] + yard["S"] if e not in {(0, 2, 3)}]   # Tor: eine Kante Lücke im Süden
    t.walls_on("wood_fence", fence)
    t.prop("garden_bed_herbs", 0, 0, 0)
    t.prop("garden_bed_herbs", 1, 0, 0)
    t.prop("scarecrow", 2, 0, 0)
    t.prop("garden_bed_flowers", 3, 0, 0)
    t.prop("garden_bed_flowers", 4, 0, 0)
    t.prop("garden_bed_flowers", 0, 2, 0)
    t.prop("garden_bed_herbs", 1, 2, 0)
    t.prop("well", 2, 1, 0)
    t.prop("garden_bed_herbs", 3, 2, 0)
    t.prop("garden_bed_flowers", 4, 2, 0)
    t.prop("bench_wood", 4, 1, 3)
    out.append(t)

    t = Template("stable", "Stable.tres", "Stall",
                 "4×2 Felder Holzstall für Pferd und Esel: Futtertrog und Wassertrog an der Rückwand, Trennzaun zwischen den Boxen, "
                 "Heuballen und Sack in der Front, Eingang an der Ostseite. Davor ein Handkarren und eine Laterne.")
    t.floor("wood_floor", cells(0, 0, 4, 2))
    r = Template.ring_edges(0, 0, 4, 2)
    t.walls_on("wood_wall", r["N"] + r["W"] + r["E"])
    t.wall("wood_fence", WALL, 0, 1, 2)
    t.wall("hay_bale", WALL, 0, 2, 2)                 # Süd: Kante 0 offen (Fenster zur Weide), 1 Zaun, 2 Heu, 3 Eingang
    t.wall("wood_fence", WALL, 1, 2, 0)               # Boxentrenner zwischen den Futtertrögen
    t.roof("wood_roof", cells(0, 0, 4, 2), 0)
    t.prop("trough_feed", 0, 0, 0)
    t.prop("trough_feed", 1, 0, 0)
    t.prop("trough_water", 3, 0, 0)
    t.prop("sacks", 0, 1, 0)
    t.prop("hand_cart", 4, 1, 3)
    t.prop("street_lamp_wood", -1, 1, 0)
    out.append(t)

    t = Template("barn", "Barn.tres", "Scheune",
                 "5×3 Felder große Holzscheune mit Bogentor nach Süden und zwei Fenstern: Heuballen, Kisten, Säcke, Fässer, Karren und "
                 "Holzstapel als Lager, Vogelscheuche im Winterquartier. Das Bogentor-Feld bleibt frei.")
    t.floor("wood_floor", cells(0, 0, 5, 3))
    r = Template.ring_edges(0, 0, 5, 3)
    for edge in r["N"] + r["S"] + r["W"] + r["E"]:
        if edge == (0, 2, 3):
            t.wall("wood_arch_door", DOOR, *edge)
        elif edge in {(1, 0, 1), (1, 5, 1)}:
            t.wall("wood_arch_window", WINDOW, *edge)
        else:
            t.wall("wood_wall", WALL, *edge)
    t.roof("wood_roof", cells(0, 0, 5, 3), 0)
    t.wall("hay_bale", WALL, 0, 0, 1)
    t.wall("hay_bale", WALL, 0, 1, 1)
    t.prop("crate", 0, 0, 0)
    t.prop("sacks", 1, 0, 0)
    t.prop("barrel", 2, 0, 0)
    t.prop("hand_cart", 3, 0, 0)
    t.prop("woodpile", 4, 0, 0)
    t.prop("scarecrow", 0, 2, 0)
    t.prop("crate", 4, 2, 0)
    t.prop("street_lamp_wood", 3, 3, 0)
    out.append(t)

    t = Template("wall_corner", "WallCorner.tres", "Mauereck mit Eckturm",
                 "Rundturm mit Zinnenmauer-Armen nach Osten und Süden (je fünf Felder) und einer Fahne. Baustein für Stadt- und Burgmauern: "
                 "an den Armen weitere Mauerstücke, Torbögen oder Türme ansetzen. Mitte der Arme anvisieren.")
    t.prop("tower_stone_round", 0, 0, 0)
    t.walls_on("stone_wall_crenel", [(0, x, 1) for x in range(1, 6)])
    t.walls_on("stone_wall_crenel", [(1, 1, z) for z in range(1, 6)])
    t.prop("banner_red", 2, 0, 0)
    out.append(t)

    t = Template("barracks", "Barracks.tres", "Kaserne",
                 "5×3 Felder Steinbau mit Bogentür und zwei Bogenfenstern, Steindach: Waffenständer an der Rückwand, Tisch mit Bank, Holzstapel "
                 "und Fass. Draußen zwei Fahnen und Eisenlaternen am Eingang. Größerer Bruder des Wachpostens.")
    t.floor("stone_floor", cells(0, 0, 5, 3))
    r = Template.ring_edges(0, 0, 5, 3)
    for edge in r["N"] + r["S"] + r["W"] + r["E"]:
        if edge == (0, 1, 3):
            t.wall("stone_arch_door", DOOR, *edge)
        elif edge in {(0, 3, 3), (1, 5, 1)}:
            t.wall("stone_arch_window", WINDOW, *edge)
        else:
            t.wall("stone_wall", WALL, *edge)
    t.roof("stone_roof", cells(0, 0, 5, 3), 0)
    t.prop("weapon_rack", 0, 0, 0)
    t.prop("weapon_rack", 1, 0, 0)
    t.prop("weapon_rack", 2, 0, 0)
    t.prop("woodpile", 4, 0, 0)
    t.prop("table_wood", 3, 1, 0)
    t.prop("bench_wood", 4, 1, 1)
    t.prop("barrel", 4, 2, 0)
    t.prop("banner_red", 0, 3, 0)
    t.prop("banner_red", 2, 3, 0)
    t.prop("street_lamp_iron", 3, 3, 0)
    out.append(t)

    t = Template("feast_hall", "FeastHall.tres", "Festhalle",
                 "7×5 Felder lange Holzhalle: nur die beiden Langseiten sind Wand (mit Bogenfenstern), die Giebelseiten bleiben offen zwischen "
                 "Holzsäulen. Ein einziges Dach überspannt die ganze Halle (Überhang bis zwei Zellen). Vier Tische mit Hockern, Feuerstelle in "
                 "der Mitte, Fahnen und Fässer. Mitte anvisieren und dort stehen.")
    t.floor("wood_floor", cells(0, 0, 7, 5))
    r = Template.ring_edges(0, 0, 7, 5)
    for edge in r["N"] + r["S"]:
        if edge[1] in (1, 3, 5):
            t.wall("wood_arch_window", WINDOW, *edge)
        else:
            t.wall("wood_wall", WALL, *edge)
    t.roof("wood_roof", cells(0, 0, 7, 5), 0)
    for cx, cz in ((0, 1), (0, 3), (6, 1), (6, 3)):
        t.prop("pillar_wood", cx, cz, 0)
    for cx, cz in ((2, 1), (4, 1), (2, 3), (4, 3)):
        t.prop("table_wood", cx, cz, 0)
    t.prop("firepit", 3, 2, 0)
    t.prop("banner_red", 1, 2, 0)
    t.prop("banner_red", 5, 2, 0)
    t.prop("barrel", 1, 0, 0)
    t.prop("barrel", 5, 0, 0)
    t.prop("street_lamp_wood", -1, 2, 0)
    t.prop("street_lamp_wood", 7, 2, 0)
    out.append(t)

    t = Template("fortress_yard", "FortressYard.tres", "Wehrhof",
                 "6×5 Felder Festungshof: hohe Zinnenmauer, vier Rundtürme an den Ecken, Torturm an der Südfront (begehbare Durchfahrt), "
                 "im Hof Brunnen, Waffenständer, Holzstapel, Fass, Handkarren, Feuerstelle, Bank und Fahnen, gepflasterter Weg vom Tor. "
                 "Größte Struktur des Wehrbaus — Mitte des Hofes anvisieren und dort stehen.")
    r = Template.ring_edges(0, 0, 6, 5)
    walls = [e for e in r["N"] + r["S"] + r["W"] + r["E"] if e != (0, 3, 5)]   # Durchfahrt des Torturms
    t.walls_on("stone_wall_crenel", walls)
    for cx, cz in ((0, 0), (6, 0), (0, 5), (6, 5)):
        t.prop("tower_stone_round", cx, cz, 0)
    t.prop("gatehouse", 3, 4, 0)
    t.floor("stone_floor", [(3, 2), (3, 3)])
    t.prop("well", 3, 1, 0)
    t.prop("weapon_rack", 1, 0, 0)
    t.prop("weapon_rack", 2, 0, 0)
    t.prop("woodpile", 5, 0, 0)
    t.prop("barrel", 4, 0, 0)
    t.prop("hand_cart", 5, 3, 3)
    t.prop("firepit", 1, 3, 0)
    t.prop("bench_wood", 1, 2, 1)
    t.prop("banner_red", 2, 3, 0)
    t.prop("banner_red", 4, 3, 0)
    t.prop("street_lamp_iron", 2, 2, 0)
    t.prop("street_lamp_iron", 4, 2, 0)

    # ───────── Wehrgänge und Großtor (Ebenen-Einträge: storey 1 = Mauerkrone) ─────────
    t = Template("wall_walk", "WallWalk.tres", "Mauer mit Wehrgang",
                 "6 Felder Steinmauer mit Wehrgang: Zinnen-Brüstung außen, begehbarer Gang (2 m breit) auf der Mauerkrone, "
                 "Holzgeländer innen und eine Steintreppe in der Westecke. In Reihe stellbar; die Treppe nur am Anfang nötig.")
    t.walls_on("stone_wall", [(0, x, 1) for x in range(6)])
    t.walls_on("stone_parapet", [(0, x, 1) for x in range(6)], storey=1)
    t.floor("stone_walkway", [(x, 1) for x in range(6)], storey=1)
    t.walls_on("wood_fence", [(0, x, 2) for x in range(1, 6)], storey=1)
    t.stairs("stone_stairs", 0, 2, 2)
    t.prop("street_lamp_iron", 5, 2, 0)
    out.append(t)

    t = Template("city_gate_grand", "CityGateGrand.tres", "Großes Stadttor",
                 "14 m breite Torfront mit DREI Rundbogen-Toren nebeneinander (Holzflügel offen), zwei Rundtürmen, Zinnenbrüstung und "
                 "durchgehendem Wehrgang über den Toren, zwei Treppen auf die Mauerkrone, Pflaster durch die Tore. "
                 "Mitte anvisieren und dort stehen.")
    t.prop("tower_stone_round", 0, 0, 0)
    t.prop("tower_stone_round", 6, 0, 0)
    t.walls_on("stone_wall", [(0, 1, 1), (0, 5, 1)])
    t.walls_on("wood_gate_open", [(0, x, 1) for x in (2, 3, 4)], kind=DOOR)
    t.floor("stone_floor", cells(2, 0, 3, 2))
    t.walls_on("stone_parapet", [(0, x, 1) for x in range(1, 6)], storey=1)
    t.floor("stone_walkway", [(x, 1) for x in range(1, 6)], storey=1)
    t.walls_on("wood_fence", [(0, x, 2) for x in (2, 3, 4)], storey=1)
    t.stairs("stone_stairs", 1, 2, 2)
    t.stairs("stone_stairs", 5, 2, 2)
    t.prop("banner_red", 1, 0, 0)
    t.prop("banner_red", 5, 0, 0)
    out.append(t)

    return out


def main() -> int:
    check_only = "--check" in sys.argv
    known = load_piece_kinds()
    problems: list[str] = []
    templates = make_all()
    for t in templates:
        errs = t.validate(known)
        problems += errs
        counts = {}
        for e in t.entries.values():
            counts[e["piece_id"]] = counts.get(e["piece_id"], 0) + 1
        print(f"{t.tid:15s} {len(t.entries):3d} Teile, größter Abstand zur Mitte {getattr(t, 'reach_from_center', 0):4.1f} m")
        if not check_only and not errs:
            (HOUSES / t.filename).write_text(t.to_tres(), encoding="utf-8")
    for p in problems:
        print("FEHLER:", p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
# scripts/agent/analyze_native_signals.py
#
# DEBUG-COMMAND für Agents — Kategorisierung nativer `signal`-Deklarationen
# als Vorstufe zur EventBus->Domain-Event-Migration (TODO-offene-probleme.md
# Punkt 5). Reines Analyse-Tool, führt KEINE Änderungen durch — Output ist
# die Datengrundlage für das dort geforderte Konzept/ADR, nicht der Code
# selbst (der kommt laut TODO erst nach der ADR-Entscheidung).
#
# Frage pro Signal: bleibt es ein natives, lokales `signal` (ADR-012-konforme
# Zielarchitektur erlaubt das für eng begrenzte Parent-Child/UI-Verdrahtung),
# oder ist es De-facto ein zweiter, EventBus-paralleler Kanal für eine
# schichtübergreifende Tatsache (Migrationskandidat)?
#
# Kategorien:
#   LOCAL        — kein .connect() außerhalb der deklarierenden Datei
#                  (Tests ausgenommen, siehe unten). Bleibt natives Signal.
#   CROSS_LAYER  — mind. ein .connect() aus einer anderen, nicht-Test-Datei.
#                  Migrationskandidat für den Domain-Event-Layer.
#   NEEDS_HUMAN  — Name kollidiert mit einer weiteren `signal`-Deklaration
#                  irgendwo im Projekt. Aus dem Quelltext allein ist dann
#                  nicht sicher feststellbar, welcher Instanz ein gegebener
#                  `x.signal_name.connect(...)`-Aufruf tatsächlich gilt
#                  (kein Typ-Checker hier) — kein Raten, sondern explizit
#                  als klärungsbedürftig markiert.
#
# Methodik-Korrektur (Round 110, während des Baus dieses Tools gefunden):
# tests/-Dateien zählen bei der Klassifikation NICHT als externe Kopplung.
# Ein Unit-Test der ein Signal beobachtet (`.connect()` um ein Signal zu
# assert-en) ist kein Business-Konsument — er beweist nur, dass das Signal
# feuert. Ohne diesen Ausschluss wäre praktisch jedes Signal mit einem
# eigenen Test fälschlich CROSS_LAYER gewesen (jedes der 99 Signale hat im
# Schnitt >=1 Test der es beobachtet). Test-Connects werden separat gezählt
# (test_observer_files), fließen aber nicht in die LOCAL/CROSS_LAYER/
# NEEDS_HUMAN-Entscheidung ein.
#
# Verwendung:
#   python3 scripts/agent/analyze_native_signals.py            # JSON (Default)
#   python3 scripts/agent/analyze_native_signals.py --pretty   # Menschenlesbar
#   python3 scripts/agent/analyze_native_signals.py --write-report  # + docs/manager/reports/

from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS_DIR = PROJECT_ROOT / "scripts"
TESTS_DIR = PROJECT_ROOT / "tests"
REPORT_PATH = PROJECT_ROOT / "docs" / "manager" / "reports" / "native-signal-categorization.md"
PROJECT_GODOT = PROJECT_ROOT / "project.godot"

SIGNAL_DECL_RE = re.compile(r"^\s*signal\s+(\w+)\s*(\([^)]*\))?", re.M)
CLASS_NAME_RE = re.compile(r"^class_name\s+(\w+)", re.M)
EXTENDS_BASEEVENTS_RE = re.compile(r"extends\s+BaseEvents\b")

# DI-Lookup-Marker (Round 110): jeder Aufruf, der ein Objekt über den
# Service-Container statt über direkte Konstruktion/Parameterübergabe
# beschafft. Deckt die drei im Projekt genutzten DI-Pfade ab:
#   - ServiceRegistry.get_service(...)
#   - ctx.get_X()/_ctx.get_X() (IUIContext-/IEntityContext-Accessor)
#   - ServiceDeps.require(...)/get_optional(...)
DI_LOOKUP_RE = re.compile(r"\b(?:get_service|deps\.(?:require|get_optional)|\w*ctx\.get_\w+)\s*\(")

# Direkte Konstruktion (`X.new(...)`) ODER Scene-Tree-Traversal
# (`get_parent()`, `get_node(...)`, `$Path`). Beides ist "direkt hereingereicht"
# im Sinne der Round-110-Regel: kein DI-Container beteiligt, sondern entweder
# frisch gebaut oder aus der bekannten Node-Hierarchie geholt (ADR-012 erlaubt
# native Signale explizit für Parent-Child-Verdrahtung).
DIRECT_CONSTRUCT_RE = re.compile(r"\.new\s*\(")
SCENE_TREE_RE = re.compile(r"\bget_parent\s*\(|\bget_node\s*\(|\$\w")

# Funktionsaufruf ohne Punkt davor (lokal, z.B. `_svc()`) ODER mit
# GROSSGESCHRIEBENEM Klassen-Prefix (statischer Aufruf, z.B.
# `PlayerSetup.build(self)`). Beliebige Argumente erlaubt (kein `\(\)`-
# Zwang mehr — sonst wird z.B. `_build_health(player)` nicht erkannt).
# Instanz-Methodenaufrufe auf kleingeschriebenen Objekt-Variablen
# (`hud.something()`) matchen bewusst NICHT — deren Herkunft ist ohne
# Typ-Info nicht sicher auflösbar.
INLINE_CALL_RE = re.compile(r"(?<![.\w])(?:([A-Z]\w*)\.)?([A-Za-z_]\w*)\([^()]*\)")
CALL_RE = re.compile(r"^(?:([A-Za-z_]\w*)\.)?([A-Za-z_]\w*)\((?:[^()]*)\)$")
SUBSCRIPT_RE = re.compile(r"^([A-Za-z_]\w*)\s*\[\s*['\"](\w+)['\"]\s*\]$")
FUNC_DEF_RE_TMPL = r"^(?:static\s+)?func\s+{fn}\s*\([^)]*\)\s*(?:->\s*[\w\[\].]+\s*)?:"

# Godot-Builtins, die zufällig auf INLINE_CALL_RE passen (Null/Objekt-
# Argument-Aufruf ohne Klassen-Prefix) aber sicher keine lokale
# Helper-Funktion sind — spart nutzlose Regex-Suchen.
NOT_LOCAL_HELPERS = {"is_instance_valid", "is_instance_of", "is_instance"}


def _load_autoload_names() -> set[str]:
    """Liest die `[autoload]`-Sektion aus project.godot. AutoLoads sind
    globale Singletons — von jedem Script aus ohne DI erreichbar. Das ist
    architektonisch die stärkste Form von Cross-Layer-Kopplung, die es gibt
    (globaler State), auch wenn kein `get_service()`/`ctx.get_X()` beteiligt
    ist. Zugriff auf einen AutoLoad-Namen zählt daher wie ein DI-Lookup."""
    if not PROJECT_GODOT.exists():
        return set()
    raw = PROJECT_GODOT.read_text(encoding="utf-8", errors="replace")
    m = re.search(r"^\[autoload\](.*?)(?:\n\[|\Z)", raw, re.S | re.M)
    if not m:
        return set()
    return set(re.findall(r"^(\w+)\s*=", m.group(1), re.M))


AUTOLOAD_NAMES = _load_autoload_names()

_RAW_CACHE: dict[Path, str] = {}


def _read_raw(path: Path) -> str:
    if path not in _RAW_CACHE:
        _RAW_CACHE[path] = path.read_text(encoding="utf-8", errors="replace")
    return _RAW_CACHE[path]


def _load_class_index() -> dict[str, Path]:
    """class_name -> Datei. Für die Auflösung qualifizierter statischer
    Aufrufe (`PlayerSetup.build(self)`), die eine andere Datei treffen als
    die, in der gerade gesucht wird. Wird erst nach der Definition von
    iter_gd_files() unten am Modulende befüllt (siehe CLASS_FILE_INDEX)."""
    idx: dict[str, Path] = {}
    for gd in iter_gd_files():
        if gd.parent == TESTS_DIR or TESTS_DIR in gd.parents:
            continue
        raw = _read_raw(gd)
        m = CLASS_NAME_RE.search(raw)
        if m:
            idx[m.group(1)] = gd
    return idx

# Godot-Engine-eingebaute Node-Properties/Singletons, die zufällig gleich
# benannte Signale wie unsere eigenen tragen (z.B. `multiplayer.connection_
# failed` = MultiplayerAPI-eigenes Signal, nicht unser NetworkBridge-Signal).
# Ein `.connect()` auf so einen Namen ist ein Fehltreffer der reinen
# Namens-Regex in collect_connects(), kein echter Connect auf unser Signal —
# wird daher aus der Provenance-Bewertung rausgefiltert statt als UNKNOWN
# gezählt (siehe categorize()).
ENGINE_BUILTIN_SINGLETONS = {"multiplayer"}


def iter_gd_files():
    """Alle .gd-Dateien unter scripts/ und tests/, keine .bak-Reste."""
    for root in (SCRIPTS_DIR, TESTS_DIR):
        if root.exists():
            for p in root.rglob("*.gd"):
                if p.suffix == ".gd" and not p.name.endswith(".gd.bak"):
                    yield p


CLASS_FILE_INDEX = _load_class_index()


def is_events_file(raw: str) -> bool:
    """*Events.gd-Dateien (EventBus-Signal-Container) sind hier nicht das
    Ziel — die haben ihren eigenen Pfad-A/Pfad-B-Graphen in service_graph.py.
    Dieses Tool ist ausschließlich für native Klassen-Signale."""
    return bool(EXTENDS_BASEEVENTS_RE.search(raw))


def collect_declarations() -> dict[str, list[dict]]:
    """signal_name -> Liste aller Deklarationsstellen (normalerweise 1, bei
    Namenskollision >1)."""
    decls: dict[str, list[dict]] = defaultdict(list)
    for gd in iter_gd_files():
        if gd.parent == TESTS_DIR or TESTS_DIR in gd.parents:
            continue  # Tests deklarieren keine Produktions-Signale
        raw = gd.read_text(encoding="utf-8", errors="replace")
        if is_events_file(raw):
            continue
        cls_m = CLASS_NAME_RE.search(raw)
        class_name = cls_m.group(1) if cls_m else None
        for m in SIGNAL_DECL_RE.finditer(raw):
            decls[m.group(1)].append({
                "file": str(gd.relative_to(PROJECT_ROOT)),
                "class_name": class_name,
                "params": (m.group(2) or "()").strip(),
            })
    return decls


def collect_connects(signal_names: set[str]) -> dict[str, list[str]]:
    """signal_name -> Liste aller Dateien (rel. Pfad) mit mind. einem
    '<irgendwas>.<signal_name>.connect(' ODER bloßem '<signal_name>.connect('.
    Eine Datei kann mehrfach ein Signal connecten — hier reicht die Menge der
    Dateien, nicht die Trefferzahl (Kopplungsfrage ist 'wer', nicht 'wie oft')."""
    connects: dict[str, set[str]] = defaultdict(set)
    name_alt = "|".join(re.escape(n) for n in sorted(signal_names))
    if not name_alt:
        return {}
    re_connect = re.compile(rf"(?:^|[.\s(=,])({name_alt})\.connect\s*\(", re.M)
    for gd in iter_gd_files():
        raw = gd.read_text(encoding="utf-8", errors="replace")
        if is_events_file(raw):
            continue
        rel = str(gd.relative_to(PROJECT_ROOT))
        for sig in set(re_connect.findall(raw)):
            connects[sig].add(rel)
    return {k: sorted(v) for k, v in connects.items()}


def is_test_file(rel_path: str) -> bool:
    return rel_path.startswith("tests/") or rel_path.startswith("tests\\")


def _dirname(rel_path: str) -> str:
    return str(Path(rel_path).parent)


def _extract_receiver(raw: str, signal: str) -> list[str]:
    """Für jeden `<receiver>.<signal>.connect(`-Treffer in `raw`: der Text
    vom Zeilenanfang (nach Tabs/Spaces) bis zum Receiver. Mehrere Treffer
    möglich (Signal wird evtl. mehrfach in derselben Datei connectet)."""
    out = []
    for m in re.finditer(rf"^[\t ]*(.*?)\.{re.escape(signal)}\.connect\s*\(", raw, re.M):
        out.append(m.group(1))
    return out


def _resolve_provenance(raw: str, receiver: str) -> str:
    """Bestimmt, wie der Receiver-Ausdruck eines .connect()-Aufrufs an sein
    Objekt gekommen ist. Rückgabe: 'DI' | 'AUTOLOAD' | 'DIRECT' |
    'ENGINE_BUILTIN' | 'UNKNOWN'.

    Regel (Round 110): ein natives Signal bleibt nativ genau dann, wenn
    JEDER Connector das Objekt direkt konstruiert/übergeben bekommen hat
    (Parameter, `X.new(...)`, oder Scene-Tree-Traversal), nie über DI/
    Service-Registry/AutoLoad geholt. Sobald ein Connector das Objekt per
    `get_service()`/`ctx.get_X()`/`deps.require()`/AutoLoad-Namen bezieht,
    hat die Signal-Deklaration die Schichtgrenze überquert.
    """
    # Fall 1: DI-Lookup direkt im Receiver-Ausdruck selbst, z.B.
    # `_ctx.get_trade_service().session_started.connect(...)`.
    if DI_LOOKUP_RE.search(receiver):
        return "DI"

    m = re.search(r"([A-Za-z_]\w*)\s*$", receiver)
    if not m:
        return "UNKNOWN"
    var = m.group(1)

    # Fall 2: Godot-Engine-Singleton-Property, die zufällig gleich benannte
    # Signale trägt wie unsere eigenen (z.B. `multiplayer.connection_failed`).
    # Kein echter Connect auf unser Signal — separat markiert, siehe
    # ENGINE_BUILTIN_SINGLETONS oben und Filterung in categorize().
    if var in ENGINE_BUILTIN_SINGLETONS:
        return "ENGINE_BUILTIN"

    # Fall 3: AutoLoad-Name — globaler Singleton, per Definition
    # schichtübergreifend erreichbar, auch ohne get_service()/ctx.get_X().
    if var in AUTOLOAD_NAMES:
        return "AUTOLOAD"

    # Fall 4: Receiver ist eine (ggf. dot-qualifizierte) Variable, z.B.
    # `_visuals` oder `self._visuals`. Basisname im selben File auflösen.
    return _resolve_var(raw, var, set(), set())


ASSIGN_RE_TMPL = r"^\s*(?:var\s+)?{var}\s*(?::=|:\s*[\w\[\]]+\s*=|=)\s*(.+?)\s*$"
LITERAL_IDENTIFIERS = {"null", "true", "false"}


def _reduce(verdicts: set) -> str:
    if "DI" in verdicts:
        return "DI"
    if "AUTOLOAD" in verdicts:
        return "AUTOLOAD"
    if "DIRECT" in verdicts:
        return "DIRECT"
    return "UNKNOWN"


def _function_body(raw: str, funcname: str) -> str | None:
    """Text-Body einer `func <funcname>(...):`-Definition im gegebenen File,
    bis zur nächsten Top-Level-`func`-Definition oder Dateiende."""
    def_m = re.search(FUNC_DEF_RE_TMPL.format(fn=re.escape(funcname)), raw, re.M)
    if not def_m:
        return None
    start = def_m.end()
    next_m = re.search(r"^(?:static\s+)?func\s+\w+\s*\(", raw[start:], re.M)
    return raw[start:start + next_m.start()] if next_m else raw[start:]


def _eval_expr(raw: str, expr: str, var_seen: set, call_seen: set) -> str:
    """Bewertet einen einzelnen Ausdruck (Zuweisungs-RHS oder Return-Wert):
    DI/AUTOLOAD, DIRECT (Konstruktion/Scene-Tree), oder rekursiv über
    enthaltene bloße Bezeichner, Dictionary-Subscripts oder Funktionsaufrufe
    (lokal ODER qualifiziert über eine andere Klasse) aufgelöst.

    `var_seen` verhindert Zirkel bei Variablen-Ketten INNERHALB des aktuellen
    Scopes; wird an Funktionsgrenzen zurückgesetzt, weil zwei verschiedene
    Funktionen im selben File zufällig gleichnamige lokale Variablen haben
    können (z.B. `health` in zwei verschiedenen Setup-Funktionen). `call_seen`
    verhindert Zirkel bei Funktionsaufrufen (A ruft B ruft A) und gilt über
    die ganze Kette hinweg."""
    if DI_LOOKUP_RE.search(expr):
        return "DI"
    if DIRECT_CONSTRUCT_RE.search(expr) or SCENE_TREE_RE.search(expr):
        return "DIRECT"

    verdicts = set()
    stripped = expr.strip()

    # Ganzer Ausdruck ist ein bloßer Bezeichner, z.B. `_visuals = visuals`.
    bare_m = re.fullmatch(r"[A-Za-z_]\w*", stripped)
    if bare_m and bare_m.group(0) not in LITERAL_IDENTIFIERS:
        verdicts.add(_resolve_var(raw, bare_m.group(0), var_seen, call_seen))

    # Dictionary-Subscript, z.B. `subs["health"]` — Basisvariable zu einer
    # Dict-literal-Return-Stelle zurückverfolgen (lokal oder über eine
    # statische Methode einer anderen Klasse) und den Wert für den Key
    # rekursiv auswerten.
    sub_m = SUBSCRIPT_RE.match(stripped)
    if sub_m:
        base, key = sub_m.groups()
        result = _resolve_dict_value(raw, base, key, set(), call_seen)
        if result:
            value_expr, value_raw = result
            verdicts.add(_eval_expr(value_raw, value_expr, set(), call_seen))

    # Funktionsaufrufe irgendwo im Ausdruck (lokal `_svc()` oder qualifiziert
    # `PlayerSetup.build(self)`), z.B. in `_svc() if is_instance_valid(_ctx)
    # else null`.
    for call_m in INLINE_CALL_RE.finditer(expr):
        prefix, fname = call_m.groups()
        verdicts.add(_resolve_call(raw, prefix, fname, call_seen))

    return _reduce(verdicts)


def _resolve_call(raw: str, prefix: str | None, funcname: str, call_seen: set) -> str:
    """Löst einen Funktionsaufruf auf: lokal (`prefix` None, gleiches File)
    oder qualifiziert-statisch (`prefix` = Klassenname, über CLASS_FILE_INDEX
    in die passende Datei gewechselt). Bewertet alle `return`-Ausdrücke im
    Funktionskörper. `call_seen` verhindert Rekursions-Zirkel; wird beim
    Wechsel in den Funktionskörper NICHT zurückgesetzt (anders als
    `var_seen` in _eval_expr), weil A->B->A eine echte Endlosschleife wäre."""
    if funcname in NOT_LOCAL_HELPERS:
        return "UNKNOWN"

    if prefix:
        target_path = CLASS_FILE_INDEX.get(prefix)
        if not target_path:
            return "UNKNOWN"  # z.B. eingebaute Godot-Klasse, kein Projekt-File
        target_raw = _read_raw(target_path)
        key = f"{prefix}.{funcname}"
    else:
        target_raw = raw
        key = funcname

    if key in call_seen:
        return "UNKNOWN"
    call_seen = call_seen | {key}

    body = _function_body(target_raw, funcname)
    if not body:
        return "UNKNOWN"

    verdicts = set()
    for ret_m in re.finditer(r"^\s*return\s+(.+?)\s*$", body, re.M):
        verdicts.add(_eval_expr(target_raw, ret_m.group(1), set(), call_seen))
    return _reduce(verdicts)


def _resolve_dict_value(raw: str, var: str, key: str, var_seen: set, call_seen: set):
    """Verfolgt `var` zu einer Dictionary-literal-Return-Stelle (lokal oder
    über eine qualifizierte statische Methode, z.B. `PlayerSetup.build(...)`,
    die eine Factory-Funktion mit Argumenten ist — kein Ein-Hop-Nullargument-
    Aufruf mehr wie bei _resolve_call, sondern beliebige Argumente über
    CALL_RE) und liefert (Wert-Ausdruck-für-`key`, Raw-Datei-in-der-er-steht)
    oder None, falls nicht auflösbar."""
    if var in var_seen:
        return None
    var_seen = var_seen | {var}

    for am in re.finditer(ASSIGN_RE_TMPL.format(var=re.escape(var)), raw, re.M):
        rhs = am.group(1).strip()
        call_m = CALL_RE.fullmatch(rhs)
        if call_m:
            prefix, funcname = call_m.groups()
            if prefix:
                target_path = CLASS_FILE_INDEX.get(prefix)
                if not target_path:
                    continue
                target_raw = _read_raw(target_path)
            else:
                target_raw = raw
            body = _function_body(target_raw, funcname)
            if not body:
                continue
            dict_m = re.search(r"return\s*\{(.*?)\n\s*\}", body, re.S)
            if not dict_m:
                continue
            val = _lookup_dict_key(dict_m.group(1), key)
            if val is not None:
                return val, target_raw
            continue

        bare_m = re.fullmatch(r"[A-Za-z_]\w*", rhs)
        if bare_m:
            result = _resolve_dict_value(raw, bare_m.group(0), key, var_seen, call_seen)
            if result:
                return result
    return None


def _lookup_dict_key(dict_body: str, key: str) -> str | None:
    m = re.search(rf"""['"]{re.escape(key)}['"]\s*:\s*(.+?)\s*,?\s*$""", dict_body, re.M)
    return m.group(1) if m else None


def _resolve_var(raw: str, var: str, var_seen: set, call_seen: set) -> str:
    """Löst die Herkunft einer einzelnen Variable auf: DI/AUTOLOAD, wenn
    irgendeine Zuweisung/Parameterbindung das ergibt; sonst DIRECT, wenn
    irgendeine auf direkte Konstruktion, Scene-Tree-Zugriff oder eine als
    Parameter empfangene Variable zurückgeht; sonst UNKNOWN. Prüft ALLE
    Zuweisungen im File (nicht nur die erste) — eine Feld-Deklaration
    `var _network = null` ist sonst fälschlich die einzige gefundene
    'Zuweisung', während die eigentliche Injektion später über eine
    Setter-Methode passiert."""
    if var in var_seen or var in LITERAL_IDENTIFIERS:
        return "UNKNOWN"
    if var in AUTOLOAD_NAMES:
        return "AUTOLOAD"
    var_seen = var_seen | {var}

    verdicts = set()

    # Parameterübergabe: `func setup(visuals: TradeVisuals, ...)` — das
    # Objekt wurde direkt hereingereicht, unabhängig davon wie der Aufrufer
    # selbst daran gekommen ist (das ist dessen Schicht, nicht diese).
    if re.search(rf"func\s+\w+\s*\([^)]*\b{re.escape(var)}\b[^)]*\)", raw):
        verdicts.add("DIRECT")

    for am in re.finditer(ASSIGN_RE_TMPL.format(var=re.escape(var)), raw, re.M):
        verdicts.add(_eval_expr(raw, am.group(1), var_seen, call_seen))

    return _reduce(verdicts)


def categorize(decls: dict[str, list[dict]], connects: dict[str, list[str]]) -> dict:
    """Kategorisierung. Für Namenskollisionen bleibt NEEDS_HUMAN (kein
    Typ-Checker verfügbar, um zu wissen welche Deklaration ein `.connect()`
    meint — unabhängig von DI).

    Für alles andere gilt die DI-Lookup-Regel aus Round 110 statt der alten
    Ordner-Heuristik ('gleiches ui/-Verzeichnis'): 'anderes File' != 'andere
    Schicht' — entscheidend ist nicht WO der Connector liegt, sondern WIE er
    an sein Objekt kommt. DI/Service-Registry-Lookup überquert per
    Definition die Schichtgrenze; direkte Konstruktion/Parameterübergabe tut
    das nicht, selbst über Dateigrenzen hinweg (z.B. eine Factory, die
    `TradeVisuals.new(hud)` baut und direkt an `TradeUIController.setup()`
    reicht). Siehe DI_LOOKUP_RE/_resolve_provenance() oben."""
    results = {}
    for name, decl_list in sorted(decls.items()):
        decl_files = {d["file"] for d in decl_list}
        connect_files = connects.get(name, [])
        test_observers = [f for f in connect_files if is_test_file(f)]
        non_test_connects = [f for f in connect_files if not is_test_file(f)]
        external_non_test = [f for f in non_test_connects if f not in decl_files]

        provenance_detail = []  # zur Nachvollziehbarkeit im Report

        if len(decl_list) > 1:
            category = "NEEDS_HUMAN"
            reason = (f"Name-Kollision: {len(decl_list)} unabhängige Deklarationen "
                      f"({', '.join(sorted(decl_files))}) — welcher .connect()-Aufruf "
                      f"zu welcher gehört ist ohne Typ-Checker nicht sicher auflösbar.")
        elif external_non_test:
            verdicts = set()
            real_files = []  # Files mit mind. 1 echtem (Nicht-ENGINE_BUILTIN) Connect
            for f in external_non_test:
                raw = (PROJECT_ROOT / f).read_text(encoding="utf-8", errors="replace")
                receivers = _extract_receiver(raw, name)
                if not receivers:
                    # Sollte nicht vorkommen (collect_connects fand ja einen
                    # Treffer), defensiv trotzdem abgedeckt.
                    verdicts.add("UNKNOWN")
                    provenance_detail.append(f"{f}: Receiver nicht extrahierbar")
                    real_files.append(f)
                    continue
                file_is_real = False
                for recv in receivers:
                    v = _resolve_provenance(raw, recv)
                    provenance_detail.append(f"{f}: `{recv.strip()}` -> {v}")
                    if v == "ENGINE_BUILTIN":
                        continue  # Fehltreffer auf Godot-Singleton, kein echter Connect
                    file_is_real = True
                    verdicts.add(v)
                if file_is_real:
                    real_files.append(f)

            if not real_files:
                category = "LOCAL"
                reason = (f"{len(external_non_test)} externe(s) Nicht-Test-Connect(s), aber "
                          f"alle erweisen sich als Godot-Engine-Singleton-Fehltreffer der "
                          f"Namens-Regex ({'; '.join(provenance_detail)}) — kein echter "
                          f"Connect auf dieses Signal. Bleibt natives Signal.")
            elif "DI" in verdicts or "AUTOLOAD" in verdicts:
                category = "CROSS_LAYER"
                di_files = [d for d in provenance_detail if d.endswith("-> DI")]
                autoload_files = [d for d in provenance_detail if d.endswith("-> AUTOLOAD")]
                parts = []
                if di_files:
                    parts.append(f"DI/Service-Registry-Lookup ({'; '.join(di_files)})")
                if autoload_files:
                    parts.append(f"AutoLoad-Zugriff ({'; '.join(autoload_files)})")
                reason = (f"{len(real_files)} echte(s) externe(s) Connect(s), mind. einer "
                          f"überquert die Schichtgrenze per {' und '.join(parts)}. "
                          f"Schichtübergreifende Kopplung.")
            elif verdicts <= {"DIRECT"} and verdicts:
                category = "LOCAL"
                reason = (f"{len(real_files)} echte(s) externe(s) Connect(s), aber alle "
                          f"beziehen das Objekt direkt konstruiert/als Parameter/Scene-Tree-"
                          f"Zugriff übergeben (kein DI-Lookup) — bleibt natives Signal trotz "
                          f"Dateigrenze.")
            else:
                category = "NEEDS_HUMAN"
                reason = (f"Herkunft des Receiver-Objekts bei mind. einem externen Connect "
                          f"nicht sicher auflösbar (kein Parameter, keine einfache "
                          f"Zuweisung/`.new()`/Scene-Tree-Zugriff/lokaler Ein-Hop-Funktions-"
                          f"aufruf im selben File gefunden): {'; '.join(provenance_detail)}. "
                          f"Manuell prüfen.")
        else:
            category = "LOCAL"
            reason = "Kein externer Nicht-Test-Connect gefunden — bleibt natives Signal."

        results[name] = {
            "declarations": decl_list,
            "category": category,
            "reason": reason,
            "external_non_test_connects": sorted(external_non_test),
            "test_observer_files": sorted(test_observers),
            "provenance_detail": provenance_detail,
        }
    return results


def write_report(results: dict) -> None:
    counts = defaultdict(int)
    for r in results.values():
        counts[r["category"]] += 1
    lines = [
        "# Native-Signal-Kategorisierung (Grundlage für TODO Punkt 5 / ADR)",
        "",
        f"Automatisch generiert von `scripts/agent/analyze_native_signals.py`. "
        f"{len(results)} native Signale geprüft.",
        "",
        f"- LOCAL: {counts['LOCAL']}",
        f"- CROSS_LAYER: {counts['CROSS_LAYER']}",
        f"- NEEDS_HUMAN: {counts['NEEDS_HUMAN']}",
        "",
        "Methodik: tests/-Connects zählen nicht als externe Kopplung (Round 110 "
        "Methodik-Korrektur — ein Unit-Test der ein Signal beobachtet ist kein "
        "Business-Konsument). Siehe Tool-Header für Details.",
        "",
        "## CROSS_LAYER — Migrationskandidaten",
        "",
    ]
    for name, r in sorted(results.items()):
        if r["category"] != "CROSS_LAYER":
            continue
        d = r["declarations"][0]
        lines.append(f"- `{name}` ({d['file']}, class `{d['class_name']}`) — "
                      f"connect von: {', '.join(r['external_non_test_connects'])}")
    lines += ["", "## NEEDS_HUMAN — manuell klären", ""]
    for name, r in sorted(results.items()):
        if r["category"] != "NEEDS_HUMAN":
            continue
        lines.append(f"- `{name}` — {r['reason']}")
    lines += ["", "## LOCAL — bleibt natives Signal", ""]
    for name, r in sorted(results.items()):
        if r["category"] != "LOCAL":
            continue
        d = r["declarations"][0]
        lines.append(f"- `{name}` ({d['file']})")
    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")


def print_pretty(results: dict) -> None:
    counts = defaultdict(int)
    for r in results.values():
        counts[r["category"]] += 1
    print(f"\n{len(results)} native Signale kategorisiert.\n")
    print(f"  LOCAL:       {counts['LOCAL']}")
    print(f"  CROSS_LAYER: {counts['CROSS_LAYER']}")
    print(f"  NEEDS_HUMAN: {counts['NEEDS_HUMAN']}\n")
    for cat in ("NEEDS_HUMAN", "CROSS_LAYER", "LOCAL"):
        names = [n for n, r in results.items() if r["category"] == cat]
        if not names:
            continue
        print(f"--- {cat} ({len(names)}) ---")
        for n in sorted(names):
            print(f"  {n}: {results[n]['reason']}")
        print()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pretty", action="store_true")
    ap.add_argument("--write-report", action="store_true")
    args = ap.parse_args()

    decls = collect_declarations()
    connects = collect_connects(set(decls.keys()))
    results = categorize(decls, connects)

    if args.write_report:
        write_report(results)
        print(f"Report geschrieben: {REPORT_PATH.relative_to(PROJECT_ROOT)}")

    if args.pretty:
        print_pretty(results)
    else:
        print(json.dumps(results, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()

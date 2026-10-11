#!/usr/bin/env python3
# scripts/agent/service_graph.py
#
# DEBUG-COMMAND für Agents — Service-Dependency-Graph mit Siblings & Risk.
#
# Zweck:
#   Bevor ein Service angefasst/ergänzt wird, soll der Agent hier sehen können
#   *wie er im Gesamtsystem hängt*, statt sich per grep ein unvollständiges Bild
#   zusammenzusuchen. Liest ausschließlich Projektdateien (BootstrapConfig.tres,
#   ServiceKeys.gd, BootPipeline.gd, *.gd), führt KEINE Änderungen durch.
#
#   Prüft strukturell genau die Fehlerklassen, die in diesem Projekt bereits
#   dokumentiert als real aufgetreten gelten (siehe ADR-017-Kommentar in
#   BootPipeline.gd zur Cross-Scope-Bridge):
#
#     - BROKEN_DEP        — deps-Eintrag zeigt auf keinen bekannten Service/
#                            keine bekannte Resource/kein Infra-Key.
#     - MISSING_FILE       — path in ServiceDefinition zeigt auf keine
#                            existierende Datei.
#     - CYCLE              — Zyklus in required+optional Deps (Kahn's Algorithmus,
#                            spiegelt ServiceDependencyResolver.gd).
#     - SCOPE_VIOLATION     — Global-Service hängt von Session-Service ab
#                            (bootet vorher, kann nicht funktionieren).
#     - UNBRIDGED_CROSS_SCOPE — Session-Service deklariert Dep auf einen
#                            Global-Service, dessen Key aber NICHT in der
#                            _bridge_app_services_into_session()-Liste in
#                            BootPipeline.gd steht → deps.require()/get_optional()
#                            bekommt zur Laufzeit still null (ADR-017).
#     - NO_SERVICE_KEY      — service_name hat keine passende Konstante in
#                            ServiceKeys.gd (Magic String statt Compile-Zeit-Fehler).
#     - NO_TEST_FOUND       — keine Testdatei referenziert die Klasse (informativ).
#
#   Seit Round 109 zusätzlich Event-Graph + Interface-Konformität (siehe
#   TODO-offene-probleme.md "Zwei parallele Pfade für dieselbe Sache"):
#
#     - DEAD_EVENT              — Signal deklariert, nirgends emittiert.
#     - UNCONSUMED_EVENT        — Signal emittiert, nirgends per .connect() konsumiert.
#     - BROKEN_EVENT_REF        — EventBus.<ns>.<x> bzw. .<ns>().<x> referenziert ein
#                                  Signal, das in keiner *Events.gd deklariert ist.
#     - DIRECT_EVENTBUS_ACCESS_IN_UI — UI-Datei nutzt Pfad A (EventBus.* direkt)
#                                  statt Pfad B (IEventBus-Indirektion, ADR-012-Ziel).
#     - UNVERIFIED_INTERFACE_CLAIM — '## implements I*'-Kommentar ohne passendes
#                                  'extends I*' — Compiler prüft in dem Fall nichts.
#     - MISSING_OVERRIDE        — Kommentar behauptet Interface-Konformität, aber
#                                  mind. eine Methode wird nicht überschrieben.
#     - NO_FORMAL_IMPLEMENTERS  — kein einziges echtes 'extends I*' für dieses
#                                  Interface im Projekt (kann Absicht sein — GDScript
#                                  kein Mehrfach-Erben — aber unverifiziert, s. TODO Punkt 4).
#     - ASSERT_FALSE_GUARD      — 'assert(false, ...)' als Pflicht-Override-Guard,
#                                  No-Op in Release-Builds ohne Debug-Flag.
#     - NON_TRIVIAL_INTERFACE_BODY — Interface-Methode enthält mehr als pass/return-Literal.
#     - EMIT_WRAPPER_NAME_MISMATCH — emit_<wrapper>() emittiert ein Signal mit
#                                  anderem Namen als der Wrapper (TODO Punkt 6).
#     - NATIVE_SIGNAL_EVENTBUS_COLLISION — natives Signal + EventBus-Signal
#                                  teilen sich einen Namen (Mess-Finding, TODO Punkt 7).
#     - EMIT_WRAPPER_UNRESOLVED — emit_<wrapper>() ohne verifizierbares Ziel-
#                                  Signal im Body. Wird NICHT per Namensgleichheit
#                                  geraten (Round 109: Tool-Bug selbst gefunden
#                                  und gefixt, siehe TODO-offene-probleme.md
#                                  Changelog-Eintrag Round 109).
#     - RAW_STRING_SERVICE_LOOKUP — get_service()/require()/get_optional() mit
#                                  rohem String-Literal statt ServiceKeys.<CONST>,
#                                  obwohl die Konstante existiert (TODO Punkt 8).
#     - INTENTIONAL_CLAIM       — 'bewusst'/'Absicht'/'Ausnahme'-Kommentar (TODO
#                                  Punkt 9). ALLE gemeldet, auch mit ADR-/TODO-
#                                  Referenz in der Nähe (has_reference im
#                                  Finding) — Referenz macht nachschlagbar,
#                                  nicht automatisch korrekt. Nur via --claims,
#                                  nicht im Default (214 Treffer).
#
# Verwendung:
#   python3 scripts/agent/service_graph.py                  # Volles JSON: Services+Events+Interfaces (Default)
#   python3 scripts/agent/service_graph.py --service quest   # JSON-Karte für 1 Service
#   python3 scripts/agent/service_graph.py --events          # Nur Event-Graph
#   python3 scripts/agent/service_graph.py --interfaces      # Nur Interface-Konformität
#   python3 scripts/agent/service_graph.py --claims          # Nur Absichts-Behauptungen (Punkt 9)
#   python3 scripts/agent/service_graph.py --pretty          # Menschenlesbares Report (Terminal)
#   python3 scripts/agent/service_graph.py --dot > graph.dot # Graphviz
#
# JSON ist der Default, nicht ein Extra-Flag: dieses Tool wird primär von Agents
# konsumiert, nicht von Menschen im Terminal gelesen. --pretty ist der Sonderfall,
# für Menschen die das Tool selbst debuggen.
#
# Exit 0 = keine ERROR-Klasse Findings, Exit 1 = mindestens 1 ERROR-Klasse Finding.
# (UNBRIDGED_CROSS_SCOPE/NO_SERVICE_KEY/NO_TEST_FOUND sind WARN, kein Fail-Exit.)

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
BOOTSTRAP_TRES = PROJECT_ROOT / "config" / "BootstrapConfig.tres"
SERVICE_KEYS_GD = PROJECT_ROOT / "scripts" / "platform" / "ServiceKeys.gd"
BOOT_PIPELINE_GD = PROJECT_ROOT / "scripts" / "platform" / "BootPipeline.gd"
TESTS_DIR = PROJECT_ROOT / "tests" / "unit"
EVENT_BUS_GD = PROJECT_ROOT / "scripts" / "eventbus" / "EventBus.gd"
INTERFACES_DIR = PROJECT_ROOT / "scripts" / "platform" / "interfaces"
GD_SCAN_DIRS = [PROJECT_ROOT / "scripts", PROJECT_ROOT / "tests"]

ERROR_KINDS = {
    "BROKEN_DEP", "MISSING_FILE", "CYCLE", "SCOPE_VIOLATION",
    # TODO-offene-probleme.md Punkt 2 (Round 109): ein Kommentar ist kein
    # Vertrag. `## implements I*` ohne passendes `extends I*` ist ein Bug,
    # kein Stil — Compiler prüft in dem Fall buchstäblich nichts.
    "UNVERIFIED_INTERFACE_CLAIM",
    # Ein Signal-Zugriff auf einen Namespace/Signal-Namen, den es laut
    # *Events.gd-Deklaration gar nicht gibt — Tippfehler oder Drift,
    # analog BROKEN_DEP.
    "BROKEN_EVENT_REF",
    # Ein emit_<wrapper>()-Aufruf, dessen tatsächliches Ziel-Signal NICHT aus
    # dem Funktions-Body verifiziert werden konnte (kein '<signal>.emit(' auf
    # ein bekanntes Signal gefunden). Früher wurde das über Namensgleichheit
    # geraten und STILL als "resolved" behandelt — das war der eigentliche
    # Bug: eine ungeprüfte Vermutung, die genauso falsch wie richtig sein
    # könnte (z.B. wenn der Body über eine Hilfsfunktion emittiert oder auf
    # ein umbenanntes Signal zeigt), aber nirgends als Unsicherheit sichtbar
    # war. Jetzt ERROR statt Raten — der Agent muss das Signal von Hand
    # verifizieren, bevor DEAD_EVENT/UNCONSUMED_EVENT für dieses Signal
    # überhaupt vertrauenswürdig sind.
    "EMIT_WRAPPER_UNRESOLVED",
}
WARN_KINDS = {
    "UNBRIDGED_CROSS_SCOPE", "NO_SERVICE_KEY", "NO_TEST_FOUND",
    # TODO-offene-probleme.md Punkt 1 (Round 109): Pfad A (direkter
    # `EventBus.*`-AutoLoad-Zugriff) statt Pfad B (`IEventBus`-Indirektion,
    # ADR-012-Zielzustand) — im UI-Layer noch nicht abgeschlossene Migration.
    "DIRECT_EVENTBUS_ACCESS_IN_UI",
    "DEAD_EVENT",
    "UNCONSUMED_EVENT",
    # Interface-Methode enthält mehr als einen trivialen Stub (pass /
    # return-Literal) — Logik lebt im Interface statt in einer
    # Implementierung, verletzt die Trennung die die anderen Methoden
    # in derselben Datei einhalten.
    "NON_TRIVIAL_INTERFACE_BODY",
    # `assert(false, ...)` als "muss überschrieben werden"-Guard — No-Op
    # in Release-Builds ohne Debug-Flag, siehe TODO-offene-probleme.md
    # Punkt 3 (neue Konvention nötig, hier nur gemeldet, nicht "gefixt").
    "ASSERT_FALSE_GUARD",
    # `## implements I*` behauptet Konformität UND `extends I*` fehlt UND
    # mind. eine Interface-Methode wird in der Datei gar nicht überschrieben.
    # Zusatzinfo neben UNVERIFIED_INTERFACE_CLAIM (welche Methoden fehlen).
    "MISSING_OVERRIDE",
    # TODO-offene-probleme.md Punkt 6 (Round 109): 'emit_<wrapper>()' löst
    # zwar korrekt auf welches Signal tatsächlich emittiert wird (Body-Parse,
    # siehe parse_signals()-Docstring) — aber wrapper != signal ist trotzdem
    # eine Namenskonvention-Verletzung, die Menschen und Agents beim Lesen
    # in die Irre führt (emit_xp() liest sich wie 'emittiert xp', tut es aber
    # nicht). Rein stilistisch, deshalb WARN, nicht ERROR.
    "EMIT_WRAPPER_NAME_MISMATCH",
    # TODO-offene-probleme.md Punkt 7 (Round 109): ein natives 'signal' auf
    # einem Service/einer Komponente trägt denselben Namen wie ein
    # EventBus-Signal in irgendeinem Namespace — Symptom von zwei parallelen
    # Kanälen für dieselbe Tatsache (Fund: player.inventory_changed vs.
    # InventorySystem.inventory_changed). Rein informativ/Mess-Finding für
    # die Migrationsentscheidung aus Punkt 7, kein Bug für sich genommen.
    "NATIVE_SIGNAL_EVENTBUS_COLLISION",
    # Unabhängig gefundener dritter Pfad, TODO Punkt 8 (Round 109):
    # ServiceKeys.gd dokumentiert im eigenen Header, dass
    # registry.get_service("inventory") durch ServiceKeys.INVENTORY ersetzt
    # gehört ("Tippfehler crashen zur Laufzeit -> durch Konstanten werden
    # sie zu Compile-Time-Fehlern") — Produktivcode (nicht Tests) ruft
    # get_service()/require()/get_optional() an mehreren Stellen trotzdem
    # mit dem rohen String-Literal auf, obwohl die passende Konstante
    # existiert. Genau der Fall, den ServiceKeys.gd verhindern soll.
    "RAW_STRING_SERVICE_LOOKUP",
    # TODO-offene-probleme.md Punkt 4 (Round 109): kein einziger `extends`-
    # Implementierer gefunden — laut Interface-Kommentar Absicht
    # (GDScript kein Mehrfach-Erben), aber noch nicht verifiziert/entschieden,
    # nur transparent gemacht.
    "NO_FORMAL_IMPLEMENTERS",
    # TODO-offene-probleme.md Punkt 9: jeder 'bewusst'/'Absicht'/'Ausnahme'-
    # Kommentar im Code, unabhängig davon ob eine ADR-/TODO-Referenz in der
    # Nähe steht — eine Referenz macht die Behauptung nachschlagbar, nicht
    # automatisch korrekt. Reines Sichtbarkeits-Finding, kein Urteil.
    "INTENTIONAL_CLAIM",
    # ADR-050 Phase 4 (Round 111): natives `signal` mit mind. einem externen
    # Nicht-Test-Connect, der laut analyze_native_signals.py's DI-Lookup-Regel
    # (Round 110) tatsächlich schichtübergreifend ist (CROSS_LAYER) — also ein
    # Migrationskandidat für den EventBus-Layer, der noch nicht migriert
    # wurde. Regressionsschutz: verhindert, dass ein künftig neu entstehender
    # 'zweiter Kanal für dieselbe Tatsache'-Fall (analog dem
    # inventory_changed-Präzedenzfall) unbemerkt durchrutscht, bis er sich zu
    # einem zweiten NATIVE_SIGNAL_EVENTBUS_COLLISION auswächst. WARN, nicht
    # ERROR — reine Messgröße für den Migrationsfortschritt aus ADR-050 Phase
    # 2, kein Fehler für sich genommen (die Migration läuft bewusst in
    # Domain-Batches, nicht auf einmal).
    "NATIVE_SIGNAL_EXTERNAL_CONNECT",
}


# ─────────────────────────────────────────────────────────────────────────────
# Parsing
# ─────────────────────────────────────────────────────────────────────────────

def _parse_string_array(text: str) -> list[str]:
    """Array[String]([\"a\", \"b\"]) -> [\"a\", \"b\"]"""
    m = re.search(r"\(\[(.*?)\]\)", text, re.S)
    if not m:
        return []
    inner = m.group(1).strip()
    if not inner:
        return []
    return re.findall(r'"([^"]*)"', inner)


def _parse_subresource_id_array(text: str) -> list[str]:
    """Array[Resource]([SubResource(\"Resource_x\"), ...]) -> [\"Resource_x\", ...]"""
    return re.findall(r'SubResource\("([^"]+)"\)', text)


def parse_bootstrap_config(path: Path) -> dict:
    if not path.exists():
        raise FileNotFoundError(f"BootstrapConfig.tres nicht gefunden: {path}")
    raw = path.read_text(encoding="utf-8")

    # Alle sub_resource-Blöcke einsammeln, keyed nach id="Resource_xxx"
    sub_resources: dict[str, dict] = {}
    block_re = re.compile(
        r'\[sub_resource type="Resource" id="([^"]+)"\](.*?)(?=\n\[|\Z)', re.S
    )
    for sub_id, body in block_re.findall(raw):
        entry: dict = {"_id": sub_id}
        m = re.search(r'^service_name\s*=\s*"([^"]*)"', body, re.M)
        if m:
            entry["service_name"] = m.group(1)
        m = re.search(r'^registry_key\s*=\s*"([^"]*)"', body, re.M)
        if m:
            entry["registry_key"] = m.group(1)
        m = re.search(r'^path\s*=\s*"([^"]*)"', body, re.M)
        if m:
            entry["path"] = m.group(1)
        m = re.search(r"^required_deps\s*=\s*(.*)$", body, re.M)
        entry["required_deps"] = _parse_string_array(m.group(1)) if m else []
        m = re.search(r"^optional_deps\s*=\s*(.*)$", body, re.M)
        entry["optional_deps"] = _parse_string_array(m.group(1)) if m else []
        sub_resources[sub_id] = entry

    def collect(array_name: str) -> list[dict]:
        m = re.search(
            rf"^{array_name}\s*=\s*Array\[\w+\]\(\[(.*?)\]\)", raw, re.S | re.M
        )
        if not m:
            return []
        ids = _parse_subresource_id_array(m.group(0))
        return [sub_resources[i] for i in ids if i in sub_resources]

    return {
        "global_services": collect("global_services"),
        "session_services": collect("session_services"),
        "global_resources": collect("global_resources"),
        "session_resources": collect("session_resources"),
    }


def parse_service_keys(path: Path) -> dict[str, str]:
    """Gibt {value: CONST_NAME} zurück, z.B. {\"quest\": \"QUEST\"}."""
    if not path.exists():
        return {}
    raw = path.read_text(encoding="utf-8")
    result = {}
    for const_name, value in re.findall(
        r'^const\s+(\w+)\s*:?=\s*"([^"]*)"', raw, re.M
    ):
        result[value] = const_name
    return result


def parse_bridge_list(path: Path) -> set[str]:
    """Extrahiert die Keys aus _bridge_app_services_into_session(..., [...]) in
    BootPipeline.gd — die einzige Quelle dafür, welche Global-Services ein
    Session-Service laut ADR-017 tatsächlich sehen darf."""
    if not path.exists():
        return set()
    raw = path.read_text(encoding="utf-8")
    m = re.search(
        r"_bridge_app_services_into_session\([^,]+,\s*[^,]+,\s*\[(.*?)\]\)",
        raw,
        re.S,
    )
    if not m:
        return set()
    consts = re.findall(r"ServiceKeys\.(\w+)", m.group(1))
    return set(consts)


def parse_class_name(gd_path: Path) -> str | None:
    full = PROJECT_ROOT / gd_path.replace("res://", "")
    if not full.exists():
        return None
    raw = full.read_text(encoding="utf-8", errors="replace")
    m = re.search(r"^class_name\s+(\w+)", raw, re.M)
    return m.group(1) if m else None


def iter_gd_files():
    """Alle .gd-Dateien unter scripts/ und tests/ (das ist der komplette
    Raum in dem EventBus-Zugriffe und Interface-Implementierungen leben
    können — Autoload-Config/Resources sind hier irrelevant)."""
    for root in GD_SCAN_DIRS:
        if root.exists():
            yield from root.rglob("*.gd")


# ─────────────────────────────────────────────────────────────────────────────
# Event graph (TODO-offene-probleme.md "Zwei parallele Pfade", Punkt 1)
# ─────────────────────────────────────────────────────────────────────────────
#
# Zwei Zugriffspfade koexistieren im Projekt:
#   Pfad A (direkt):    EventBus.<ns>.<signal>.connect(...) / .emit(...)
#                        EventBus.<ns>.emit_<signal>(...)
#   Pfad B (Indirektion): <irgendein_ausdruck>.<ns>().<signal>.connect(...)
#                        <irgendein_ausdruck>.<ns>().emit_<signal>(...)
#                        (IEventBus/EventBusAdapter/MockEventBus-Fassade,
#                        ADR-012-Zielzustand — siehe IUIContext.gd)
# Pfad B wird über den Accessor-Namen erkannt (".world()." etc.), nicht über
# eine feste Empfänger-Variable — die Fassade wird unter vielen Namen
# gehalten (_bus, _ctx.bus(), ...).

def parse_event_namespaces(path: Path) -> dict[str, str]:
    """EventBus.gd: 'var combat: CombatEvents' -> {'combat': 'CombatEvents'}."""
    if not path.exists():
        return {}
    raw = path.read_text(encoding="utf-8")
    result = {}
    for name, cls in re.findall(r"^var\s+(\w+)\s*:\s*(\w+)\s*$", raw, re.M):
        result[name] = cls
    return result


def parse_signals(path: Path) -> tuple[list[dict], dict[str, str], list[str]]:
    """Extrahiert 'signal name(...)'-Deklarationen (auch mehrzeilig, siehe
    CombatEvents.player_killed_by_player) aus einer *Events.gd-Datei, sowie
    eine emit_<wrapper> -> <tatsächliches Signal>-Map.

    WICHTIG: der Wrapper-Name matcht den Signal-Namen NICHT immer 1:1
    (z.B. 'emit_xp()' emittiert tatsächlich 'xp_gained', 'emit_notification()'
    emittiert 'notification_requested') — deshalb wird der Funktions-Body
    geparst ('<signal>.emit(') statt den Namen zu raten. Ein Namens-Raten
    hätte hier reihenweise falsche BROKEN_EVENT_REF-Findings erzeugt.

    Wenn im Body KEIN eindeutiger '<signal>.emit('-Aufruf auf ein bekanntes
    Signal gefunden wird, wird NICHT stillschweigend Namensgleichheit
    angenommen (das wäre dieselbe Art Fehler nur eine Ebene höher — eine
    ungeprüfte Vermutung, kein Beweis: der Body könnte über eine Hilfsfunktion
    emittieren oder auf ein falsch benanntes Signal zeigen). Stattdessen
    landet der Wrapper-Name in der dritten Rückgabe (unresolved) und wird vom
    Aufrufer als EMIT_WRAPPER_UNRESOLVED-Finding sichtbar gemacht."""
    if not path.exists():
        return [], {}, []
    raw = path.read_text(encoding="utf-8", errors="replace")

    signals = []
    for m in re.finditer(r"signal\s+(\w+)\s*\(", raw):
        signals.append(m.group(1))
    # Signale ohne Parameter, z.B. 'signal foo' ohne Klammern
    for m in re.finditer(r"^signal\s+(\w+)\s*$", raw, re.M):
        signals.append(m.group(1))
    signal_names = set(signals)

    wrapper_target: dict[str, str] = {}
    unresolved: list[str] = []
    for name, body in _split_top_level_funcs(raw):
        if not name.startswith("emit_"):
            continue
        wrapper = name[len("emit_"):]
        m = re.search(r"(\w+)\.emit\s*\(", body)
        if m and m.group(1) in signal_names:
            wrapper_target[wrapper] = m.group(1)
        else:
            unresolved.append(wrapper)

    has_wrapper = {t for t in wrapper_target.values()}
    return (
        [{"name": n, "has_emit_wrapper": n in has_wrapper} for n in sorted(signal_names)],
        wrapper_target,
        unresolved,
    )


def build_event_index(ns_map: dict[str, str]) -> dict[str, dict]:
    """namespace -> {class_name, path, signals:[...]}. Sucht die *Events.gd-
    Datei per class_name-Match statt per Pfad-Konvention (die Namespaces
    liegen fachlich verteilt, siehe EventBus.gd-Kommentar 'in der jeweiligen
    Domain anlegen')."""
    class_to_path: dict[str, Path] = {}
    for gd in iter_gd_files():
        raw = gd.read_text(encoding="utf-8", errors="replace")
        m = re.search(r"^class_name\s+(\w+)\s+extends\s+BaseEvents", raw, re.M)
        if m:
            class_to_path[m.group(1)] = gd

    index = {}
    for ns, cls in ns_map.items():
        gd_path = class_to_path.get(cls)
        signals, wrapper_target, unresolved_wrappers = parse_signals(gd_path) if gd_path else ([], {}, [])
        index[ns] = {
            "class_name": cls,
            "path": str(gd_path.relative_to(PROJECT_ROOT)) if gd_path else None,
            "signals": signals,
            "wrapper_target": wrapper_target,  # emit_<wrapper> -> tatsächliches Signal
            "unresolved_wrappers": unresolved_wrappers,  # emit_<wrapper> ohne verifizierbares Ziel
        }
    return index


def scan_event_usages(namespaces: set[str], wrapper_targets: dict[str, dict[str, str]]) -> dict[str, dict]:
    """Durchsucht alle .gd-Dateien nach Zugriffen auf bekannte Namespaces und
    ordnet sie Pfad A / Pfad B zu. Rückgabe: {(ns,signal): {emitted_a, emitted_b,
    connected_a, connected_b}}, plus direct_access_ui_files.

    wrapper_targets: {namespace: {wrapper_name: tatsächliches_signal}} — nötig
    weil 'emit_<wrapper>()' den Signal-Namen NICHT immer im Funktionsnamen trägt
    (siehe parse_signals()-Docstring)."""
    ns_alt = "|".join(re.escape(n) for n in sorted(namespaces))
    # Pfad A: EventBus.<ns>.<signal>.connect|emit(   ODER   EventBus.<ns>.emit_<wrapper>(
    re_a_sig = re.compile(rf"EventBus\.({ns_alt})\.(\w+)\.(connect|emit)\s*\(")
    re_a_wrap = re.compile(rf"EventBus\.({ns_alt})\.emit_(\w+)\s*\(")
    # Pfad B: .<ns>().<signal>.connect|emit(   ODER   .<ns>().emit_<wrapper>(
    re_b_sig = re.compile(rf"\.({ns_alt})\(\)\.(\w+)\.(connect|emit)\s*\(")
    re_b_wrap = re.compile(rf"\.({ns_alt})\(\)\.emit_(\w+)\s*\(")

    usage: dict[tuple, dict] = {}

    def bump(ns: str, sig: str, field: str):
        key = (ns, sig)
        usage.setdefault(key, {
            "emitted_a": 0, "emitted_b": 0, "connected_a": 0, "connected_b": 0,
        })
        usage[key][field] += 1

    def resolve_wrapper(ns: str, wrapper: str) -> str:
        return wrapper_targets.get(ns, {}).get(wrapper, wrapper)

    direct_access_ui_files: dict[str, int] = {}

    for gd in iter_gd_files():
        if gd == EVENT_BUS_GD or gd.parent == INTERFACES_DIR:
            continue
        raw = gd.read_text(encoding="utf-8", errors="replace")
        rel = str(gd.relative_to(PROJECT_ROOT))

        a_hits = 0
        for ns, sig, verb in re_a_sig.findall(raw):
            bump(ns, sig, "connected_a" if verb == "connect" else "emitted_a")
            a_hits += 1
        for ns, wrapper in re_a_wrap.findall(raw):
            bump(ns, resolve_wrapper(ns, wrapper), "emitted_a")
            a_hits += 1
        for ns, sig, verb in re_b_sig.findall(raw):
            bump(ns, sig, "connected_b" if verb == "connect" else "emitted_b")
        for ns, wrapper in re_b_wrap.findall(raw):
            bump(ns, resolve_wrapper(ns, wrapper), "emitted_b")

        # ADR-012: UI-Layer soll auf Pfad B migriert sein (siehe IUIContext.gd).
        # scripts/eventbus/ selbst ist per Definition Pfad-A-Quelle, hier
        # bereits oben ausgeschlossen.
        if a_hits and rel.startswith("scripts/ui/"):
            direct_access_ui_files[rel] = a_hits

    return {"usage": usage, "direct_access_ui_files": direct_access_ui_files}


def analyze_events(event_index: dict[str, dict]) -> tuple[dict, list[dict]]:
    findings = []

    def add(kind: str, service: str, msg: str):
        findings.append({"kind": kind, "service": service, "message": msg})

    namespaces = set(event_index.keys())
    wrapper_targets = {ns: data["wrapper_target"] for ns, data in event_index.items()}
    scan = scan_event_usages(namespaces, wrapper_targets)
    usage = scan["usage"]

    known_signals = {
        ns: {s["name"] for s in data["signals"]} for ns, data in event_index.items()
    }

    # Nicht verifizierbare Wrapper laut sichtbar machen statt raten
    # (s. parse_signals()-Docstring — kein Namens-Fallback mehr).
    for ns, data in event_index.items():
        for wrapper in data.get("unresolved_wrappers", []):
            add("EMIT_WRAPPER_UNRESOLVED", f"{ns}.emit_{wrapper}",
                f"Body von emit_{wrapper}() enthält keinen verifizierbaren '<signal>.emit(...)'-Aufruf "
                f"auf ein bekanntes Signal in {data['class_name']} — Ziel-Signal von Hand prüfen, "
                f"wird NICHT per Namensgleichheit geraten")

    events_out: dict[str, dict] = {}
    for ns, data in event_index.items():
        if data["path"] is None:
            add("BROKEN_EVENT_REF", ns,
                f"Namespace '{ns}' in EventBus.gd deklariert (var {ns}: {data['class_name']}), "
                f"aber keine Klasse '{data['class_name']}(extends BaseEvents)' im Projekt gefunden")
            continue
        for sig in data["signals"]:
            name = sig["name"]
            u = usage.get((ns, name), {"emitted_a": 0, "emitted_b": 0, "connected_a": 0, "connected_b": 0})
            emitted = u["emitted_a"] + u["emitted_b"]
            connected = u["connected_a"] + u["connected_b"]
            full_name = f"{ns}.{name}"
            events_out[full_name] = {
                "namespace": ns, "signal": name, "path": data["path"],
                "has_emit_wrapper": sig["has_emit_wrapper"],
                "emitted_direct": u["emitted_a"], "emitted_indirect": u["emitted_b"],
                "connected_direct": u["connected_a"], "connected_indirect": u["connected_b"],
            }
            if emitted == 0:
                add("DEAD_EVENT", full_name, "Signal deklariert, aber im gesamten Projekt nirgends emittiert")
            elif connected == 0:
                add("UNCONSUMED_EVENT", full_name,
                    f"Signal wird emittiert ({emitted}x) aber nirgends per .connect() konsumiert")

    # Zugriffe auf Namespace/Signal-Kombinationen, die in keiner *Events.gd
    # deklariert sind (Tippfehler, veraltete Referenz nach Rename).
    for (ns, sig) in usage:
        if ns in known_signals and sig not in known_signals[ns]:
            add("BROKEN_EVENT_REF", f"{ns}.{sig}",
                f"Code referenziert 'EventBus.{ns}.{sig}' bzw. '.{ns}().{sig}', aber kein "
                f"passendes 'signal {sig}(...)' in der zugehörigen Events-Klasse deklariert")

    for rel, count in sorted(scan["direct_access_ui_files"].items()):
        add("DIRECT_EVENTBUS_ACCESS_IN_UI", rel,
            f"{count}x direkter 'EventBus.*'-Zugriff (Pfad A) statt IEventBus-Indirektion (Pfad B, "
            f"ADR-012-Zielzustand) — TODO-offene-probleme.md Punkt 1")

    # TODO-offene-probleme.md Punkt 6: wrapper != tatsächliches Signal.
    # Funktional korrekt aufgelöst (parse_signals() parst den Body), aber
    # eine stille Namensabweichung ist trotzdem eine Falle beim Lesen/Grep.
    wrapper_mismatches = []
    for ns, data in event_index.items():
        for wrapper, target in data["wrapper_target"].items():
            if wrapper == target:
                continue
            full_name = f"{ns}.{target}"
            wrapper_mismatches.append({"namespace": ns, "wrapper": wrapper, "signal": target})
            if full_name in events_out:
                events_out[full_name]["wrapper_mismatch"] = wrapper
            add("EMIT_WRAPPER_NAME_MISMATCH", full_name,
                f"emit_{wrapper}() emittiert tatsächlich Signal '{target}' — Wrapper-Name und "
                f"Signal-Name laufen auseinander, funktional aufgelöst aber irreführend beim Lesen")
    events_out["_wrapper_mismatches"] = wrapper_mismatches

    # TODO-offene-probleme.md Punkt 7: Mess-Grundlage für die Architekturfrage
    # (typisierter Domain-Event-Layer vs. String-Namespace-EventBus). Zählt
    # native 'signal'-Deklarationen außerhalb von *Events.gd/eventbus/ und
    # meldet Namenskollisionen mit EventBus-Signalen (Symptom-Fund:
    # player.inventory_changed vs. InventorySystem.inventory_changed).
    all_eventbus_signal_names: dict[str, list[str]] = {}
    for ns, names in known_signals.items():
        for n in names:
            all_eventbus_signal_names.setdefault(n, []).append(ns)

    native_signals: dict[str, list[str]] = {}
    for gd in iter_gd_files():
        if gd == EVENT_BUS_GD or gd.parent == INTERFACES_DIR:
            continue
        rel = str(gd.relative_to(PROJECT_ROOT))
        if rel.endswith("Events.gd") or rel.startswith("scripts/eventbus/"):
            continue
        raw = gd.read_text(encoding="utf-8", errors="replace")
        cls_m = re.search(r"^class_name\s+(\w+)", raw, re.M)
        owner = cls_m.group(1) if cls_m else rel
        for m in re.finditer(r"^signal\s+(\w+)\s*[\(\n]", raw, re.M):
            native_signals.setdefault(m.group(1), []).append(owner)

    native_collisions = []
    for name, owners in sorted(native_signals.items()):
        bus_namespaces = all_eventbus_signal_names.get(name)
        if not bus_namespaces:
            continue
        native_collisions.append({"signal": name, "native_owners": owners, "eventbus_namespaces": bus_namespaces})
        add("NATIVE_SIGNAL_EVENTBUS_COLLISION", name,
            f"Natives Signal '{name}' auf {', '.join(owners)} UND EventBus-Signal in "
            f"{', '.join(bus_namespaces)} — zwei Kanäle für denselben Namen, TODO Punkt 7 prüfen")
    events_out["_native_signal_audit"] = {
        "total_native_signal_declarations": sum(len(v) for v in native_signals.values()),
        "collisions": native_collisions,
    }

    return events_out, findings


# ─────────────────────────────────────────────────────────────────────────────
# Interface conformance (TODO-offene-probleme.md "Zwei parallele Pfade",
# Punkte 2-4)
# ─────────────────────────────────────────────────────────────────────────────

_TRIVIAL_RETURN_RE = re.compile(
    r'^return\s+(null|true|false|""|\{\}|\[\]|-?\d+(\.\d+)?)\s*$'
)


def _split_top_level_funcs(raw: str) -> list[tuple[str, str]]:
    """(func_name, body_text) für jede 'func name(...) -> T:'-Definition auf
    Top-Level (Interfaces haben keine verschachtelten inneren Klassen)."""
    starts = [(m.start(), m.group(1)) for m in re.finditer(r"^func\s+(\w+)\s*\(", raw, re.M)]
    out = []
    for i, (pos, name) in enumerate(starts):
        end = starts[i + 1][0] if i + 1 < len(starts) else len(raw)
        chunk = raw[pos:end]
        header_end = chunk.find(":\n")
        body = chunk[header_end + 2:] if header_end != -1 else ""
        out.append((name, body))
    return out


def _classify_body(body: str) -> str:
    lines = [l.strip() for l in body.splitlines() if l.strip() and not l.strip().startswith("#")]
    if any(l.startswith("assert(false") or l.startswith("assert (false") for l in lines):
        return "ASSERT_FALSE_GUARD"
    if not lines:
        return "TRIVIAL_EMPTY"
    if all(l == "pass" or _TRIVIAL_RETURN_RE.match(l) for l in lines):
        return "TRIVIAL_STUB"
    return "NON_TRIVIAL"


def parse_interface(path: Path) -> dict:
    raw = path.read_text(encoding="utf-8", errors="replace")
    m = re.search(r"^class_name\s+(\w+)", raw, re.M)
    cls = m.group(1) if m else path.stem
    methods = []
    for name, body in _split_top_level_funcs(raw):
        methods.append({"name": name, "body_kind": _classify_body(body)})
    return {"class_name": cls, "path": str(path.relative_to(PROJECT_ROOT)), "methods": methods}


def find_interface_claims(interface_names: set[str]) -> dict[str, list[dict]]:
    """interface_name -> Liste von {path, via_extends, via_comment, defined_methods}
    über das gesamte Projekt (außer der Interface-Datei selbst)."""
    claims: dict[str, list[dict]] = {n: [] for n in interface_names}
    for gd in iter_gd_files():
        if gd.parent == INTERFACES_DIR:
            continue
        raw = gd.read_text(encoding="utf-8", errors="replace")
        rel = str(gd.relative_to(PROJECT_ROOT))

        extends_hits = set(re.findall(r"^(?:class_name\s+\w+\s+)?extends\s+(I\w+)", raw, re.M))
        # Zwei Schreibweisen im Projekt gefunden für dieselbe Behauptung
        # ("implements X" per ISaveProvider.gd-Migrationsnotiz, "Implementiert X"
        # in EquipmentService.gd) — beide sind reiner Kommentar, keine echte
        # Vererbung, also gleich behandelt.
        comment_hits = set(re.findall(r"^##?\s*(?:implements|Implementiert)\s+(I\w+)", raw, re.M))

        claimed = (extends_hits | comment_hits) & interface_names
        if not claimed:
            continue
        defined_methods = set(re.findall(r"^func\s+(\w+)\s*\(", raw, re.M))
        for iface in claimed:
            claims[iface].append({
                "path": rel,
                "via_extends": iface in extends_hits,
                "via_comment": iface in comment_hits,
                "defined_methods": defined_methods,
            })
    return claims


def analyze_interfaces() -> tuple[dict, list[dict]]:
    findings = []

    def add(kind: str, service: str, msg: str):
        findings.append({"kind": kind, "service": service, "message": msg})

    if not INTERFACES_DIR.exists():
        return {}, findings

    interfaces = {}
    for path in sorted(INTERFACES_DIR.glob("*.gd")):
        parsed = parse_interface(path)
        interfaces[parsed["class_name"]] = parsed

    claims = find_interface_claims(set(interfaces.keys()))

    out = {}
    for cls, data in interfaces.items():
        for meth in data["methods"]:
            if meth["body_kind"] == "ASSERT_FALSE_GUARD":
                add("ASSERT_FALSE_GUARD", f"{cls}.{meth['name']}",
                    "assert(false, ...) als Pflicht-Override-Guard — No-Op in Release-Builds "
                    "ohne Debug-Flag (TODO-offene-probleme.md Punkt 3)")
            elif meth["body_kind"] == "NON_TRIVIAL":
                add("NON_TRIVIAL_INTERFACE_BODY", f"{cls}.{meth['name']}",
                    "Methode enthält mehr als einen trivialen Stub (pass/return-Literal) — "
                    "echte Logik lebt im Interface statt in einer Implementierung")

        implementers = claims.get(cls, [])
        real_extends = [i for i in implementers if i["via_extends"]]
        comment_only = [i for i in implementers if i["via_comment"] and not i["via_extends"]]

        if not implementers:
            add("NO_FORMAL_IMPLEMENTERS", cls,
                "Kein 'extends " + cls + "' und kein '## implements " + cls + "' irgendwo im Projekt "
                "gefunden — laut Interface-Kommentar ggf. Absicht (Duck-Typing statt Mehrfach-Erben, "
                "siehe TODO-offene-probleme.md Punkt 4), aber unverifiziert")
        elif not real_extends:
            add("NO_FORMAL_IMPLEMENTERS", cls,
                f"{len(implementers)} Datei(en) behaupten Konformität nur per Kommentar, "
                f"kein einziges echtes 'extends {cls}' im Projekt (TODO-offene-probleme.md Punkt 4)")

        method_names = [m["name"] for m in data["methods"]]
        for impl in comment_only:
            add("UNVERIFIED_INTERFACE_CLAIM", impl["path"],
                f"'## implements {cls}'-Kommentar ohne passendes 'extends {cls}' — Compiler prüft "
                f"nichts, 'is {cls}' wäre zur Laufzeit false (TODO-offene-probleme.md Punkt 2)")
            missing = [m for m in method_names if m not in impl["defined_methods"]]
            if missing:
                add("MISSING_OVERRIDE", impl["path"],
                    f"behauptet '{cls}' zu implementieren, überschreibt aber nicht: {missing}")

        out[cls] = {
            "path": data["path"],
            "methods": data["methods"],
            "implementers_via_extends": sorted(i["path"] for i in real_extends),
            "implementers_via_comment_only": sorted(i["path"] for i in comment_only),
        }

    return out, findings


# ─────────────────────────────────────────────────────────────────────────────
# Graph model
# ─────────────────────────────────────────────────────────────────────────────

class Node:
    def __init__(self, name: str, kind: str, path: str = "", scope: str = ""):
        self.name = name
        self.kind = kind  # "service" | "resource" | "infra"
        self.path = path
        self.scope = scope  # "global" | "session" | ""
        self.required: list[str] = []
        self.optional: list[str] = []
        self.dependents: set[str] = set()  # fan-in, filled after construction
        self.class_name: str | None = None


def build_graph(cfg: dict, key_map: dict[str, str]) -> dict[str, Node]:
    nodes: dict[str, Node] = {}

    for entry in cfg["global_resources"] + cfg["session_resources"]:
        key = entry.get("registry_key", "")
        if key:
            nodes[key] = Node(key, "resource", entry.get("path", ""))

    # Infra-Key event_bus wird außerhalb BootstrapConfig direkt registriert
    # (BootPipeline.boot_app: registry.register_resource(EventBusAdapter.new(), ...))
    nodes.setdefault("event_bus", Node("event_bus", "infra"))

    for scope, key in (("global", "global_services"), ("session", "session_services")):
        for entry in cfg[key]:
            name = entry.get("service_name", "")
            if not name:
                continue
            n = Node(name, "service", entry.get("path", ""), scope)
            n.required = entry.get("required_deps", [])
            n.optional = entry.get("optional_deps", [])
            n.class_name = parse_class_name(n.path) if n.path else None
            nodes[name] = n

    for n in nodes.values():
        for dep in n.required + n.optional:
            if dep in nodes:
                nodes[dep].dependents.add(n.name)

    return nodes


def find_cycles(nodes: dict[str, Node]) -> list[list[str]]:
    """Kahn's Algorithmus über required+optional — spiegelt
    ServiceDependencyResolver.gd, wo beide Listen für die Boot-Reihenfolge
    gleich zählen."""
    indeg = {name: 0 for name in nodes}
    adj: dict[str, list[str]] = {name: [] for name in nodes}
    for n in nodes.values():
        for dep in set(n.required + n.optional):
            if dep in nodes:
                adj[dep].append(n.name)
                indeg[n.name] += 1

    queue = [n for n, d in indeg.items() if d == 0]
    visited = 0
    indeg_work = dict(indeg)
    while queue:
        cur = queue.pop()
        visited += 1
        for nxt in adj[cur]:
            indeg_work[nxt] -= 1
            if indeg_work[nxt] == 0:
                queue.append(nxt)

    if visited == len(nodes):
        return []

    # Es gibt einen Zyklus — grob lokalisieren: alle Knoten mit indeg_work > 0
    remaining = sorted(n for n, d in indeg_work.items() if d > 0)
    return [remaining] if remaining else []


def topo_order(nodes: dict[str, Node], scope: str) -> list[str]:
    scoped = {n for n, node in nodes.items() if node.scope == scope}
    indeg = {n: 0 for n in scoped}
    adj: dict[str, list[str]] = {n: [] for n in scoped}
    for name in scoped:
        node = nodes[name]
        for dep in set(node.required + node.optional):
            if dep in scoped:
                adj[dep].append(name)
                indeg[name] += 1
    queue = sorted(n for n, d in indeg.items() if d == 0)
    order = []
    while queue:
        queue.sort()
        cur = queue.pop(0)
        order.append(cur)
        for nxt in adj[cur]:
            indeg[nxt] -= 1
            if indeg[nxt] == 0:
                queue.append(nxt)
    return order


# ─────────────────────────────────────────────────────────────────────────────
# Findings
# ─────────────────────────────────────────────────────────────────────────────

def analyze_raw_string_service_lookups(key_map: dict[str, str]) -> list[dict]:
    """TODO-offene-probleme.md Punkt 8 (Round 109): dritter Pfad, unabhängig
    vom Event/Interface-Fund entdeckt. get_service()/require()/get_optional()
    mit rohem String-Literal statt ServiceKeys.<CONST> — nur gemeldet, wenn
    die passende Konstante tatsächlich existiert (key_map), sonst wäre es
    Spekulation statt ein belegter Fund. Bewusst nur scripts/, nicht tests/:
    Test-Doubles/Mocks verwenden Ad-hoc-Keys oft legitim ohne Bezug zu
    ServiceKeys.gd."""
    re_call = re.compile(r'\.(get_service|require|get_optional)\(\s*"([a-z_][a-z0-9_]*)"\s*\)')
    findings = []
    for gd in (PROJECT_ROOT / "scripts").rglob("*.gd"):
        if gd == SERVICE_KEYS_GD:
            continue
        raw = gd.read_text(encoding="utf-8", errors="replace")
        rel = str(gd.relative_to(PROJECT_ROOT))
        for lineno, line in enumerate(raw.splitlines(), start=1):
            for method, literal in re_call.findall(line):
                const = key_map.get(literal)
                if const is None:
                    continue  # kein bekannter Service-Key -> anderes Problem, nicht dieser Check
                findings.append({
                    "kind": "RAW_STRING_SERVICE_LOOKUP",
                    "service": f"{rel}:{lineno}",
                    "message": f'.{method}("{literal}") mit Roh-String-Literal statt '
                               f'ServiceKeys.{const} — Konstante existiert bereits',
                })
    return findings


_CLAIM_WORD_RE = re.compile(r"\b(bewusst\w*|Absicht\w*|Ausnahme\w*)\b", re.IGNORECASE)
_CLAIM_REF_RE = re.compile(r"ADR-\d+|TODO", re.IGNORECASE)


def analyze_native_signal_migration() -> tuple[dict, list[dict]]:
    """ADR-050 Phase 4 — Regressionsschutz für die native-Signal->Domain-
    Event-Migration. Ruft NICHT die alte 'gleicher ui/-Ordner'-Heuristik auf
    (die stand nur im ADR-Text als Platzhalter, bevor Round 110 die
    DI-Lookup-Regel gebaut hat) — importiert stattdessen direkt
    analyze_native_signals.py und nutzt dessen bereits gehärtete
    Provenance-Auflösung (DI/AUTOLOAD/DIRECT/Scene-Tree/Ein-Hop-Funktions-
    aufrufe/Dictionary-Subscript-Tracing, siehe dortige Docstrings) — ein
    zweiter, einfacherer Reimplementierungs-Pfad hätte hier exakt die Sorte
    'zwei Kanäle für dieselbe Tatsache' reproduziert, vor der ADR-050 selbst
    warnt, nur auf Tool-Ebene statt auf Signal-Ebene.

    Liefert (report_dict, findings). Ein WARN-Finding pro Signal in
    Kategorie CROSS_LAYER — die Instanzen, für die ADR-050 Phase 2 noch
    nicht gelaufen ist. Sinkt die Anzahl nach einem Migrations-Batch nicht,
    ist entweder der Batch nicht fertig oder ein neues Signal ist seither
    dazugekommen (siehe ADR-050 'Positiv': genau dafür ist dieser Finding-
    Typ als kostenloser Regressionsindikator gedacht)."""
    agent_dir = str(Path(__file__).resolve().parent)
    if agent_dir not in sys.path:
        sys.path.insert(0, agent_dir)
    import analyze_native_signals as ans  # noqa: PLC0415 — bewusst lokal, kein Modul-Level-Zyklus mit service_graph

    decls = ans.collect_declarations()
    connects = ans.collect_connects(set(decls.keys()))
    categorized = ans.categorize(decls, connects)

    findings = []
    counts = {"LOCAL": 0, "CROSS_LAYER": 0, "NEEDS_HUMAN": 0}
    for name, info in sorted(categorized.items()):
        counts[info["category"]] += 1
        if info["category"] != "CROSS_LAYER":
            continue
        decl_files = ", ".join(sorted({d["file"] for d in info["declarations"]}))
        findings.append({
            "kind": "NATIVE_SIGNAL_EXTERNAL_CONNECT",
            "service": decl_files,
            "message": f"signal '{name}' hat externe(n) Nicht-Test-Connect(s) mit "
                       f"DI/AutoLoad-Herkunft — ADR-050-Migrationskandidat, noch nicht "
                       f"migriert: {info['reason']}",
        })

    report = {
        "counts": counts,
        "total_unique_signal_names": len(categorized),
        "cross_layer_signals": sorted(
            n for n, i in categorized.items() if i["category"] == "CROSS_LAYER"
        ),
        "needs_human_signals": sorted(
            n for n, i in categorized.items() if i["category"] == "NEEDS_HUMAN"
        ),
    }
    return report, findings


def print_native_signal_report(report: dict, findings: list[dict]):
    print("=" * 70)
    print("  Native-Signal-Migration (ADR-050 Phase 4 — Regressionsschutz)")
    print("=" * 70)
    c = report["counts"]
    print(f"\n{report['total_unique_signal_names']} eindeutige Signal-Namen — "
          f"LOCAL: {c['LOCAL']}, CROSS_LAYER: {c['CROSS_LAYER']}, "
          f"NEEDS_HUMAN: {c['NEEDS_HUMAN']}")
    if findings:
        print(f"\n⚠️  {len(findings)} NATIVE_SIGNAL_EXTERNAL_CONNECT (Migrationskandidaten, "
              f"ADR-050 Phase 2 noch offen):\n")
        for f in findings:
            print(f"  [{f['service']}] {f['message']}")
    else:
        print("\n✅ Keine offenen CROSS_LAYER-Migrationskandidaten mehr.")
    if report["needs_human_signals"]:
        print(f"\n{len(report['needs_human_signals'])} weiterhin NEEDS_HUMAN "
              f"(ADR-050 Phase 1, Namenskollisionen — kein Automatismus möglich): "
              f"{', '.join(report['needs_human_signals'])}")



    """Round 109 Nachtrag, TODO Punkt 9 — bewusst NICHT gefiltert nach ADR-/
    TODO-Referenz in der Nähe. Erste Version dieses Checks hat nur Claims ohne
    Referenz gemeldet ('unbacked'); Korrektur nach Rückmeldung: eine
    ADR-Referenz macht eine Behauptung nachschlagbar, nicht automatisch
    richtig — ADRs sind selbst nicht verifiziert und können veraltet sein.
    Deshalb: jeder 'bewusst'/'Absicht'/'Ausnahme'-Kommentar wird gemeldet,
    ADR-/TODO-Bezug ist nur eine Zusatzinfo im Finding (has_reference), kein
    Filterkriterium. Kein automatisches Urteil richtig/falsch — macht nur
    sichtbar, was bisher stillschweigend als 'gewollt' galt. Bewusst WARN,
    nicht ERROR: 214 Treffer projektweit, die meisten vermutlich legitim —
    Einzelprüfung folgt manuell, dieser Check ist nur die vollständige
    Fundliste dafür, nicht das Urteil."""
    findings = []
    for gd in (PROJECT_ROOT / "scripts").rglob("*.gd"):
        raw = gd.read_text(encoding="utf-8", errors="replace")
        rel = str(gd.relative_to(PROJECT_ROOT))
        lines = raw.splitlines()
        for lineno, line in enumerate(lines, start=1):
            hash_idx = line.find("#")
            if hash_idx == -1:
                continue
            comment = line[hash_idx:]
            words = _CLAIM_WORD_RE.findall(comment)
            if not words:
                continue
            context = "\n".join(lines[max(0, lineno - 4):min(len(lines), lineno + 3)])
            has_reference = bool(_CLAIM_REF_RE.search(context))
            findings.append({
                "kind": "INTENTIONAL_CLAIM",
                "service": f"{rel}:{lineno}",
                "message": f"Unverifizierte Absichts-Behauptung ({', '.join(sorted(set(w.lower() for w in words)))}): "
                           f"{comment.strip()[:160]}",
                "has_reference": has_reference,
            })
    return findings


def analyze(nodes: dict[str, Node], key_map: dict[str, str], bridge: set[str]) -> list[dict]:
    findings = []

    def add(kind: str, service: str, msg: str):
        findings.append({"kind": kind, "service": service, "message": msg})

    global_names = {n for n, node in nodes.items() if node.scope == "global"}
    session_names = {n for n, node in nodes.items() if node.scope == "session"}

    for name, node in nodes.items():
        if node.kind != "service":
            continue

        # MISSING_FILE
        if node.path:
            full = PROJECT_ROOT / node.path.replace("res://", "")
            if not full.exists():
                add("MISSING_FILE", name, f"path='{node.path}' existiert nicht auf Disk")

        # BROKEN_DEP
        for dep in node.required + node.optional:
            if dep not in nodes:
                add("BROKEN_DEP", name, f"deklariert Dep '{dep}', die in keiner ServiceDefinition/ResourceDefinition/Infra existiert")

        # SCOPE_VIOLATION — global service depending on a session service
        if node.scope == "global":
            for dep in node.required + node.optional:
                if dep in session_names:
                    add("SCOPE_VIOLATION", name,
                        f"Global-Service hängt von Session-Service '{dep}' ab — bootet vor ihm, kann nicht aufgelöst werden")

        # UNBRIDGED_CROSS_SCOPE — session service depending on a global service
        # whose ServiceKeys const isn't in the BootPipeline bridge list (ADR-017)
        if node.scope == "session":
            for dep in node.required + node.optional:
                if dep in global_names:
                    const = key_map.get(dep)
                    if const is None or const not in bridge:
                        add("UNBRIDGED_CROSS_SCOPE", name,
                            f"Dep '{dep}' ist ein Global-Service, aber sein ServiceKeys-Const ist NICHT in "
                            f"BootPipeline._bridge_app_services_into_session() → deps.require()/get_optional() "
                            f"bekommt zur Laufzeit still null (ADR-017)")

        # NO_SERVICE_KEY
        if name not in key_map:
            add("NO_SERVICE_KEY", name, "kein passendes const in ServiceKeys.gd — Magic String statt Compile-Zeit-Schutz")

        # NO_TEST_FOUND (best effort — grep nach class_name in tests/unit)
        if node.class_name and TESTS_DIR.exists():
            found = False
            for tf in TESTS_DIR.glob("*.gd"):
                if node.class_name in tf.read_text(encoding="utf-8", errors="replace"):
                    found = True
                    break
            if not found:
                add("NO_TEST_FOUND", name, f"keine Testdatei in tests/unit referenziert Klasse '{node.class_name}'")

    cycles = find_cycles(nodes)
    for cyc in cycles:
        add("CYCLE", ", ".join(cyc), "Zyklus in required+optional Deps — Boot-Reihenfolge unauflösbar")

    return findings


def siblings_of(nodes: dict[str, Node], name: str) -> list[str]:
    """Andere Services, die mind. 1 Dep mit `name` teilen — 'was existiert
    schon in der Nähe dessen was ich gerade baue'."""
    if name not in nodes:
        return []
    my_deps = set(nodes[name].required + nodes[name].optional)
    if not my_deps:
        return []
    result = []
    for other, node in nodes.items():
        if other == name or node.kind != "service":
            continue
        other_deps = set(node.required + node.optional)
        if my_deps & other_deps:
            result.append(other)
    return sorted(result)


# ─────────────────────────────────────────────────────────────────────────────
# Output
# ─────────────────────────────────────────────────────────────────────────────

def service_to_dict(nodes: dict[str, Node], name: str, key_map: dict[str, str]) -> dict:
    node = nodes[name]
    return {
        "name": name,
        "scope": node.scope or node.kind,
        "path": node.path,
        "class_name": node.class_name,
        "service_key_const": key_map.get(name),
        "required_deps": node.required,
        "optional_deps": node.optional,
        "dependents": sorted(node.dependents),
        "siblings": siblings_of(nodes, name),
    }


def print_service_card(nodes: dict[str, Node], name: str, key_map: dict[str, str]):
    if name not in nodes:
        print(f"Unbekannter Service/Key: '{name}'")
        print("Verfügbare Namen (Ausschnitt):", ", ".join(sorted(nodes)[:20]), "...")
        sys.exit(1)
    node = nodes[name]
    print(f"── {name} " + "─" * max(1, 50 - len(name)))
    print(f"  scope:          {node.scope or node.kind}")
    print(f"  path:           {node.path or '(keine — Resource/Infra)'}")
    print(f"  class_name:     {node.class_name or '-'}")
    print(f"  ServiceKeys:    {key_map.get(name, '⚠ FEHLT')}")
    print(f"  required_deps:  {node.required or '-'}")
    print(f"  optional_deps:  {node.optional or '-'}")
    print(f"  dependents ({len(node.dependents)}): {sorted(node.dependents) or '-'}")
    sibs = siblings_of(nodes, name)
    print(f"  siblings ({len(sibs)}): {sibs or '-'}")


def print_full_report(nodes: dict[str, Node], findings: list[dict], key_map: dict[str, str]):
    services = {n: node for n, node in nodes.items() if node.kind == "service"}
    print("=" * 70)
    print("  WildGrove Service Graph")
    print("=" * 70)
    print(f"\n{len(services)} Services  |  "
          f"{sum(1 for n in nodes.values() if n.kind == 'resource')} Resources  |  "
          f"{sum(1 for n in nodes.values() if n.kind == 'infra')} Infra-Keys\n")

    for scope in ("global", "session"):
        order = topo_order(nodes, scope)
        print(f"Boot-Reihenfolge [{scope}] ({len(order)}):")
        print("  " + " → ".join(order) if order else "  (leer)")
        print()

    print("-" * 70)
    errors = [f for f in findings if f["kind"] in ERROR_KINDS]
    warns = [f for f in findings if f["kind"] in WARN_KINDS]

    if errors:
        print(f"\n❌ {len(errors)} ERROR-Findings:\n")
        for f in errors:
            print(f"  [{f['kind']}] {f['service']}: {f['message']}")
    else:
        print("\n✅ Keine ERROR-Findings (keine Broken Deps / Cycles / Scope-Violations / Missing Files).")

    if warns:
        print(f"\n⚠️  {len(warns)} WARN-Findings:\n")
        by_kind: dict[str, list] = {}
        for f in warns:
            by_kind.setdefault(f["kind"], []).append(f)
        for kind, items in by_kind.items():
            print(f"  {kind} ({len(items)}):")
            for f in items:
                print(f"    - {f['service']}: {f['message']}")
            print()

    print("-" * 70)
    print("\nTop 10 nach Fan-in (Blast-Radius — viele Abhängige = riskant zu ändern):\n")
    ranked = sorted(services.items(), key=lambda kv: len(kv[1].dependents), reverse=True)[:10]
    for n, node in ranked:
        if node.dependents:
            print(f"  {len(node.dependents):>2}  {n}  <- {sorted(node.dependents)}")
    print()


def print_events_report(events: dict, findings: list[dict]):
    print("=" * 70)
    print("  WildGrove Event Graph")
    print("=" * 70)
    print(f"\n{len(events)} Signale erfasst.\n")
    dead = [f for f in findings if f["kind"] == "DEAD_EVENT"]
    unconsumed = [f for f in findings if f["kind"] == "UNCONSUMED_EVENT"]
    broken = [f for f in findings if f["kind"] == "BROKEN_EVENT_REF"]
    direct_ui = [f for f in findings if f["kind"] == "DIRECT_EVENTBUS_ACCESS_IN_UI"]
    mismatch = [f for f in findings if f["kind"] == "EMIT_WRAPPER_NAME_MISMATCH"]
    collision = [f for f in findings if f["kind"] == "NATIVE_SIGNAL_EVENTBUS_COLLISION"]
    unresolved = [f for f in findings if f["kind"] == "EMIT_WRAPPER_UNRESOLVED"]

    if unresolved:
        print(f"❌ {len(unresolved)} EMIT_WRAPPER_UNRESOLVED (Ziel-Signal nicht verifizierbar):")
        for f in unresolved:
            print(f"  - {f['service']}: {f['message']}")
        print()
    if broken:
        print(f"❌ {len(broken)} BROKEN_EVENT_REF:")
        for f in broken:
            print(f"  - {f['service']}: {f['message']}")
        print()
    if dead:
        print(f"⚠️  {len(dead)} DEAD_EVENT (deklariert, nie emittiert):")
        for f in dead:
            print(f"  - {f['service']}")
        print()
    if unconsumed:
        print(f"⚠️  {len(unconsumed)} UNCONSUMED_EVENT (emittiert, nie connected):")
        for f in unconsumed:
            print(f"  - {f['service']}")
        print()
    if direct_ui:
        print(f"⚠️  {len(direct_ui)} UI-Dateien mit Pfad-A-Zugriff (statt IEventBus, ADR-012):")
        for f in direct_ui:
            print(f"  - {f['service']}: {f['message']}")
        print()
    if mismatch:
        print(f"⚠️  {len(mismatch)} EMIT_WRAPPER_NAME_MISMATCH (Wrapper-Name ≠ Signal-Name):")
        for f in mismatch:
            print(f"  - {f['service']}: {f['message']}")
        print()
    if collision:
        print(f"⚠️  {len(collision)} NATIVE_SIGNAL_EVENTBUS_COLLISION (Mess-Finding TODO Punkt 7):")
        for f in collision:
            print(f"  - {f['service']}: {f['message']}")
        print()
    if not (broken or dead or unconsumed or direct_ui or mismatch or collision or unresolved):
        print("✅ Keine Findings.")


def print_interfaces_report(interfaces: dict, findings: list[dict]):
    print("=" * 70)
    print("  WildGrove Interface Conformance")
    print("=" * 70)
    for cls, data in interfaces.items():
        print(f"\n── {cls} ({data['path']}) " + "─" * 10)
        print(f"  extends-Implementierer:      {data['implementers_via_extends'] or '-'}")
        print(f"  nur-Kommentar-Implementierer: {data['implementers_via_comment_only'] or '-'}")
        for m in data["methods"]:
            flag = {"ASSERT_FALSE_GUARD": "⚠", "NON_TRIVIAL": "⚠"}.get(m["body_kind"], " ")
            print(f"  {flag} {m['name']}(): {m['body_kind']}")

    print("\n" + "-" * 70)
    by_kind: dict[str, list] = {}
    for f in findings:
        by_kind.setdefault(f["kind"], []).append(f)
    if not findings:
        print("\n✅ Keine Findings.")
    for kind, items in by_kind.items():
        marker = "❌" if kind in ERROR_KINDS else "⚠️ "
        print(f"\n{marker} {kind} ({len(items)}):")
        for f in items:
            print(f"  - {f['service']}: {f['message']}")


def to_dot(nodes: dict[str, Node]) -> str:
    lines = ["digraph services {", '  rankdir="LR";', '  node [shape=box, fontsize=10];']
    for n, node in nodes.items():
        if node.kind == "service":
            color = "lightblue" if node.scope == "global" else "lightyellow"
        else:
            color = "lightgray"
        lines.append(f'  "{n}" [style=filled, fillcolor={color}];')
    for n, node in nodes.items():
        for dep in node.required:
            lines.append(f'  "{dep}" -> "{n}";')
        for dep in node.optional:
            lines.append(f'  "{dep}" -> "{n}" [style=dashed];')
    lines.append("}")
    return "\n".join(lines)


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--service", help="Nur diesen einzelnen Service/Resource-Key ausgeben")
    ap.add_argument("--events", action="store_true",
                     help="Nur Event-Graph ausgeben (Namespaces/Signale, Pfad A vs. B, dead/unconsumed)")
    ap.add_argument("--interfaces", action="store_true",
                     help="Nur Interface-Konformität ausgeben (extends vs. Kommentar, Stub-Klassifikation)")
    ap.add_argument("--claims", action="store_true",
                     help="Nur unverifizierte 'bewusst'/'Absicht'/'Ausnahme'-Kommentare (TODO Punkt 9). "
                          "Nicht im Default enthalten (214 Treffer würden den Default-Lauf zuspammen).")
    ap.add_argument("--native-signals", action="store_true",
                     help="ADR-050 Phase 4: native Signal->Domain-Event-Migrationsstand "
                          "(CROSS_LAYER-Kandidaten, Regressionsschutz). Nicht im Default "
                          "enthalten — eigener, teurerer Scan (importiert analyze_native_signals.py).")
    ap.add_argument("--pretty", action="store_true",
                     help="Menschenlesbares Text-Report statt JSON (JSON ist der Default)")
    ap.add_argument("--dot", action="store_true", help="Graphviz-DOT auf stdout")
    args = ap.parse_args()

    if args.events:
        ns_map = parse_event_namespaces(EVENT_BUS_GD)
        event_index = build_event_index(ns_map)
        events_out, ev_findings = analyze_events(event_index)
        if args.pretty:
            print_events_report(events_out, ev_findings)
        else:
            print(json.dumps({"events": events_out, "findings": ev_findings}, indent=2, ensure_ascii=False))
        sys.exit(1 if any(f["kind"] in ERROR_KINDS for f in ev_findings) else 0)

    if args.interfaces:
        interfaces_out, if_findings = analyze_interfaces()
        if args.pretty:
            print_interfaces_report(interfaces_out, if_findings)
        else:
            print(json.dumps({"interfaces": interfaces_out, "findings": if_findings}, indent=2, ensure_ascii=False))
        sys.exit(1 if any(f["kind"] in ERROR_KINDS for f in if_findings) else 0)

    if args.claims:
        claim_findings = analyze_intentional_claims()
        with_ref = sum(1 for f in claim_findings if f["has_reference"])
        if args.pretty:
            print("=" * 70)
            print("  Unverifizierte Absichts-Behauptungen (TODO Punkt 9)")
            print("=" * 70)
            print(f"\n{len(claim_findings)} Treffer gesamt — {with_ref} mit ADR-/TODO-Referenz in der Nähe, "
                  f"{len(claim_findings) - with_ref} ohne.")
            print("Referenz macht nachschlagbar, nicht automatisch korrekt — beide Gruppen unten, "
                  "keine ist vorgefiltert.\n")
            for f in claim_findings:
                ref = "[ADR/TODO in Nähe]" if f["has_reference"] else "[KEINE Referenz]"
                print(f"  {ref:20} {f['service']}: {f['message']}")
        else:
            print(json.dumps({"findings": claim_findings}, indent=2, ensure_ascii=False))
        sys.exit(0)  # WARN-only Check, kein Exit-Fail — siehe analyze_intentional_claims()-Docstring.

    if args.native_signals:
        ns_report, ns_findings = analyze_native_signal_migration()
        if args.pretty:
            print_native_signal_report(ns_report, ns_findings)
        else:
            print(json.dumps({"native_signals": ns_report, "findings": ns_findings},
                              indent=2, ensure_ascii=False))
        sys.exit(0)  # WARN-only, kein Fail-Exit — reine Migrations-Fortschrittsmessung.

    cfg = parse_bootstrap_config(BOOTSTRAP_TRES)
    key_map = parse_service_keys(SERVICE_KEYS_GD)
    bridge = parse_bridge_list(BOOT_PIPELINE_GD)
    nodes = build_graph(cfg, key_map)

    total_declared = len(cfg["global_services"]) + len(cfg["session_services"])
    if total_declared == 0:
        print("FEHLER: 0 Services aus BootstrapConfig.tres geparst — Parser vermutlich kaputt "
              "(Datei-Format geändert?). Breche ab statt falsche Daten zu zeigen.", file=sys.stderr)
        sys.exit(2)

    if args.dot:
        print(to_dot(nodes))
        return

    if args.service and args.service not in nodes:
        if args.pretty:
            print_service_card(nodes, args.service, key_map)  # exits 1 with a helpful message
        print(json.dumps({"error": f"unknown service/key '{args.service}'",
                           "available": sorted(nodes)}, indent=2, ensure_ascii=False))
        sys.exit(1)

    if args.pretty:
        if args.service:
            print_service_card(nodes, args.service, key_map)
        else:
            findings = analyze(nodes, key_map, bridge)
            findings += analyze_raw_string_service_lookups(key_map)
            ns_map = parse_event_namespaces(EVENT_BUS_GD)
            events_out, ev_findings = analyze_events(build_event_index(ns_map))
            interfaces_out, if_findings = analyze_interfaces()
            print_full_report(nodes, findings, key_map)
            print()
            print_events_report(events_out, ev_findings)
            print()
            print_interfaces_report(interfaces_out, if_findings)
            all_findings = findings + ev_findings + if_findings
            if any(f["kind"] in ERROR_KINDS for f in all_findings):
                sys.exit(1)
        return

    # Default: JSON.
    if args.service:
        out = service_to_dict(nodes, args.service, key_map)
        print(json.dumps(out, indent=2, ensure_ascii=False))
        return

    findings = analyze(nodes, key_map, bridge)
    findings += analyze_raw_string_service_lookups(key_map)
    ns_map = parse_event_namespaces(EVENT_BUS_GD)
    events_out, ev_findings = analyze_events(build_event_index(ns_map))
    interfaces_out, if_findings = analyze_interfaces()
    all_findings = findings + ev_findings + if_findings
    out = {
        "services": {
            n: service_to_dict(nodes, n, key_map)
            for n, node in nodes.items() if node.kind == "service"
        },
        "boot_order": {
            "global": topo_order(nodes, "global"),
            "session": topo_order(nodes, "session"),
        },
        "events": events_out,
        "interfaces": interfaces_out,
        "findings": all_findings,
    }
    print(json.dumps(out, indent=2, ensure_ascii=False))

    if any(f["kind"] in ERROR_KINDS for f in all_findings):
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()

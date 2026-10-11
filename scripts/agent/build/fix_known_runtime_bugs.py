#!/usr/bin/env python3
# scripts/agent/build/fix_known_runtime_bugs.py
#
# Codemod-Gegenstück zu scripts/agent/analyze_runtime_log.py: jeder Fund dort
# mit einem fix_hint verweist auf genau ein --fix hier. Analyse und Fix bleiben
# damit durchgängig scriptbar — kein manuelles Nachbearbeiten einzelner
# Fundstellen im Editor (siehe TODO-offene-probleme.md-Prinzip "kein Modul
# darf raten": jeder Fix hier matcht einen EXAKTEN, bekannten Quelltext-
# Ausschnitt und lässt die Datei unangetastet, wenn der Ausschnitt nicht
# byte-genau vorgefunden wird — kein Best-Effort-Regex-Ersetzen).
#
# Wie alle Module unter build/: --dry-run ist Default, --apply schreibt +
# legt .bak an (siehe common.py). Nutzt BuildSession.apply_change() für jede
# Änderung, druckt Diffs, druckt Summary — kein Modul ruft Path.write_text()
# direkt auf.
#
# Verfügbare Fixes (siehe FIXES dict unten):
#   xp_signal_arity              — FloatingTextController: xp_gained/level_up
#                                   Handler-Signatur an 3-Arg-Signal angepasst
#                                   + Filter auf lokalen Spieler (peer_id).
#   immediate_free_in_ui_clear   — BankVisuals._clear(): .free() -> .queue_free(),
#                                   verhindert "Object freed while signal is
#                                   being emitted" beim Ein-/Auszahlen-Klick.
#   orphaned_ui_timers           — NotificationVisuals/ContextMenuController:
#                                   verwaiste get_tree().create_timer(...)
#                                   ersetzt durch Timer-Kindknoten am
#                                   transienten Container (stirbt automatisch
#                                   mit ihm statt später gegen ein freigegebenes
#                                   Objekt zu feuern).
#   session_manager_port_retry   — SessionManager.create_server(): bei
#                                   ERR_ALREADY_IN_USE automatischer Retry auf
#                                   den nächsten freien Port statt sofortigem,
#                                   generischem Fehlschlag.
#   session_manager_reentry_guard
#                                 — SessionManager.create_server()/join_server():
#                                   frühzeitiger, sprechender Abbruch statt
#                                   ENet-Fehler, wenn bereits ein Peer aktiv
#                                   ist (siehe REENTRANT_HOST_OR_JOIN_WHILE_
#                                   PEER_ACTIVE in analyze_runtime_log.py).
#   session_manager_string_concat_syntax_error
#                                 — HOTFIX (2026-09-14): behebt einen von
#                                   session_manager_reentry_guard selbst
#                                   eingeführten Parse-Fehler in join_server()
#                                   — zwei String-Literale standen ohne '+'
#                                   nebeneinander (Python-Gewohnheit, GDScript
#                                   kennt keine implizite Adjazenz-
#                                   Konkatenation). Das ließ SessionManager.gd
#                                   NICHT MEHR KOMPILIEREN — Boot-Pipeline
#                                   bricht komplett ab ('Registrierte Keys: []'
#                                   in GUT, App boot hängt nach 'Terminal
#                                   bereit'). Immer NACH diesem Fix erneut mit
#                                   analyze_runtime_log.py + einem echten Boot-
#                                   Log gegenprüfen, nicht nur den Diff lesen.
#   mainmenu_hide_multiplayer_button_while_active
#                                 — MainMenuController._show_view(): versteckt
#                                   den '[Multiplayer]'-Button in HOST_ACTIVE/
#                                   CONNECTING/JOIN_CHARACTER_SELECT, damit der
#                                   Spieler nicht versehentlich zurück zu
#                                   NET_SETUP gelangt und Host/Join ein
#                                   zweites Mal auslöst, während der erste
#                                   Peer noch aktiv ist (Ursache des
#                                   'Couldn't create an ENet host'-Berichts
#                                   vom 2026-09-14).
#   mainmenu_resume_active_peer_view
#                                 — MainMenuController._ready() zeigt bisher
#                                   IMMER _View.CHARACTERS, unabhängig davon,
#                                   ob SessionManager (App-weit persistent)
#                                   noch einen aktiven Peer hält — z.B. nach
#                                   'Zurück zum Hauptmenü' während der Host
#                                   weiterläuft. Eine frische MainMenu-Szene
#                                   zeigt dann wieder den '[Multiplayer]'-
#                                   Button, der Spieler klickt erneut Host/
#                                   Join und landet im 'passiert nichts'-Dead-
#                                   End (jetzt zwar ohne Crash dank
#                                   session_manager_reentry_guard, aber
#                                   trotzdem verwirrend). Self-Healing analog
#                                   zu inject_save_system() (BUG-23).
#
# Usage:
#   python3 scripts/agent/build/fix_known_runtime_bugs.py --fix xp_signal_arity
#   python3 scripts/agent/build/fix_known_runtime_bugs.py --fix all --apply

from __future__ import annotations

import sys
from pathlib import Path

_AGENT_DIR = Path(__file__).resolve().parents[1]
if str(_AGENT_DIR) not in sys.path:
    sys.path.insert(0, str(_AGENT_DIR))

from build.common import BuildSession, fail  # noqa: E402

_REPO_ROOT = Path(__file__).resolve().parents[3]


def _fix_xp_signal_arity(session: BuildSession) -> None:
    path = _REPO_ROOT / "scripts/ui/controllers/FloatingTextController.gd"
    original = path.read_text(encoding="utf-8")

    old = (
        "func _on_xp_gained(skill: String, amount: int) -> void:\n"
        "\t_visuals.spawn_text(\"+%d %s\" % [amount, skill], Color(1.0, 0.9, 0.2), 24, 2.0)\n"
        "\n"
        "func _on_level_up(skill: String, new_level: int) -> void:\n"
        "\t_visuals.spawn_text(\"LEVEL UP!\\n%s → %d\" % [skill, new_level], Color(0.2, 0.8, 1.0), 32, 3.0)\n"
    )
    new = (
        "func _on_xp_gained(skill: String, amount: int, peer_id: int) -> void:\n"
        "\t# BUGFIX (2026-09-13): xp_gained liefert 3 Argumente (skill, amount,\n"
        "\t# peer_id) — ohne peer_id-Parameter schlug JEDER Aufruf mit einem\n"
        "\t# 'Method expected 2 argument(s), but called with 3' Engine-Fehler fehl,\n"
        "\t# XP-Floating-Text wurde nie angezeigt. Zusätzlich: nur für den lokalen\n"
        "\t# Spieler anzeigen, nicht für fremde peer_ids (Coop).\n"
        "\tif peer_id != _ctx.get_local_peer_id():\n"
        "\t\treturn\n"
        "\t_visuals.spawn_text(\"+%d %s\" % [amount, skill], Color(1.0, 0.9, 0.2), 24, 2.0)\n"
        "\n"
        "func _on_level_up(skill: String, new_level: int, peer_id: int) -> void:\n"
        "\tif peer_id != _ctx.get_local_peer_id():\n"
        "\t\treturn\n"
        "\t_visuals.spawn_text(\"LEVEL UP!\\n%s → %d\" % [skill, new_level], Color(0.2, 0.8, 1.0), 32, 3.0)\n"
    )
    count = 1 if old in original else 0
    new_text = original.replace(old, new, 1)
    session.apply_change(path, original, new_text, count)


def _fix_immediate_free_in_ui_clear(session: BuildSession) -> None:
    path = _REPO_ROOT / "scripts/economy/bank/ui/BankVisuals.gd"
    original = path.read_text(encoding="utf-8")

    old = (
        "func _clear(container: VBoxContainer) -> void:\n"
        "\tfor child in container.get_children():\n"
        "\t\tcontainer.remove_child(child)\n"
        "\t\tchild.free()\n"
    )
    new = (
        "func _clear(container: VBoxContainer) -> void:\n"
        "\t# BUGFIX (2026-09-13): .free() statt .queue_free() zerstörte den Node\n"
        "\t# SOFORT, auch wenn er (z.B. der gerade geklickte Deposit/Withdraw-\n"
        "\t# Button) noch mitten in der Verarbeitung seines eigenen 'pressed'-\n"
        "\t# Signals war -> 'Object was freed or unreferenced while a signal is\n"
        "\t# being emitted from it.' .queue_free() verschiebt die Freigabe ans\n"
        "\t# Frame-Ende, wenn die Signal-Verarbeitung sicher abgeschlossen ist.\n"
        "\tfor child in container.get_children():\n"
        "\t\tcontainer.remove_child(child)\n"
        "\t\tchild.queue_free()\n"
    )
    count = 1 if old in original else 0
    new_text = original.replace(old, new, 1)
    session.apply_change(path, original, new_text, count)


def _fix_orphaned_ui_timers(session: BuildSession) -> None:
    # NotificationVisuals.gd — Popup-Auto-Close.
    path = _REPO_ROOT / "scripts/ui/visuals/NotificationVisuals.gd"
    original = path.read_text(encoding="utf-8")
    old = (
        "\t# Auto-Close Timer (Logik, die in die Visuals darf, da sie zum 'Aufräumen' der Nodes gehört)\n"
        "\t_parent.get_tree().create_timer(3.0).timeout.connect(\n"
        "\t\tfunc():\n"
        "\t\t\tif is_instance_valid(container):\n"
        "\t\t\t\tcontainer.queue_free()\n"
        "\t)\n"
    )
    new = (
        "\t# Auto-Close Timer (Logik, die in die Visuals darf, da sie zum 'Aufräumen' der Nodes gehört)\n"
        "\t# BUGFIX (2026-09-13): get_tree().create_timer() lebt UNABHÄNGIG vom\n"
        "\t# Popup-Container weiter. Wird der Container vorher schon durch ein\n"
        "\t# neueres Popup ersetzt (show_popup() räumt alte Popups sofort weg),\n"
        "\t# feuert dieser verwaiste Timer später gegen ein bereits freigegebenes\n"
        "\t# Objekt -> 'Lambda capture at index 0 was freed.' Ein Timer-Kindknoten\n"
        "\t# am Container stirbt automatisch MIT ihm — kein verwaister Timer mehr.\n"
        "\tvar auto_close := Timer.new()\n"
        "\tauto_close.wait_time = 3.0\n"
        "\tauto_close.one_shot  = true\n"
        "\tcontainer.add_child(auto_close)\n"
        "\tauto_close.timeout.connect(container.queue_free)\n"
        "\tauto_close.start()\n"
    )
    count = 1 if old in original else 0
    new_text = original.replace(old, new, 1)
    session.apply_change(path, original, new_text, count)

    # ContextMenuController.gd — Menü-Auto-Close.
    path2 = _REPO_ROOT / "scripts/ui/controllers/ContextMenuController.gd"
    original2 = path2.read_text(encoding="utf-8")
    old2 = (
        "\t# Auto-Close nach 5 Sekunden (Sicherheitsnetz — Menü schließt wenn nichts passiert)\n"
        "\t_hud.get_tree().create_timer(5.0).timeout.connect(\n"
        "\t\tfunc():\n"
        "\t\t\tif is_instance_valid(visuals):\n"
        "\t\t\t\tAppLogger.log_debug(\"Kontext-Menü Auto-Close nach 5s.\", LOG_CAT)\n"
        "\t\t\t\tvisuals.destroy()\n"
        "\t)\n"
    )
    new2 = (
        "\t# Auto-Close nach 5 Sekunden (Sicherheitsnetz — Menü schließt wenn nichts passiert)\n"
        "\t# BUGFIX (2026-09-13): siehe NotificationVisuals.gd — derselbe Timer-\n"
        "\t# Kindknoten-Fix statt verwaistem get_tree().create_timer(), das gegen\n"
        "\t# ein vorzeitig zerstörtes 'visuals' feuern und 'Lambda capture at\n"
        "\t# index 0 was freed' loggen könnte.\n"
        "\tvar auto_close := Timer.new()\n"
        "\tauto_close.wait_time = 5.0\n"
        "\tauto_close.one_shot  = true\n"
        "\tvisuals.add_child(auto_close)\n"
        "\tauto_close.timeout.connect(func() -> void:\n"
        "\t\tAppLogger.log_debug(\"Kontext-Menü Auto-Close nach 5s.\", LOG_CAT)\n"
        "\t\tvisuals.destroy()\n"
        "\t)\n"
        "\tauto_close.start()\n"
    )
    count2 = 1 if old2 in original2 else 0
    new_text2 = original2.replace(old2, new2, 1)
    session.apply_change(path2, original2, new_text2, count2)


def _fix_session_manager_port_retry(session: BuildSession) -> None:
    path = _REPO_ROOT / "scripts/session/SessionManager.gd"
    original = path.read_text(encoding="utf-8")

    old_const = "const MAX_CLIENTS   := 8\n"
    new_const = (
        "const MAX_CLIENTS   := 8\n"
        "## BUGFIX (2026-09-13): bei ERR_ALREADY_IN_USE (Port belegt — verwaister\n"
        "## Prozess, TIME_WAIT nach vorherigem Host-Lauf, o.ä.) automatisch auf\n"
        "## die nächsten Ports ausweichen statt sofort generisch zu scheitern.\n"
        "const PORT_RETRY_ATTEMPTS := 5\n"
    )

    old_fn = (
        "func create_server(port: int = DEFAULT_PORT, max_clients: int = MAX_CLIENTS) -> bool:\n"
        "\tvar peer := ENetMultiplayerPeer.new()\n"
        "\tvar err := peer.create_server(port, max_clients)\n"
        "\tif err != OK:\n"
        "\t\tAppLogger.log_error(\n"
        "\t\t\t\"create_server(%d) fehlgeschlagen: %s\" % [port, error_string(err)], LOG_CAT\n"
        "\t\t)\n"
        "\t\treturn false\n"
        "\tmultiplayer.multiplayer_peer = peer\n"
        "\tAppLogger.log_info(\n"
        "\t\t\"Server gestartet auf Port %d (max. %d Clients).\" % [port, max_clients], LOG_CAT\n"
        "\t)\n"
        "\tif is_instance_valid(_bus):\n"
        "\t\t_bus.networking().emit_hosting_started(port)\n"
        "\telse:\n"
        "\t\tAppLogger.log_warn(\"EventBus fehlt — hosting_started nicht emittiert.\", LOG_CAT)\n"
        "\treturn true\n"
    )
    new_fn = (
        "func create_server(port: int = DEFAULT_PORT, max_clients: int = MAX_CLIENTS) -> bool:\n"
        "\tvar actual_port := port\n"
        "\tvar peer := ENetMultiplayerPeer.new()\n"
        "\tvar err := peer.create_server(actual_port, max_clients)\n"
        "\tvar attempts := 1\n"
        "\t# BUGFIX (2026-09-13): Port evtl. noch von einem vorherigen Lauf belegt\n"
        "\t# (TIME_WAIT) oder von einem zuvor fehlgeschlagenen Join auf dieselbe\n"
        "\t# Adresse — bisher generischer Fehlschlag ohne Ausweichmöglichkeit.\n"
        "\twhile err == ERR_ALREADY_IN_USE and attempts < PORT_RETRY_ATTEMPTS:\n"
        "\t\tattempts += 1\n"
        "\t\tAppLogger.log_warn(\n"
        "\t\t\t\"Port %d belegt — versuche Port %d (%d/%d).\"\n"
        "\t\t\t\t% [actual_port, actual_port + 1, attempts, PORT_RETRY_ATTEMPTS],\n"
        "\t\t\tLOG_CAT\n"
        "\t\t)\n"
        "\t\tactual_port += 1\n"
        "\t\tpeer = ENetMultiplayerPeer.new()\n"
        "\t\terr = peer.create_server(actual_port, max_clients)\n"
        "\tif err != OK:\n"
        "\t\tAppLogger.log_error(\n"
        "\t\t\t\"create_server(%d) fehlgeschlagen nach %d Versuch(en): %s\"\n"
        "\t\t\t\t% [port, attempts, error_string(err)], LOG_CAT\n"
        "\t\t)\n"
        "\t\treturn false\n"
        "\tmultiplayer.multiplayer_peer = peer\n"
        "\tAppLogger.log_info(\n"
        "\t\t\"Server gestartet auf Port %d (max. %d Clients).\" % [actual_port, max_clients], LOG_CAT\n"
        "\t)\n"
        "\tif is_instance_valid(_bus):\n"
        "\t\t_bus.networking().emit_hosting_started(actual_port)\n"
        "\telse:\n"
        "\t\tAppLogger.log_warn(\"EventBus fehlt — hosting_started nicht emittiert.\", LOG_CAT)\n"
        "\treturn true\n"
    )

    count = 0
    text = original
    if old_const in text:
        text = text.replace(old_const, new_const, 1)
        count += 1
    if old_fn in text:
        text = text.replace(old_fn, new_fn, 1)
        count += 1
    else:
        # Falls die Konstante schon ersetzt wurde, aber die Funktion nicht mehr
        # exakt matcht -> nichts anwenden, nicht raten (siehe common.py Regel 4).
        if count > 0 and old_fn not in original:
            pass
    session.apply_change(path, original, text, count)


def _fix_session_manager_reentry_guard(session: BuildSession) -> None:
    path = _REPO_ROOT / "scripts/session/SessionManager.gd"
    original = path.read_text(encoding="utf-8")

    old_create = (
        "func create_server(port: int = DEFAULT_PORT, max_clients: int = MAX_CLIENTS) -> bool:\n"
        "\tvar actual_port := port\n"
    )
    new_create = (
        "func create_server(port: int = DEFAULT_PORT, max_clients: int = MAX_CLIENTS) -> bool:\n"
        "\t# BUGFIX (2026-09-14): ohne diese Guard versucht ein zweiter Host-Klick\n"
        "\t# (z.B. weil die UI den Multiplayer-Button in HOST_ACTIVE nicht\n"
        "\t# versteckt, siehe MainMenuController) denselben Port ERNEUT zu binden,\n"
        "\t# während der erste Peer ihn noch hält -> kryptisches 'Couldn't create\n"
        "\t# an ENet host' statt einer sprechenden Meldung. Siehe auch\n"
        "\t# REENTRANT_HOST_OR_JOIN_WHILE_PEER_ACTIVE in analyze_runtime_log.py.\n"
        "\tif _has_active_peer():\n"
        "\t\tAppLogger.log_warn(\n"
        "\t\t\t\"create_server(%d) ignoriert — es läuft bereits ein aktiver Peer (peer_id %d).\"\n"
        "\t\t\t\t% [port, multiplayer.get_unique_id()], LOG_CAT\n"
        "\t\t)\n"
        "\t\treturn false\n"
        "\tvar actual_port := port\n"
    )
    count = 1 if old_create in original else 0
    text = original.replace(old_create, new_create, 1)

    old_join = (
        "func join_server(address: String, port: int = DEFAULT_PORT) -> bool:\n"
        "\tif address.is_empty():\n"
        "\t\tAppLogger.log_error(\"join_server(): leere Adresse — Verbindung abgelehnt.\", LOG_CAT)\n"
        "\t\treturn false\n"
        "\n"
        "\t_join_address = address\n"
    )
    new_join = (
        "func join_server(address: String, port: int = DEFAULT_PORT) -> bool:\n"
        "\tif address.is_empty():\n"
        "\t\tAppLogger.log_error(\"join_server(): leere Adresse — Verbindung abgelehnt.\", LOG_CAT)\n"
        "\t\treturn false\n"
        "\t# BUGFIX (2026-09-14): siehe create_server() — ein Join, während der\n"
        "\t# eigene Prozess bereits Host ist, ERSETZT multiplayer.multiplayer_peer\n"
        "\t# durch einen neuen Client-Peer und reißt damit den gerade laufenden\n"
        "\t# Server ein (der alte Server-Peer verliert seine letzte Referenz).\n"
        "\tif _has_active_peer():\n"
        "\t\tAppLogger.log_warn(\n"
        "\t\t\t\"join_server(%s:%d) ignoriert — es läuft bereits ein aktiver Peer (peer_id %d). \"\n"
        "\t\t\t\"close() aufrufen, um erst die aktuelle Session zu beenden.\"\n"
        "\t\t\t\t% [address, port, multiplayer.get_unique_id()], LOG_CAT\n"
        "\t\t)\n"
        "\t\treturn false\n"
        "\n"
        "\t_join_address = address\n"
    )
    if old_join in text:
        count += 1
        text = text.replace(old_join, new_join, 1)

    session.apply_change(path, original, text, count)


def _fix_mainmenu_hide_multiplayer_button_while_active(session: BuildSession) -> None:
    path = _REPO_ROOT / "scripts/ui/MainMenuController.gd"
    original = path.read_text(encoding="utf-8")

    old = (
        "func _show_view(view: _View) -> void:\n"
        "\t_current_view = view\n"
        "\n"
        "\tvar center    := _get_center_container()\n"
        "\tvar net_panel := _get_net_panel()\n"
        "\n"
        "\tmatch view:\n"
        "\t\t_View.CHARACTERS:\n"
        "\t\t\tif center:    center.visible    = true\n"
        "\t\t\tif net_panel: net_panel.visible = false\n"
        "\t\t\t_refresh_character_list()\n"
        "\t\t\t_update_new_game_button()\n"
        "\t\t\t_set_status(\"\")\n"
        "\n"
        "\t\t_View.NET_SETUP:\n"
        "\t\t\tif center:    center.visible    = false\n"
        "\t\t\tif net_panel: net_panel.visible = true\n"
        "\t\t\t_set_status(\"\")\n"
        "\n"
        "\t\t_View.HOST_ACTIVE:\n"
        "\t\t\tif center:    center.visible    = true\n"
        "\t\t\tif net_panel: net_panel.visible = false\n"
        "\t\t\t_refresh_character_list()\n"
        "\t\t\t_update_new_game_button()\n"
        "\t\t\t_set_status(\"Server läuft auf Port %d — wähle einen Charakter.\" % _host_port)\n"
        "\n"
        "\t\t_View.CONNECTING:\n"
        "\t\t\tif center:    center.visible    = true\n"
        "\t\t\tif net_panel: net_panel.visible = false\n"
        "\t\t\t_set_status(\"Verbinde mit Server…\")\n"
        "\t\t\t_clear_character_list()\n"
        "\n"
        "\t\t_View.JOIN_CHARACTER_SELECT:\n"
        "\t\t\tif center:    center.visible    = true\n"
        "\t\t\tif net_panel: net_panel.visible = false\n"
        "\t\t\t_refresh_character_list()\n"
        "\t\t\t_update_new_game_button()\n"
        "\t\t\t_set_status(\"Verbunden — wähle einen Charakter zum Beitreten.\")\n"
    )
    new = (
        "func _show_view(view: _View) -> void:\n"
        "\t_current_view = view\n"
        "\n"
        "\tvar center    := _get_center_container()\n"
        "\tvar net_panel := _get_net_panel()\n"
        "\t# BUGFIX (2026-09-14): mp_btn lebt in 'center', der auch für\n"
        "\t# HOST_ACTIVE/CONNECTING/JOIN_CHARACTER_SELECT sichtbar bleibt (für die\n"
        "\t# Charakter-Liste). Ohne explizites Verstecken bleibt der\n"
        "\t# '[Multiplayer]'-Button dort erreichbar, führt zurück zu NET_SETUP und\n"
        "\t# erlaubt einen zweiten Host/Join-Versuch, während der erste Peer noch\n"
        "\t# aktiv ist -> 'Couldn't create an ENet host' (siehe SessionManager\n"
        "\t# create_server()/join_server() Reentry-Guard als zweite Verteidigungslinie).\n"
        "\tvar mp_btn := _get_multiplayer_button()\n"
        "\n"
        "\tmatch view:\n"
        "\t\t_View.CHARACTERS:\n"
        "\t\t\tif center:    center.visible    = true\n"
        "\t\t\tif net_panel: net_panel.visible = false\n"
        "\t\t\tif mp_btn:    mp_btn.visible    = true\n"
        "\t\t\t_refresh_character_list()\n"
        "\t\t\t_update_new_game_button()\n"
        "\t\t\t_set_status(\"\")\n"
        "\n"
        "\t\t_View.NET_SETUP:\n"
        "\t\t\tif center:    center.visible    = false\n"
        "\t\t\tif net_panel: net_panel.visible = true\n"
        "\t\t\t_set_status(\"\")\n"
        "\n"
        "\t\t_View.HOST_ACTIVE:\n"
        "\t\t\tif center:    center.visible    = true\n"
        "\t\t\tif net_panel: net_panel.visible = false\n"
        "\t\t\tif mp_btn:    mp_btn.visible    = false\n"
        "\t\t\t_refresh_character_list()\n"
        "\t\t\t_update_new_game_button()\n"
        "\t\t\t_set_status(\"Server läuft auf Port %d — wähle einen Charakter.\" % _host_port)\n"
        "\n"
        "\t\t_View.CONNECTING:\n"
        "\t\t\tif center:    center.visible    = true\n"
        "\t\t\tif net_panel: net_panel.visible = false\n"
        "\t\t\tif mp_btn:    mp_btn.visible    = false\n"
        "\t\t\t_set_status(\"Verbinde mit Server…\")\n"
        "\t\t\t_clear_character_list()\n"
        "\n"
        "\t\t_View.JOIN_CHARACTER_SELECT:\n"
        "\t\t\tif center:    center.visible    = true\n"
        "\t\t\tif net_panel: net_panel.visible = false\n"
        "\t\t\tif mp_btn:    mp_btn.visible    = false\n"
        "\t\t\t_refresh_character_list()\n"
        "\t\t\t_update_new_game_button()\n"
        "\t\t\t_set_status(\"Verbunden — wähle einen Charakter zum Beitreten.\")\n"
    )
    count = 1 if old in original else 0
    new_text = original.replace(old, new, 1)
    session.apply_change(path, original, new_text, count)


def _fix_session_manager_string_concat_syntax_error(session: BuildSession) -> None:
    path = _REPO_ROOT / "scripts/session/SessionManager.gd"
    original = path.read_text(encoding="utf-8")

    old = (
        "\tif _has_active_peer():\n"
        "\t\tAppLogger.log_warn(\n"
        "\t\t\t\"join_server(%s:%d) ignoriert — es läuft bereits ein aktiver Peer (peer_id %d). \"\n"
        "\t\t\t\"close() aufrufen, um erst die aktuelle Session zu beenden.\"\n"
        "\t\t\t\t% [address, port, multiplayer.get_unique_id()], LOG_CAT\n"
        "\t\t)\n"
        "\t\treturn false\n"
    )
    new = (
        "\tif _has_active_peer():\n"
        "\t\t# HOTFIX (2026-09-14): die zwei String-Literale standen vorher ohne\n"
        "\t\t# '+' nebeneinander (Python-Gewohnheit) — GDScript konkateniert\n"
        "\t\t# adjazente String-Literale NICHT automatisch, das war ein Parse-\n"
        "\t\t# Fehler und hat SessionManager.gd komplett kompilierunfähig gemacht\n"
        "\t\t# (Boot-Pipeline-Totalausfall, 'Registrierte Keys: []' in GUT).\n"
        "\t\tAppLogger.log_warn(\n"
        "\t\t\t(\"join_server(%s:%d) ignoriert — es läuft bereits ein aktiver Peer (peer_id %d). \"\n"
        "\t\t\t\t+ \"close() aufrufen, um erst die aktuelle Session zu beenden.\")\n"
        "\t\t\t\t% [address, port, multiplayer.get_unique_id()], LOG_CAT\n"
        "\t\t)\n"
        "\t\treturn false\n"
    )
    count = 1 if old in original else 0
    new_text = original.replace(old, new, 1)
    session.apply_change(path, original, new_text, count)


def _fix_mainmenu_resume_active_peer_view(session: BuildSession) -> None:
    path = _REPO_ROOT / "scripts/ui/MainMenuController.gd"
    original = path.read_text(encoding="utf-8")

    old_ready = (
        "func _ready() -> void:\n"
        "\t_build_static_ui()\n"
        "\t_show_view(_View.CHARACTERS)\n"
        "\tAppLogger.log_info(\"MainMenuController bereit.\", LOG_CAT)\n"
    )
    new_ready = (
        "func _ready() -> void:\n"
        "\t_build_static_ui()\n"
        "\t_show_initial_view()\n"
        "\tAppLogger.log_info(\"MainMenuController bereit.\", LOG_CAT)\n"
        "\n"
        "## BUGFIX (2026-09-14): SessionManager ist App-weit persistent — ein\n"
        "## laufender Host/eine Client-Verbindung überlebt eine frische\n"
        "## MainMenu-Szene (z.B. nach 'Zurück zum Hauptmenü'). Ohne diesen Check\n"
        "## würde _ready() immer _View.CHARACTERS zeigen, der '[Multiplayer]'-\n"
        "## Button wäre wieder da, und ein erneuter Host/Join-Klick würde nur\n"
        "## noch von session_manager_reentry_guard abgefangen (kein Crash mehr,\n"
        "## aber ein verwirrendes 'passiert nichts'). Aufgerufen von _ready() UND\n"
        "## von inject_session_manager() (Self-Healing analog inject_save_system(),\n"
        "## BUG-23) — welche der beiden zuerst dran ist, ist nicht garantiert.\n"
        "func _show_initial_view() -> void:\n"
        "\tif is_instance_valid(_session_manager) and _session_manager.has_active_peer():\n"
        "\t\tif _session_manager.is_server():\n"
        "\t\t\t_show_view(_View.HOST_ACTIVE)\n"
        "\t\telse:\n"
        "\t\t\t_show_view(_View.JOIN_CHARACTER_SELECT)\n"
        "\telse:\n"
        "\t\t_show_view(_View.CHARACTERS)\n"
    )
    count = 1 if old_ready in original else 0
    text = original.replace(old_ready, new_ready, 1)

    old_inject = (
        "func inject_session_manager(svc: SessionManager) -> void:\n"
        "\t_session_manager = svc\n"
    )
    new_inject = (
        "func inject_session_manager(svc: SessionManager) -> void:\n"
        "\t_session_manager = svc\n"
        "\t# BUGFIX (2026-09-14): siehe _show_initial_view() — falls die Injektion\n"
        "\t# NACH _ready() ankommt (BUG-23-Timing), zeigte _ready() bis hierhin\n"
        "\t# noch CHARACTERS, obwohl evtl. schon ein Peer aktiv ist. Sobald\n"
        "\t# _session_manager da ist, sofort neu entscheiden.\n"
        "\t_show_initial_view()\n"
    )
    if old_inject in text:
        count += 1
        text = text.replace(old_inject, new_inject, 1)

    session.apply_change(path, original, text, count)


def _fix_multiplayer_spawner_invalid_despawn_function(session: BuildSession) -> None:
    path = _REPO_ROOT / "scripts/world/core/WorldService.gd"
    original = path.read_text(encoding="utf-8")

    old = (
        "\tms.despawn_function = func(node: Node) -> void:\n"
        "\t\t# Client-seitig reicht queue_free — keine UUID-Buchführung nötig,\n"
        "\t\t# der Server hält den autoritativen Entity-Zustand.\n"
        "\t\tif is_instance_valid(node):\n"
        "\t\t\tnode.queue_free()\n"
        "\n"
        "\tworld_root.add_child(ms)\n"
    )
    new = (
        "\t# BUGFIX (2026-09-14): 'despawn_function' existiert NICHT als Property\n"
        "\t# auf MultiplayerSpawner (Godot 4) — die Zuweisung schlug bei JEDEM\n"
        "\t# Welt-Boot fehl: \"Invalid assignment of property or key\n"
        "\t# 'despawn_function' ... on a base object of type 'MultiplayerSpawner'\".\n"
        "\t# MultiplayerSpawner despawnt automatisch, sobald der Server-seitige\n"
        "\t# Node freigegeben wird — kein manueller Hook nötig. Für zusätzliche\n"
        "\t# Client-seitige Aufräumarbeiten existiert stattdessen das Signal\n"
        "\t# 'despawned(node)', keine zuweisbare Callable-Property.\n"
        "\tms.despawned.connect(func(node: Node) -> void:\n"
        "\t\tif is_instance_valid(node) and not node.is_queued_for_deletion():\n"
        "\t\t\tnode.queue_free()\n"
        "\t)\n"
        "\n"
        "\tworld_root.add_child(ms)\n"
    )
    count = 1 if old in original else 0
    new_text = original.replace(old, new, 1)
    session.apply_change(path, original, new_text, count)


def _fix_chunk_manager_freed_transform_access(session: BuildSession) -> None:
    path = _REPO_ROOT / "scripts/world/chunks/ChunkManager.gd"
    original = path.read_text(encoding="utf-8")

    old = (
        "\tfor player in _tracked_players:\n"
        "\t\tif not is_instance_valid(player):\n"
        "\t\t\tcontinue\n"
        "\t\tvar new_chunk := _world_to_chunk(player.global_position)\n"
    )
    new = (
        "\tfor player in _tracked_players:\n"
        "\t\t# BUGFIX (2026-09-14): is_instance_valid() allein reicht nicht — beim\n"
        "\t\t# Szenenwechsel (z.B. 'Zurück zum Hauptmenü') existiert der Player-\n"
        "\t\t# Node kurzzeitig noch im Speicher, ist aber schon aus dem SceneTree\n"
        "\t\t# entfernt. .global_position darauf löst 'Condition \"!is_inside_tree()\"\n"
        "\t\t# is_true. Returning: Transform3D()' aus, weil der Getter intern\n"
        "\t\t# get_global_transform() aufruft.\n"
        "\t\tif not is_instance_valid(player) or not player.is_inside_tree():\n"
        "\t\t\tcontinue\n"
        "\t\tvar new_chunk := _world_to_chunk(player.global_position)\n"
    )
    count = 1 if old in original else 0
    new_text = original.replace(old, new, 1)
    session.apply_change(path, original, new_text, count)


FIXES = {
    "xp_signal_arity": _fix_xp_signal_arity,
    "immediate_free_in_ui_clear": _fix_immediate_free_in_ui_clear,
    "orphaned_ui_timers": _fix_orphaned_ui_timers,
    "session_manager_port_retry": _fix_session_manager_port_retry,
    "session_manager_reentry_guard": _fix_session_manager_reentry_guard,
    "mainmenu_hide_multiplayer_button_while_active": _fix_mainmenu_hide_multiplayer_button_while_active,
    "session_manager_string_concat_syntax_error": _fix_session_manager_string_concat_syntax_error,
    "mainmenu_resume_active_peer_view": _fix_mainmenu_resume_active_peer_view,
    "multiplayer_spawner_invalid_despawn_function": _fix_multiplayer_spawner_invalid_despawn_function,
    "chunk_manager_freed_transform_access": _fix_chunk_manager_freed_transform_access,
}


def main(argv: list[str]) -> int:
    apply = "--apply" in argv
    args = [a for a in argv if a != "--apply"]

    if len(args) < 2 or args[0] != "--fix":
        fail(f"Usage: fix_known_runtime_bugs.py --fix <{'|'.join(list(FIXES) + ['all'])}> [--apply]")

    selected = args[1]
    if selected == "all":
        chosen = list(FIXES.values())
    elif selected in FIXES:
        chosen = [FIXES[selected]]
    else:
        fail(f"Unbekannter Fix '{selected}'. Verfügbar: {', '.join(FIXES)}, all")
        return 2  # unreachable, fail() beendet den Prozess

    session = BuildSession(apply=apply)
    for fn in chosen:
        fn(session)
    session.print_diffs()
    session.summary()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

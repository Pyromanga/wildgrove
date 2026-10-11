# scripts/agent/build/ — Codemod-Module

Gegenstück zu `service_graph.py`: das dort ist read-only und meldet
Findings, hier werden die dazugehörigen Migrationen tatsächlich
durchgeführt. Aufgerufen über `scripts/agent/service_build.py <modul>`, nie
direkt.

**Kein Git-Repo in diesem Projekt.** Jedes Modul MUSS über
`BuildSession.apply_change()` schreiben (Backup + Dry-Run-Default sind dort
eingebaut), nie direkt `Path.write_text()`.

## Muster für ein neues Modul

1. Datei `scripts/agent/build/fix_<name>.py`.
2. `def run(apply: bool) -> BuildSession` als öffentliche Schnittstelle.
3. Wiederverwendet nach Möglichkeit Parser/Daten aus `service_graph.py`
   (`import service_graph as sg`) statt einen zweiten Parser zu bauen, der
   von den Findings abweichen könnte.
4. Mehrdeutige Fälle bleiben unangetastet, werden nicht geraten (siehe
   `fix_raw_string_lookups.py`-Kommentar zum `EMIT_WRAPPER_UNRESOLVED`-Fall
   in `service_graph.py` — derselbe Grundsatz gilt hier).
5. In `service_build.py` unter `MODULES` eintragen.

## Status pro TODO-Punkt (TODO-offene-probleme.md, Round 109)

| # | Thema | Status | Warum |
|---|---|---|---|
| 8 | `get_service("x")` → `ServiceKeys.X` | ✅ `raw-strings` | Reiner Text-Tausch, kein Kontrollfluss betroffen, Konstante existiert oder nicht — keine Mehrdeutigkeit. |
| 1 | EventBus Pfad A → B | ✅ `eventbus-direct` | Umgesetzt (Round 109): `IAppContext`/`AppContext` + `AppScope.register_event_bus()` schaffen den Injektionspunkt, danach ist der Text-Tausch pro Datei mechanisch — Modul migriert nur Dateien, die bereits `_bus: IEventBus` / `_ctx: IUIContext\|IAppContext` haben, alles andere bleibt unangetastet und wird im Dry-Run gemeldet statt geraten. `MainMenuController`/`HUDManager` sind migriert und aus der `test_event_bus_access_boundary.gd`-Whitelist raus; `service_build.py eventbus-direct` (Dry-Run) meldet für das gesamte Projekt „keine Direktzugriffe außerhalb der Whitelist". |
| 2 | `## implements I*` → `extends I*` | ❌ noch kein Modul | Kein reiner Text-Tausch: `extends I*` ändert den tatsächlichen Vererbungsbaum (GDScript, kein Mehrfach-Erben) — kann bestehende `extends`-Ketten brechen. Erfordert vorher pro Klasse eine Entscheidung, nicht mechanisch für alle 14 Provider gleich lösbar. |
| 3–6 | Verschiedene | ❌ | Teils neue Konvention nötig (Punkt 3), teils reine Namensfragen die bewusst "pro Fall entscheiden" verlangen (Punkt 6) — kein automatischer Fix vorgesehen. |
| 7 | EventBus → typisierter Domain-Event-Layer | ❌ | Laut TODO-Text selbst: "Vor Code: eigenes Konzept/ADR mit Migrationsplan" — bewusst kein Codemod-Kandidat, bevor die Zielarchitektur überhaupt entschieden ist. |
| — | Strukturelle Datei-Verschiebungen/Ordner-Reorg | ❌ noch kein Modul | Angefragt (siehe Round-109-Gespräch), aber ungebaut: müsste `.tscn`/`.tres`-`ext_resource`-Pfade + `project.godot`-Autoloads mitziehen (191/198 Skripte nutzen `class_name`, sind also pfad-unabhängig referenziert — aber Szenen/Resources referenzieren über echte `res://`-Pfade). Braucht eigenes Modul `move_file.py` mit Referenz-Scan über `*.tscn`/`*.tres`/`project.godot`, nicht nur `*.gd`. Nächster Kandidat, wenn strukturelle Änderungen anstehen — noch nicht gebaut, weil bisher kein konkreter Verschiebe-Fall vorlag.

## Nächster sinnvoller Schritt

`raw-strings` und `eventbus-direct` sind beide end-to-end bewiesen (Round 109).
Offen sind Punkt 2 (`## implements I*` → `extends I*`, braucht vorher eine
Pro-Klasse-Entscheidung, kein mechanischer Fix) und die strukturelle
Datei-Verschiebung/Ordner-Reorg (`move_file.py`, noch nicht gebaut — siehe
Tabelle oben).

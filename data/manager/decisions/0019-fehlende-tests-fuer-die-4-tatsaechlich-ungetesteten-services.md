# 0019 — Fehlende Tests fuer die 4 tatsaechlich ungetesteten Services nachgezogen (ServiceTicker/SceneManager/DataService/WorldGenerationService), Coverage-Heuristik im Overview-Tool korrigiert

Zeit: 2026-08-29 01:22 UTC
Rolle: manager

## Gewählt
architecture_overview.py hatte per Dateinamens-Heuristik 8 Services als ungetestet gemeldet -- Gegenpruefung zeigte, dass 4 davon (playerstates/gamemanager/gamesave/savesystem) bereits Tests unter abweichenden Dateinamen hatten (z.B. test_player_state_service.gd fuer Service 'playerstates'). Coverage-Check auf die etablierte Header-Konvention 'Tests fuer <ClassName>' umgestellt (zeilenbasiert, deckt auch Mehrfach-Subjekt-Header wie test_stat_modifier.gd ab) statt Dateinamens-Raten oder reiner class_name-Textsuche (letztere hatte false positives durch Mock/Fake-Nutzung in fremden Tests). Fuer die 4 echten Luecken neue Testdateien geschrieben: test_service_ticker.gd (Registrierung/Tick-Dispatch/Cleanup ungueltiger Referenzen), test_scene_manager.gd (STATE_SCENE_MAP-Daten, on_ready()-Verdrahtung -- bewusst ohne echten Szenenwechsel-Seiteneffekt), test_data_service.gd (laedt bewusst echte Projekt-.tres-Daten, robust gegen Datenaenderungen durch Invarianten-Checks statt hartcodierter IDs), test_world_generation_service.gd (reine Berechnungslogik direkt getestet, Thread-Wrapper bewusst ausgeklammert -- keine verifizierbare Godot-Runtime in dieser Sandbox).

## Verworfene Alternativen
- Den urspruenglichen Dateinamens-Heuristik-Fund unkritisch uebernehmen und fuer alle 8 gemeldeten Services Tests schreiben -- verworfen, haette zu 4 Duplikat-Testdateien fuer bereits getestete Services gefuehrt (echte Verschwendung, plus Verwirrung: zwei Testdateien fuer denselben Service unter verschiedenen Namen). | generate_world_async() (Thread-Pfad) mittesten -- verworfen, echtes Thread-Timing ist in dieser Sandbox nicht gegen eine echte Godot-Runtime verifizierbar, ein falsch-gruener oder haengender Test waere schlimmer als keiner.

## Begründung
Die Diskrepanz zwischen Tool-Meldung und echtem Repo-Zustand (4 von 8 bereits getestet) haette denselben Fehler wiederholt, der diesen Round ausgeloest hat: einer Behauptung glauben statt den Quelldateien. Vor dem Schreiben neuer Tests wurde deshalb erst manuell mit find/grep nachgeprueft, welche Services WIRKLICH keine Testdatei haben -- danach die Heuristik selbst repariert, damit zukuenftige Laeufe des Tools nicht denselben falschen Befund liefern.

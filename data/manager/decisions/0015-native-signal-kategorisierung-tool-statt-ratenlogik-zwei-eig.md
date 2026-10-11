# 0015 — Native-Signal-Kategorisierung: Tool statt Ratenlogik, zwei eigene Methodik-Fehler unterwegs korrigiert

Zeit: 2026-08-02 20:37 UTC
Rolle: manager

## Gewählt
Neues Analyse-Tool scripts/agent/analyze_native_signals.py kategorisiert alle 99 nativen Signal-Deklarationen (91 eindeutige Namen) automatisch in LOCAL/CROSS_LAYER/NEEDS_HUMAN als Datengrundlage für die TODO-Punkt-5-ADR. Ergebnis: 21 LOCAL, 52 CROSS_LAYER, 18 NEEDS_HUMAN (4 davon echte Namenskollisionen, 14 mutmaßliche Parent-Child-UI-Fälle ohne .tscn-Bestätigung). Report unter docs/manager/reports/native-signal-categorization.md.

## Verworfene Alternativen
- Kategorisierung von Hand statt per Tool — verworfen, gleiche Begründung wie beim emit-Wrapper-Codemod: 91 Fälle von Hand sind fehleranfälliger als ein Skript, und das Tool ist wiederverwendbar sobald der Code sich weiterentwickelt.
- Erste Tool-Version ungeprüft übernehmen — verworfen, zwei Methodik-Fehler noch vor Ausgabe selbst gefunden: (1) tests/-Connects fälschlich als externe Kopplung gezählt, (2) 'anderes File' faelschlich mit 'andere Schicht' gleichgesetzt, obwohl TODO Punkt 5 Parent-Child-UI-Verdrahtung über Dateigrenzen hinweg explizit als lokal erlaubt.

## Begründung
Kein Code-Schritt in Punkt 5 vor der ADR, aber Messgrundlage schaffen ohne zu raten war explizit gefordert (TODO: 'automatisch wo eindeutig, explizit als braucht Mensch markiert wo nicht'). Beide Methodik-Fehler waeren sonst unbemerkt in die spaetere Migrationsentscheidung eingeflossen — Namenskollisionen und Parent-Child-Faelle haetten sonst falsch entweder als LOCAL versteckt oder als CROSS_LAYER faelschlich zur Migration vorgeschlagen.

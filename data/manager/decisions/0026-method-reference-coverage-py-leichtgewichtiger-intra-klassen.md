# 0026 — method_reference_coverage.py: leichtgewichtiger Intra-Klassen-Call-Graph ergaenzt (loest die request_X-ruft-on_X_confirmed-Indirektion echt auf)

Zeit: 2026-09-01 23:08 UTC
Rolle: manager

## Gewählt
Statt einer reinen '.methodname(' Textsuche gegen Testdateien jetzt zusaetzlich ein Call-Graph INNERHALB jeder Service-Klasse: fuer jede Methode wird ihr Koerper nach Aufrufen anderer Methoden DERSELBEN Klasse durchsucht (\bname\(-Textsuche, kein AST/Typechecker). Von jeder DIREKT getesteten Methode aus wird per BFS ueber diesen Graph propagiert -- alles Erreichbare gilt als INDIREKT getestet (Status '~', mit Angabe der aufrufenden Methode). Ausgabe unterscheidet jetzt drei Zustaende (direkt/indirekt/keins) statt nur zwei. Ergebnis: bank/equipment/item_protection/pickpocket bleiben bei 100%, trade/shop/auction_house/quest/skill_system springen von den vorherigen 71-75% auf tatsaechliche 100% (die 'Luecken' waren nie echte Luecken, siehe Decision 0021/0025) -- UND deckt neue, vorher durch denselben Blindspot maskierte Luecken in aura/character_creation/combat/data/death_loot/respawn/session_manager/pvp auf, die zufaellig NICHT ueber einen getesteten Aufrufer erreichbar sind.

## Verworfene Alternativen
- Die alten 'indirekt getestet, aber Metrik zeigt Luecke'-Faelle einzeln von Hand als bekannte Ausnahme dokumentieren (wie in Decision 0021/0025 bereits gemacht) statt das Tool zu verbessern -- verworfen nach Nachfrage des Menschen: eine von Hand gepflegte Ausnahmeliste veraltet genauso wie jede andere Handdoku (siehe Grundproblem dieses gesamten Rounds), ein Call-Graph loest die Ursache strukturell statt Symptome zu dokumentieren.

## Begründung
Direkter Anlass war eine Rueckfrage des Menschen ('fehlt ein vernuenftiger Call-Graph?') nach der Erklaerung der Indirektions-Luecke -- berechtigter Einwand: eine Metrik, die bei jedem Batch dieselbe Kategorie falscher Luecken meldet, sollte repariert statt jedes Mal neu erklaert werden. Der Call-Graph bleibt bewusst intra-Klasse und textbasiert (keine volle Semantik-Engine) -- das trifft genau das beobachtete Muster (synchroner Same-Class-Aufruf) ohne die Komplexitaet einer echten Call-Graph-Analyse mit Vererbung/Interfaces/dynamischem Dispatch, die fuer den Zweck hier ueberdimensioniert waere.

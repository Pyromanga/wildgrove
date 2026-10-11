# 0030 — ADR-051 Stufe 1 umgesetzt: unabhaengige Quest-Slots pro NPC

Zeit: 2026-09-26 21:31 UTC
Rolle: manager

## Gewählt
QuestNPCDialogController: neue innere Klasse ExtraSlot + add_independent_slot(), additiv neben dem unveraenderten Primaer-Strang. QuestNPC._add_extra_quest_slot() als Subklassen-Hook. on_interact()-Prioritaet aktiv>anbietbar>erledigt ueber Primaer+Extras. Separate on_extra_objective_updated(q_id,obj_id,current) statt Erweiterung der alten 2-Parameter-Methode, um obj_id-Verwechslung bei Mehrobjective-Quests zu vermeiden. 0 Aenderungen an den 6 bestehenden NPC-Subklassen/ihren Tests.

## Verworfene Alternativen
- Bestehende Felder (quest_id/next_quest_id) durch ein generisches Array ersetzen (echte Vereinheitlichung)
- Slots als Resource/.tres-Daten statt Code-Hook _add_extra_quest_slot()

## Begründung
Additive Erweiterung minimiert Risiko: alle 6 lebenden NPCs (Erik/Mira/Senna/Wei/Babatunde/Talia) und alle bestehenden Tests bleiben unveraendert lauffaehig (bei leerem _extra_slots ist jeder Codepfad byte-identisch zum Alt-Verhalten). Volle Vereinheitlichung (Alternative 1) haette hoeheres Regressionsrisiko fuer denselben funktionalen Gewinn gehabt. Resource-Daten (Alternative 2) waeren ein groesserer, fuer Stufe 1 nicht noetiger Umbau -- passender erst wenn Stufe 3 (Content-Forge-Schema fuer Dialogsystem) ansteht.

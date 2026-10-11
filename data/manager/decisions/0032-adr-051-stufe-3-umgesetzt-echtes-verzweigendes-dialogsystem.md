# 0032 — ADR-051 Stufe 3 umgesetzt: echtes verzweigendes Dialogsystem

Zeit: 2026-10-02 21:10 UTC
Rolle: manager

## Gewählt
Neue Klasse DialogueTreeController (DialogueNode/DialogueChoice generisch, condition-Strings gegen echten QuestService ausgewertet, wiederverwendet NPCDialogueChoiceUI aus Stufe 2). QuestNPC._build_dialogue_tree()-Hook (Default null) ersetzt bei Bedarf komplett das Slot-System. Neuer Lesezugriff IEntityContext.get_quest_service() (+ EntityContext/EntityOrchestrator/WorldService-Durchreichung ueber ServiceKeys.QUEST) fuer Bedingungen ueber FREMDE Quests. Demo-NPC VillageElderNPC (Dorfaeltester Rasmus) reagiert auf quest_babatunde_tale ohne diese zu vergeben, statt eine lebende Quest-Kette umzubauen.

## Verworfene Alternativen
- Talia/Wei/Babatunde direkt auf Baeume umstellen statt neuen Demo-NPC zu bauen
- Dialogbaeume als .tres-Ressourcen ueber content_forge.py statt GDScript-Code

## Begründung
Ein neuer, eigenstaendiger Demo-NPC hat null Regressionsrisiko fuer bereits funktionierende, getestete Slot-Ketten und demonstriert trotzdem den Kernpunkt (Reaktion auf fremde Quests) vollstaendig. Content-Forge-Ressourcen fuer Dialogtexte wuerden dem im Projekt etablierten Muster widersprechen (Quest-MECHANIK ist .tres-verwaltet, NPC-DIALOGTEXT ist immer schon Code, siehe alle 6 bisherigen NPC-Subklassen) -- waere Mehraufwand ohne Mehrwert fuer Stufe 3.

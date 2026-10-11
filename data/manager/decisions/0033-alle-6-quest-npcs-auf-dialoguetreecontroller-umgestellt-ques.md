# 0033 — Alle 6 Quest-NPCs auf DialogueTreeController umgestellt + quest_npc_scaffold.py

Zeit: 2026-10-06 10:01 UTC
Rolle: manager

## Gewählt
MinerNPC/HerbalistNPC/WoodcutterNPC/WudangMasterNPC/AncestorSpiritNPC/GuardNPC von QuestNPC-Slot-System auf DialogueTreeController.build_quest_giver() umgestellt (neue generische Factory: UND-Bedingungen, Live-Fortschritts-Templating, Single-Choice-Autoskip als Engine-Erweiterungen dafuer noetig). GuardNPC (Talia) bekam dabei ein echtes dauerhaftes 2-Themen-Menue (Dieb im Pelz / Friedhofswache). Neues Tool scripts/agent/build/quest_npc_scaffold.py automatisiert Quest-.tres (ruft content_forge.py intern auf) + NPC-.gd-Generierung aus einer Spec fuer den Standardfall; WorldEntityRegistry/WorldSpawner-Verdrahtung bleibt bewusst manueller letzter Schritt (kein stabiler Textanker in diesen Dateien).

## Verworfene Alternativen
- Slot-System parallel weiterpflegen statt zu konvertieren
- quest_npc_scaffold.py auch WorldEntityRegistry/WorldSpawner automatisch editieren lassen

## Begründung
Ein einziger Dialog-Mechanismus im ganzen Projekt ist wartbarer als zwei parallele (Slot-System UND Baum-System) - die Konversion war ueberall verhaltenserhaltend moeglich (Stufe-1/2-UX exakt reproduziert durch build_quest_giver()). Automatisches Editieren von WorldEntityRegistry/WorldSpawner wurde verworfen, weil beide Dateien wiederholt durch parallele Terrain-/Pet-/Smithing-Arbeit an wechselnden Stellen veraendert wurden - ein blind suchendes Tool haette irgendwann an der falschen Stelle eingefuegt, siehe common.py Regel 4 (kein Raten).

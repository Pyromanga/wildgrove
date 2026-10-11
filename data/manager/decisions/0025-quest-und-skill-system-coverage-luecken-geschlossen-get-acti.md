# 0025 — quest und skill_system Coverage-Luecken geschlossen (get_active_quests/get_completed_quests/get_quest_definition/on_local_identity_ready, inject_network_bridge/get_xp_to_next_level)

Zeit: 2026-09-01 20:31 UTC
Rolle: manager

## Gewählt
QuestService: get_active_quests()/get_completed_quests()/get_quest_definition() (bekannt/unbekannt) sowie on_local_identity_ready() (mit und ohne NetworkBridge, inkl. Auto-Start-Quest-Aktivierung fuer den lokalen Spieler ueber einen lokal konstruierten MockDataServiceAutoStart) ergaenzt. SkillSystem: inject_network_bridge() (Referenz + economy_state_received-Connect) und get_xp_to_next_level() (unbekannter Skill = Default 100, Level-Up aendert Schwelle) ergaenzt. on_quest_complete_confirmed()/on_xp_add_confirmed() bleiben als 'nicht direkt referenziert' stehen -- bekannte Grenze der Textsuche-Heuristik, beide werden bereits identisch ueber request_complete_quest()/request_add_xp() im No-Network-Pfad durchlaufen, kein echter Gap (gleiches Muster wie trade/shop/auction_house im vorletzten Batch).

## Verworfene Alternativen
- Fuer on_local_identity_ready() die geteilte before_each()-Fixture umbauen statt einen lokalen zweiten Service zu konstruieren -- verworfen, MockDataService.get_auto_start_quests() ist in der Fixture hart auf [] gesetzt und wird von mehreren anderen Tests als 'keine Auto-Start-Quests' vorausgesetzt; ein lokal konstruierter Service mit einer MockDataServiceAutoStart-Subklasse ist der isoliertere Eingriff (gleiches Prinzip wie beim EquipmentService-Batch).

## Begründung
quest/skill_system waren die naechstgroessten echten Luecken (67%/70%) nach Bank/Trade/Shop/Auction/Equipment/Protection/Pickpocket/World. Beide sind kleinere, ueberschaubare Batches -- passend fuer den Abschluss dieser Serie von Coverage-Naeherungs-Verbesserungen. Mit diesem Batch sind alle Services mit >=60% Ausgangs-Coverage entweder bei 100% oder nur noch durch die bekannte Indirekt-Aufruf-Grenze der Heuristik begrenzt.

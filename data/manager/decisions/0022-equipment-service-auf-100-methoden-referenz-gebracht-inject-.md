# 0022 — equipment-Service auf 100% Methoden-Referenz gebracht (inject_network_bridge/request_equip/request_unequip/on_unequip_confirmed/get_debug_report)

Zeit: 2026-09-01 08:37 UTC
Rolle: manager

## Gewählt
Fuenf echte Luecken in EquipmentService geschlossen (der Matcher-Fix im letzten Batch hatte bereits gezeigt, dass on_equip_confirmed()/inject_world_service() faelschlich als Luecke gemeldet waren -- test_equipment_service_r4.gd deckte sie schon ab). Neue Tests in test_equipment_service.gd: inject_network_bridge() (Referenz + economy_state_received-Connect), request_equip()/request_unequip() sowohl No-Network- als auch Client-Routing-Pfad (MockBridgeAsClient-Spy, gleiches Muster wie bank/trade/shop), on_unequip_confirmed(), get_debug_report() (befuellt + leer). Fuer request_equip() musste zusaetzlich ein lokaler EquipmentService mit DataService-Dep aufgebaut werden (die geteilte before_each()-Fixture hat keine 'data'-Dep, weil on_equip_confirmed() sie fuer die item_id->ItemDefinition-Aufloesung braucht) -- gleiches Konstruktionsmuster wie test_round_trip_equip_save_reload_restores_item() bereits im selben File nutzt.

## Verworfene Alternativen
- Fuer request_equip() die geteilte before_each()-Fixture um eine 'data'-Dep erweitern, statt lokal einen zweiten Service zu bauen -- verworfen, haette alle ~30 bestehenden Tests in der Datei potenziell beeinflusst (DataService-Verhalten aendert on_equip_confirmed()s fruehen Return-Pfad); ein lokal konstruierter Service mit demselben Muster wie der bereits vorhandene Round-Trip-Test ist der kleinere, isoliertere Eingriff.

## Begründung
Equipment ist wie Bank/Trade/Shop ein Pfad mit echtem Multiplayer-Fairness-Risiko (ein Spieler koennte sich auf dem Client fuer Items ausruesten, die er nicht besitzt, waere die Guard-Verweigerung ungetestet). Nach dem Matcher-Fix zeigte sich, dass zwei der urspruenglich gemeldeten fuenf Luecken bereits abgedeckt waren -- die verbliebenen drei plus die zwei komplett fehlenden (get_debug_report, inject_network_bridge) wurden in diesem Batch geschlossen.

# 0023 — item_protection und pickpocket auf 100% Methoden-Referenz gebracht (Sicherheits-/Anti-Cheat-Pfade)

Zeit: 2026-09-01 09:23 UTC
Rolle: manager

## Gewählt
Naechste Prioritaet nach Bank/Trade/Shop/Auction-House/Equipment: die zwei kleineren, aber sicherheitsrelevanten Services (ItemProtectionService als Anti-Cheat-Schutzmechanismus, PickpocketService als Diebstahl-Mechanik mit Exploit-Potenzial). ItemProtectionService: inject_network_bridge() + request_apply_protection() (No-Network- und Client-Routing-Pfad, gleiches MockBridgeAsClient-Muster wie bisher) ergaenzt -- Kernpunkt: auf dem Client darf weder der Schutz gesetzt noch das Scroll verbraucht werden, beides jetzt explizit assertet. PickpocketService: inject_network_bridge(), request_pickpocket() (No-Network + Client-Routing), on_notification_received() (Client-seitiger UI-Notification-Pfad, bisher komplett ungetestet) ergaenzt.

## Verworfene Alternativen
- network_bridge (24%, groesste absolute Luecke) stattdessen jetzt angehen -- weiterhin verworfen aus demselben Grund wie letzter Batch: duenne RPC-Wrapper, kein Business-Logik-Risiko, braucht echtes Multiplayer-Setup. Bleibt letzter Punkt auf der Liste.

## Begründung
ItemProtectionService und PickpocketService sind beide Ziel von Client-Manipulationsversuchen (Schutz erschleichen, Diebstahl ohne Server-Bestaetigung) -- der No-Network-Pfad war bereits gut getestet, aber der Client-Routing-Zweig (der eigentliche Punkt, an dem ein manipulierter Client versuchen wuerde, den Server-Guard zu umgehen) war blind. Beide Services jetzt vollstaendig referenziert.

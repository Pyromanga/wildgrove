# 0028 — inject_network_bridge() Coverage-Luecke ueberall geschlossen (5 Services, echter AST bestaetigt sauber)

Zeit: 2026-09-03 23:51 UTC
Rolle: manager

## Gewählt
Der AST-Umstellung (Decision 0027) hat als erstes wiederkehrendes Muster inject_network_bridge() in fuenf Services als echt ungetestet aufgedeckt: InventorySystem/CurrencyService (mit economy_state_received-Connect-Test, gleiches Late-Inject-Doppel-Connect-Schutz-Pattern wie Trade/Skill), PvPService/AuraService/DeathLootService (einfachere Variante, nur Referenz-Zuweisung ohne Signal-Connect). Jeweils per Referenz-Test (assert_same(_svc._network, bridge)) ergaenzt, bei Inventory/Currency zusaetzlich der Connect-Nachweis + Doppel-Connect-Schutz.

## Verworfene Alternativen
- Alle fuenf in einer gemeinsamen Utility-Testdatei buendeln statt in die jeweils bestehende Testdatei einzufuegen -- verworfen, widerspricht der etablierten Ein-Testdatei-pro-Service-Konvention dieses Projekts, keine Notwendigkeit fuer eine Sonderloesung nur weil das Muster wiederkehrt.

## Begründung
inject_network_bridge() ist der Phase-C8-Late-Inject-Pfad (ADR-022) -- wird er nicht korrekt verdrahtet, bleibt ein Client fuer Mehrspieler-Rueck-Sync (economy_state_received) stumm, ohne dass ein Compile-Fehler oder eine offensichtliche Fehlermeldung darauf hinweist. Dass gleich fuenf Services denselben blinden Fleck hatten, bestaetigt: es war ein systematisches Muster, kein Einzelfall -- genau die Art Lueckenklasse, die ein Call-Graph/AST-Werkzeug zuverlaessig findet, eine Handpruefung aber leicht uebersieht.

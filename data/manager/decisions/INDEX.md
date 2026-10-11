# Decision Index (autogeneriert — nicht von Hand editieren)

Neu regenerieren: `python3 scripts/agent/manager/log_decision.py --reindex-only`

| # | Status | Titel | Datei |
|---|---|---|---|
| 0001 | aktiv | 0001 — Manager-Runtime: in-repo Protokoll statt Subagents/Orchestrator | `0001-manager-runtime-in-repo-protokoll-statt-subagents-orchestrat.md` |
| 0002 | aktiv | 0002 — Infrastruktur vor Architektur-Abriss | `0002-infrastruktur-vor-architektur-abriss.md` |
| 0003 | aktiv | 0003 — Determinismus ist Zielarchitektur, kein aktueller Zwang | `0003-determinismus-ist-zielarchitektur-kein-aktueller-zwang.md` |
| 0004 | aktiv | 0004 — Baseline-Rollen: code-builder, code-tester, code-reviewer, metrik-master | `0004-baseline-rollen-code-builder-code-tester-code-reviewer-metri.md` |
| 0005 | aktiv | 0005 — Test-Runner-Lücke: kein GUT/gdUnit4, kein Godot-Binary in Sandbox | `0005-test-runner-l-cke-kein-gut-gdunit4-kein-godot-binary-in-sand.md` |
| 0006 | aktiv | 0006 — Protokollbruch: Ad-hoc-Analyse in /tmp statt geloggtem Repo-Tool | `0006-protokollbruch-ad-hoc-analyse-in-tmp-statt-geloggtem-repo-to.md` |
| 0007 | aktiv | 0007 — ADR-Verwaltung wird Tool-pflichtig, analog TODO-Datei | `0007-adr-verwaltung-wird-tool-pflichtig-analog-todo-datei.md` |
| 0008 | aktiv | 0008 — ADR-Audit-Befund: 2 von 45 ADRs sind script-enforced, 43 unverifiziert | `0008-adr-audit-befund-2-von-45-adrs-sind-script-enforced-43-unver.md` |
| 0009 | aktiv | 0009 — Erster Self-Healing-Fall: Manager reagiert statt zu beraten | `0009-erster-self-healing-fall-manager-reagiert-statt-zu-beraten.md` |
| 0010 | aktiv | 0010 — ADRs von 0 neu aufbauen statt 43 einzeln zu triagieren | `0010-adrs-von-0-neu-aufbauen-statt-43-einzeln-zu-triagieren.md` |
| 0011 | aktiv | 0011 — Meine fruehere Verifikation war fehlerhaft: falsches Feld statt ERROR_KINDS geprueft | `0011-meine-fruehere-verifikation-war-fehlerhaft-falsches-feld-sta.md` |
| 0012 | aktiv | 0012 — WorldSaveHandler.gd: falsche ## implements-Behauptung entfernt statt Code ergaenzt | `0012-worldsavehandler-gd-falsche-implements-behauptung-entfernt-s.md` |
| 0013 | aktiv | 0013 — Kein GDScript-Contract-Test jetzt -- service_graph.py ist das Interims-Aequivalent | `0013-kein-gdscript-contract-test-jetzt-service-graph-py-ist-das-i.md` |
| 0014 | aktiv | 0014 — Emit-Wrapper-Umbenennung: Wrapper an Signal angleichen, nicht umgekehrt | `0014-emit-wrapper-umbenennung-wrapper-an-signal-angleichen-nicht-.md` |
| 0015 | aktiv | 0015 — Native-Signal-Kategorisierung: Tool statt Ratenlogik, zwei eigene Methodik-Fehler unterwegs korrigiert | `0015-native-signal-kategorisierung-tool-statt-ratenlogik-zwei-eig.md` |
| 0016 | aktiv | 0016 — ADR-050: Migrationskonzept fuer Native-Signal-Cross-Layer-Faelle, EventBus wiederverwenden statt neuer Mechanismus | `0016-adr-050-migrationskonzept-fuer-native-signal-cross-layer-fae.md` |
| 0017 | aktiv | 0017 — ADR-050 Phase 2, zweiter Batch: Auction/Trade/Shop-Kollision (transaction_failed/purchase_completed) vollstaendig auf EventBus migriert | `0017-adr-050-phase-2-zweiter-batch-auction-trade-shop-kollision-t.md` |
| 0018 | aktiv | 0018 — architecture_overview.py: Architektur-Abriss als Script statt Gedaechtnisleistung/manuell gepflegter Doku | `0018-architecture-overview-py-architektur-abriss-als-script-statt.md` |
| 0019 | aktiv | 0019 — Fehlende Tests fuer die 4 tatsaechlich ungetesteten Services nachgezogen (ServiceTicker/SceneManager/DataService/WorldGenerationService), Coverage-Heuristik im Overview-Tool korrigiert | `0019-fehlende-tests-fuer-die-4-tatsaechlich-ungetesteten-services.md` |
| 0020 | aktiv | 0020 — method_reference_coverage.py: statische Methoden-Referenz-Naeherung statt echter Line-Coverage (Phase-3-Gate respektiert) | `0020-method-reference-coverage-py-statische-methoden-referenz-nae.md` |
| 0021 | aktiv | 0021 — Wirtschaftskritische Coverage-Luecken geschlossen (bank/trade/shop/auction_house), method_reference_coverage.py Matcher-Bug gefixt | `0021-wirtschaftskritische-coverage-luecken-geschlossen-bank-trade.md` |
| 0022 | aktiv | 0022 — equipment-Service auf 100% Methoden-Referenz gebracht (inject_network_bridge/request_equip/request_unequip/on_unequip_confirmed/get_debug_report) | `0022-equipment-service-auf-100-methoden-referenz-gebracht-inject-.md` |
| 0023 | aktiv | 0023 — item_protection und pickpocket auf 100% Methoden-Referenz gebracht (Sicherheits-/Anti-Cheat-Pfade) | `0023-item-protection-und-pickpocket-auf-100-methoden-referenz-geb.md` |
| 0024 | aktiv | 0024 — WorldService von 50% auf 89% gebracht + zwei Matcher-Bugs in beiden Coverage-Tools gefixt (Klammer-Beifang, kaputte Verschachtelung) | `0024-worldservice-von-50-auf-89-gebracht-zwei-matcher-bugs-in-bei.md` |
| 0025 | aktiv | 0025 — quest und skill_system Coverage-Luecken geschlossen (get_active_quests/get_completed_quests/get_quest_definition/on_local_identity_ready, inject_network_bridge/get_xp_to_next_level) | `0025-quest-und-skill-system-coverage-luecken-geschlossen-get-acti.md` |
| 0026 | aktiv | 0026 — method_reference_coverage.py: leichtgewichtiger Intra-Klassen-Call-Graph ergaenzt (loest die request_X-ruft-on_X_confirmed-Indirektion echt auf) | `0026-method-reference-coverage-py-leichtgewichtiger-intra-klassen.md` |
| 0027 | aktiv | 0027 — method_reference_coverage.py auf echten GDScript-AST umgestellt (gdtoolkit), ZoneService.gd 'set'-Variable umbenannt | `0027-method-reference-coverage-py-auf-echten-gdscript-ast-umgeste.md` |
| 0028 | aktiv | 0028 — inject_network_bridge() Coverage-Luecke ueberall geschlossen (5 Services, echter AST bestaetigt sauber) | `0028-inject-network-bridge-coverage-luecke-ueberall-geschlossen-5.md` |
| 0029 | aktiv | 0029 — NPC-Dialog mit mehreren Quest-Strängen: nur Plan (ADR-051), keine Umsetzung | `0029-npc-dialog-mit-mehreren-quest-str-ngen-nur-plan-adr-051-kein.md` |
| 0030 | aktiv | 0030 — ADR-051 Stufe 1 umgesetzt: unabhaengige Quest-Slots pro NPC | `0030-adr-051-stufe-1-umgesetzt-unabhaengige-quest-slots-pro-npc.md` |
| 0031 | aktiv | 0031 — ADR-051 Stufe 2 umgesetzt: einfache Auswahlliste bei mehreren ansprechbaren Slots | `0031-adr-051-stufe-2-umgesetzt-einfache-auswahlliste-bei-mehreren.md` |
| 0032 | aktiv | 0032 — ADR-051 Stufe 3 umgesetzt: echtes verzweigendes Dialogsystem | `0032-adr-051-stufe-3-umgesetzt-echtes-verzweigendes-dialogsystem.md` |
| 0033 | aktiv | 0033 — Alle 6 Quest-NPCs auf DialogueTreeController umgestellt + quest_npc_scaffold.py | `0033-alle-6-quest-npcs-auf-dialoguetreecontroller-umgestellt-ques.md` |

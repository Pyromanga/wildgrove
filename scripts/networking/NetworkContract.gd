# res://scripts/networking/NetworkContract.gd
class_name NetworkContract extends RefCounted

## NetworkContract — Definiert die Authority-Grenze vor dem Network-Layer.
##
## Definiert die Authority-Grenze: welche Systeme server-autoritativ sind,
## welche client-autoritativ, und wie der RPC-Kontrakt aussieht.
##
## VERWENDUNG:
##   Kein Runtime-Code — diese Klasse ist ein lebendiges Architektur-Dokument
##   und Linting-Hilfe (static assertions, Helper-Methoden).
##
## KONVENTION (R11):
##   request_*()                  — Methoden die in Tier 2/3 via RPC an die Autorität gehen.
##                                  In Tier 1 (Solo): synchroner direkter Aufruf.
##   receive_*_from_network()     — ÖFFENTLICHE Einstiegspunkte für NetworkBridge._rpc_*().
##                                  Delegieren intern an _on_*_confirmed().
##                                  NetworkBridge darf NUR diese Methoden aufrufen — keine
##                                  privaten _on_*_confirmed() direkt (ADR-R11).
##   _on_*_confirmed()            — PRIVATE Authority-Mutation.
##                                  Darf nur von request_*() (Tier 1) oder
##                                  receive_*_from_network() (Tier 2/3) aufgerufen werden.
##
## WARUM receive_*_from_network() statt direkter _on_*_confirmed()-Aufrufe:
##   Die privaten Methoden sind Implementierungsdetails. Wenn sich ihre Signatur
##   ändert (z.B. Dictionary → typed params), bricht der Network-Layer stumm.
##   receive_*_from_network() ist der stabile Kontrakt — typisiert, dokumentiert,
##   testbar ohne echten MultiplayerPeer.
##
## IMPLEMENTIERUNG (ab MIGRATION-010 Phase 2, R11):
##   NetworkBridge.gd ist der einzige Node, der @rpc-Methoden hostet und
##   intern an RefCounted-Services delegiert. Siehe docs/adr/010-multiplayer-authority-tiers.md.
##
## ─────────────────────────────────────────────
## SERVER-AUTORITATIV (request_/confirmed_-Pattern PFLICHT):
## Authority-Gating: assert(not multiplayer.has_multiplayer_peer() or multiplayer.is_server())
## ─────────────────────────────────────────────
##   InventorySystem    — add_item, remove_item, trade
##   QuestService       — start_quest, complete_quest, update_objective
##   EntityOrchestrator — spawn_entity, despawn_entity (inkl. UUID-Vergabe)
##   PlayerStateService — state-Wechsel (FREE/BUSY/MENU)
##   SkillSystem        — xp_gain, level_up
##   CombatSystem       — roll_critical(), calculate_damage() (Krit-Würfe server-autoritativ)
##   EntityOrchestrator.resolve_for_player(uuid, peer_id, max_range, actor_uuid="") — ADR-023,
##                        einziger kanonischer Weg, wie ein Request eine konkrete
##                        Server-Entity referenziert. Reine Plausibilitätsprüfung
##                        (Distanz gegen client-reported Position) — kein
##                        Movement-Anti-Cheat, siehe ADR-023/024/025 dazu. Jeder
##                        objektbezogene request_*() (Interaktion, Despawn,
##                        Quest-Trigger mit Objekt-Bezug) löst darüber auf, nie
##                        über eine vom Client selbst gesendete Objekt-Referenz.
##                        actor_uuid (Bugfix 2026-09-26, Pets): optional, misst
##                        die Distanz ab einer ANDEREN registrierten Entity statt
##                        dem Player-Node von peer_id — z.B. dem Pet, das die
##                        Aktion tatsächlich ausführt (siehe PetAbilityComponent).
##                        Wahrt dasselbe Prinzip: zeigt auf eine servereigene,
##                        bereits registrierte Entity mit eigener (bei Pets:
##                        replizierter) Position, NIE eine roh übertragene Position.
##   WorldService.resolve_and_dispatch_interaction(uuid, action_id, peer_id, actor_uuid="") —
##                        ADR-020, Autoritäts-seitige Ausführung von
##                        InteractableComponent._on_interacted()-Hooks
##                        (Harvestables, Tiere, Gegner). Nutzt resolve_for_player()
##                        (s.o., inkl. actor_uuid); die dafür verwendete max_range kommt aus der
##                        Entity's EIGENER InteractableComponent.detection_radius
##                        (servereigener State), NIEMALS aus einem RPC-Parameter —
##                        ein RPC, das eine Reichweite vom Client entgegennähme,
##                        würde die Plausibilitätsprüfung in resolve_for_player()
##                        wertlos machen. Aus demselben Grund ist peer_id in
##                        NetworkBridge._rpc_request_entity_interaction() kein
##                        Client-Parameter, sondern kommt aus
##                        multiplayer.get_remote_sender_id(). NUR die Objekt-
##                        Referenzen (entity_uuid, optional actor_uuid) und die Absicht
##                        (action_id) überqueren das Netz vom Client aus — keine Positionen.
##                        Loot-Roll und XP-Bemessung laufen seit R-1/R-2 (Round 43)
##                        NICHT mehr in InteractionExecutor auf dem ausführenden Peer,
##                        sondern in `InteractionResolver.resolve()` — aufgerufen aus
##                        demselben Autoritäts-Guard wie oben, direkt auf der Autorität.
##                        `_rpc_add_item`/`_rpc_add_xp` existieren seit Round 45 nicht
##                        mehr: root-cause-Analyse ergab, dass kein legitimer Spielcode
##                        mehr einen client-gewählten qty/amount-Wert übers Netz sendet
##                        (siehe TODO-offene-probleme.md, "Server validiert RPC-Werte
##                        nicht", Option A) — die Fläche wurde entfernt statt nachträglich
##                        validiert. `InventorySystem.on_item_add_confirmed()`/
##                        `SkillSystem.on_xp_add_confirmed()` werden nur noch aus
##                        Autoritäts-eigenem Code aufgerufen, nie per RPC.
##
##   Player-Movement (ADR-025/026) — server-autoritativ wie jedes andere System
##                        oben, aber mit einer eigenen Übertragungsart (s. UNRELIABLE
##                        unten): der Client sendet keine Position, sondern rohe
##                        Eingabe (move_vec, camera_yaw, jump_requested, input_seq).
##                        Player.gd._loop_free_authoritative() simuliert mit
##                        PlayerMover.calculate_velocity() — demselben Code wie die
##                        Client-Side-Prediction (ADR-026), nur auf der Autorität
##                        ausgeführt. move_speed/gravity kommen NIE vom Client (würde
##                        die Autorität wertlos machen) — effective_speed wird über
##                        StatModifierService.get_effective_stat(_, _, peer_id)
##                        serverseitig aus dem tatsächlichen peer_id aufgelöst,
##                        NIE aus einem Client-Parameter (derselbe Grundsatz wie bei
##                        max_range in resolve_for_player() oben).
##
## ─────────────────────────────────────────────
## UNRELIABLE (Input-Streams, ADR-025):
## Eigene Kategorie neben reliable/server-autoritativ/client-autoritativ/shared —
## bislang nutzte NetworkBridge ausschließlich "reliable" RPCs. Erste Ausnahme:
## ─────────────────────────────────────────────
##   NetworkBridge.submit_movement_input() / _rpc_submit_movement_input()
##     — @rpc("any_peer", "call_remote", "unreliable_ordered"). Grund: 20+ Hz
##       Eingabe-Rate — ein einzelnes verlorenes reliable-Paket würde die
##       Warteschlange stauen (Head-of-Line-Blocking), bei unreliable wird ein
##       verlorener Input einfach vom nächsten Tick überholt. "ordered" statt
##       reliable_unordered, weil ein VERALTETER Input, der nach einem neueren
##       ankäme, die Autorität rückwärts simulieren ließe — Reihenfolge muss
##       erhalten bleiben, Zustellung nicht.
##     WICHTIG — abweichend von den reliable-RPCs oben: Paketverlust ist hier
##       KEIN Fehlerfall. Kein Retry-Timer wie beim Snapshot-Request
##       (_send_snapshot_request()) — ein fehlender Input wird stillschweigend
##       durch den nächsten überholt (siehe Player.gd._consume_next_remote_input(),
##       das bei leerem Puffer den letzten bekannten Bewegungs-Input weiterverwendet,
##       aber NIE einen gepufferten jump_requested wiederholt — sonst würde ein
##       einzelner Sprung-Input bei Paketverlust-Wiederverwendung zu Dauer-Sprüngen).
##     input_seq überquert das Netz ungeprüft (Client wählt den Wert), ist aber
##       unkritisch: die Autorität vertraut NIE dem Bewegungsergebnis, das der Client
##       behauptet — sie simuliert selbst. input_seq dient ausschließlich als
##       Korrelations-ID für Reconciliation (ADR-026), kein Wert, den ein manipulierter
##       Client zu seinem Vorteil verändern könnte (im schlimmsten Fall bricht nur die
##       EIGENE Reconciliation des Clients, kein Angriffsvektor gegen andere Spieler
##       oder die Autorität selbst).
##
## ─────────────────────────────────────────────
## RATE-LIMITING (Schritt 3, Round 48):
## ─────────────────────────────────────────────
##   Jeder mutierende `@rpc("any_peer")`-Handler in NetworkBridge prüft nach dem
##   `_is_authority()`-Guard zusätzlich `_is_rate_limited(rpc_name, peer_id)` —
##   ein Fixed-Window-Zähler (Sekunde) pro (peer_id, rpc_name)-Paar, siehe
##   `NetworkBridge.RATE_LIMITS`. Verworfene Aufrufe werden geloggt, nicht
##   eskaliert (kein Auto-Kick). Ausnahme: `_rpc_submit_movement_input`
##   (ADR-025) — 20+ Hz, unreliable, absichtlich nicht limitiert.
##
## ─────────────────────────────────────────────
## CLIENT-AUTORITATIV (darf State direkt mutieren):
## ─────────────────────────────────────────────
##   TouchInput, PlayerCamera — Input, Kamera-Rotation, Look-Smoothing
##   HUDManager, LayoutManager — UI-State, Animation
##   Settings — lokale Display/Audio-Präferenzen
##   AppLogger — Logging ist lokal
##
## ─────────────────────────────────────────────
## SHARED / READ-ONLY REPLICA (Client hat Kopie, Server ist Truth):
## ─────────────────────────────────────────────
##   WorldData — Client hat eine lokale Kopie für Rendering,
##               Server ist die einzige Schreibquelle.
##   DataService — Item/Quest/Skill-Definitionen sind statisch → kein Sync nötig.

## Gibt true zurück wenn der übergebene Methodenname der request_-Konvention folgt.
## Nützlich für Runtime-Checks in Tests.
static func is_valid_request_method(method_name: String) -> bool:
	return method_name.begins_with("request_") or method_name.begins_with("on_") and "_confirmed" in method_name

## Gibt die erwartete confirm-Methode für eine request-Methode zurück.
## Beispiel: "request_add_item" → "on_item_add_confirmed"
## Konvention: request_<noun>_<verb> → on_<noun>_<verb>_confirmed
static func get_confirm_method_for(request_method: String) -> String:
	if not request_method.begins_with("request_"):
		return ""
	var stripped := request_method.substr(8)  # Remove "request_"
	return "on_%s_confirmed" % stripped

## Assertions für Tests — wirft einen Fehler wenn eine server-autoritative
## Klasse direkt State mutiert ohne request_/confirmed_-Pattern.
## Wird in IntegrationTest.gd aufgerufen.
static func assert_server_authoritative_uses_request_pattern(obj: Object, method: String) -> void:
	assert(
		is_valid_request_method(method),
		"[NetworkContract] Server-autoritative Methode '%s' in '%s' verletzt request_-Konvention."
		% [method, obj.get_class()]
	)

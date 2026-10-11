## tests/unit/test_session_manager.gd
## Unit-Tests für SessionManager — Sprint B.
##
## Abdeckung:
##   SM-01  has_active_peer() = false ohne gesetzten Peer
##   SM-02  is_server() = true ohne Peer (Tier-1-Trivialfall)
##   SM-03  get_local_peer_id() = 1 ohne Peer
##   SM-04  create_server() gibt false zurück in headless (kein ENet-Stack)
##   SM-05  join_server() gibt false zurück in headless
##   SM-06  close() ist idempotent ohne Peer
##   SM-07  register_player_slot() speichert und get_player_id_for_peer() gibt zurück
##   SM-08  get_player_id_for_peer() für unbekannte peer_id = ""
##   SM-09  get_all_slots() gibt Kopie zurück (keine Referenz-Lecks)
##   SM-10  _on_peer_disconnected() entfernt Slot und emittiert peer_left
##   SM-11  configure() setzt kein Dep (no-op, nur Logging)
##   SM-12  on_cleanup() ruft close() und disconnected EventBus-Signale
##   SM-13  get_local_player_id() löst über get_player_id_for_peer(get_local_peer_id()) auf (ADR-029 Plan-Schritt 4)
##   SM-14  get_peer_id_for_player() — Rückwärts-Auflösung für Rücksync-Routing (ADR-029 Plan-Schritt 4)
##
## ADR-018-Rest (Runde 53): SessionManager hat keine eigenen rohen Signale
## mehr — alle Lifecycle-Ereignisse laufen über eine injizierte
## MockEventBus-Instanz (_bus.networking()), nicht mehr über `_sm.<signal>`.

extends GutTest

var _sm: SessionManager = null
var _bus: MockEventBus = null

func before_each() -> void:
	_bus = MockEventBus.new()
	_sm = SessionManager.new()
	_sm.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: _bus}))
	# on_ready() verbindet multiplayer.*-Signale — braucht SceneTree
	add_child_autofree(_sm)

func after_each() -> void:
	_sm.on_cleanup()
	_sm = null
	if FileAccess.file_exists(HANDSHAKE_TEST_PATH):
		DirAccess.remove_absolute(HANDSHAKE_TEST_PATH)
	if FileAccess.file_exists(HANDSHAKE_TEST_PATH + ".tmp"):
		DirAccess.remove_absolute(HANDSHAKE_TEST_PATH + ".tmp")

# ─────────────────────────────────────────────
# SM-01…SM-03: Tier-1-Grundzustand (kein Peer)
# ─────────────────────────────────────────────

func test_has_active_peer_false_without_peer() -> void:
	assert_false(_sm.has_active_peer(), "Ohne Peer: has_active_peer() muss false sein.")

func test_is_server_true_without_peer() -> void:
	assert_true(_sm.is_server(), "Ohne Peer ist dieser Prozess immer die Autorität (Tier 1).")

func test_get_local_peer_id_is_1_without_peer() -> void:
	assert_eq(_sm.get_local_peer_id(), 1, "Ohne Peer ist die lokale peer_id immer 1.")

# ─────────────────────────────────────────────
# SM-04…SM-05: Host/Join in headless-Umgebung
# ─────────────────────────────────────────────

func test_create_server_returns_false_without_enet() -> void:
	# In der headless GUT-Umgebung ist kein ENet-Netzwerk-Stack verfügbar.
	# create_server() muss false zurückgeben statt zu crashen.
	var result := _sm.create_server(7777)
	assert_false(result, "create_server() muss false zurückgeben wenn kein ENet-Stack.")

func test_join_server_returns_false_without_enet() -> void:
	## HINWEIS: ENetMultiplayerPeer.create_client() prüft bei gültigen Adressen
	## (z.B. "127.0.0.1") nur lokale Voraussetzungen und schlägt selbst ohne
	## echten Server NICHT synchron fehl — die Verbindung wird nur "eingeleitet"
	## (siehe join_server()-Doku). Ein deterministischer Fehlerfall ohne echten
	## Netzwerk-Stack ist eine strukturell ungültige Adresse, die ENet schon bei
	## der Host-Auflösung zurückweist.
	var result := _sm.join_server("", 7777)
	assert_false(result, "join_server() muss bei ungültiger Adresse false zurückgeben.")

# ─────────────────────────────────────────────
# SM-06: close() idempotent
# ─────────────────────────────────────────────

func test_close_without_peer_does_not_crash() -> void:
	_sm.close()
	_sm.close()  # Zweiter Aufruf darf nicht crashen
	assert_true(true, "close() ohne Peer muss idempotent sein.")

# ─────────────────────────────────────────────
# SM-07…SM-09: Player-Slot-Registry
# ─────────────────────────────────────────────

func test_register_player_slot_and_get_back() -> void:
	_sm.register_player_slot(1, "charakter_1234")
	assert_eq(
		_sm.get_player_id_for_peer(1), "charakter_1234",
		"register_player_slot() muss player_id speichern und get_player_id_for_peer() zurückgeben."
	)

func test_get_player_id_for_unknown_peer_returns_empty() -> void:
	assert_eq(
		_sm.get_player_id_for_peer(99), "",
		"get_player_id_for_peer() für unbekannte peer_id muss leeren String zurückgeben."
	)

func test_get_all_slots_returns_copy() -> void:
	_sm.register_player_slot(1, "host")
	_sm.register_player_slot(2, "peer_2")
	var slots := _sm.get_all_slots()
	slots[99] = "manipuliert"  # Außenmodifikation darf Registry nicht ändern
	assert_eq(
		_sm.get_player_id_for_peer(99), "",
		"get_all_slots() muss eine echte Kopie zurückgeben — kein Referenz-Leak."
	)
	assert_eq(slots.size(), 3, "Kopie enthält 3 Einträge (inkl. manipuliertem).")
	assert_eq(_sm.get_all_slots().size(), 2, "Original-Registry bleibt bei 2 Einträgen.")

# ─────────────────────────────────────────────
# SM-10: Slot-Cleanup bei Disconnect
# ─────────────────────────────────────────────

func test_peer_disconnected_removes_slot_and_emits_signal() -> void:
	_sm.register_player_slot(2, "peer_2")
	var signal_received := [false]
	var received_peer   := [-1]
	_bus.networking().peer_left.connect(func(p: int) -> void:
		signal_received[0] = true
		received_peer[0] = p
	)
	# Simuliere Disconnect direkt (kein echter Peer nötig)
	_sm._on_peer_disconnected(2)
	assert_true(signal_received[0], "EventBus.networking().peer_left muss emittiert werden.")
	assert_eq(received_peer[0], 2, "peer_left muss korrekte peer_id übergeben.")
	assert_eq(
		_sm.get_player_id_for_peer(2), "",
		"Slot muss nach Disconnect aus der Registry entfernt sein."
	)

# ─────────────────────────────────────────────
# SM-11: configure() ist no-op (kein Dep erforderlich)
# ─────────────────────────────────────────────

func test_configure_with_empty_deps_does_not_crash() -> void:
	var sm2 := SessionManager.new()
	sm2.configure(ServiceDeps.from_dict({}))
	# Kein Crash = Test bestanden
	assert_true(true, "configure() mit leeren deps darf nicht crashen.")

func test_peer_disconnected_without_event_bus_does_not_crash() -> void:
	## Round 53: alle Emissionen laufen jetzt ausschließlich über
	## _bus.networking() (keine eigenen Signale mehr als Fallback) — muss
	## daher explizit gegen fehlenden Bus abgesichert sein, nicht nur
	## implizit "kein Aufrufer" wie vorher.
	var sm2 := SessionManager.new()
	sm2.configure(ServiceDeps.from_dict({}))
	add_child_autofree(sm2)
	sm2.register_player_slot(5, "peer_5")
	sm2._on_peer_disconnected(5)
	assert_eq(sm2.get_player_id_for_peer(5), "", "Slot-Entfernung darf auch ohne EventBus funktionieren.")

# ─────────────────────────────────────────────
# SM-12: on_cleanup() ist idempotent
# ─────────────────────────────────────────────

func test_on_cleanup_is_idempotent() -> void:
	_sm.register_player_slot(1, "host")
	_sm.on_cleanup()
	_sm.on_cleanup()  # Zweiter Aufruf darf nicht crashen
	assert_true(true, "on_cleanup() muss idempotent sein.")

# ─────────────────────────────────────────────
# SM-G03: Reconnect / Timeout / Peer-Cleanup
# ─────────────────────────────────────────────

func test_peer_disconnected_emits_peer_cleanup_requested() -> void:
	## G-03: peer_cleanup_requested muss VOR peer_left emittiert werden
	## damit Services Daten sichern können bevor der Slot entfernt wird.
	_sm.register_player_slot(3, "peer_3")
	var cleanup_fired := [false]
	var left_fired    := [false]
	var cleanup_order := [-1]
	var left_order    := [-1]
	var call_counter  := [0]

	_bus.networking().peer_cleanup_requested.connect(func(p: int) -> void:
		if p == 3:
			call_counter[0] += 1
			cleanup_order[0] = call_counter[0]
			cleanup_fired[0] = true
	)
	_bus.networking().peer_left.connect(func(p: int) -> void:
		if p == 3:
			call_counter[0] += 1
			left_order[0] = call_counter[0]
			left_fired[0] = true
	)

	_sm._on_peer_disconnected(3)

	assert_true(cleanup_fired[0], "peer_cleanup_requested muss bei Disconnect emittiert werden.")
	assert_true(left_fired[0],    "peer_left muss bei Disconnect emittiert werden.")
	assert_lt(cleanup_order[0], left_order[0],
		"peer_cleanup_requested muss VOR peer_left emittiert werden.")

func test_close_resets_retry_count() -> void:
	## G-03: close() setzt _retry_count zurück — nach close() keine Retries mehr.
	_sm._retry_count = 2
	_sm.close()
	assert_eq(_sm._retry_count, 0, "close() muss _retry_count auf 0 zurücksetzen.")

func test_join_timeout_constants_are_sane() -> void:
	## G-03: Timeout und Retry-Werte prüfen — keine absurden Defaults.
	assert_gt(SessionManager.JOIN_TIMEOUT_SEC, 0.0,
		"JOIN_TIMEOUT_SEC muss positiv sein.")
	assert_gte(SessionManager.MAX_RETRIES, 0,
		"MAX_RETRIES muss >= 0 sein.")
	assert_gt(SessionManager.RETRY_BASE_DELAY_SEC, 0.0,
		"RETRY_BASE_DELAY_SEC muss positiv sein.")

# ─────────────────────────────────────────────
# ADR-010 Round 55: Tier 3 (Dedizierter Server)
# ─────────────────────────────────────────────

func test_is_dedicated_server_false_by_default() -> void:
	assert_false(_sm.is_dedicated_server(),
		"Ohne enable_dedicated_server_mode() muss is_dedicated_server() false sein (Tier 1/2 unverändert).")

func test_enable_dedicated_server_mode_sets_flag() -> void:
	_sm.enable_dedicated_server_mode()
	assert_true(_sm.is_dedicated_server(),
		"enable_dedicated_server_mode() muss is_dedicated_server() auf true setzen.")

func test_dedicated_server_mode_does_not_change_tier1_defaults() -> void:
	## Deployment-Konfiguration, kein zweiter Code-Fork: ohne aktiven Peer bleibt
	## is_server()/get_local_peer_id() unverändert, auch mit gesetztem Flag.
	_sm.enable_dedicated_server_mode()
	assert_true(_sm.is_server(), "is_server() muss ohne Peer weiterhin true bleiben.")
	assert_eq(_sm.get_local_peer_id(), 1, "get_local_peer_id() muss ohne Peer weiterhin 1 bleiben.")

func test_dedicated_server_world_id_is_reserved_and_distinct() -> void:
	## Darf nicht mit echten Charakter-IDs oder ServiceOrchestrator._on_client_connected()s
	## "client_%d"-Muster kollidieren.
	var id := SessionManager.DEDICATED_SERVER_WORLD_ID
	assert_false(id.is_empty(), "DEDICATED_SERVER_WORLD_ID darf nicht leer sein.")
	assert_false(id.begins_with("client_"),
		"DEDICATED_SERVER_WORLD_ID darf nicht mit dem Client-Auto-ID-Muster kollidieren.")

# ─────────────────────────────────────────────
# ADR-029 Phase 1: Join-Handshake (_handle_join_handshake — testbare
# Kernlogik, getrennt von der @rpc-Hülle, siehe Kommentar in SessionManager.gd)
# ─────────────────────────────────────────────

const HANDSHAKE_TEST_PATH := "user://unit_test_session_manager_credentials.json"

func _fresh_credentials() -> PlayerCredentialStore:
	if FileAccess.file_exists(HANDSHAKE_TEST_PATH):
		DirAccess.remove_absolute(HANDSHAKE_TEST_PATH)
	var store := PlayerCredentialStore.new(HANDSHAKE_TEST_PATH)
	_sm.set_credentials_for_testing(store)
	return store

func test_first_contact_registers_slot_with_real_uuid() -> void:
	_fresh_credentials()
	_sm._handle_join_handshake(7, "uuid-alice", "secret-alice")
	assert_eq(_sm.get_player_id_for_peer(7), "uuid-alice",
		"Erfolgreicher Handshake muss den Slot mit der echten player_uuid registrieren.")

func test_first_contact_marks_handshake_done() -> void:
	var store := _fresh_credentials()
	_sm._handle_join_handshake(7, "uuid-alice", "secret-alice")
	assert_true(store.has_registered("uuid-alice"),
		"Erster Kontakt muss die player_uuid im PlayerCredentialStore registrieren.")

func test_mismatched_secret_does_not_register_slot() -> void:
	_fresh_credentials()
	_sm._handle_join_handshake(7, "uuid-alice", "secret-alice")
	_sm._peer_slots.erase(7)  # Slot zurücksetzen, um den zweiten Versuch isoliert zu prüfen
	_sm._handshake_done.erase(7)
	_sm._handle_join_handshake(7, "uuid-alice", "wrong-secret")
	assert_eq(_sm.get_player_id_for_peer(7), "",
		"Abgelehnter Handshake (falsches Secret) darf keinen Slot registrieren.")

func test_repeated_handshake_from_same_peer_is_ignored() -> void:
	_fresh_credentials()
	_sm._handle_join_handshake(7, "uuid-alice", "secret-alice")
	_sm._handle_join_handshake(7, "uuid-mallory", "secret-mallory")
	assert_eq(_sm.get_player_id_for_peer(7), "uuid-alice",
		"Ein zweiter Handshake vom selben Peer nach erfolgreichem ersten darf den Slot nicht überschreiben.")

func test_different_peers_can_use_different_uuids() -> void:
	_fresh_credentials()
	_sm._handle_join_handshake(2, "uuid-alice", "secret-alice")
	_sm._handle_join_handshake(3, "uuid-bob", "secret-bob")
	assert_eq(_sm.get_player_id_for_peer(2), "uuid-alice")
	assert_eq(_sm.get_player_id_for_peer(3), "uuid-bob")

func test_two_different_peers_cannot_share_one_uuid_without_matching_secret() -> void:
	## Kernszenario aus ADR-029: zwei unterschiedliche Menschen dürfen sich nicht
	## dieselbe player_uuid teilen, ohne dass der zweite auch das Secret kennt.
	_fresh_credentials()
	_sm._handle_join_handshake(2, "uuid-shared", "alice-secret")
	_sm._handle_join_handshake(3, "uuid-shared", "totally-different-secret")
	assert_eq(_sm.get_player_id_for_peer(2), "uuid-shared",
		"Peer 2 (Erst-Registrierer) muss registriert bleiben.")
	assert_eq(_sm.get_player_id_for_peer(3), "",
		"Peer 3 darf die player_uuid von Peer 2 nicht ohne passendes Secret übernehmen.")

func test_credentials_persist_across_session_manager_restarts() -> void:
	## Simuliert einen Server-Neustart: neue SessionManager-Instanz, aber
	## dieselbe Credentials-Datei — Secret-Bindung muss erhalten bleiben.
	var store_a := _fresh_credentials()
	_sm._handle_join_handshake(2, "uuid-alice", "secret-alice")

	var sm2 := SessionManager.new()
	sm2.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: MockEventBus.new()}))
	add_child_autofree(sm2)
	var store_b := PlayerCredentialStore.new(HANDSHAKE_TEST_PATH)
	store_b.load()
	sm2.set_credentials_for_testing(store_b)

	sm2._handle_join_handshake(9, "uuid-alice", "wrong-secret")
	assert_eq(sm2.get_player_id_for_peer(9), "",
		"Nach einem simulierten Neustart muss ein falsches Secret für eine bekannte player_uuid weiterhin abgelehnt werden.")
	sm2.on_cleanup()

# ─────────────────────────────────────────────
# SM-13 / SM-14 — ADR-029 Plan-Schritt 4 (Round 63)
# ─────────────────────────────────────────────

func test_get_local_player_id_resolves_via_local_peer_slot() -> void:
	## Ohne Peer ist get_local_peer_id() == 1 (SM-03) — get_local_player_id()
	## muss denselben Slot fragen, den register_player_slot(1, ...) füllt.
	_sm.register_player_slot(1, "local-char-uuid")
	assert_eq(_sm.get_local_player_id(), "local-char-uuid",
		"get_local_player_id() muss get_player_id_for_peer(get_local_peer_id()) liefern.")

func test_get_local_player_id_empty_before_slot_registered() -> void:
	## Boot-Reihenfolge-Fehler (Aufruf vor Phase S8.7) — leerer String, kein
	## geratener Platzhalter (siehe SessionManager.gd-Kommentar).
	assert_eq(_sm.get_local_player_id(), "",
		"get_local_player_id() ohne registrierten lokalen Slot muss '' liefern.")

func test_get_peer_id_for_player_reverse_resolves() -> void:
	_sm.register_player_slot(1, "host")
	_sm.register_player_slot(2, "peer_2")
	assert_eq(_sm.get_peer_id_for_player("peer_2"), 2,
		"get_peer_id_for_player() muss die peer_id des registrierten Slots liefern.")
	assert_eq(_sm.get_peer_id_for_player("host"), 1)

func test_get_peer_id_for_player_returns_minus_one_when_unknown() -> void:
	assert_eq(_sm.get_peer_id_for_player("nobody-home"), -1,
		"Unbekannte player_id → -1 (0 ist bewusst kein Sentinel, siehe Kommentar).")

func test_get_peer_id_for_player_minus_one_after_disconnect() -> void:
	## Rücksync-Routing (send_economy_update_for_player) darf nach einem
	## Disconnect nicht an eine veraltete peer_id senden — _on_peer_disconnected()
	## entfernt den Slot (SM-10), get_peer_id_for_player() muss das widerspiegeln.
	_sm.register_player_slot(2, "peer_2")
	_sm._on_peer_disconnected(2)
	assert_eq(_sm.get_peer_id_for_player("peer_2"), -1,
		"Nach Disconnect darf die player_id keinem Peer mehr zugeordnet sein.")

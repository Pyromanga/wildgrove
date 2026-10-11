# res://tests/unit/test_chat_service.gd
extends GutTest

## Unit-Tests für ChatService (ADR-043 "Chat/Social").
##
## Strategie: ChatService extends Service (RefCounted) — kein add_child
## nötig für den Tier-1-Pfad (analog test_aura_service.gd). Für die
## Netzwerk-Pfade wird ein SpyNetworkBridge injiziert (analog
## test_auction_house_service.gd/test_pvp_death_loss_service.gd, Round 97/98).
##
## Abgedeckt:
##   - request_send_message()/on_send_message_confirmed(): global + whisper,
##     Validierung (leer, zu lang, unbekannter Kanal, Whisper ohne Ziel),
##     Rate-Limit
##   - Lokale Emission auf der Autorität: global immer, whisper nur wenn der
##     lokale Peer Absender oder Ziel ist (ADR-042-Konvention)
##   - Broadcast/gezielte Zustellung über SpyNetworkBridge
##   - Client-Empfangspfade (broadcast_event_received / chat_message_received)
##   - on_cleanup() trennt beide Netzwerk-Signale sauber

const P_SENDER := "sender-uuid"
const P_TARGET := "target-uuid"
const P_OTHER := "bystander-uuid"

var _svc: ChatService

func before_each() -> void:
	_svc = ChatService.new()
	_svc.configure(ServiceDeps.from_dict({}))

func after_each() -> void:
	_svc.on_cleanup()
	_svc = null

class SpyNetworkBridge extends NetworkBridge:
	var broadcast_calls: Array[Dictionary] = []
	var targeted_calls: Array[Dictionary] = []
	var local_player_id: String = ""
	func broadcast_to_all_peers(kind: String, payload: Dictionary) -> void:
		broadcast_calls.append({"kind": kind, "payload": payload})
	func send_chat_message_for_player(player_id: String, payload: Dictionary) -> void:
		targeted_calls.append({"player_id": player_id, "payload": payload})
	func get_local_player_id() -> String:
		return local_player_id

# ─────────────────────────────────────────────────────────────────────────────
# Validierung (Tier 1, ohne NetworkBridge — direkter Autoritäts-Pfad)
# ─────────────────────────────────────────────────────────────────────────────

func test_global_message_emits_locally() -> void:
	var received: Array = []
	_svc.message_received.connect(func(entry): received.append(entry))
	_svc.request_send_message(P_SENDER, ChatService.CHANNEL_GLOBAL, "Hallo Welt")
	assert_eq(received.size(), 1)
	assert_eq(String(received[0]["sender_player_id"]), P_SENDER)
	assert_eq(String(received[0]["channel"]), ChatService.CHANNEL_GLOBAL)
	assert_eq(String(received[0]["text"]), "Hallo Welt")

func test_empty_message_is_rejected() -> void:
	var received: Array = []
	var rejected: Array = []
	_svc.message_received.connect(func(entry): received.append(entry))
	_svc.message_rejected.connect(func(sender, reason): rejected.append([sender, reason]))
	_svc.request_send_message(P_SENDER, ChatService.CHANNEL_GLOBAL, "   ")
	assert_true(received.is_empty(), "Nur-Whitespace-Nachrichten dürfen nicht emittieren.")
	assert_eq(rejected, [[P_SENDER, "empty_message"]])

func test_message_is_clamped_to_max_length() -> void:
	var received: Array = []
	_svc.message_received.connect(func(entry): received.append(entry))
	var long_text := "x".repeat(ChatService.MAX_MESSAGE_LENGTH + 50)
	_svc.request_send_message(P_SENDER, ChatService.CHANNEL_GLOBAL, long_text)
	assert_eq(received.size(), 1, "Zu lange Nachrichten werden gekappt, nicht abgelehnt.")
	assert_eq(String(received[0]["text"]).length(), ChatService.MAX_MESSAGE_LENGTH)

func test_whisper_without_target_is_rejected() -> void:
	var rejected: Array = []
	_svc.message_rejected.connect(func(sender, reason): rejected.append([sender, reason]))
	_svc.request_send_message(P_SENDER, ChatService.CHANNEL_WHISPER, "psst", "")
	assert_eq(rejected, [[P_SENDER, "whisper_needs_target"]])

func test_unknown_channel_is_rejected() -> void:
	var rejected: Array = []
	_svc.message_rejected.connect(func(sender, reason): rejected.append([sender, reason]))
	_svc.request_send_message(P_SENDER, "party", "hi")
	assert_eq(rejected, [[P_SENDER, "unknown_channel"]])

func test_rate_limit_rejects_second_message_within_window() -> void:
	var received: Array = []
	var rejected: Array = []
	_svc.message_received.connect(func(entry): received.append(entry))
	_svc.message_rejected.connect(func(sender, reason): rejected.append([sender, reason]))
	_svc.request_send_message(P_SENDER, ChatService.CHANNEL_GLOBAL, "erste")
	_svc.request_send_message(P_SENDER, ChatService.CHANNEL_GLOBAL, "zweite, zu schnell")
	assert_eq(received.size(), 1, "Nur die erste Nachricht darf durchgehen.")
	assert_eq(rejected, [[P_SENDER, "rate_limited"]])

func test_rate_limit_is_per_sender() -> void:
	var received: Array = []
	_svc.message_received.connect(func(entry): received.append(entry))
	_svc.request_send_message(P_SENDER, ChatService.CHANNEL_GLOBAL, "von sender")
	_svc.request_send_message(P_OTHER, ChatService.CHANNEL_GLOBAL, "von other")
	assert_eq(received.size(), 2, "Rate-Limit darf andere Absender nicht blockieren.")

func test_whisper_target_can_differ_from_sender_without_network() -> void:
	var received: Array = []
	_svc.message_received.connect(func(entry): received.append(entry))
	_svc.request_send_message(P_SENDER, ChatService.CHANNEL_WHISPER, "psst", P_TARGET)
	assert_eq(received.size(), 1,
		"Ohne NetworkBridge (Tier 1) gibt es kein Bystander-Dreiecksproblem — immer lokal emittieren.")
	assert_eq(String(received[0]["target_player_id"]), P_TARGET)

# ─────────────────────────────────────────────────────────────────────────────
# Netzwerk-Pfade (ADR-042/ADR-043) — SpyNetworkBridge
# ─────────────────────────────────────────────────────────────────────────────

func test_global_message_broadcasts_to_all_peers() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)

	_svc.request_send_message(P_SENDER, ChatService.CHANNEL_GLOBAL, "an alle")

	assert_eq(net.broadcast_calls.size(), 1)
	assert_eq(net.broadcast_calls[0]["kind"], "chat")
	assert_eq(String(net.broadcast_calls[0]["payload"]["text"]), "an alle")
	assert_eq(net.targeted_calls.size(), 0, "Global darf nicht über die gezielte Whisper-Zustellung laufen.")

func test_whisper_sends_targeted_to_both_participants() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	net.local_player_id = "someone-else-entirely"
	_svc.inject_network_bridge(net)

	_svc.request_send_message(P_SENDER, ChatService.CHANNEL_WHISPER, "geheim", P_TARGET)

	assert_eq(net.broadcast_calls.size(), 0, "Whisper darf nicht global broadcastet werden.")
	assert_eq(net.targeted_calls.size(), 2, "Beide Teilnehmer (Absender + Ziel) müssen gezielt beliefert werden.")
	var recipients: Array = []
	for c in net.targeted_calls:
		recipients.append(c["player_id"])
	assert_true(P_SENDER in recipients)
	assert_true(P_TARGET in recipients)

func test_whisper_sends_single_targeted_call_when_sender_equals_target() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)
	_svc.request_send_message(P_SENDER, ChatService.CHANNEL_WHISPER, "an mich selbst", P_SENDER)
	assert_eq(net.targeted_calls.size(), 1,
		"Wenn Ziel == Absender darf nicht zweimal an dieselbe player_id gesendet werden.")

func test_whisper_does_not_emit_locally_when_authority_is_bystander() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	net.local_player_id = P_OTHER  # Autorität ist weder Absender noch Ziel.
	_svc.inject_network_bridge(net)

	var received: Array = []
	_svc.message_received.connect(func(entry): received.append(entry))
	_svc.request_send_message(P_SENDER, ChatService.CHANNEL_WHISPER, "geheim", P_TARGET)

	assert_true(received.is_empty(),
		"Ein unbeteiligter Host darf ein fremdes Whisper nicht in seiner eigenen UI sehen.")

func test_whisper_emits_locally_when_authority_is_sender() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	net.local_player_id = P_SENDER
	_svc.inject_network_bridge(net)

	var received: Array = []
	_svc.message_received.connect(func(entry): received.append(entry))
	_svc.request_send_message(P_SENDER, ChatService.CHANNEL_WHISPER, "geheim", P_TARGET)

	assert_eq(received.size(), 1)

func test_whisper_emits_locally_when_authority_is_target() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	net.local_player_id = P_TARGET
	_svc.inject_network_bridge(net)

	var received: Array = []
	_svc.message_received.connect(func(entry): received.append(entry))
	_svc.request_send_message(P_SENDER, ChatService.CHANNEL_WHISPER, "geheim", P_TARGET)

	assert_eq(received.size(), 1)

func test_global_message_still_emits_locally_when_authority_is_bystander() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	net.local_player_id = P_OTHER
	_svc.inject_network_bridge(net)

	var received: Array = []
	_svc.message_received.connect(func(entry): received.append(entry))
	_svc.request_send_message(P_SENDER, ChatService.CHANNEL_GLOBAL, "an alle")

	assert_eq(received.size(), 1,
		"Der globale Kanal betrifft per Definition jeden — auch einen unbeteiligten Host.")

# ─────────────────────────────────────────────────────────────────────────────
# Client-Empfang
# ─────────────────────────────────────────────────────────────────────────────

func test_broadcast_event_received_routes_chat_kind_into_message_received() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)

	var received: Array = []
	_svc.message_received.connect(func(entry): received.append(entry))
	net.broadcast_event_received.emit("chat", {"sender_player_id": P_SENDER, "channel": "global", "text": "hi"})

	assert_eq(received.size(), 1)

func test_broadcast_event_received_ignores_other_kinds() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)

	var received: Array = []
	_svc.message_received.connect(func(entry): received.append(entry))
	net.broadcast_event_received.emit("auction_house", {"event": "listings_snapshot", "listings": []})

	assert_true(received.is_empty(), "ChatService darf nur auf kind == 'chat' reagieren.")

func test_chat_message_received_routes_into_message_received() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)

	var received: Array = []
	_svc.message_received.connect(func(entry): received.append(entry))
	net.chat_message_received.emit({"sender_player_id": P_SENDER, "channel": "whisper", "text": "psst"})

	assert_eq(received.size(), 1)

func test_on_cleanup_disconnects_network_signals() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)
	_svc.on_cleanup()

	assert_false(net.broadcast_event_received.is_connected(_svc._on_broadcast_event_received))
	assert_false(net.chat_message_received.is_connected(_svc._on_chat_message_received))

# ─────────────────────────────────────────────────────────────────────────────
# Round 100 (ADR-044): lokales Stummschalten
# ─────────────────────────────────────────────────────────────────────────────

func test_is_muted_false_by_default() -> void:
	assert_false(_svc.is_muted(P_SENDER))

func test_mute_player_suppresses_global_message() -> void:
	_svc.mute_player(P_SENDER)
	var received: Array = []
	_svc.message_received.connect(func(entry): received.append(entry))
	_svc.request_send_message(P_SENDER, ChatService.CHANNEL_GLOBAL, "hallo")
	assert_true(received.is_empty(), "Nachrichten stummgeschalteter Absender dürfen nicht emittieren.")

func test_mute_player_suppresses_incoming_broadcast() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)
	_svc.mute_player(P_SENDER)

	var received: Array = []
	_svc.message_received.connect(func(entry): received.append(entry))
	net.broadcast_event_received.emit("chat", {"sender_player_id": P_SENDER, "channel": "global", "text": "hi"})

	assert_true(received.is_empty())

func test_mute_player_suppresses_incoming_whisper() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)
	_svc.mute_player(P_SENDER)

	var received: Array = []
	_svc.message_received.connect(func(entry): received.append(entry))
	net.chat_message_received.emit({"sender_player_id": P_SENDER, "channel": "whisper", "text": "psst"})

	assert_true(received.is_empty())

func test_unmute_player_restores_delivery() -> void:
	_svc.mute_player(P_SENDER)
	_svc.unmute_player(P_SENDER)
	var received: Array = []
	_svc.message_received.connect(func(entry): received.append(entry))
	_svc.request_send_message(P_SENDER, ChatService.CHANNEL_GLOBAL, "wieder da")
	assert_eq(received.size(), 1)

func test_mute_is_per_sender_not_global() -> void:
	_svc.mute_player(P_SENDER)
	var received: Array = []
	_svc.message_received.connect(func(entry): received.append(entry))
	_svc.request_send_message(P_OTHER, ChatService.CHANNEL_GLOBAL, "von jemand anderem")
	assert_eq(received.size(), 1, "Ein Mute darf andere Absender nicht betreffen.")

func test_on_cleanup_clears_mute_list() -> void:
	_svc.mute_player(P_SENDER)
	_svc.on_cleanup()
	assert_false(_svc.is_muted(P_SENDER))

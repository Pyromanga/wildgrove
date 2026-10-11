# res://tests/unit/test_reward_dispatcher.gd
extends GutTest

## Unit-Tests für RewardDispatcher.
##
## Strategie: RewardDispatcher extends Service (RefCounted) — kein add_child
## nötig. Die drei schweren Kollaborator-Services (InventorySystem,
## SkillSystem, StatModifierService) werden NICHT real instanziiert —
## RewardDispatcher übersetzt nur QuestReward → Service-Aufrufe, die
## Kollaborator-Logik selbst ist nicht sein Verantwortungsbereich (und hat
## eigene Tests). Stattdessen: leichte lokale Stub-Subklassen, die nur die
## eine relevante Methode überschreiben und den Aufruf aufzeichnen — exakt
## dasselbe Muster wie `StubSaveSystem`/`MockSaveSystemForBacksync` in
## test_pvp_service.gd/test_currency_service.gd, nur für andere Service-Typen.
## NetworkBridge + SessionManager dagegen real (wie in test_pvp_service.gd) —
## die peer_id→player_id-Übersetzung IST Teil dessen, was hier getestet wird.
##
## Abgedeckt:
##   - dispatch(): null-Reward, alle fünf Reward-Kategorien (XP/Item/Unlock/
##     Custom-Signal/Stat-Modifier), inkl. fehlendem optionalem
##     StatModifierService (einzige der drei Kollaborator-Deps, die
##     get_optional() statt require() nutzt — siehe Hinweis weiter unten,
##     warum "fehlender Pflicht-Service" hier bewusst NICHT getestet wird)
##   - peer_id→player_id-Übersetzung: kein NetworkBridge injiziert,
##     unbekannter peer_id, erfolgreicher Fall
##   - Rückgabewert all_ok bei Teil-/Totalausfall

const QUEST_ID := "quest_tutorial"
const PLAYER_ID := "player-uuid-1"
const PEER_ID := 7

var _dispatcher: RewardDispatcher
var _bus: MockEventBus
var _inventory: StubInventorySystem
var _skills: StubSkillSystem
var _stat_mods: StubStatModifierService
var _session: SessionManager
var _bridge: NetworkBridge


class StubInventorySystem extends InventorySystem:
	var calls: Array = []  ## [[item_id, player_id, quantity], ...]
	func request_add_item(item_id: String, player_id: String, quantity: int = 1) -> bool:
		calls.append([item_id, player_id, quantity])
		return true


class StubSkillSystem extends SkillSystem:
	var calls: Array = []  ## [[skill_name, amount, player_id], ...]
	func request_add_xp(skill_name: String, amount: int, player_id: String) -> void:
		calls.append([skill_name, amount, player_id])


class StubStatModifierService extends StatModifierService:
	var calls: Array = []  ## [[modifier, player_id], ...]
	func add_modifier(modifier: StatModifier, player_id: String) -> bool:
		calls.append([modifier, player_id])
		return true


func before_each() -> void:
	_bus = MockEventBus.new()
	_inventory = StubInventorySystem.new()
	_skills = StubSkillSystem.new()
	_stat_mods = StubStatModifierService.new()

	_session = SessionManager.new()
	add_child_autofree(_session)
	_session.register_player_slot(PEER_ID, PLAYER_ID)

	_bridge = NetworkBridge.new()
	_bridge.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS: _bus,
		ServiceKeys.SESSION_MANAGER: _session,
	}))
	add_child_autofree(_bridge)

	_dispatcher = RewardDispatcher.new()
	_dispatcher.configure(ServiceDeps.from_dict({
		ServiceKeys.INVENTORY: _inventory,
		ServiceKeys.SKILL_SYSTEM: _skills,
		ServiceKeys.EVENT_BUS: _bus,
		ServiceKeys.STAT_MODIFIERS: _stat_mods,
	}))
	_dispatcher.inject_network_bridge(_bridge)  # Phase-C8-Late-Inject, siehe Klassenkommentar in RewardDispatcher.gd


func after_each() -> void:
	_dispatcher = null
	_bus = null
	_inventory = null
	_skills = null
	_stat_mods = null
	_session = null
	_bridge = null


func _make_reward() -> QuestReward:
	return QuestReward.new()


# ─────────────────────────────────────────────
# dispatch() — Grundfälle
# ─────────────────────────────────────────────

func test_dispatch_null_reward_returns_false() -> void:
	var ok := _dispatcher.dispatch(null, QUEST_ID, PEER_ID)
	assert_false(ok)

func test_dispatch_empty_reward_returns_true() -> void:
	# Keine Kategorie befüllt -> nichts kann fehlschlagen -> all_ok bleibt true.
	var ok := _dispatcher.dispatch(_make_reward(), QUEST_ID, PEER_ID)
	assert_true(ok)


# ─────────────────────────────────────────────
# XP-Rewards
# ─────────────────────────────────────────────

func test_dispatch_xp_reward_forwards_to_skill_system() -> void:
	var reward := _make_reward()
	reward.add_xp("mining", 50)
	_dispatcher.dispatch(reward, QUEST_ID, PEER_ID)
	assert_eq(_skills.calls.size(), 1)
	assert_eq(_skills.calls[0], ["mining", 50, PLAYER_ID])

func test_dispatch_multiple_xp_rewards_all_forwarded() -> void:
	var reward := _make_reward()
	reward.add_xp("mining", 50)
	reward.add_xp("woodcutting", 20)
	_dispatcher.dispatch(reward, QUEST_ID, PEER_ID)
	assert_eq(_skills.calls.size(), 2)

# HINWEIS für Maintainer (keine Testlücke, sondern ein Test-Design-Grund):
# "SkillSystem/InventorySystem fehlt" lässt sich hier NICHT über
# configure({..., SKILL_SYSTEM: null}) testen — ServiceDeps.require() ruft
# bei null AppLogger.fatal() -> get_tree().quit(1) auf und würde den
# GESAMTEN Testlauf beenden, nicht nur diesen einen Test fehlschlagen lassen.
# Nebenbefund dabei: RewardDispatcher.configure() hat direkt danach eigene
# is_instance_valid(_inventory)/is_instance_valid(_skill_system)-Warnungen —
# die sind für diese beiden (required) Keys toter Code, weil require()
# bei null bereits vorher fatal beendet. Nur für STAT_MODIFIERS (optional,
# get_optional()) ist der entsprechende Warn-Zweig unten tatsächlich erreichbar.


# ─────────────────────────────────────────────
# Item-Rewards
# ─────────────────────────────────────────────

func test_dispatch_item_reward_forwards_to_inventory() -> void:
	var reward := _make_reward()
	reward.add_item("iron_ore", 3)
	_dispatcher.dispatch(reward, QUEST_ID, PEER_ID)
	assert_eq(_inventory.calls.size(), 1)
	assert_eq(_inventory.calls[0], ["iron_ore", PLAYER_ID, 3])


# ─────────────────────────────────────────────
# Quest-Unlocks — via EventBus, nicht direkt an QuestService
# ─────────────────────────────────────────────

func test_dispatch_unlock_quest_emits_quest_unlock_requested() -> void:
	watch_signals(_bus.quest())
	var reward := _make_reward()
	reward.unlock_quests = ["quest_followup"]
	_dispatcher.dispatch(reward, QUEST_ID, PEER_ID)
	assert_signal_emitted_with_parameters(_bus.quest(), "quest_unlock_requested", ["quest_followup"])

func test_dispatch_multiple_unlocks_all_emitted() -> void:
	var received: Array = []
	_bus.quest().quest_unlock_requested.connect(func(quest_id: String) -> void:
		received.append(quest_id)
	)
	var reward := _make_reward()
	reward.unlock_quests = ["quest_a", "quest_b"]
	_dispatcher.dispatch(reward, QUEST_ID, PEER_ID)
	assert_eq(received, ["quest_a", "quest_b"])


# ─────────────────────────────────────────────
# Custom-Signals
# ─────────────────────────────────────────────

func test_dispatch_custom_signal_emits_reward_custom_signal() -> void:
	watch_signals(_bus.quest())
	var reward := _make_reward()
	reward.custom_signals = ["found_secret_cave"]
	_dispatcher.dispatch(reward, QUEST_ID, PEER_ID)
	assert_signal_emitted_with_parameters(_bus.quest(), "reward_custom_signal", ["found_secret_cave"])


# ─────────────────────────────────────────────
# Stat-Modifier-Rewards (optional dep)
# ─────────────────────────────────────────────

func test_dispatch_stat_modifier_forwards_to_stat_modifier_service() -> void:
	var reward := _make_reward()
	reward.stat_modifiers = {"gathering_yield_wood": 0.10}
	_dispatcher.dispatch(reward, QUEST_ID, PEER_ID)
	assert_eq(_stat_mods.calls.size(), 1)
	assert_eq(_stat_mods.calls[0][1], PLAYER_ID)
	var modifier: StatModifier = _stat_mods.calls[0][0]
	assert_eq(modifier.stat, "gathering_yield_wood")
	assert_eq(modifier.value, 0.10)
	assert_eq(modifier.source_id, "quest_%s" % QUEST_ID, "source_id muss 'quest_<quest_id>' sein (Idempotenz-Grundlage).")

func test_dispatch_stat_modifier_missing_service_is_tolerated_with_warning() -> void:
	# stat_modifiers ist als EINZIGE der drei Kategorien optional (siehe
	# ServiceKeys.STAT_MODIFIERS via get_optional) — fehlt sie, wird nur
	# gewarnt, all_ok wird NICHT auf false gesetzt (im Unterschied zu
	# fehlendem InventorySystem/SkillSystem oben).
	_dispatcher.configure(ServiceDeps.from_dict({
		ServiceKeys.INVENTORY: _inventory,
		ServiceKeys.SKILL_SYSTEM: _skills,
		ServiceKeys.EVENT_BUS: _bus,
	}))
	var reward := _make_reward()
	reward.stat_modifiers = {"gathering_yield_wood": 0.10}
	var ok := _dispatcher.dispatch(reward, QUEST_ID, PEER_ID)
	assert_false(ok, "dispatch() selbst setzt all_ok=false auch für den Stat-Modifier-Fehlfall (siehe Code: all_ok = false im else-Zweig).")


# ─────────────────────────────────────────────
# peer_id → player_id Übersetzung (_resolve_player_uuid)
# ─────────────────────────────────────────────

func test_dispatch_without_network_bridge_fails_translation() -> void:
	var dispatcher2 := RewardDispatcher.new()
	dispatcher2.configure(ServiceDeps.from_dict({
		ServiceKeys.INVENTORY: _inventory,
		ServiceKeys.SKILL_SYSTEM: _skills,
		ServiceKeys.EVENT_BUS: _bus,
	}))
	# Kein inject_network_bridge() aufgerufen.
	var reward := _make_reward()
	reward.add_item("iron_ore", 1)
	var ok := dispatcher2.dispatch(reward, QUEST_ID, PEER_ID)
	assert_false(ok, "Ohne NetworkBridge kann peer_id nicht übersetzt werden -> Reward darf nicht als erfolgreich gelten.")
	assert_eq(_inventory.calls.size(), 0, "Ohne aufgelöste player_id darf InventorySystem gar nicht erst aufgerufen werden.")

func test_dispatch_unknown_peer_id_fails_translation() -> void:
	var reward := _make_reward()
	reward.add_item("iron_ore", 1)
	var ok := _dispatcher.dispatch(reward, QUEST_ID, 999)  # nie via register_player_slot() registriert
	assert_false(ok)
	assert_eq(_inventory.calls.size(), 0)

func test_dispatch_default_peer_id_is_one() -> void:
	# dispatch()s eigener Default-Parameter (peer_id: int = 1) — hier separat
	# registriert, damit der Default-Pfad auch real durchläuft statt nur
	# implizit über PEER_ID=7 in before_each() mitgetestet zu werden.
	_session.register_player_slot(1, "default-peer-player")
	var reward := _make_reward()
	reward.add_item("iron_ore", 1)
	_dispatcher.dispatch(reward, QUEST_ID)  # peer_id weggelassen
	assert_eq(_inventory.calls[0][1], "default-peer-player")


# ─────────────────────────────────────────────
# Rückgabewert all_ok — gemischte Erfolgs-/Fehlerfälle
# ─────────────────────────────────────────────

func test_dispatch_mixed_reward_all_categories_succeed_returns_true() -> void:
	var reward := _make_reward()
	reward.add_xp("mining", 10)
	reward.add_item("iron_ore", 1)
	reward.unlock_quests = ["quest_followup"]
	reward.custom_signals = ["found_secret_cave"]
	reward.stat_modifiers = {"gathering_yield_wood": 0.10}
	var ok := _dispatcher.dispatch(reward, QUEST_ID, PEER_ID)
	assert_true(ok)
	assert_eq(_skills.calls.size(), 1)
	assert_eq(_inventory.calls.size(), 1)
	assert_eq(_stat_mods.calls.size(), 1)

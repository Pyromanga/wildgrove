# tests/integration/test_pvp_death_loss_protections.gd
extends GutTest

## PvPDeathLossService × ItemProtectionService — "Ebene A" (Service-
## Integration, kein Netzwerk) aus dem E2E-Testplan. Höchstes wirtschaftliches
## Risiko im gesamten Testplan: ein Fehler hier bedeutet entweder Item-/Gold-
## Dupes (Schutz greift, wo er nicht sollte) oder zu Unrecht verlorene
## Spieler-Items (Schutz greift NICHT, wo er sollte) — beides direkt
## spürbarer Spielerschaden, kein kosmetischer Bug.
##
## Besonderheit gegenüber test_quest_reward_chain.gd: PvPDeathLossService.
## apply_death_loss() ist vollständig DETERMINISTISCH — keine RNG-Auswahl,
## welche Items verloren gehen. Der Verlust-Prozentsatz kommt aus einer
## festen Tier-Tabelle (RISK_TIERS, nach dem risikierten Wert — Gold +
## sell_price×Menge — des KILLERS), und jedes nicht geschützte Item verliert
## exakt round(quantity × loss_percent) Stück. Das macht exakte
## Zahlen-Asserts möglich statt nur "irgendwas wurde verloren".
##
## EHRLICHER HINWEIS (wie test_quest_reward_chain.gd): geschrieben ohne
## laufendes Godot/GUT in dieser Sandbox (kein Binary, kein Netzwerk) — nach
## bestem Wissen gegen PvPDeathLossService.apply_death_loss()/
## _apply_item_loss()/_apply_gold_loss(), ItemProtectionService.
## consume_pvp_protection(), PvPService.set_voluntary_skull() konstruiert,
## aber NICHT ausgeführt. Vor Vertrauen:
##   godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration/ -gexit
##
## Bootet die eigene Session selbst über SceneLifecycleHarness (siehe dort
## für die "nackter Node3D statt echter World.tscn"-Annahme) — nur EIN
## Platzhalter-Spieler wird dafür tatsächlich "eingeloggt" (SESSION_OWNER_ID
## unten, rein um is_playing() zu erfüllen). VICTIM_ID/KILLER_ID sind davon
## unabhängige, synthetische player_id-Schlüssel, keine echten verbundenen
## Peers — Currency/Inventory/PvP-Services sind reine player_id-keyed
## Dictionaries und erwarten (Annahme, siehe Kopfkommentar-Muster in
## QuestService/InventorySystem: _ensure_player()-artiger Lazy-Init) keinen
## tatsächlich verbundenen Netzwerk-Peer für einen synthetischen Key. In
## einer Solo-Session (kein _network.has_peer()) greift ohnehin keiner der
## `_require_authority()`-Guards, da die alle nur bei vorhandenem, NICHT-
## autoritativem Peer blockieren.
##
## Deckt ab:
##   1. Unprotected item + Gold: Verlust exakt nach Tier-Tabelle, Killer
##      bekommt genau das, was der Victim verliert (kein Gold verschwindet
##      oder wird verdoppelt).
##   2. is_pve_death_protected und is_theft_protected: vollständig
##      ausgenommen (ADR-038 "permanente Schutzkategorien"), UNABHÄNGIG vom
##      Skull-Status.
##   3. is_pvp_protected: rettet das Item genau einmal UND wird dabei
##      verbraucht (Flag danach false) — kein wiederverwendbarer Freifahrtschein.
##   4. victim_was_skulled=true erzwingt 100% Verlust, überschreibt die
##      Tier-Tabelle — nur für NICHT permanent geschützte Items (Punkt 2
##      bleibt auch hier ausgenommen).
##
## Deckt NICHT ab: die Scroll-Anwendung selbst (request_apply_protection() —
## wie ein Spieler is_pvp_protected/is_pve_death_protected überhaupt gesetzt
## bekommt; hier werden die ItemInstance-Flags direkt gesetzt, um isoliert
## PvPDeathLossService zu prüfen, nicht die Scroll-Kette davor), Aura-Kill-
## Penalty-Seiteneffekt auf den Killer (apply_kill_penalty(), eigener
## Verantwortungsbereich von AuraService).

const VICTIM_ID := "it_victim_deathloss"
const KILLER_ID := "it_killer_deathloss"
const SESSION_OWNER_ID := "it_pvp_death_loss_session_owner"

# Killer-Gold exakt auf die 50_000-Schwelle gesetzt → RISK_TIERS liefert 0.20
# (20%) deterministisch, siehe PvPDeathLossService.RISK_TIERS.
const KILLER_RISK_GOLD := 50_000
const EXPECTED_LOSS_PERCENT := 0.20

const VICTIM_GOLD := 100
const UNPROTECTED_ITEM_ID := "log_normal"
const UNPROTECTED_ITEM_QTY := 10  # round(10 * 0.20) = 2 — eindeutig ungleich 0

var _harness: SceneLifecycleHarness
var _skip_reason: String = ""

func _orch() -> Node:
	return get_node("/root/ServiceOrchestrator")

func _skip_if_unavailable() -> bool:
	if not _skip_reason.is_empty():
		pending(_skip_reason)
		return true
	return false

func before_each() -> void:
	_skip_reason = ""
	_harness = SceneLifecycleHarness.new(self)

	var booted := await _harness.boot_fresh_session(SESSION_OWNER_ID)
	if not booted:
		_skip_reason = "Session-Boot fehlgeschlagen: %s" % _harness.last_error
		return
	for key in ["pvp_death_loss", "currency", "inventory", "pvp", "item_protection"]:
		if _orch().get_service(key) == null:
			_skip_reason = "Service '%s' nicht registriert — Test übersprungen." % key
			return

	# Sauberer Ausgangszustand pro Testfall: Gold auf 0, dann exakt auf den
	# gewünschten Wert setzen. request_remove_gold() ist der einzige
	# öffentliche Rückweg auf 0 (kein set_gold() vorgesehen — bewusst, kein
	# Cheat-Vektor in Produktion).
	var currency: CurrencyService = _orch().get_service("currency")
	var victim_gold_now := currency.get_gold(VICTIM_ID)
	if victim_gold_now > 0:
		currency.request_remove_gold(VICTIM_ID, victim_gold_now)
	var killer_gold_now := currency.get_gold(KILLER_ID)
	if killer_gold_now > 0:
		currency.request_remove_gold(KILLER_ID, killer_gold_now)
	currency.request_add_gold(VICTIM_ID, VICTIM_GOLD)
	currency.request_add_gold(KILLER_ID, KILLER_RISK_GOLD)

	var pvp = _orch().get_service("pvp")
	pvp.set_voluntary_skull(VICTIM_ID, false)
	pvp.set_voluntary_skull(KILLER_ID, false)

	# "first_blood" (Erster PvP-Kill) schaltet über RewardDispatcher einen
	# einmaligen Gold-Bonus frei — würde sonst beim ersten apply_death_loss()
	# im jeweiligen Test unbemerkt mit ins Killer-Gold einfließen und die
	# Transfer-Arithmetik-Assertions verfälschen. Hier schon vorab freischalten
	# (idempotent — grant_progress() nach Unlock ist ein No-Op), damit der
	# Bonus nicht mitten im eigentlichen Test-Kill nochmal feuert.
	var achievements = _orch().get_service("achievement")
	if achievements:
		achievements.grant_progress(KILLER_ID, "first_blood")

func after_each() -> void:
	if _harness:
		await _harness.return_to_main_menu()
		_harness.cleanup()

func test_unprotected_item_and_gold_lost_per_risk_tier() -> void:
	if _skip_if_unavailable():
		return
	var inventory = _orch().get_service("inventory")
	var currency: CurrencyService = _orch().get_service("currency")
	var death_loss = _orch().get_service("pvp_death_loss")

	inventory.request_add_item(UNPROTECTED_ITEM_ID, VICTIM_ID, UNPROTECTED_ITEM_QTY)
	var gold_before_killer := currency.get_gold(KILLER_ID)

	death_loss.apply_death_loss(VICTIM_ID, KILLER_ID)

	var expected_gold_lost := int(round(float(VICTIM_GOLD) * EXPECTED_LOSS_PERCENT))
	var expected_item_lost := int(round(float(UNPROTECTED_ITEM_QTY) * EXPECTED_LOSS_PERCENT))

	assert_eq(
		currency.get_gold(VICTIM_ID), VICTIM_GOLD - expected_gold_lost,
		"Victim muss exakt %d Gold verlieren (Tier: %.0f%% von %d Gold)." % [expected_gold_lost, EXPECTED_LOSS_PERCENT * 100.0, VICTIM_GOLD]
	)
	assert_eq(
		currency.get_gold(KILLER_ID), gold_before_killer + expected_gold_lost,
		"Killer muss GENAU das verlorene Gold erhalten (keine Vernichtung, keine Verdopplung)."
	)
	assert_true(
		inventory.has_item(UNPROTECTED_ITEM_ID, VICTIM_ID, UNPROTECTED_ITEM_QTY - expected_item_lost),
		"Victim darf exakt %d von %d '%s' behalten." % [UNPROTECTED_ITEM_QTY - expected_item_lost, UNPROTECTED_ITEM_QTY, UNPROTECTED_ITEM_ID]
	)
	assert_false(
		inventory.has_item(UNPROTECTED_ITEM_ID, VICTIM_ID, UNPROTECTED_ITEM_QTY - expected_item_lost + 1),
		"Victim darf NICHT mehr als den erwarteten Rest behalten (kein zu geringer Verlust)."
	)

func test_pve_death_protected_and_theft_protected_items_fully_exempt() -> void:
	if _skip_if_unavailable():
		return
	var inventory = _orch().get_service("inventory")
	var death_loss = _orch().get_service("pvp_death_loss")

	inventory.request_add_item(UNPROTECTED_ITEM_ID, VICTIM_ID, 1)
	var pve_protected_inst: ItemInstance = inventory.get_item_instance(VICTIM_ID, UNPROTECTED_ITEM_ID)
	assert_not_null(pve_protected_inst, "Item-Instanz muss nach request_add_item() existieren.")
	if not pve_protected_inst:
		return
	pve_protected_inst.is_pve_death_protected = true

	# Zweites, unabhängiges Item für den Theft-Protection-Fall — eigener
	# item_id nötig, sonst würde is_pve_death_protected oben dieselbe
	# Instanz treffen und die beiden Schutzkategorien wären nicht getrennt
	# testbar.
	const THEFT_PROTECTED_ITEM_ID := "cactus_fiber"
	inventory.request_add_item(THEFT_PROTECTED_ITEM_ID, VICTIM_ID, 1)
	var theft_protected_inst: ItemInstance = inventory.get_item_instance(VICTIM_ID, THEFT_PROTECTED_ITEM_ID)
	assert_not_null(theft_protected_inst, "Zweite Item-Instanz muss existieren.")
	if not theft_protected_inst:
		return
	theft_protected_inst.is_theft_protected = true

	death_loss.apply_death_loss(VICTIM_ID, KILLER_ID)

	assert_true(
		inventory.has_item(UNPROTECTED_ITEM_ID, VICTIM_ID, 1),
		"is_pve_death_protected muss das Item VOLLSTÄNDIG vor PvP-Verlust bewahren (ADR-038)."
	)
	assert_true(
		inventory.has_item(THEFT_PROTECTED_ITEM_ID, VICTIM_ID, 1),
		"is_theft_protected muss das Item VOLLSTÄNDIG vor PvP-Verlust bewahren (ADR-038)."
	)

func test_pvp_protected_item_saved_once_and_flag_consumed() -> void:
	if _skip_if_unavailable():
		return
	var inventory = _orch().get_service("inventory")
	var death_loss = _orch().get_service("pvp_death_loss")

	inventory.request_add_item(UNPROTECTED_ITEM_ID, VICTIM_ID, 1)
	var inst: ItemInstance = inventory.get_item_instance(VICTIM_ID, UNPROTECTED_ITEM_ID)
	assert_not_null(inst, "Item-Instanz muss existieren.")
	if not inst:
		return
	inst.is_pvp_protected = true

	death_loss.apply_death_loss(VICTIM_ID, KILLER_ID)

	assert_true(
		inventory.has_item(UNPROTECTED_ITEM_ID, VICTIM_ID, 1),
		"is_pvp_protected muss das Item beim ERSTEN Tod retten."
	)
	assert_false(
		inst.is_pvp_protected,
		"is_pvp_protected muss nach Gebrauch verbraucht sein (consume_pvp_protection()) — " +
		"sonst wäre es ein wiederverwendbarer Freifahrtschein statt eines Einmal-Schutzes."
	)

	# Zweiter Tod, ohne erneute Schutzanwendung: das Item ist jetzt ein
	# gewöhnliches ungeschütztes Item und MUSS beim erneuten Verlust-Tier
	# verloren gehen (round(1 * 0.20) = 0 bei qty=1 — also mit qty=1 nicht
	# unterscheidbar von "durch Rundung verschont". Deshalb hier auf 100%
	# Verlust über set_voluntary_skull() erzwingen, um den Verbrauch
	# eindeutig nachzuweisen statt sich auf Rundung zu verlassen.)
	_orch().get_service("pvp").set_voluntary_skull(VICTIM_ID, true)
	death_loss.apply_death_loss(VICTIM_ID, KILLER_ID)
	assert_false(
		inventory.has_item(UNPROTECTED_ITEM_ID, VICTIM_ID, 1),
		"Nach Verbrauch des Schutzes muss dasselbe Item beim NÄCHSTEN Tod wie jedes andere behandelt werden."
	)

func test_skulled_victim_loses_everything_except_permanent_protections() -> void:
	if _skip_if_unavailable():
		return
	var inventory = _orch().get_service("inventory")
	var currency: CurrencyService = _orch().get_service("currency")
	var death_loss = _orch().get_service("pvp_death_loss")

	inventory.request_add_item(UNPROTECTED_ITEM_ID, VICTIM_ID, UNPROTECTED_ITEM_QTY)
	inventory.request_add_item("cactus_fiber", VICTIM_ID, 1)
	var protected_inst: ItemInstance = inventory.get_item_instance(VICTIM_ID, "cactus_fiber")
	assert_not_null(protected_inst, "Item-Instanz muss existieren.")
	if protected_inst:
		protected_inst.is_pve_death_protected = true

	_orch().get_service("pvp").set_voluntary_skull(VICTIM_ID, true)
	assert_true(_orch().get_service("pvp").is_skulled(VICTIM_ID), "Setup-Vorbedingung: Victim muss jetzt geskullt sein.")

	death_loss.apply_death_loss(VICTIM_ID, KILLER_ID)

	assert_eq(
		currency.get_gold(VICTIM_ID), 0,
		"Geskullter Tod muss 100%% des Golds kosten (loss_percent=1.0, überschreibt die Tier-Tabelle)."
	)
	assert_false(
		inventory.has_item(UNPROTECTED_ITEM_ID, VICTIM_ID, 1),
		"Geskullter Tod muss ein ungeschütztes Item vollständig verlieren (round(qty*1.0) == qty)."
	)
	assert_true(
		inventory.has_item("cactus_fiber", VICTIM_ID, 1),
		"is_pve_death_protected muss AUCH bei einem geskullten Tod (100%% Verlust) noch schützen — " +
		"das ist der ganze Zweck einer 'permanenten' Schutzkategorie (ADR-038)."
	)

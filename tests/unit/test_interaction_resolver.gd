# res://tests/unit/test_interaction_resolver.gd
extends GutTest

## Unit-Tests für InteractionResolver.resolve() — ADR-020 Option B, R-1 (Round 43).
##
## Bewusst mit ECHTEN LootTable/LootEntry/StatModifierService-Instanzen getestet
## (keine Mocks/Doubles), wie in ADR-020 "Mitigationen" gefordert — der Punkt
## dieses Resolvers ist gerade, dass die Berechnung selbst (nicht nur ihr
## Aufruf-Pfad) verifiziert wird. Nur der IEventBus ist ein Test-Double
## (MockEventBus), weil er reine Transport-Infrastruktur ist, kein Teil der
## zu testenden Berechnung.
##
## ADR-029 Round 69: resolve() nimmt jetzt zusätzlich zur peer_id (int, für die
## loot_collected/xp_gained-Attribution) eine player_id: String entgegen (die
## stabile Identität, ausschließlich für den StatModifierService-Aufruf) —
## siehe Klassenkommentar in InteractionResolver.gd. Alle Aufrufe unten geben
## "p<peer_id>" als player_id mit, außer wo explizit die Isolation zwischen
## zwei unterschiedlichen player_ids getestet wird.
##
## Abgedeckt:
##   - resolve() ohne loot_table: kein loot_collected, aber xp_gained falls konfiguriert
##   - resolve() mit loot_table: loot_collected pro gedroptem Item, korrekt attribuiert
##   - resolve() xp_type == "none": kein xp_gained
##   - resolve() xp_amount <= 0: kein xp_gained trotz gesetztem xp_type
##   - resolve() peer_id wird an beide Emits durchgereicht, nicht geraten
##   - resolve() stat_modifiers skaliert die Drop-Menge über yield_stat_id
##   - resolve() ohne stat_modifiers (null): unskaliert (multiplier 1.0)
##   - resolve() Skalierung ist PRO player_id (Bug-Fix ggü. alter InteractionExecutor-Fassung)
##   - resolve() mit data == null: kein Crash, leeres Dictionary, keine Emits
##   - resolve() mit bus == null: kein Crash, leeres Dictionary, keine Emits
##   - resolve() Rückgabewert entspricht den tatsächlich gedropten Mengen

func _make_data(id: String = "mine", xp_type: String = "none", xp_amount: int = 0) -> InteractableData:
	var d := InteractableData.new()
	d.id         = id
	d.xp_type    = xp_type
	d.xp_amount  = xp_amount
	return d

## Einzelner garantierter Drop — weight so hoch gesetzt, dass roll() ihn IMMER
## trifft (roll_val <= entry.weight kann bei total_weight == entry.weight nie
## überschritten werden). Deterministisch, kein Flake durch randf().
func _make_guaranteed_loot_table(item_id: String, qty_min: int, qty_max: int) -> LootTable:
	var entry := LootEntry.new()
	entry.item_id      = item_id
	entry.weight       = 100.0
	entry.quantity_min = qty_min
	entry.quantity_max = qty_max
	var table := LootTable.new()
	table.entries   = [entry]
	table.max_rolls = 1
	return table

# ─────────────────────────────────────────────
# Ohne loot_table
# ─────────────────────────────────────────────

func test_resolve_without_loot_table_emits_no_loot() -> void:
	var bus := MockEventBus.new()
	watch_signals(bus.world())
	InteractionResolver.resolve(_make_data(), 1, "p1", bus)
	assert_signal_not_emitted(bus.world(), "loot_collected",
		"Ohne loot_table darf kein loot_collected emittiert werden")

func test_resolve_without_loot_table_returns_empty_dict() -> void:
	var bus := MockEventBus.new()
	var result := InteractionResolver.resolve(_make_data(), 1, "p1", bus)
	assert_eq(result.size(), 0, "Ohne loot_table muss resolve() ein leeres Dictionary liefern")

# ─────────────────────────────────────────────
# Mit loot_table — echte Loot-Berechnung
# ─────────────────────────────────────────────

func test_resolve_with_loot_table_emits_loot_collected() -> void:
	var bus := MockEventBus.new()
	var data := _make_data()
	data.loot_table = _make_guaranteed_loot_table("log_oak", 3, 3)
	watch_signals(bus.world())
	InteractionResolver.resolve(data, 1, "p1", bus)
	assert_signal_emitted_with_parameters(bus.world(), "loot_collected", ["log_oak", 3, 1])

func test_resolve_with_loot_table_returns_resolved_drops() -> void:
	var bus := MockEventBus.new()
	var data := _make_data()
	data.loot_table = _make_guaranteed_loot_table("iron_ore", 2, 2)
	var result := InteractionResolver.resolve(data, 1, "p1", bus)
	assert_eq(result.get("iron_ore"), 2, "Rückgabewert muss die tatsächlich gewürfelte Menge enthalten")

func test_resolve_attributes_loot_to_given_player_id_not_default() -> void:
	var bus := MockEventBus.new()
	var data := _make_data()
	data.loot_table = _make_guaranteed_loot_table("log_oak", 1, 1)
	watch_signals(bus.world())
	InteractionResolver.resolve(data, 7, "p7", bus)
	assert_signal_emitted_with_parameters(bus.world(), "loot_collected", ["log_oak", 1, 7])

# ─────────────────────────────────────────────
# XP-Emission
# ─────────────────────────────────────────────

func test_resolve_emits_xp_gained_when_configured() -> void:
	var bus := MockEventBus.new()
	var data := _make_data("chop", "woodcutting", 5)
	watch_signals(bus.player())
	InteractionResolver.resolve(data, 1, "p1", bus)
	assert_signal_emitted_with_parameters(bus.player(), "xp_gained", ["woodcutting", 5, 1])

func test_resolve_xp_attributed_to_given_player_id() -> void:
	var bus := MockEventBus.new()
	var data := _make_data("chop", "woodcutting", 5)
	watch_signals(bus.player())
	InteractionResolver.resolve(data, 9, "p9", bus)
	assert_signal_emitted_with_parameters(bus.player(), "xp_gained", ["woodcutting", 5, 9])

func test_resolve_xp_type_none_emits_no_xp() -> void:
	var bus := MockEventBus.new()
	var data := _make_data("inspect", "none", 10)
	watch_signals(bus.player())
	InteractionResolver.resolve(data, 1, "p1", bus)
	assert_signal_not_emitted(bus.player(), "xp_gained",
		"xp_type == 'none' darf kein xp_gained emittieren, unabhängig von xp_amount")

func test_resolve_xp_amount_zero_emits_no_xp() -> void:
	var bus := MockEventBus.new()
	var data := _make_data("chop", "woodcutting", 0)
	watch_signals(bus.player())
	InteractionResolver.resolve(data, 1, "p1", bus)
	assert_signal_not_emitted(bus.player(), "xp_gained",
		"xp_amount <= 0 darf kein xp_gained emittieren, auch mit gesetztem xp_type")

# ─────────────────────────────────────────────
# Yield-Skalierung über StatModifierService (Nebenbefund-Fix)
# ─────────────────────────────────────────────

func test_resolve_scales_quantity_with_stat_modifier() -> void:
	var bus := MockEventBus.new()
	var data := _make_data()
	data.loot_table   = _make_guaranteed_loot_table("log_oak", 10, 10)
	data.yield_stat_id = "gathering_yield_wood"
	var mods := StatModifierService.new()
	mods.add_modifier(StatModifier.permanent(
		"test_bonus", "gathering_yield_wood", StatModifier.Operation.PERCENT_ADD, 0.5
	), "p1")
	var result := InteractionResolver.resolve(data, 1, "p1", bus, mods)
	assert_eq(result.get("log_oak"), 15,
		"10 Basis-Menge × 1.5 (PERCENT_ADD 0.5) muss 15 ergeben")

func test_resolve_without_stat_modifiers_is_unscaled() -> void:
	var bus := MockEventBus.new()
	var data := _make_data()
	data.loot_table    = _make_guaranteed_loot_table("log_oak", 4, 4)
	data.yield_stat_id = "gathering_yield_wood"
	var result := InteractionResolver.resolve(data, 1, "p1", bus, null)
	assert_eq(result.get("log_oak"), 4,
		"Ohne stat_modifiers (null) darf keine Skalierung stattfinden (multiplier 1.0)")

func test_resolve_scaling_is_per_player_id() -> void:
	## Bug-Fix gegenüber der alten InteractionExecutor-Fassung: die dortige
	## get_effective_stat()-Aufruf ohne player_id las IMMER Spieler 1s Modifier,
	## unabhängig davon wer tatsächlich geerntet hat. resolve() muss den
	## übergebenen player_id tatsächlich verwenden, nicht raten/Default nehmen.
	var bus := MockEventBus.new()
	var mods := StatModifierService.new()
	mods.add_modifier(StatModifier.permanent(
		"p1_bonus", "gathering_yield_wood", StatModifier.Operation.PERCENT_ADD, 1.0
	), "p1")
	# Spieler 2 hat bewusst KEINEN Modifier.

	var data_p1 := _make_data()
	data_p1.loot_table    = _make_guaranteed_loot_table("log_oak", 10, 10)
	data_p1.yield_stat_id = "gathering_yield_wood"
	var result_p1 := InteractionResolver.resolve(data_p1, 1, "p1", bus, mods)

	var data_p2 := _make_data()
	data_p2.loot_table    = _make_guaranteed_loot_table("log_oak", 10, 10)
	data_p2.yield_stat_id = "gathering_yield_wood"
	var result_p2 := InteractionResolver.resolve(data_p2, 2, "p2", bus, mods)

	assert_eq(result_p1.get("log_oak"), 20, "Spieler 1 mit +100%-Modifier muss 20 bekommen")
	assert_eq(result_p2.get("log_oak"), 10, "Spieler 2 ohne Modifier muss unskaliert 10 bekommen")

# ─────────────────────────────────────────────
# Defensive Guards — kein Crash
# ─────────────────────────────────────────────

func test_resolve_with_null_data_no_crash_returns_empty() -> void:
	var bus := MockEventBus.new()
	var result: Dictionary = InteractionResolver.resolve(null, 1, "p1", bus)
	assert_eq(result.size(), 0, "resolve() mit data == null muss leeres Dictionary liefern, nicht crashen")

func test_resolve_with_null_bus_no_crash_returns_empty() -> void:
	var data := _make_data("chop", "woodcutting", 5)
	var result := InteractionResolver.resolve(data, 1, "p1", null)
	assert_eq(result.size(), 0, "resolve() mit bus == null muss leeres Dictionary liefern, nicht crashen")

func test_resolve_with_null_bus_no_crash_even_with_loot_table() -> void:
	var data := _make_data()
	data.loot_table = _make_guaranteed_loot_table("log_oak", 1, 1)
	# Darf nicht crashen, obwohl es ohne bus keine Möglichkeit gibt, das Ergebnis zuzustellen.
	InteractionResolver.resolve(data, 1, "p1", null)
	assert_true(true, "resolve() mit gesetzter loot_table aber bus == null darf nicht crashen")

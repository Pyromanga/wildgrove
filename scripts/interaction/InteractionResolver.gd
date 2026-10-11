class_name InteractionResolver
extends RefCounted

## InteractionResolver — berechnet das Ergebnis einer abgeschlossenen Interaktion
## (Loot-Roll + XP-Menge) AUSSCHLIESSLICH auf der Autorität.
##
## ADR-020 Option B, zweite Hälfte (Round 42 hat nur den Transport gebracht,
## siehe dortige "Umsetzungsstand"). Vorher lag dieselbe Berechnung in
## `InteractionExecutor._on_tween_finished()` — das lief pro Peer lokal, also
## konnte ein modifizierter Client sich sein eigenes Ergebnis ausdenken und dem
## Server nur noch das fertige Ergebnis melden (R-1). `InteractionExecutor`
## zeigt weiterhin den Tween/die Fortschrittsbar (Latenz-Verdeckung, rein
## visuell) — das eigentliche Ergebnis kommt jetzt ausschließlich von hier,
## aufgerufen aus dem bereits autoritäts-geguardeten `_on_interacted()`-Hook
## der jeweiligen Entity (HarvestableEntity, EnemyNPC — das Referenzmuster aus
## ADR-020s "Konsequenzen").
##
## Bewusst eine zustandslose statische Utility-Klasse (kein ServiceNode) —
## exakt dasselbe Muster wie AnimalCatcher/EnemyAttack: keine eigene Lifecycle,
## kein DI-Container-Eintrag nötig, nur eine reine Funktion über explizit
## übergebene Abhängigkeiten. Macht die Klasse ohne Mocks testbar (ADR-020
## "Mitigationen": "als eigenständiger, ungemockter Service getestet — echte
## Loot-Tabellen, echte Skill-Level").
##
## NICHT verantwortlich für:
##   - Autoritäts-Guard (liegt beim Aufrufer, siehe HarvestableEntity/EnemyNPC)
##   - Transport zur Autorität (ADR-020 Round 42, WorldService/NetworkBridge)
##   - Despawn/Entity-Lifecycle (bleibt entity-spezifisch)

const LOG_CAT := "InteractionResolver"

## Rollt data.loot_table (falls vorhanden) und emittiert die Ergebnisse +
## data.xp_type/xp_amount über den übergebenen IEventBus — attribuiert an
## peer_id, NIE an den lokalen Peer des Aufrufers.
##
## [param data]           InteractableData der abgeschlossenen Aktion (aus der
##                         InteractableComponent der Entity, NICHT aus einer
##                         client-gemeldeten Kopie).
## [param peer_id]      Wer die Interaktion ausgeführt hat — kommt vom
##                         Aufrufer, der ihn bereits authority-seitig kennt
##                         (RPC-Sender-ID bzw. resolve_for_player()). Bleibt
##                         die Attributions-ID für loot_collected/xp_gained
##                         (siehe TODO-offene-probleme.md, "Bewusst NICHT Teil
##                         dieses Punkts").
## [param player_id]      Stabile Identität desselben Spielers — Round 69,
##                         GEKLÄRTE Design-Frage (siehe TODO-offene-probleme.md,
##                         § Wichtig, Punkt 5): der Aufrufer löst sie zusätzlich
##                         zu peer_id auf und übergibt beide, statt
##                         InteractionResolver selbst eine Auflösungs-Fähigkeit
##                         (NetworkBridge-Dep oder Callable) zu geben, die nur
##                         für den stat_modifiers-Aufruf unten gebraucht würde.
##                         Leerer String ist ein gültiger, expliziter
##                         "unbekannt"-Wert (StatModifierService.get_effective_stat()
##                         behandelt ihn als "kein Bonus", kein Crash).
## [param bus]             IEventBus zum Emittieren von loot_collected/xp_gained.
##                         null → kein Crash, aber auch keine Wirkung (siehe Log).
## [param stat_modifiers]  Optional — skaliert die Drop-Menge über
##                         data.yield_stat_id, GENAU für player_id (BUG-FIX
##                         gegenüber der alten InteractionExecutor-Fassung, die
##                         get_effective_stat() ohne Id aufrief und damit
##                         immer Spieler 1s Modifier las, unabhängig davon wer
##                         tatsächlich geerntet hat).
##
## [return] Die gewürfelten Drops als { item_id: quantity } — für Tests und
## Logging. Der Aufrufer braucht den Rückgabewert für die Wirkung selbst nicht,
## die läuft bereits über die Emits.
static func resolve(
		data: InteractableData,
		peer_id: int,
		player_id: String,
		bus: IEventBus,
		stat_modifiers: StatModifierService = null
) -> Dictionary:
	if not is_instance_valid(data):
		AppLogger.log_warn("resolve(): keine InteractableData — nichts zu tun.", LOG_CAT)
		return {}
	if bus == null:
		AppLogger.log_warn(
			"resolve('%s'): kein IEventBus — Ergebnis kann nicht zugestellt werden." % data.id,
			LOG_CAT
		)
		return {}

	var resolved_drops: Dictionary = {}
	if data.loot_table:
		var yield_multiplier := 1.0
		if is_instance_valid(stat_modifiers) and not data.yield_stat_id.is_empty() and not player_id.is_empty():
			yield_multiplier = stat_modifiers.get_effective_stat(data.yield_stat_id, 1.0, player_id)
		resolved_drops = data.loot_table.roll(yield_multiplier)

	for item_id in resolved_drops:
		var qty: int = resolved_drops[item_id]
		bus.world().emit_loot_collected(item_id, qty, peer_id)

	if data.xp_type != "none" and data.xp_amount > 0:
		bus.player().emit_xp_gained(data.xp_type, data.xp_amount, peer_id)

	AppLogger.log_debug(
		"resolve('%s', Spieler %d): %d Item-Typ(en), %s"
		% [
			data.id, peer_id, resolved_drops.size(),
			("%d %s XP" % [data.xp_amount, data.xp_type]) if data.xp_type != "none" else "keine XP"
		],
		LOG_CAT
	)
	return resolved_drops

class_name ProfessionTrade
extends RefCounted

## ProfessionTrade — Tausch-Angebot eines Berufs-NPCs ("Bring mir X, ich mache dir Y").
##
## Nutzt DIESELBE serverseitige Logik wie Bauteil-Nutzung (StructureUse: Zutaten prüfen/verbrauchen,
## Ergebnis geben, Cooldown, Rückgabe bei vollem Inventar). Dafür wird aus dem Katalog-Eintrag eine
## BuildPieceDefinition (Kind TARGET, nur use_*-Felder) gebaut — es entsteht kein zweiter Weg.

static func make_def(trade: Dictionary, id: String) -> BuildPieceDefinition:
	var d := BuildPieceDefinition.new()
	d.id = "trade_" + id
	d.display_name = String(trade.get("label", ""))
	d.kind = BuildPieceDefinition.Kind.TARGET
	d.use_label = String(trade.get("label", ""))
	d.use_duration = float(trade.get("duration", 2.0))
	d.use_cooldown = float(trade.get("cooldown", 3.0))
	d.use_consumes = (trade.get("consumes", {}) as Dictionary).duplicate()
	d.use_gives = (trade.get("gives", {}) as Dictionary).duplicate()
	return d

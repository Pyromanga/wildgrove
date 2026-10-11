class_name FarmPlotRegistry
extends RefCounted

## FarmPlotRegistry — Persistenz für FarmPlot-Zustand (2026-09-27, "bepflanzte
## Felder nicht persistent" — FarmPlot.gd dokumentierte das bislang selbst als
## bekannte Lücke, siehe dortiger Klassenkommentar "PERSISTENZ").
##
## Gleiches Sparse-Registry-Muster wie TerrainMaterialLayer/DigFindRegistry:
## nur Plots mit stage != EMPTY tauchen überhaupt auf (ein leerer Pflanzplatz
## braucht keinen Eintrag — das ist ohnehin der Default nach on_spawn()).
##
## KEY: WorldData.make_key("farm_plot", global_position) — FarmPlots stehen an
## FESTEN, von WorldSpawner deterministisch berechneten Positionen (Dorf-Layout),
## nicht an zufälligen Seed-Positionen wie Bäume/Erze. Ein Positions-Key ist
## hier also stabil über Save/Load hinweg, genau wie bei
## typed_tree_positions/harvested_objects (siehe dortiger WorldData-Kommentar
## "nur ein Schema für Positionen").
##
## ready_at: absoluter Unix-Zeitstempel (Time.get_unix_time_from_system()),
## NICHT eine "verbleibende Sekunden"-Zahl — dieselbe Wahl wie FarmPlot.gd's
## bewusst echtzeitbasiertes Wachstum (siehe dortiger Klassenkommentar, "läuft
## weiter, während kein Spieler in der Nähe ist"), nur konsequent bis übers
## Speichern/Neuladen hinaus weitergedacht: eine Pflanze wächst dadurch auch
## weiter, während die App komplett zu ist, statt bei jedem Neuladen wieder
## bei voller Wachstumsdauer anzufangen. Einmal bei _try_plant() gesetzt,
## nie mehr neu berechnet — kein Nachführen bei jedem Speichern nötig, damit
## kann dieser Wert nicht veralten.
##
## crop_id wird BEWUSST NICHT hier gespeichert: laut FarmPlot.gd ist die
## Feldfrucht pro Plot eine Spawn-Zeit-Konstante (WorldSpawner-Konfiguration),
## kein Spieler-Datum — kommt bei jedem on_spawn() ohnehin wieder korrekt aus
## cfg["crop_id"]. Würde sich das Dorf-Layout mal ändern (andere Crop an
## derselben Position), soll die NEUE Konfiguration gelten, nicht ein alter
## gespeicherter Wert.

## { key: {"stage": int, "ready_at": float} }
var _records: Dictionary = {}

func is_empty() -> bool:
	return _records.is_empty()

func get_state(key: String) -> Dictionary:
	return _records.get(key, {})

## stage == FarmPlot.Stage.EMPTY löscht den Eintrag statt ihn zu speichern
## (Sparse-Prinzip, s.o. — EMPTY ist ohnehin der Default ohne Eintrag).
func set_state(key: String, stage: int, ready_at: float) -> void:
	if stage == 0:  # FarmPlot.Stage.EMPTY — Wert dupliziert statt Klassen-Enum
		# zu importieren (FarmPlot ist ein Node-Skript, diese Klasse bewusst
		# ohne Node-Abhängigkeit, siehe TerrainMaterialLayer für dasselbe Prinzip).
		_records.erase(key)
	else:
		_records[key] = {"stage": stage, "ready_at": ready_at}

func clear(key: String) -> void:
	_records.erase(key)

func clear_all() -> void:
	_records.clear()

# ─────────────────────────────────────────────
# Persistenz
# ─────────────────────────────────────────────

func to_save() -> Array:
	var out: Array = []
	for key: String in _records.keys():
		var rec: Dictionary = _records[key]
		out.append({"key": key, "stage": int(rec["stage"]), "ready_at": float(rec["ready_at"])})
	return out

## Lädt aus to_save()-Format. Ungültige/unvollständige Einträge werden übersprungen
## statt zu crashen — ein kaputter Save darf die Welt nicht killen.
func load_save(raw: Variant) -> void:
	_records.clear()
	if not raw is Array:
		return
	for entry in (raw as Array):
		if not entry is Dictionary:
			continue
		var rec: Dictionary = entry
		if not (rec.has("key") and rec.has("stage") and rec.has("ready_at")):
			continue
		var key: Variant = rec["key"]
		var stage: Variant = rec["stage"]
		var ready_at: Variant = rec["ready_at"]
		if not (key is String) or not (stage is int or stage is float) or not (ready_at is int or ready_at is float):
			continue
		set_state(String(key), int(stage), float(ready_at))

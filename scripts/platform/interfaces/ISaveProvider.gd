# res://scripts/platform/interfaces/ISaveProvider.gd
class_name ISaveProvider

## ISaveProvider — Statisches Interface für alle SaveSystem-Provider.
##
## Statt has_method("get_save_key") zur Laufzeit zu prüfen, erbt jeder Provider
## von dieser Klasse — der Vertrag ist zur Compile-Zeit sichtbar, nicht erst beim Laden.
##
## Migration: InventorySystem, QuestService, SkillSystem, WorldService,
## WorldTimeService — alle müssen "extends ISaveProvider" ergänzen.
## (WorldSaveHandler ist KEIN eigener Provider — reine Delegations-Hilfsklasse
## für WorldService, siehe WorldSaveHandler.gd-Klassenkommentar, Round 110.)
##
## Verwendung:
##   class_name MyService extends ServiceNode
##   extends ISaveProvider   # GDScript: mehrere extends via Komposition möglich
##   → oder: ServiceNode als primäre Elternklasse behalten und ISaveProvider
##     als Mixin-Konvention nutzen (class_name reicht für statische Typisierung)
##
## ──────────────────────────────────────────
## RESTORE-KONVENTION (Pull, nicht Push)
## ──────────────────────────────────────────
## Das SaveSystem schreibt keinen State zurück in Provider — Provider lesen
## ihren State selbst in configure() via SaveSystem.get_state_for(key).
## Beispiel:
##
##   func configure(deps: ServiceDeps) -> void:
##       _save_system = deps.require(ServiceKeys.SAVE_SYSTEM) as SaveSystem
##       if is_instance_valid(_save_system):
##           _save_system.register_save_provider(self)
##           var saved := _save_system.get_state_for(get_save_key())
##           _restore(saved)   # private Hilfsmethode, kein Interface-Contract
##
## Kein load_save_data()-Pflichtmethod im Interface — das würde eine Push-Architektur
## erzwingen, die dem Pull-Pattern widerspricht und die Boot-Reihenfolge
## (SaveSystem.begin_session vor configure()) zur Pflicht macht.

## Eindeutiger Schlüssel im Save-Dictionary.
## Muss pro Provider einmalig sein — Konvention: SAVE_KEY als Konstante.
func get_save_key() -> String:
	assert(false, "ISaveProvider.get_save_key() muss überschrieben werden!")
	return ""

## Gibt den zu speichernden State als Dictionary zurück.
## Wichtig: immer .duplicate() zurückgeben — SaveSystem darf keine Referenzen halten.
func get_save_data() -> Dictionary:
	assert(false, "ISaveProvider.get_save_data() muss überschrieben werden!")
	return {}

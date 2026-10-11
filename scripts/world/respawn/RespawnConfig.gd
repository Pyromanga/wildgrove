extends Resource
class_name RespawnConfig

## RespawnConfig — Konfigurierbare Respawn-Einstellungen pro Entity-Typ.
##
## Wird von RespawnService genutzt um zu bestimmen wie lange ein geerntetes
## Objekt braucht bis es wieder erscheint.
##
## Verwendung in WorldService._register_respawn_configs():
##   var cfg := RespawnConfig.new()
##   cfg.entity_type   = "oak_tree"
##   cfg.cooldown_secs = 300.0   # 5 Minuten (Spielzeit)
##   cfg.use_game_time = false   # false = Echtzeit, true = Spielzeit (Stunden)
##   respawn_service.register_config(cfg)

## Die type_id wie in EntityOrchestrator registriert (z.B. "oak_tree", "iron_ore").
@export var entity_type: String = ""

## Wartezeit in Sekunden (Echtzeit) bis die Entity respawnt.
## Beispielwerte:
##   Baum:     300s  (5 Minuten)
##   Eisenerz: 600s  (10 Minuten)
##   Goldader: 1800s (30 Minuten)
@export var cooldown_secs: float = 300.0

## Wenn true: cooldown_secs = Spielzeit-Stunden statt Echtzeit-Sekunden.
## (Zukunfts-Feature — aktuell immer false/Echtzeit)
@export var use_game_time: bool = false

## Maximale Anzahl Instanzen dieses Typs die gleichzeitig in der Welt sein dürfen.
## 0 = unbegrenzt (Standard: so viele wie in WorldData.typed_tree_positions definiert).
@export var max_instances: int = 0

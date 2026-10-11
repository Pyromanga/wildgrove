class_name QolUnlocks
extends RefCounted

## QolUnlocks — zentrale Freischalt-Prüfung für "Sammel"-QoL-Buttons (Wunsch
## "Spieler lieben es, Dinge freizuschalten" / "so bauen, dass es leicht hinter
## ein Achievement/eine Quest o.ä. gesetzt werden kann").
##
## AKTUELLER STAND: Alle Features unten sind auf `true` gesetzt (== für jeden
## sofort nutzbar) — bewusst so verdrahtet, aber über GENAU EINEN
## match-Zweig pro Feature statt verstreut in jedem Panel-Controller. Ein
## Feature später hinter eine Bedingung zu setzen ist dadurch eine
## Ein-Zeilen-Änderung hier, nicht eine Suche durch die UI-Controller.
##
## WIE MAN EIN FEATURE SPÄTER GATED (drei Wege, je nachdem was am Content
## schon existiert — Methodennamen siehe AchievementService.gd/QuestService.gd/
## SkillSystem.gd):
##   1. Achievement:  return _ctx.get_achievement_service().is_unlocked(player_id, "achievement_id")
##   2. Quest:        return _ctx.get_quest().is_quest_completed("quest_id", player_id)
##   3. Skill-Level:  return _ctx.get_skill_system().get_level("handel", player_id) >= 5
## `ctx`/`player_id` werden deshalb schon jetzt durchgereicht, obwohl der
## Rückgabewert aktuell konstant ist — der Aufrufer (Visuals/Controller) muss
## sich später nicht ändern, nur der match-Zweig hier.
##
## CONTENT-VORSCHLÄGE (siehe Antwort im Chat für die ausführliche Begründung):
##   - BANK_DEPOSIT_ALL  → Achievement "Sicher verwahrt" (50 Items manuell eingelagert)
##     ODER Bankier-Quest ("Talk to the Bank NPC about a Vault Key")
##   - SHOP_SELL_ALL     → Achievement "Kaufmann" (500 Gold durch Verkäufe verdient)
##     ODER Handel-Skill Level 5

const BANK_DEPOSIT_ALL := "bank_deposit_all"
const SHOP_SELL_ALL     := "shop_sell_all"

static func is_unlocked(feature_id: String, _ctx: IUIContext, _player_id: String) -> bool:
	match feature_id:
		BANK_DEPOSIT_ALL, SHOP_SELL_ALL:
			return true
		_:
			# Unbekannte Feature-ID: sicherer Default ist "gesperrt" — ein Tippfehler
			# in der ID soll ein Feature verstecken, nicht versehentlich freischalten.
			return false

## Kurzer Hinweistext fürs UI, falls ein Feature (noch) gesperrt ist — z.B. als
## Tooltip auf dem deaktivierten Button. Rein kosmetisch, hat keinen Einfluss
## auf is_unlocked() selbst.
static func locked_hint(feature_id: String) -> String:
	match feature_id:
		BANK_DEPOSIT_ALL:
			return "Noch nicht freigeschaltet."
		SHOP_SELL_ALL:
			return "Noch nicht freigeschaltet."
		_:
			return "Noch nicht freigeschaltet."

class_name TutorialGuideDialogController
extends RefCounted

## TutorialGuideDialogController — Dialog-State für TutorialGuideNPC
## (ADR-048 Round 106, Tutorial-Teil 2).
##
## Analog DialogueTreeController (progression/quests/ui/), aber ohne
## Quest-State-Machine — hier gibt es keine drei Zustände, nur einen
## Zähler durch eine feste Tipp-Reihe. Ein Tipp pro Gespräch, danach von
## vorn (siehe on_interact()) — bewusst wiederholbar statt einmalig, damit
## ein Spieler jederzeit erneut vorbeischauen kann, ohne dass der NPC nach
## dem letzten Tipp nur noch stumm dasteht.
##
## Kein Node, kein Server-Bezug — reiner Anzeige-Text, exakt wie
## DialogueTreeController._show_dialog(). Kein Fortschritts-Tracking pro
## Spieler (anders als CharacterCreationService.has_seen_creation()): die
## Tipps sind kosmetisch/wiederholbar, kein einmaliges Gate.

## Bewusst als generische UI-Beschreibung gehalten (Panel-/Symbolnamen aus
## HUDBuilder.gd), NICHT als Tastenkombination — das Spiel steuert sich
## über Joystick + Touch-Buttons (siehe HUDBuilder.gd:
## JoystickComponent/InteractionButtonComponent/ContextButtonComponent),
## keine dokumentierte Tastatur-Belegung im Projekt, die hier verlässlich
## zitiert werden könnte.
const TIPS: Array[String] = [
	"Mit dem Steuerkreuz unten links bewegst du dich durch Wildgrove.",
	"Der große Knopf unten rechts interagiert mit dem, was gerade markiert ist — Bäume, Erze, Tiere, NPCs wie mich.",
	"Dein Inventar findest du über das Taschen-Symbol — dort landet alles, was du sammelst und herstellst.",
	"Im Skill-Fenster siehst du, wie sich deine Fertigkeiten durchs bloße Tun weiterentwickeln.",
	"Das Quest-Tagebuch zeigt offene Aufgaben — sprich mit NPCs, die etwas zu erledigen haben.",
	"Bei den Errungenschaften siehst du, was du bereits geschafft hast.",
	"Der Händler, der Bankier und das Auktionshaus warten ein Stück weiter östlich — schau vorbei, sobald du etwas zu handeln hast.",
]

var _index: int = 0
var _dialog_label: Label3D
var _scene_tree: SceneTree
var _bus: IEventBus

func _init(dialog_label: Label3D, scene_tree: SceneTree, bus: IEventBus) -> void:
	_dialog_label = dialog_label
	_scene_tree   = scene_tree
	_bus          = bus

## Ein Tipp pro Aufruf. Nach dem letzten Tipp: Abschlusszeile, danach setzt
## sich der Zähler zurück, sodass das nächste Gespräch wieder bei Tipp 1
## beginnt.
func on_interact() -> void:
	if _index >= TIPS.size():
		_show_dialog("Das war's von mir — sprich einfach nochmal mit mir, wenn du dich noch mal umschauen willst!")
		_index = 0
		return
	_show_dialog(TIPS[_index])
	_index += 1

func _show_dialog(text: String) -> void:
	_dialog_label.text    = text
	_dialog_label.visible = true
	_scene_tree.create_timer(6.0).timeout.connect(func():
		if is_instance_valid(_dialog_label):
			_dialog_label.visible = false
	)
	_bus.world().emit_interaction_reward_text(text.replace("\n", " "))

# 0031 — ADR-051 Stufe 2 umgesetzt: einfache Auswahlliste bei mehreren ansprechbaren Slots

Zeit: 2026-09-27 11:08 UTC
Rolle: manager

## Gewählt
Neue Klasse NPCDialogueChoiceUI (CanvasLayer, kein HUD/IUIContext-Coupling). QuestNPCDialogController.set_choice_ui_factory(Callable) + on_interact() zeigt Menue nur wenn >1 Slot ansprechbar UND Factory gesetzt ist, sonst Stufe-1-Fallback (_auto_pick_and_show(), unveraendert). Menue-Label automatisch aus erster Zeile des Angebots-/Encourage-Texts abgeleitet, kein neuer Pflichtparameter. QuestNPC.on_spawn() verdrahtet die Factory fuer ALLE NPCs automatisch.

## Verworfene Alternativen
- Choice-UI ueber bestehenden ContextMenuController/HUD integrieren
- Pro Slot einen expliziten Label-Parameter verlangen statt Text-Ableitung

## Begründung
ContextMenuController ist eng an HUD/IUIContext/Player-Interactables gekoppelt -- Integration dort waere naeher an Stufe 3 (echtes Dialogsystem) als an der fuer Stufe 2 gewuenschten einfachen Loesung gewesen, siehe ADR-051. Auto-Ableitung des Labels haelt die Stufe-1-API unveraendert und gibt jedem kuenftigen add_independent_slot()-Aufruf die Auswahlliste ohne Zusatzaufwand.

# scripts/Interactable.gd
extends Node

signal interacted(player)

var display_name := "Objekt"
var on_cooldown := false

func interact(player) -> void:
	if on_cooldown:
		return
	on_cooldown = true
	emit_signal("interacted", player)
	# Cooldown nach 1 Sekunde zurücksetzen
	await get_tree().create_timer(1.0).timeout
	on_cooldown = false
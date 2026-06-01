# res://scripts/core/Service.gd
class_name Service extends RefCounted

var name: String = ""

# Lifecycle-Methoden für alle Arten von Services
func init() -> void: pass
func on_ready() -> void: pass
func _log_cat() -> String: return "%s/Service" % name
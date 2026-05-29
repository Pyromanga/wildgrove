extends "res://addons/gut/test.gd"

# Wir nutzen das globale Kernel-Singleton direkt.
# Falls du ihn lokal tracken willst, nenne die Variable anders als das Singleton!
var _test_kernel = null 

func before_all():
	# Wenn Kernel ein Autoload ist, ist er bereits im Tree.
	# Wir prüfen nur, ob er bereit ist.
	if not Kernel.is_inside_tree():
		# Falls GUT den Autoload nicht automatisch lädt (selten):
		_test_kernel = Kernel
	
	if not Kernel._is_initialized:
		await Kernel.services_ready

func test_check_kernel_integrity():
	assert_not_null(Kernel, "Kernel Singleton sollte existieren")
	assert_true(Kernel._is_initialized, "Kernel sollte initialisiert sein")

# after_all: Wenn du den echten Kernel nutzt, NICHT löschen!
# Sonst sind alle folgenden Tests kaputt.
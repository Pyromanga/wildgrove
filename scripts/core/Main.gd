extends Node

const LOG_CAT := "Main"

func _ready() -> void:
    # 1. Start den Bootstrap-Prozess
    var loader = ServiceLoader.new()
    loader.setup_services(self)
    
    # 2. Wir warten nicht mehr auf ein Signal in Main, 
    #    sondern nutzen das Event-System, das wir gerade gebaut haben.
    Kernel.events.system.services_initialized.connect(_on_services_ready)
    
    # Jetzt Phase 2+3 antriggern (nachdem alle Services registriert sind)
    # Kleiner Trick: Call deferred, um den laufenden _ready()-Call nicht zu stören
    loader.init_services.call_deferred()

func _on_services_ready() -> void:
    Logger.log_info("System bereit. Starte Game-Loop...", LOG_CAT)
    
    # Delegation: Die Factory weiß, wie man die Welt baut. 
    # Die Main.gd muss das nicht wissen!
    var world = Kernel.world_manager.create_world() # (Beispiel für einen neuen Service)
    add_child(world)
    
    # HUD-Erstellung durch den UI-Factory Service
    var hud = Kernel.ui_factory.create_hud()
    add_child(hud)
    
    # Der Builder (dein "Injektor") übernimmt den Rest
    HUDBuilder.build_all(hud)
    
    Logger.log_info("Spiel läuft.", LOG_CAT)
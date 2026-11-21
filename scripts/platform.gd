extends RefCounted
# Capacità della piattaforma. Il browser non può aprire socket TCP/UDP, scaricare pacchetti sul disco
# né chiudere la pagina: ciò che non esiste sul web si nasconde da qui, in un solo punto.

static func is_web() -> bool:
	return OS.has_feature("web")

# Stanze LAN su socket TCP/UDP: solo app native.
static func lan_available() -> bool:
	return not is_web()

# Aggiornatore dai pacchetti delle release GitHub: la versione web si aggiorna da sola a ogni caricamento.
static func updater_available() -> bool:
	return not is_web()

# Su una pagina web "Esci" non ha alcun effetto, quindi il pulsante non viene mostrato.
static func can_quit() -> bool:
	return not is_web()

# Punto d'innesto per le partite online senza server (WebRTC + tracker WebSocket). Sul web è sempre disponibile:
# WebRTCPeerConnection e WebSocketPeer sono nel template web e usano le API native del browser.
# Sulle app native resta false finché la sessione online non le abilita: basta allargare questa condizione.
static func online_available() -> bool:
	return is_web()

static func fullscreen_available() -> bool:
	return is_web()

static func toggle_fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

static func is_fullscreen() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN

extends RefCounted
const OnlineLink = preload("res://scripts/online_link.gd")
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

# Partite online senza server (WebRTC + tracker WebSocket). Sul web usano le API del browser; sulle app native
# servono l'estensione webrtc-native: se manca o non si carica la modalità non viene offerta.
static func online_available() -> bool:
	return is_web() or OnlineLink.supported()

static func fullscreen_available() -> bool:
	return is_web()

static func toggle_fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

static func is_fullscreen() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN

# Impostazioni video avanzate (risoluzione, FSR, V-Sync…): solo Windows e Mac. Il web e Android hanno le proprie.
static func pc_available() -> bool:
	return not is_web() and not OS.has_feature("android") and not OS.has_feature("ios")

static func is_windows() -> bool:
	return OS.get_name() == "Windows"

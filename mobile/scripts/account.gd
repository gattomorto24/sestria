extends Node
signal changed
var game: Node3D
var profile := {}
var busy := false
var message := ""
var bridge: Object
var config := {}
const PROFILE_PATH := "user://google_profile.json"

func setup(owner_game: Node3D) -> void:
	game=owner_game
	process_mode=Node.PROCESS_MODE_ALWAYS
	var settings=JSON.parse_string(FileAccess.get_file_as_string("res://config/google_auth.json"))
	if settings is Dictionary:
		config=settings
	if FileAccess.file_exists(PROFILE_PATH):
		var stored=JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
		if stored is Dictionary and stored.get("sub","") is String and str(stored.sub).is_valid_int():
			profile={"sub":str(stored.sub),"name":str(stored.get("name","Giocatore")).left(80),"email":str(stored.get("email","")).left(160)}
	if Engine.has_singleton("SestriaGoogle"):
		bridge=Engine.get_singleton("SestriaGoogle")
		bridge.connect("signed_in",_signed_in)
		bridge.connect("sign_in_failed",_failed)
		bridge.connect("signed_out",_signed_out)

func available() -> bool:
	return bridge!=null and str(config.get("web_client_id","")).ends_with(".apps.googleusercontent.com")

func sign_in() -> void:
	if busy:
		return
	if not available():
		message="Accesso Google disponibile nell’APK Android configurato."
		changed.emit()
		return
	busy=true
	message="Scegli il tuo account nella finestra di Google."
	changed.emit()
	bridge.signIn(str(config.web_client_id))

func _signed_in(raw: String) -> void:
	busy=false
	var item=JSON.parse_string(raw)
	if not item is Dictionary or not str(item.get("sub","")).is_valid_int():
		_failed("Risposta Google non valida.")
		return
	profile={"sub":str(item.sub),"name":str(item.get("name","Giocatore")).left(80),"email":str(item.get("email","")).left(160)}
	var file := FileAccess.open(PROFILE_PATH,FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(profile))
	message="Accesso completato. Il profilo è salvato su questo dispositivo."
	changed.emit()

func sign_out() -> void:
	profile.clear()
	if FileAccess.file_exists(PROFILE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))
	if bridge:
		bridge.signOut()
	message="Disconnesso. Le statistiche di questo dispositivo restano disponibili."
	changed.emit()

func _signed_out() -> void:
	busy=false
	changed.emit()

func _failed(reason: String) -> void:
	busy=false
	message=reason.left(250)
	changed.emit()

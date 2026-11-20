extends Node
signal changed
const REPOSITORY := "gattomorto24/sestria"
const RELEASES := "https://github.com/"+REPOSITORY+"/releases"
const API := "https://api.github.com/repos/"+REPOSITORY+"/releases/latest"
const APK_PATH := "user://updates/sestria-update.apk"
const PART_PATH := APK_PATH+".part"
const MAX_APK := 180*1024*1024
var current_version := "4.3"
var current_code := 43
var state := "idle"
var message := "Cerca le nuove versioni pubblicate su GitHub."
var release := {}
var progress := 0.0
var last_checked := ""
var bridge: Object
var request: HTTPRequest
var progress_clock := 0.0

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	if Engine.has_singleton("SestriaUpdates"):
		bridge=Engine.get_singleton("SestriaUpdates")
		current_version=bridge.getVersionName()
		current_code=bridge.getVersionCode()
	request=HTTPRequest.new()
	request.use_threads=true
	request.timeout=25
	request.body_size_limit=2*1024*1024
	request.max_redirects=6
	add_child(request)
	request.request_completed.connect(completed)

static func version_parts(value: String) -> Array:
	var expression := RegEx.new()
	expression.compile("^v?([0-9]{1,5})\\.([0-9]{1,5})(?:\\.([0-9]{1,5}))?$")
	var result := expression.search(value)
	if not result:
		return []
	return [int(result.get_string(1)),int(result.get_string(2)),int(result.get_string(3))]

static func newer(candidate: String, installed: String) -> bool:
	var a := version_parts(candidate)
	var b := version_parts(installed)
	if a.is_empty() or b.is_empty():
		return false
	for i in 3:
		if a[i] != b[i]:
			return a[i]>b[i]
	return false

static func parse_release(info: Dictionary, installed: String) -> Dictionary:
	if info.get("draft",true) or info.get("prerelease",true):
		return {}
	var tag := str(info.get("tag_name",""))
	if version_parts(tag).is_empty() or not newer(tag,installed):
		return {}
	if not info.get("assets") is Array:
		return {}
	for item in info.assets:
		if not item is Dictionary:
			continue
		var name := str(item.get("name",""))
		var url := str(item.get("browser_download_url",""))
		var digest := str(item.get("digest",""))
		var bytes := int(item.get("size",0))
		if not name.begins_with("Sestria-v") or not name.ends_with("-Android.apk") or item.get("state","")!="uploaded":
			continue
		if not url.begins_with(RELEASES+"/download/"+tag+"/") or bytes<=0 or bytes>MAX_APK or not digest.begins_with("sha256:"):
			continue
		var sha := digest.trim_prefix("sha256:").to_lower()
		var pattern := RegEx.new()
		pattern.compile("^[0-9a-f]{64}$")
		if not pattern.search(sha):
			continue
		return {"version":tag.trim_prefix("v"),"name":name,"url":url,"sha256":sha,"size":bytes,"notes":str(info.get("body","")).left(6000),"page":RELEASES+"/tag/"+tag}
	return {}

func check_updates() -> void:
	if state in ["checking","downloading","verifying"]:
		return
	release={}
	state="checking"
	message="Controllo delle release su GitHub…"
	progress=0
	request.download_file=""
	request.timeout=25
	request.body_size_limit=2*1024*1024
	changed.emit()
	var error := request.request(API,PackedStringArray(["Accept: application/vnd.github+json","User-Agent: Sestria-Android/"+current_version,"X-GitHub-Api-Version: 2022-11-28"]))
	if error != OK:
		fail("Impossibile avviare la verifica. Controlla la connessione e riprova.")

func download_update() -> void:
	if state!="available" or release.is_empty():
		return
	if not bridge:
		OS.shell_open(str(release.page))
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://updates"))
	remove_file(PART_PATH)
	state="downloading"
	message="Download da GitHub…"
	progress=0
	request.download_file=PART_PATH
	request.timeout=300
	request.body_size_limit=MAX_APK
	changed.emit()
	var error := request.request(str(release.url),PackedStringArray(["User-Agent: Sestria-Android/"+current_version,"Accept-Encoding: identity"]))
	if error != OK:
		fail("Download non avviato. Riprova più tardi.")

func _process(delta: float) -> void:
	if state=="downloading":
		progress_clock+=delta
		if progress_clock>=.25:
			progress_clock=0
			progress=clampf(float(request.get_downloaded_bytes())/maxf(1,float(release.size)),0,1)
			message="Scaricati %.1f / %.1f MB" % [request.get_downloaded_bytes()/1048576.0,float(release.size)/1048576.0]
			changed.emit()

func completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if state=="checking":
		last_checked=Time.get_datetime_string_from_system().replace("T"," ")
		if result!=HTTPRequest.RESULT_SUCCESS:
			fail("GitHub non raggiungibile. Controlla Internet e riprova.")
		elif code==404:
			state="current"
			message="Non ci sono ancora release pubblicate. Versione installata: "+current_version
			changed.emit()
		elif code in [403,429]:
			fail("GitHub ha limitato temporaneamente le richieste. Riprova tra qualche minuto.")
		elif code!=200:
			fail("GitHub ha risposto con errore %d. Riprova più tardi." % code)
		else:
			var info=JSON.parse_string(body.get_string_from_utf8())
			if not info is Dictionary or version_parts(str(info.get("tag_name",""))).is_empty():
				fail("La release non contiene una versione valida.")
				return
			release=parse_release(info,current_version)
			if not newer(str(info.tag_name),current_version):
				state="current"
				message="Sestria è aggiornato. Versione "+current_version
			elif release.is_empty():
				fail("È presente una nuova release, ma l’APK Android verificabile non è ancora pronto.")
				return
			else:
				state="available"
				message="Sestria "+str(release.version)+" è disponibile."
			changed.emit()
	elif state=="downloading":
		if result!=HTTPRequest.RESULT_SUCCESS or code!=200:
			remove_file(PART_PATH)
			fail("Download interrotto. Tocca Verifica per riprovare.")
			return
		state="verifying"
		message="Verifica integrità e firma dell’aggiornamento…"
		changed.emit()
		await get_tree().process_frame
		var file := FileAccess.open(PART_PATH,FileAccess.READ)
		if not file or file.get_length()!=int(release.size):
			remove_file(PART_PATH)
			fail("File incompleto: aggiornamento scartato.")
			return
		file.close()
		if FileAccess.get_sha256(PART_PATH)!=str(release.sha256):
			remove_file(PART_PATH)
			fail("Il file scaricato non corrisponde alla release. Aggiornamento scartato.")
			return
		var verdict: String=bridge.validateUpdate(ProjectSettings.globalize_path(PART_PATH),str(release.version))
		if verdict!="":
			remove_file(PART_PATH)
			fail(verdict)
			return
		remove_file(APK_PATH)
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(PART_PATH),ProjectSettings.globalize_path(APK_PATH))!=OK:
			fail("Impossibile salvare l’aggiornamento. Controlla lo spazio libero.")
			return
		state="ready"
		progress=1
		message="Aggiornamento verificato. Puoi installarlo mantenendo i tuoi progressi."
		changed.emit()

func install_update() -> void:
	if state=="ready" and bridge:
		var error: String=bridge.installUpdate(ProjectSettings.globalize_path(APK_PATH),str(release.version))
		message=error if not error.is_empty() else "Conferma l’aggiornamento nella finestra di Android. Se hai abilitato l’autorizzazione, torna qui e tocca Installa."
		changed.emit()

func cancel() -> void:
	if state in ["checking","downloading"]:
		request.cancel_request()
		remove_file(PART_PATH)
		state="idle"
		message="Operazione annullata."
		changed.emit()

func fail(note: String) -> void:
	state="error"
	message=note
	changed.emit()

static func remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

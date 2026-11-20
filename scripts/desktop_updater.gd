extends Node
# Aggiornamenti desktop: legge le release pubbliche di GitHub, scarica il pacchetto
# della propria piattaforma, ne verifica la SHA-256 e lo mostra nella cartella Download.
# L'installazione resta manuale: l'app non sostituisce mai se stessa.
signal changed
const REPOSITORY := "gattomorto24/sestria"
const RELEASES := "https://github.com/"+REPOSITORY+"/releases"
const API := "https://api.github.com/repos/"+REPOSITORY+"/releases/latest"
const MAX_PACKAGE := 600*1024*1024
const FALLBACK_VERSION := "4.5"
var current_version := FALLBACK_VERSION
var state := "idle"
var message := "Cerca le nuove versioni pubblicate su GitHub."
var release := {}
var progress := 0.0
var last_checked := ""
var saved_path := ""
var request: HTTPRequest
var progress_clock := 0.0
var download_dir := ""

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	var configured := str(ProjectSettings.get_setting("application/config/version",""))
	if not version_parts(configured).is_empty():
		current_version=configured
	download_dir=OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	request=HTTPRequest.new()
	request.use_threads=true
	request.timeout=25
	request.body_size_limit=2*1024*1024
	request.max_redirects=6
	add_child(request)
	request.request_completed.connect(completed)

static func platform_suffix() -> String:
	match OS.get_name():
		"macOS":
			return "-macOS-universal.zip"
		"Windows":
			return "-Windows-x64.zip"
	return ""

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

static func parse_release(info: Dictionary, installed: String, suffix: String) -> Dictionary:
	if suffix.is_empty() or info.get("draft",true) or info.get("prerelease",true):
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
		if not name.begins_with("Sestria-v") or not name.ends_with(suffix) or item.get("state","")!="uploaded":
			continue
		if name.contains("/") or name.contains("\\") or name.contains(".."):
			continue
		if not url.begins_with(RELEASES+"/download/"+tag+"/") or bytes<=0 or bytes>MAX_PACKAGE or not digest.begins_with("sha256:"):
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
	var error := request.request(API,PackedStringArray(["Accept: application/vnd.github+json","User-Agent: Sestria-Desktop/"+current_version,"X-GitHub-Api-Version: 2022-11-28"]))
	if error != OK:
		fail("Impossibile avviare la verifica. Controlla la connessione e riprova.")

func part_path() -> String:
	return download_dir.path_join(str(release.name)+".part")

func final_path() -> String:
	return download_dir.path_join(str(release.name))

func download_update() -> void:
	if state!="available" or release.is_empty():
		return
	if download_dir.is_empty() or not DirAccess.dir_exists_absolute(download_dir):
		OS.shell_open(str(release.page))
		return
	remove_file(part_path())
	state="downloading"
	message="Download da GitHub…"
	progress=0
	request.download_file=part_path()
	request.timeout=600
	request.body_size_limit=MAX_PACKAGE
	changed.emit()
	var error := request.request(str(release.url),PackedStringArray(["User-Agent: Sestria-Desktop/"+current_version,"Accept-Encoding: identity"]))
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
			release=parse_release(info,current_version,platform_suffix())
			if not newer(str(info.tag_name),current_version):
				state="current"
				message="Sestria è aggiornato. Versione "+current_version
			elif release.is_empty():
				fail("È presente una nuova release, ma il pacchetto verificabile per questo sistema non è ancora pronto.")
				return
			else:
				state="available"
				message="Sestria "+str(release.version)+" è disponibile."
			changed.emit()
	elif state=="downloading":
		if result!=HTTPRequest.RESULT_SUCCESS or code!=200:
			remove_file(part_path())
			fail("Download interrotto. Premi Verifica per riprovare.")
			return
		state="verifying"
		message="Verifica dell’integrità del pacchetto…"
		changed.emit()
		await get_tree().process_frame
		var file := FileAccess.open(part_path(),FileAccess.READ)
		if not file or file.get_length()!=int(release.size):
			remove_file(part_path())
			fail("File incompleto: pacchetto scartato.")
			return
		file.close()
		if FileAccess.get_sha256(part_path())!=str(release.sha256):
			remove_file(part_path())
			fail("Il file scaricato non corrisponde alla release. Pacchetto scartato.")
			return
		remove_file(final_path())
		if DirAccess.rename_absolute(part_path(),final_path())!=OK:
			remove_file(part_path())
			fail("Impossibile salvare il pacchetto. Controlla lo spazio libero.")
			return
		saved_path=final_path()
		state="ready"
		progress=1
		message="Pacchetto verificato e salvato in Download. Chiudi Sestria, estrai l’archivio e sostituisci la versione installata."
		changed.emit()

func reveal_update() -> void:
	if state=="ready" and not saved_path.is_empty():
		OS.shell_show_in_file_manager(saved_path)

func cancel() -> void:
	if state in ["checking","downloading"]:
		request.cancel_request()
		if state=="downloading":
			remove_file(part_path())
		state="idle"
		message="Operazione annullata."
		changed.emit()

func fail(note: String) -> void:
	state="error"
	message=note
	changed.emit()

static func remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

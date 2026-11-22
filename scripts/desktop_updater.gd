extends Node
# Aggiornamenti desktop. Legge le release pubbliche di GitHub e, se la release ha un pacchetto contenuti firmato
# compatibile con questa app, lo scarica, lo verifica e lo applica al riavvio successivo (modo "content").
# Altrimenti ripiega sul pacchetto completo della piattaforma: SHA-256 verificata, salvato in Download,
# installazione manuale (modo "package"). Il pacchetto contenuti non cambia motore né codice nativo.
signal changed
const Content = preload("res://scripts/content_pack.gd")
const REPOSITORY := "gattomorto24/sestria"
const RELEASES := "https://github.com/"+REPOSITORY+"/releases"
const API := "https://api.github.com/repos/"+REPOSITORY+"/releases/latest"
const MAX_PACKAGE := 600*1024*1024
const FALLBACK_VERSION := "4.8"
var current_version := FALLBACK_VERSION
var base_version := FALLBACK_VERSION
var state := "idle"
var message := "Cerca le nuove versioni pubblicate su GitHub."
var release := {}
var progress := 0.0
var last_checked := ""
var saved_path := ""
var request: HTTPRequest
var progress_clock := 0.0
var download_dir := ""
var step := ""
var api := API
var releases := RELEASES
var pending_info := {}
var pending_manifest := {}
var fallback_reason := ""

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	var configured := str(ProjectSettings.get_setting("application/config/version",""))
	if not version_parts(configured).is_empty():
		current_version=configured
	base_version=Content.base_version()
	if Content.running_version()!="0.0":
		current_version=Content.running_version()
	if OS.is_debug_build():
		# Solo nelle build di sviluppo: un server di prova al posto di GitHub (tests/content_update_e2e.gd).
		if not OS.get_environment("SESTRIA_UPDATE_API").is_empty():
			api=OS.get_environment("SESTRIA_UPDATE_API")
		if not OS.get_environment("SESTRIA_UPDATE_RELEASES").is_empty():
			releases=OS.get_environment("SESTRIA_UPDATE_RELEASES")
	var staged := Content.staged_version()
	if not staged.is_empty():
		state="ready"
		progress=1
		release={"mode":"content","version":staged}
		message="Sestria %s è già scaricato e verificato. Riavvia l’app per applicarlo." % staged
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

static func parse_release(info: Dictionary, installed: String, suffix: String, base_url := RELEASES) -> Dictionary:
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
		if not url.begins_with(base_url+"/download/"+tag+"/") or bytes<=0 or bytes>MAX_PACKAGE or not digest.begins_with("sha256:"):
			continue
		var sha := digest.trim_prefix("sha256:").to_lower()
		var pattern := RegEx.new()
		pattern.compile("^[0-9a-f]{64}$")
		if not pattern.search(sha):
			continue
		return {"version":tag.trim_prefix("v"),"name":name,"url":url,"sha256":sha,"size":bytes,"notes":str(info.get("body","")).left(6000),"page":base_url+"/tag/"+tag,"mode":"package"}
	return {}

func check_updates() -> void:
	if state in ["checking","downloading","verifying"]:
		return
	release={}
	pending_info={}
	pending_manifest={}
	fallback_reason=""
	state="checking"
	step="api"
	message="Controllo delle release su GitHub…"
	progress=0
	request.download_file=""
	request.timeout=25
	request.body_size_limit=2*1024*1024
	changed.emit()
	var error := request.request(api,PackedStringArray(["Accept: application/vnd.github+json","User-Agent: Sestria-Desktop/"+current_version,"X-GitHub-Api-Version: 2022-11-28"]))
	if error != OK:
		fail("Impossibile avviare la verifica. Controlla la connessione e riprova.")

func part_path() -> String:
	return download_dir.path_join(str(release.name)+".part")

func final_path() -> String:
	return download_dir.path_join(str(release.name))

func download_update() -> void:
	if state!="available" or release.is_empty():
		return
	if release.get("mode","package")=="content":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Content.dir))
		Content.remove_file(Content.part_path(str(release.name)))
		request.download_file=Content.part_path(str(release.name))
		request.timeout=600
		request.body_size_limit=int(release.size)+1024
		step="pack"
		state="downloading"
		message="Download dell’aggiornamento…"
		progress=0
		changed.emit()
		var content_error := request.request(str(release.url),PackedStringArray(["User-Agent: Sestria-Desktop/"+current_version,"Accept-Encoding: identity"]))
		if content_error != OK:
			fail("Download non avviato. Riprova più tardi.")
		return
	if download_dir.is_empty() or not DirAccess.dir_exists_absolute(download_dir):
		OS.shell_open(str(release.page))
		return
	remove_file(part_path())
	step="package"
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
	if state=="checking" and step=="manifest":
		manifest_received(result,code,body)
	elif state=="checking":
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
			if not newer(str(info.tag_name),current_version):
				state="current"
				message="Sestria è aggiornato. Versione "+current_version
				changed.emit()
				return
			pending_info=info
			var tag := str(info.tag_name)
			var staged := Content.staged_version()
			if not staged.is_empty() and not newer(tag,staged):
				state="ready"
				progress=1
				release={"mode":"content","version":staged}
				message="Sestria %s è già scaricato e verificato. Riavvia l’app per applicarlo." % staged
				changed.emit()
				return
			var manifest_asset := Content.find_asset(info,Content.manifest_name(tag.trim_prefix("v")),releases,tag) if not Content.platform_key().is_empty() else {}
			if manifest_asset.is_empty() or int(manifest_asset.size)>Content.MAX_MANIFEST:
				offer_package("Questa versione non include un aggiornamento dei contenuti.")
				return
			step="manifest"
			request.body_size_limit=Content.MAX_MANIFEST*2
			var error := request.request(str(manifest_asset.url),PackedStringArray(["User-Agent: Sestria-Desktop/"+current_version,"Accept-Encoding: identity"]))
			if error != OK:
				offer_package("Impossibile leggere il manifest dell’aggiornamento.")
	elif state=="downloading" and step=="pack":
		if result!=HTTPRequest.RESULT_SUCCESS or code!=200:
			Content.remove_file(Content.part_path(str(release.name)))
			fail("Download interrotto. Premi Verifica per riprovare.")
			return
		state="verifying"
		message="Verifica firma e integrità dell’aggiornamento…"
		changed.emit()
		await get_tree().process_frame
		var reason := Content.install_downloaded(Content.part_path(str(release.name)),pending_manifest,release.pack,str(release.get("digest","")))
		if not reason.is_empty():
			fail(reason)
			return
		state="ready"
		progress=1
		message="Aggiornamento %s scaricato e verificato. Riavvia Sestria per applicarlo: i tuoi progressi restano al loro posto." % str(release.version)
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

# Risposta del manifest firmato: se è valido e compatibile si offre l'aggiornamento dei contenuti.
func manifest_received(result: int, code: int, body: PackedByteArray) -> void:
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200:
		offer_package("Il manifest dell’aggiornamento non è raggiungibile.")
		return
	var verdict := Content.verify_manifest(body.get_string_from_utf8())
	if not verdict.ok:
		offer_package(str(verdict.error))
		return
	var manifest: Dictionary = verdict.manifest
	var tag := str(pending_info.tag_name)
	var entry := Content.pack_entry(manifest)
	if str(manifest.version)!=tag.trim_prefix("v") or entry.is_empty():
		offer_package("Il manifest non descrive un pacchetto per questo sistema.")
		return
	if str(manifest.version) in Content.rejected_versions():
		offer_package("Su questo computer l’aggiornamento dei contenuti non è riuscito.")
		return
	var incompatible := Content.incompatibility(manifest,entry,base_version)
	if not incompatible.is_empty():
		offer_package(incompatible)
		return
	var asset := Content.find_asset(pending_info,str(entry.name),releases,tag)
	if asset.is_empty() or int(asset.size)!=int(entry.size) or (not str(asset.digest).is_empty() and str(asset.digest)!=str(entry.sha256)):
		offer_package("Il pacchetto dei contenuti non è ancora pronto su GitHub.")
		return
	pending_manifest=manifest
	release={"mode":"content","version":str(manifest.version),"name":str(entry.name),"url":str(asset.url),"sha256":str(entry.sha256),"digest":str(asset.digest),"size":int(entry.size),"pack":entry,"notes":str(pending_info.get("body","")).left(6000),"page":releases+"/tag/"+tag}
	state="available"
	message="Sestria %s è disponibile. L’aggiornamento è piccolo e si applica da solo al riavvio." % str(release.version)
	changed.emit()

# Nessun pacchetto contenuti utilizzabile: si propone il pacchetto completo e si spiega perché.
func offer_package(reason: String) -> void:
	fallback_reason=reason
	release=parse_release(pending_info,current_version,platform_suffix(),releases)
	if release.is_empty():
		fail("È presente una nuova release, ma il pacchetto verificabile per questo sistema non è ancora pronto.")
		return
	state="available"
	message="Sestria %s è disponibile come pacchetto completo. %s" % [str(release.version),reason]
	changed.emit()

# Applica l'aggiornamento già scaricato: riavvia l'app, e al nuovo avvio boot.gd monta il pacchetto.
func restart_to_apply() -> void:
	if state!="ready" or release.get("mode","")!="content":
		return
	if not Content.restart(get_tree()):
		message="Non riesco a riavviare da solo: chiudi e riapri Sestria per applicare l’aggiornamento."
		changed.emit()

func reveal_update() -> void:
	if state=="ready" and not saved_path.is_empty():
		OS.shell_show_in_file_manager(saved_path)

func cancel() -> void:
	if state in ["checking","downloading"]:
		request.cancel_request()
		if state=="downloading":
			if step=="pack":
				Content.remove_file(Content.part_path(str(release.name)))
			else:
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

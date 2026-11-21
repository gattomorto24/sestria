extends RefCounted
# Aggiornamenti dei contenuti senza reinstallare l'app.
# Ogni release può includere un pacchetto di risorse (.pck con script, scene, asset e shader) per piattaforma e un
# manifest firmato (RSA-3072 / SHA-256, chiave pubblica incorporata qui sotto). L'app scarica il pacchetto in
# user://, ne verifica firma, SHA-256, dimensione e intestazione del motore, e al riavvio successivo lo monta sopra
# i file integrati prima di caricare il gioco (vedi boot.gd). Il pacchetto NON cambia motore Godot né codice nativo
# (Java su Android): per quelli serve ancora il pacchetto completo.
# Questo file è identico in scripts/ e mobile/scripts/ (tools/export_content_pack.sh lo controlla).
const PUBLIC_KEY_PEM := """-----BEGIN PUBLIC KEY-----
MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEA3U3I0YUqIL3Tj7+Xob5r
gUJt6XMuTk9DqUXPnToC9GT8njJSRS8q3RosJGrf/d8CfRdAe9jdnkNEivZ/UTjl
BuRZf/3tMiSduZ1laqWyulHGxzVoxiA1t1McXct7hnhXm93THIJU2f7MGBi0s+Br
sqM2C9OdGls7aEnLVC2VZ+3qxIL07yQsS0a23lYWpg2pz28nnq0l6lRN7KytBlF0
rDcz7C/PcA2xeNsrCrp3hL6Llz5eOEjawh52t1fEHt+U5hkEjDP4dLdcFtDWNd1T
Zruqz5JRFohkAXhGcc8OER6YCqVqNMx2ABmu+t78X77qewQ94iiDZ7sNgDsDspXf
IBokHzJJb/28WHfdLE155UAHmsrr7HDsCUpEYeN17wjqX7p0OxVNGoDhZdCv4rFy
zcCieeBJcW/+d//RXzBKaTHdSqvxuFxEiqY5wj8UYwe4g7+uBgYXfXkoiekl/UGe
6u2J+VR9EmyQp8VVQePu/xrx1IWiO+IwHKL5HYr3db29AgMBAAE=
-----END PUBLIC KEY-----
"""
const INFO_PATH := "res://content.json"
const SCHEMA := 1
const MAX_MANIFEST := 64*1024
const MAX_PACK := 150*1024*1024
const PCK_MAGIC := 0x43504447
static var dir := "user://updates/content"
# Chiave con cui si verificano i manifest: quella incorporata; solo i test la sostituiscono.
static var trusted_key := PUBLIC_KEY_PEM
static var builtin := ""
static var boot_status := "none"
static var boot_note := ""

# ---------- versioni ----------

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

static func read_info() -> Dictionary:
	var file := FileAccess.open(INFO_PATH,FileAccess.READ)
	if not file:
		return {}
	var info = JSON.parse_string(file.get_as_text())
	return info if info is Dictionary else {}

# Versione dei contenuti in esecuzione: dopo il montaggio è quella del pacchetto.
static func running_version() -> String:
	var value := str(read_info().get("content",""))
	return value if not version_parts(value).is_empty() else "0.0"

# Versione dei contenuti integrati nell'app, fissata prima di montare qualsiasi pacchetto.
static func builtin_version() -> String:
	return builtin if not builtin.is_empty() else running_version()

# Versione del pacchetto completo installato (motore e codice nativo), che nessun pacchetto contenuti modifica.
static func base_version() -> String:
	if Engine.has_singleton("SestriaUpdates"):
		var native := str(Engine.get_singleton("SestriaUpdates").getVersionName())
		if not version_parts(native).is_empty():
			return native
	var configured := str(ProjectSettings.get_setting("application/config/version",""))
	if not version_parts(configured).is_empty():
		return configured
	return builtin_version()

static func platform_key() -> String:
	match OS.get_name():
		"macOS":
			return "macos"
		"Windows":
			return "windows"
		"Android":
			return "android"
	return ""

# ---------- manifest firmato ----------

static func engine_label(info: Dictionary = Engine.get_version_info()) -> String:
	return "%d.%d" % [int(info.get("major",0)),int(info.get("minor",0))]

# Il manifest è "riga 1 = JSON compatto, riga 2 = firma RSA PKCS#1 v1.5 SHA-256 in base64 della riga 1".
static func verify_manifest(text: String, key_pem := "") -> Dictionary:
	var newline := text.find("\n")
	if newline<=0 or text.length()>MAX_MANIFEST*2:
		return {"ok":false,"error":"Manifest non valido."}
	var body := text.substr(0,newline)
	var signature := Marshalls.base64_to_raw(text.substr(newline+1).strip_edges())
	var key := CryptoKey.new()
	if key.load_from_string(key_pem if not key_pem.is_empty() else trusted_key,true)!=OK or signature.is_empty():
		return {"ok":false,"error":"Firma del manifest assente o chiave non valida."}
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(body.to_utf8_buffer())
	if not Crypto.new().verify(HashingContext.HASH_SHA256,hashing.finish(),signature,key):
		return {"ok":false,"error":"Firma del manifest non valida: aggiornamento ignorato."}
	var manifest = JSON.parse_string(body)
	if not manifest is Dictionary or int(manifest.get("schema",0))!=SCHEMA or version_parts(str(manifest.get("version",""))).is_empty() or not manifest.get("packs") is Dictionary:
		return {"ok":false,"error":"Manifest non riconosciuto."}
	return {"ok":true,"manifest":manifest}

# Voce del pacchetto per questa piattaforma, già controllata (nome, dimensione, SHA-256).
static func pack_entry(manifest: Dictionary, key: String = platform_key()) -> Dictionary:
	var entry = manifest.get("packs",{}).get(key)
	if not entry is Dictionary:
		return {}
	var name := str(entry.get("name",""))
	var size := int(entry.get("size",0))
	var sha := str(entry.get("sha256","")).to_lower()
	var pattern := RegEx.new()
	pattern.compile("^Sestria-v[0-9]{1,5}\\.[0-9]{1,5}(\\.[0-9]{1,5})?-[a-z]+-content\\.pck$")
	var hex := RegEx.new()
	hex.compile("^[0-9a-f]{64}$")
	if not pattern.search(name) or size<=0 or size>MAX_PACK or not hex.search(sha) or version_parts(str(entry.get("min_base",""))).is_empty():
		return {}
	return {"name":name,"size":size,"sha256":sha,"min_base":str(entry.min_base)}

# Stringa vuota se il pacchetto può girare su questa app, altrimenti il motivo (in italiano).
static func incompatibility(manifest: Dictionary, entry: Dictionary, base: String, engine: String = engine_label()) -> String:
	if str(manifest.get("engine",""))!=engine:
		return "Questa versione usa un motore grafico diverso (%s, tu hai %s)." % [str(manifest.get("engine","?")),engine]
	if newer(str(entry.get("min_base","")),base):
		return "Questa versione richiede componenti nativi che la tua app non ha (serve almeno la %s, hai la %s)." % [str(entry.min_base),base]
	return ""

# Cerca nelle risorse di una release l'asset del manifest e quello del pacchetto di questa piattaforma.
static func find_asset(info: Dictionary, name: String, repository_url: String, tag: String) -> Dictionary:
	if not info.get("assets") is Array:
		return {}
	for item in info.assets:
		if not item is Dictionary or str(item.get("name",""))!=name or item.get("state","")!="uploaded":
			continue
		var url := str(item.get("browser_download_url",""))
		if not url.begins_with(repository_url+"/download/"+tag+"/") or int(item.get("size",0))<=0:
			continue
		return {"name":name,"url":url,"size":int(item.size),"digest":str(item.get("digest","")).trim_prefix("sha256:").to_lower() if str(item.get("digest","")).begins_with("sha256:") else ""}
	return {}

static func manifest_name(version: String) -> String:
	return "Sestria-v"+version+"-content.json"

# ---------- file e stato ----------

static func state_path() -> String:
	return dir.path_join("state.json")

static func part_path(name: String) -> String:
	return dir.path_join(name+".part")

static func read_state() -> Dictionary:
	var file := FileAccess.open(state_path(),FileAccess.READ)
	if not file:
		return {}
	var state = JSON.parse_string(file.get_as_text())
	return state if state is Dictionary else {}

# Scrittura atomica: file temporaneo e rinomina.
static func write_state(state: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var temp := state_path()+".tmp"
	var file := FileAccess.open(temp,FileAccess.WRITE)
	if not file:
		return false
	file.store_string(JSON.stringify(state))
	file.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temp),ProjectSettings.globalize_path(state_path()))==OK

static func remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

# Elimina pacchetti e resti di scaricamenti che lo stato non referenzia (prima di montare, così su Windows nessun file è in uso).
static func clean_directory(keep: String) -> void:
	var folder := DirAccess.open(dir)
	if not folder:
		return
	for name in folder.get_files():
		if name!="state.json" and name!=keep:
			remove_file(dir.path_join(name))

static func installed_record() -> Dictionary:
	var record = read_state().get("installed")
	return record if record is Dictionary else {}

static func rejected_versions() -> Array:
	var list = read_state().get("rejected")
	return list if list is Array else []

# Versione scaricata ma non ancora in esecuzione ("" se non c'è).
static func staged_version() -> String:
	var record := installed_record()
	var version := str(record.get("version",""))
	if version.is_empty() or not FileAccess.file_exists(dir.path_join(str(record.get("file","")))):
		return ""
	return version if newer(version,running_version()) else ""

static func pack_engine(path: String) -> String:
	var file := FileAccess.open(path,FileAccess.READ)
	if not file or file.get_length()<32 or file.get_32()!=PCK_MAGIC:
		return ""
	file.get_32()
	var major := file.get_32()
	var minor := file.get_32()
	return "%d.%d" % [major,minor]

# Controlla un file scaricato e, se è valido, lo rende il pacchetto installato (in attesa di riavvio).
# Restituisce "" oppure il motivo del rifiuto; in caso di rifiuto il file viene cancellato.
static func install_downloaded(part: String, manifest: Dictionary, entry: Dictionary, github_digest: String = "") -> String:
	var version := str(manifest.version)
	var reason := ""
	var file := FileAccess.open(part,FileAccess.READ)
	if not file or file.get_length()!=int(entry.size):
		reason = "File incompleto: aggiornamento scartato."
	else:
		file.close()
		var sha := FileAccess.get_sha256(part)
		if sha!=str(entry.sha256) or (not github_digest.is_empty() and github_digest!=sha):
			reason = "Il file scaricato non corrisponde alla release. Aggiornamento scartato."
		elif pack_engine(part)!=str(manifest.get("engine","")):
			reason = "Il pacchetto non è stato creato per il motore di questa app."
		elif not newer(version,builtin_version()):
			reason = "Questa versione è già inclusa nell'app."
	if reason.is_empty():
		var final := dir.path_join("sestria-content-"+version+".pck")
		remove_file(final)
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(part),ProjectSettings.globalize_path(final))!=OK:
			reason = "Impossibile salvare l'aggiornamento. Controlla lo spazio libero."
		else:
			var state := read_state()
			state["installed"] = {"version":version,"file":final.get_file(),"sha256":str(entry.sha256),"size":int(entry.size),"min_base":str(entry.min_base),"engine":str(manifest.engine),"status":"pending","boots":0}
			if not write_state(state):
				remove_file(final)
				reason = "Impossibile registrare l'aggiornamento."
	if not reason.is_empty():
		remove_file(part)
	return reason

# ---------- avvio, conferma e rollback ----------

static func discard(version: String = "", reject := false) -> void:
	var state := read_state()
	var record := installed_record()
	if reject:
		var list := rejected_versions()
		var rejected_version := version if not version.is_empty() else str(record.get("version",""))
		if not rejected_version.is_empty() and not rejected_version in list:
			list.append(rejected_version)
		state["rejected"] = list
	state.erase("installed")
	write_state(state)
	if not str(record.get("file","")).is_empty():
		remove_file(dir.path_join(str(record.file)))

# Da chiamare per primo all'avvio, prima di caricare qualsiasi scena del gioco.
# Ritorna lo stato: "none" (nessun pacchetto), "applied" (montato), "discarded" (scartato, si usano i file integrati).
static func apply_at_boot(skip := false) -> String:
	if builtin.is_empty():
		builtin = running_version()
	boot_status = "none"
	boot_note = ""
	var record := installed_record()
	if record.is_empty():
		clean_directory("")
		return boot_status
	clean_directory(str(record.get("file","")))
	var path := dir.path_join(str(record.get("file","")))
	var problem := ""
	if skip:
		return boot_status
	if str(record.get("file","")).is_empty() or not FileAccess.file_exists(path):
		problem = "pacchetto assente"
	elif not newer(str(record.get("version","")),builtin):
		problem = "l'app contiene già questa versione"
	elif newer(str(record.get("min_base","")),base_version()):
		problem = "richiede componenti nativi più recenti"
	elif str(record.get("status",""))=="pending" and int(record.get("boots",0))>=1:
		problem = "il precedente avvio con questo pacchetto non è riuscito"
	else:
		var file := FileAccess.open(path,FileAccess.READ)
		if not file or file.get_length()!=int(record.get("size",-1)):
			problem = "dimensione errata"
		else:
			file.close()
			if FileAccess.get_sha256(path)!=str(record.get("sha256","")):
				problem = "pacchetto corrotto"
			elif pack_engine(path)!=engine_label():
				problem = "motore non compatibile"
	if problem.is_empty():
		if str(record.get("status",""))=="pending":
			var state := read_state()
			state.installed["boots"] = int(record.get("boots",0))+1
			write_state(state)
		if ProjectSettings.load_resource_pack(ProjectSettings.globalize_path(path),true):
			if running_version()==str(record.version):
				boot_status = "applied"
				boot_note = "Contenuti %s attivi." % str(record.version)
				return boot_status
			problem = "il pacchetto non dichiara la versione prevista"
			# I file sono già montati e non si smontano: serve un riavvio senza il pacchetto.
			discard(str(record.version),true)
			boot_status = "restart"
			boot_note = "Aggiornamento non valido: ripristino dei contenuti integrati."
			return boot_status
		problem = "impossibile aprire il pacchetto"
	discard(str(record.get("version","")),not problem.begins_with("l'app contiene"))
	boot_status = "discarded"
	boot_note = "Aggiornamento ignorato (%s): si usano i contenuti integrati." % problem
	push_warning("SESTRIA content: "+boot_note)
	return boot_status

# Dopo il montaggio: carica tutti gli script e le scene del gioco. Un errore di sintassi in un solo script rende
# il pacchetto inutilizzabile; ritorna il percorso del primo file che non si carica, "" se tutto è a posto.
static func validate_loaded() -> String:
	for folder: String in ["res://scripts","res://scenes"]:
		var listing := DirAccess.open(folder)
		if not listing:
			continue
		for file: String in listing.get_files():
			var name: String = file.trim_suffix(".remap")
			var path: String = folder.path_join(name)
			if name.ends_with(".gd"):
				var script = load(path)
				if not script is GDScript or not script.can_instantiate():
					return path
			elif name.ends_with(".tscn") and not load(path) is PackedScene:
				return path
	return ""

# Chiamata quando il gioco è partito davvero: il pacchetto non verrà più rimosso come "avvio fallito".
static func confirm_boot() -> void:
	var record := installed_record()
	if boot_status=="applied" and str(record.get("status",""))=="pending":
		var state := read_state()
		state.installed["status"] = "confirmed"
		state.installed["boots"] = 0
		write_state(state)

# Il gioco non si è caricato con il pacchetto montato: lo rifiuta; il chiamante deve riavviare l'app.
static func reject_after_failed_boot() -> void:
	discard("",true)
	boot_status = "restart"
	boot_note = "I nuovi contenuti non si caricano: ripristino dei contenuti integrati."

# Conferma l'avvio dopo che la scena ha disegnato due fotogrammi.
static func confirm_when_running(tree: SceneTree) -> void:
	await tree.process_frame
	await tree.process_frame
	if tree.current_scene!=null:
		confirm_boot()

# ---------- riavvio ----------

static func macos_bundle(executable: String) -> String:
	var index := executable.find(".app/")
	return executable.substr(0,index+4) if index>0 else ""

# Il plugin Java di Android (JNISingleton) espone i metodi tramite has_java_method, non has_method.
static func can_restart_natively(bridge: Object) -> bool:
	if bridge==null:
		return false
	return bridge.has_method("restartApp") or (bridge.has_method("has_java_method") and bridge.has_java_method("restartApp"))

# Riavvia l'app: desktop con un nuovo processo, Android tramite il plugin nativo. Ritorna false se non è possibile.
static func restart(tree: SceneTree) -> bool:
	if OS.get_name()=="Android":
		if Engine.has_singleton("SestriaUpdates"):
			var bridge := Engine.get_singleton("SestriaUpdates")
			if can_restart_natively(bridge):
				bridge.restartApp()
				return true
		return false
	var executable := OS.get_executable_path()
	var arguments := OS.get_cmdline_args()
	var pid := -1
	var bundle := macos_bundle(executable) if OS.get_name()=="macOS" else ""
	if not bundle.is_empty():
		var open_arguments := PackedStringArray(["-n",bundle])
		if not arguments.is_empty():
			open_arguments.append("--args")
			open_arguments.append_array(arguments)
		pid = OS.create_process("/usr/bin/open",open_arguments)
	else:
		pid = OS.create_process(executable,arguments)
	if pid<=0:
		return false
	tree.create_timer(.8).timeout.connect(tree.quit)
	return true

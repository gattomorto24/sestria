extends Node
# Salvataggio su Google Drive, uguale su Mac, Windows, Android e web: accesso con il «codice dispositivo» di Google
# (si apre una pagina, si digita un codice) e dati in un solo file creato da SESTRIA (scope drive.file: l'app vede
# soltanto i file che ha creato lei, non gli altri del tuo Drive; il flusso a codice non ammette drive.appdata). Il token resta in user://drive_token.json sul dispositivo.
const Bundle = preload("res://scripts/hub/drive_bundle.gd")
const CONFIG_PATH := "res://config/drive_auth.json"
const TOKEN_PATH := "user://drive_token.json"
const SCOPE := "openid email profile https://www.googleapis.com/auth/drive.file"
const FILE_NAME := "SESTRIA - salvataggio.json"
const MAX_BYTES := 2*1024*1024
const POLL_MS := 20000
signal changed
var game: Node
var config := {}
var endpoints := {"device":"https://oauth2.googleapis.com/device/code","token":"https://oauth2.googleapis.com/token",
	"userinfo":"https://openidconnect.googleapis.com/v1/userinfo","drive":"https://www.googleapis.com/drive/v3","upload":"https://www.googleapis.com/upload/drive/v3"}
var state := "off"               # off, code, signed_in
var message := ""
var user_code := ""
var verification_url := ""
var account := {}                # {name, email}
var refresh_token := ""
var access_token := ""
var access_until := 0
var busy := false
var last_sync := ""
var last_hash := ""
var device_code := ""
var interval := 5
var code_expires := 0
var next_poll := 0
var next_check := 0
var file_id := ""
var generation := 0
var test_mode := false

func available() -> bool:
	return str(config.get("client_id","")).ends_with(".apps.googleusercontent.com") and not str(config.get("client_secret","")).is_empty()

func setup(owner_game: Node) -> void:
	game = owner_game
	name = "DriveSync"
	process_mode = Node.PROCESS_MODE_ALWAYS
	if FileAccess.file_exists(CONFIG_PATH):
		var raw = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if raw is Dictionary:
			config = raw
	if FileAccess.file_exists(TOKEN_PATH):
		var stored = JSON.parse_string(FileAccess.get_file_as_string(TOKEN_PATH))
		if stored is Dictionary and str(stored.get("refresh_token","")).length() > 10:
			refresh_token = str(stored.refresh_token)
			account = {"name":str(stored.get("name","")).left(80),"email":str(stored.get("email","")).left(160)}
			state = "signed_in"
			next_check = Time.get_ticks_msec()+4000
	var override := OS.get_environment("SESTRIA_DRIVE_TEST")
	if not override.is_empty() and OS.is_debug_build():
		# Solo nelle build di sviluppo: un server di prova al posto di Google (tools/fake_google.py).
		for key in endpoints:
			endpoints[key] = override+"/"+key
		config = {"client_id":"test.apps.googleusercontent.com","client_secret":"test"}
		test_mode = true

# ---- Rete ----

func request(url: String, method: int, headers: PackedStringArray, body: Variant, timeout := 25.0) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = timeout
	http.use_threads = true
	# Il browser decomprime da solo le risposte di Google: se anche Godot provasse a farlo darebbe errore sul web.
	http.accept_gzip = false
	http.body_size_limit = MAX_BYTES
	add_child(http)
	var payload: PackedByteArray = body if body is PackedByteArray else str(body).to_utf8_buffer()
	var error := http.request_raw(url,headers,method,payload)
	if error != OK:
		http.queue_free()
		return {"ok":false,"code":0,"body":"","error":error}
	var result: Array = await http.request_completed
	http.queue_free()
	var text: String = (result[3] as PackedByteArray).get_string_from_utf8()
	return {"ok":result[0] == HTTPRequest.RESULT_SUCCESS,"code":int(result[1]),"body":text}

static func form(fields: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key in fields:
		parts.append(str(key).uri_encode()+"="+str(fields[key]).uri_encode())
	return "&".join(parts)

func parse(text: String) -> Dictionary:
	var data = JSON.parse_string(text)
	return data if data is Dictionary else {}

# ---- Accesso con codice dispositivo ----

func start_sign_in() -> void:
	if state == "code" or busy:
		return
	if not available():
		message = "Google Drive non è configurato in questa versione."
		changed.emit()
		return
	busy = true
	message = "Contatto Google…"
	changed.emit()
	var answer := await request(endpoints.device,HTTPClient.METHOD_POST,PackedStringArray(["Content-Type: application/x-www-form-urlencoded"]),form({"client_id":config.client_id,"scope":SCOPE}))
	busy = false
	var data := parse(answer.body)
	if not answer.ok or answer.code != 200 or not data.has("device_code") or not data.has("user_code"):
		message = "Non riesco a contattare Google. Controlla la connessione e riprova."
		changed.emit()
		return
	device_code = str(data.device_code)
	user_code = str(data.user_code)
	verification_url = str(data.get("verification_url",data.get("verification_uri","https://www.google.com/device")))
	interval = clampi(int(data.get("interval",5)),2,30)
	code_expires = Time.get_ticks_msec()+clampi(int(data.get("expires_in",600)),60,1800)*1000
	next_poll = Time.get_ticks_msec()+interval*1000
	state = "code"
	message = "Apri la pagina di Google e digita il codice."
	changed.emit()

func cancel() -> void:
	if state == "code":
		state = "off"
		user_code = ""
		message = ""
		changed.emit()

func poll_code() -> void:
	busy = true
	var answer := await request(endpoints.token,HTTPClient.METHOD_POST,PackedStringArray(["Content-Type: application/x-www-form-urlencoded"]),form({"client_id":config.client_id,"client_secret":config.client_secret,"device_code":device_code,"grant_type":"urn:ietf:params:oauth:grant-type:device_code"}))
	busy = false
	if state != "code":
		return
	var data := parse(answer.body)
	if OS.get_environment("SESTRIA_DRIVE_DEBUG") != "":
		print("DRIVE poll: ok=%s codice=%d risposta=%s" % [answer.ok,answer.code,str(data.keys())+" "+str(data.get("error",""))])
	if data.has("refresh_token") and data.has("access_token"):
		refresh_token = str(data.refresh_token)
		access_token = str(data.access_token)
		access_until = Time.get_ticks_msec()+maxi(60,int(data.get("expires_in",3600))-120)*1000
		await load_account()
		state = "signed_in"
		user_code = ""
		save_token()
		message = "Account collegato. Sincronizzo i dati…"
		changed.emit()
		sync(true)
		return
	var error := str(data.get("error",""))
	if error == "slow_down":
		interval = mini(interval+5,40)
	elif error in ["access_denied","expired_token"]:
		state = "off"
		user_code = ""
		message = "Accesso annullato." if error == "access_denied" else "Il codice è scaduto. Riprova."
		changed.emit()
		return
	next_poll = Time.get_ticks_msec()+interval*1000

func load_account() -> void:
	var answer := await request(endpoints.userinfo,HTTPClient.METHOD_GET,PackedStringArray(["Authorization: Bearer "+access_token]),"")
	var data := parse(answer.body)
	account = {"name":str(data.get("name",data.get("given_name","Giocatore"))).left(80),"email":str(data.get("email","")).left(160)}

func save_token() -> void:
	var file := FileAccess.open(TOKEN_PATH,FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"refresh_token":refresh_token,"name":account.get("name",""),"email":account.get("email","")}))
		file.close()

func sign_out() -> void:
	generation += 1
	if not refresh_token.is_empty() and not test_mode:
		# revoca il token presso Google (senza aspettare la risposta)
		request(endpoints.token.replace("/token","/revoke"),HTTPClient.METHOD_POST,PackedStringArray(["Content-Type: application/x-www-form-urlencoded"]),form({"token":refresh_token}),10.0)
	refresh_token = ""
	access_token = ""
	account = {}
	file_id = ""
	last_hash = ""
	state = "off"
	message = "Disconnesso. I dati restano su questo dispositivo e su Drive."
	if FileAccess.file_exists(TOKEN_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TOKEN_PATH))
	changed.emit()

# ---- Token di accesso ----

func ensure_token() -> bool:
	if Time.get_ticks_msec() < access_until and not access_token.is_empty():
		return true
	var answer := await request(endpoints.token,HTTPClient.METHOD_POST,PackedStringArray(["Content-Type: application/x-www-form-urlencoded"]),form({"client_id":config.client_id,"client_secret":config.client_secret,"refresh_token":refresh_token,"grant_type":"refresh_token"}))
	var data := parse(answer.body)
	if data.has("access_token"):
		access_token = str(data.access_token)
		access_until = Time.get_ticks_msec()+maxi(60,int(data.get("expires_in",3600))-120)*1000
		return true
	if str(data.get("error","")) == "invalid_grant":
		# accesso revocato dall'utente o scaduto: serve ricollegare l'account
		sign_out()
		message = "L'accesso a Google non è più valido. Collega di nuovo l'account."
		changed.emit()
	return false

func auth_header() -> PackedStringArray:
	return PackedStringArray(["Authorization: Bearer "+access_token])

# ---- Drive ----

func find_file() -> int:
	var url: String = endpoints.drive+"/files?spaces=drive&q="+("name = '%s' and trashed = false" % FILE_NAME).uri_encode()+"&fields="+"files(id,modifiedTime)".uri_encode()+"&pageSize=5"
	var answer := await request(url,HTTPClient.METHOD_GET,auth_header(),"")
	if not answer.ok or answer.code != 200:
		return FAILED
	var files: Array = parse(answer.body).get("files",[])
	file_id = str(files[0].id) if not files.is_empty() else ""
	return OK

func download() -> Dictionary:
	var answer := await request(endpoints.drive+"/files/"+file_id+"?alt=media",HTTPClient.METHOD_GET,auth_header(),"")
	if not answer.ok or answer.code != 200:
		return {"failed":true}
	return parse(answer.body)

func upload(bundle: Dictionary) -> bool:
	var text := JSON.stringify(bundle)
	if text.length() > MAX_BYTES:
		return false
	var boundary := "sestria"+str(Time.get_ticks_usec())
	var meta := {"name":FILE_NAME,"mimeType":"application/json"}
	var body := "--%s\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n%s\r\n--%s\r\nContent-Type: application/json\r\n\r\n%s\r\n--%s--" % [boundary,JSON.stringify(meta),boundary,text,boundary]
	var headers := auth_header()
	headers.append("Content-Type: multipart/related; boundary="+boundary)
	var method := HTTPClient.METHOD_POST if file_id.is_empty() else HTTPClient.METHOD_PATCH
	var url: String = endpoints.upload+"/files"+("" if file_id.is_empty() else "/"+file_id)+"?uploadType=multipart&fields=id"
	var answer := await request(url,method,headers,body)
	if not answer.ok or answer.code >= 300:
		return false
	var data := parse(answer.body)
	if file_id.is_empty() and data.has("id"):
		file_id = str(data.id)
	return true

# Sincronizza: scarica da Drive, unisce con i dati di questo dispositivo, applica e (se serve) ricarica. `force` anche in partita no.
func sync(force := false) -> void:
	if state != "signed_in" or busy or game == null:
		return
	if game.phase != "menu" and not force:
		return
	busy = true
	var ticket := generation
	message = "Sincronizzazione…"
	changed.emit()
	var done := await run_sync()
	if ticket != generation:
		return
	busy = false
	if done:
		last_sync = Time.get_datetime_string_from_system().replace("T"," ")
		message = "Sincronizzato."
		last_hash = hash_local()
	elif state == "signed_in":
		message = "Non riesco a sincronizzare: riprovo più tardi."
		next_check = Time.get_ticks_msec()+60000
	changed.emit()

func hash_local() -> String:
	var local := Bundle.collect(game)
	local.erase("saved")
	return str(JSON.stringify(local,"",true).hash())

func run_sync() -> bool:
	if not await ensure_token():
		return false
	if await find_file() != OK:
		return false
	var local := Bundle.collect(game)
	var remote := {}
	if not file_id.is_empty():
		remote = await download()
		if remote.get("failed",false):
			return false
	var merged := Bundle.merge(local,remote)
	if not Bundle.same(merged,local):
		Bundle.apply(game,merged)
	if remote.is_empty() or not Bundle.same(merged,remote):
		if not await upload(merged):
			return false
	return true

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if state == "code":
		if now > code_expires:
			state = "off"
			user_code = ""
			message = "Il codice è scaduto. Riprova."
			changed.emit()
		elif now >= next_poll and not busy:
			poll_code()
	elif state == "signed_in" and now >= next_check and not busy and game != null:
		next_check = now+POLL_MS
		if last_hash.is_empty() or hash_local() != last_hash:
			sync()

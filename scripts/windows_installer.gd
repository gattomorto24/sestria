extends RefCounted
# Launcher di SESTRIA per Windows: installazione guidata che trasforma la cartella con Sestria.exe in un'app vera,
# copiata in %LOCALAPPDATA%\Programs\Sestria, con collegamento sul desktop, voce nel menu Start e disinstallazione
# in «App installate». Non servono diritti di amministratore (tutto in HKCU e nel profilo dell'utente).
# I salvataggi restano in %APPDATA%\Godot\app_userdata\Sestria: installare, aggiornare o disinstallare non li tocca.
#
# Per i test, `runner`, `exe_override` e `env` sostituiscono i comandi di sistema, l'eseguibile e le variabili d'ambiente.
const APP_NAME := "SESTRIA"
const FOLDER := "Sestria"
const EXE := "Sestria.exe"
const UNINSTALL_KEY := "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Sestria"
const RECORD := "user://launcher.json"
const MARKER := "Sestria.install.json"
const UNINSTALL_FLAG := "--sestria-uninstall"
const UNINSTALL_RUN_FLAG := "--sestria-uninstall-run"
const SELFTEST_FLAG := "--sestria-installer-selftest"

static var runner := Callable()          # (programma: String, argomenti: Array) -> int
static var exe_override := ""            # percorso dell'eseguibile in esecuzione (test)
static var env := {}                     # variabili d'ambiente (test)
static var uninstall_key := UNINSTALL_KEY  # chiave del registro (collaudo: una chiave di prova)
static var record_path := RECORD         # dove si ricorda l'installazione (test: altrove)

# ---- Ambiente ----

static func variable(name: String) -> String:
	return str(env[name]) if env.has(name) else OS.get_environment(name)

static func to_windows(path: String) -> String:
	return path.replace("/","\\")

static func current_exe() -> String:
	return exe_override if not exe_override.is_empty() else OS.get_executable_path()

static func exe_dir() -> String:
	return current_exe().get_base_dir()

static func default_install_dir() -> String:
	var base := variable("LOCALAPPDATA")
	if base.is_empty():
		base = variable("USERPROFILE").path_join("AppData/Local")
	return base.path_join("Programs").path_join(FOLDER)

static func start_menu_dir() -> String:
	var base := variable("APPDATA")
	if base.is_empty():
		base = variable("USERPROFILE").path_join("AppData/Roaming")
	return base.path_join("Microsoft/Windows/Start Menu/Programs")

static func desktop_dir() -> String:
	var overridden := variable("SESTRIA_DESKTOP")
	if not overridden.is_empty():
		return overridden
	var system := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	return system if not system.is_empty() else variable("USERPROFILE").path_join("Desktop")

static func shortcut_paths(options: Dictionary) -> Array:
	var list: Array = []
	if options.get("desktop",true):
		list.append(desktop_dir().path_join(APP_NAME+".lnk"))
	if options.get("start_menu",true):
		list.append(start_menu_dir().path_join(APP_NAME+".lnk"))
	return list

static func same_path(a: String, b: String) -> bool:
	return to_windows(a).to_lower().trim_suffix("\\") == to_windows(b).to_lower().trim_suffix("\\")

static func record() -> Dictionary:
	if not FileAccess.file_exists(record_path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(record_path))
	return data if data is Dictionary else {}

# L'app è installata e questo è l'eseguibile installato.
static func running_installed() -> bool:
	var info := record()
	return not info.is_empty() and info.get("dir","") is String and not str(info.dir).is_empty() and same_path(exe_dir(),str(info.dir))

# Esiste un'installazione (anche se si sta usando la copia portatile).
static func installed_dir() -> String:
	var info := record()
	var dir := str(info.get("dir",""))
	return dir if not dir.is_empty() and FileAccess.file_exists(dir.path_join(EXE)) else ""

static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version","4.7"))

# ---- Esecuzione dei comandi ----

static func run(program: String, arguments: Array) -> int:
	if runner.is_valid():
		return int(runner.call(program,arguments))
	var output := []
	return OS.execute(program,arguments,output,true)

static func ps_quote(text: String) -> String:
	return "'"+text.replace("'","''")+"'"

# Script PowerShell che crea i collegamenti .lnk (WScript.Shell). Si scrive in UTF-8 con BOM.
static func shortcut_script(links: Array, target: String, workdir: String) -> String:
	var lines := PackedStringArray(["$ErrorActionPreference = 'Stop'","$shell = New-Object -ComObject WScript.Shell"])
	for link in links:
		var path := to_windows(link)
		lines.append("New-Item -ItemType Directory -Force -Path %s | Out-Null" % ps_quote(path.get_base_dir()))
		lines.append("$s = $shell.CreateShortcut(%s)" % ps_quote(path))
		lines.append("$s.TargetPath = %s" % ps_quote(to_windows(target)))
		lines.append("$s.WorkingDirectory = %s" % ps_quote(to_windows(workdir)))
		lines.append("$s.IconLocation = %s" % ps_quote(to_windows(target)+",0"))
		lines.append("$s.Description = 'SESTRIA'")
		lines.append("$s.Save()")
	return "\r\n".join(lines)+"\r\n"

static func write_script(text: String) -> String:
	var folder := variable("TEMP")
	if folder.is_empty():
		folder = OS.get_cache_dir()
	var path := folder.path_join("sestria_shortcuts.ps1")
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null:
		return ""
	file.store_buffer(PackedByteArray([0xEF,0xBB,0xBF]))
	file.store_string(text)
	file.close()
	return path

# Collegamenti: .lnk con PowerShell; se non riesce, file .url che puntano allo stesso eseguibile.
static func create_shortcuts(links: Array, target: String, workdir: String) -> String:
	if links.is_empty():
		return ""
	var script := write_script(shortcut_script(links,target,workdir))
	var code := -1
	if not script.is_empty():
		code = run("powershell.exe",["-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",to_windows(script)])
		DirAccess.remove_absolute(script)
	if code == 0:
		return ""
	for link in links:
		var url_path: String = str(link).trim_suffix(".lnk")+".url"
		DirAccess.make_dir_recursive_absolute(url_path.get_base_dir())
		var file := FileAccess.open(url_path,FileAccess.WRITE)
		if file == null:
			return "Non riesco a creare il collegamento in "+url_path.get_base_dir()
		file.store_string("[InternetShortcut]\r\nURL=file:///%s\r\nIconFile=%s\r\nIconIndex=0\r\n" % [to_windows(target).replace("\\","/"),to_windows(target)])
		file.close()
	return ""

static func registry_commands(dir: String, size_kb: int) -> Array:
	var exe := to_windows(dir.path_join(EXE))
	var entries := [
		["DisplayName","REG_SZ",APP_NAME],["DisplayVersion","REG_SZ",version()],["Publisher","REG_SZ","SESTRIA"],
		["InstallLocation","REG_SZ",to_windows(dir)],["DisplayIcon","REG_SZ",exe],
		["UninstallString","REG_SZ","\"%s\" -- %s" % [exe,UNINSTALL_FLAG]],
		["NoModify","REG_DWORD","1"],["NoRepair","REG_DWORD","1"],["EstimatedSize","REG_DWORD",str(size_kb)]]
	return entries.map(func(e):return ["add",uninstall_key,"/v",e[0],"/t",e[1],"/d",e[2],"/f"])

# ---- Installazione ----

# File da copiare: tutto ciò che sta accanto all'eseguibile (exe, librerie .dll, LEGGIMI).
static func files_to_copy() -> Array:
	var names: Array = []
	var dir := DirAccess.open(exe_dir())
	if dir == null:
		return names
	for name in dir.get_files():
		if name == MARKER or name.begins_with("."):
			continue
		names.append(name)
	return names

static func total_size(names: Array) -> int:
	var total := 0
	for name in names:
		var file := FileAccess.open(exe_dir().path_join(name),FileAccess.READ)
		if file:
			total += file.get_length()
	return total

# Controlli prima di installare. Restituisce un messaggio d'errore o "".
static func check(dir: String) -> String:
	if dir.strip_edges().is_empty():
		return "Scegli una cartella di installazione."
	if running_installed():
		return "SESTRIA è già installata e in esecuzione dalla cartella di installazione."
	if same_path(dir,exe_dir()):
		return "La cartella di installazione non può essere quella da cui stai avviando il gioco."
	if not FileAccess.file_exists(current_exe()):
		return "Non trovo il file del gioco da copiare."
	return ""

# Esegue l'installazione. `progress` riceve (percentuale 0..1, testo). Restituisce {"ok":bool,"message":String,"exe":String}.
static func install(dir: String, options: Dictionary, progress := Callable()) -> Dictionary:
	var problem := check(dir)
	if not problem.is_empty():
		return {"ok":false,"message":problem,"exe":""}
	var names := files_to_copy()
	if names.is_empty() or not names.has(current_exe().get_file()):
		return {"ok":false,"message":"Non trovo il file del gioco da copiare.","exe":""}
	var tell := func(part: float, text: String):
		if progress.is_valid():
			progress.call(part,text)
	tell.call(.05,"Creo la cartella…")
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return {"ok":false,"message":"Non riesco a creare la cartella "+dir,"exe":""}
	var count := 0
	for name in names:
		tell.call(.1+.6*count/float(names.size()),"Copio "+name+"…")
		var target := dir.path_join(name)
		var done := DirAccess.copy_absolute(exe_dir().path_join(name),target)
		if done != OK:
			return {"ok":false,"message":"Copia di %s non riuscita (errore %d)." % [name,done],"exe":""}
		count += 1
	var exe := dir.path_join(current_exe().get_file())
	if current_exe().get_file() != EXE and not FileAccess.file_exists(dir.path_join(EXE)):
		DirAccess.copy_absolute(exe,dir.path_join(EXE))
		exe = dir.path_join(EXE)
	var marker := FileAccess.open(dir.path_join(MARKER),FileAccess.WRITE)
	if marker:
		marker.store_string(JSON.stringify({"version":version(),"installed":Time.get_datetime_string_from_system()}))
		marker.close()
	tell.call(.75,"Creo i collegamenti…")
	var links := shortcut_paths(options)
	var shortcut_problem := create_shortcuts(links,exe,dir)
	tell.call(.9,"Registro l'app in Windows…")
	var kb := int(total_size(names)/1024)
	var registry_failed := false
	for arguments in registry_commands(dir,kb):
		if run("reg.exe",arguments) != 0:
			registry_failed = true
	var info := FileAccess.open(record_path,FileAccess.WRITE)
	if info:
		info.store_string(JSON.stringify({"dir":dir,"version":version(),"links":links}))
		info.close()
	tell.call(1.0,"Fatto.")
	var message := "SESTRIA è installata in "+to_windows(dir)+"."
	if not shortcut_problem.is_empty():
		message += " "+shortcut_problem
	if registry_failed:
		message += " La voce in «App installate» non è stata registrata: puoi comunque avviare il gioco dal collegamento."
	return {"ok":true,"message":message,"exe":exe}

# ---- Disinstallazione ----

# Dalla copia installata: si copia in una cartella temporanea e si rilancia da lì, perché non può cancellare se stessa.
static func start_uninstall() -> bool:
	var dir := exe_dir()
	var temp := variable("TEMP")
	if temp.is_empty():
		temp = OS.get_cache_dir()
	var stage := temp.path_join("SestriaUninstall")
	DirAccess.make_dir_recursive_absolute(stage)
	for name in files_to_copy():
		DirAccess.copy_absolute(dir.path_join(name),stage.path_join(name))
	var helper := stage.path_join(current_exe().get_file())
	if not FileAccess.file_exists(helper):
		return false
	return OS.create_process(helper,["--headless","--",UNINSTALL_RUN_FLAG,dir]) > 0

# Esegue la rimozione dalla copia temporanea: cartella di installazione, collegamenti e voce del registro.
static func finish_uninstall(dir: String) -> Dictionary:
	var info := record()
	var links: Array = info.get("links",[])
	for link in shortcut_paths({"desktop":true,"start_menu":true}):
		if not links.has(link):
			links.append(link)
	var removed := remove_tree(dir)
	for link in links:
		for path in [str(link),str(link).trim_suffix(".lnk")+".url"]:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
	run("reg.exe",["delete",uninstall_key,"/f"])
	if FileAccess.file_exists(record_path):
		DirAccess.remove_absolute(record_path)
	return {"ok":removed,"dir":dir}

static func remove_tree(path: String) -> bool:
	var dir := DirAccess.open(path)
	if dir == null:
		return true
	for name in dir.get_files():
		DirAccess.remove_absolute(path.path_join(name))
	for name in dir.get_directories():
		remove_tree(path.path_join(name))
	return DirAccess.remove_absolute(path) == OK

# Collaudo sul computer reale: installa e disinstalla in una cartella temporanea, con collegamenti e chiave di registro
# di prova, e scrive l'esito in %TEMP%\sestria-selftest.txt. Uso: Sestria.exe -- --sestria-installer-selftest
static func selftest() -> Dictionary:
	var temp := variable("TEMP")
	if temp.is_empty():
		temp = OS.get_cache_dir()
	var base := temp.path_join("SestriaSelfTest")
	remove_tree(base)
	var saved := [env,record_path,uninstall_key]
	env = {"LOCALAPPDATA":base+"/Local","APPDATA":base+"/Roaming","USERPROFILE":base+"/Home","TEMP":temp,"SESTRIA_DESKTOP":base+"/Desktop"}
	record_path = base+"/launcher.json"
	uninstall_key = "HKCU\\Software\\SestriaSelfTest"
	var report := PackedStringArray()
	var counter := {"failed":0}
	var note := func(ok: bool, text: String):
		report.append(("OK    " if ok else "ERRORE ")+text)
		if not ok:
			counter.failed += 1
	var target := default_install_dir()
	var result := install(target,{"desktop":true,"start_menu":true})
	note.call(result.ok,"Installazione: "+str(result.message))
	note.call(FileAccess.file_exists(target.path_join(EXE)),"Eseguibile copiato in "+to_windows(target))
	for link in shortcut_paths({"desktop":true,"start_menu":true}):
		note.call(FileAccess.file_exists(link) or FileAccess.file_exists(str(link).trim_suffix(".lnk")+".url"),"Collegamento creato: "+to_windows(link))
	note.call(run("reg.exe",["query",uninstall_key,"/v","DisplayName"]) == 0,"Voce di registro scritta")
	note.call(running_installed() == false and installed_dir() == target,"Installazione ricordata")
	var removal := finish_uninstall(target)
	note.call(removal.ok and not DirAccess.dir_exists_absolute(target),"Cartella rimossa")
	for link in shortcut_paths({"desktop":true,"start_menu":true}):
		note.call(not FileAccess.file_exists(link),"Collegamento rimosso: "+to_windows(link))
	note.call(run("reg.exe",["query",uninstall_key,"/v","DisplayName"]) != 0,"Voce di registro eliminata")
	remove_tree(base)
	env = saved[0]
	record_path = saved[1]
	uninstall_key = saved[2]
	var failed: int = counter.failed
	var text := "COLLAUDO LAUNCHER SESTRIA %s · %d errori\r\n%s\r\n" % [version(),failed,"\r\n".join(report)]
	var path := temp.path_join("sestria-selftest.txt")
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file:
		file.store_string(text)
		file.close()
	print(text)
	return {"failed":failed,"path":path,"report":text}

# Gestisce le opzioni da riga di comando; restituisce true se il gioco deve fermarsi. Si chiama all'avvio di game.gd.
static func handle_command_line(tree: SceneTree) -> bool:
	var arguments := OS.get_cmdline_user_args()
	if UNINSTALL_RUN_FLAG in arguments:
		var index := arguments.find(UNINSTALL_RUN_FLAG)
		var dir: String = arguments[index+1] if index+1 < arguments.size() else ""
		if not dir.is_empty():
			await tree.create_timer(2.0).timeout
			var result := finish_uninstall(dir)
			for attempt in 5:
				if result.ok:
					break
				await tree.create_timer(1.5).timeout
				result = finish_uninstall(dir)
		tree.quit()
		return true
	if SELFTEST_FLAG in arguments:
		selftest()
		tree.quit()
		return true
	if UNINSTALL_FLAG in arguments:
		start_uninstall()
		tree.quit()
		return true
	return false

# ---- Interfaccia (nuovo stile rustico: scripts/hub) ----

const Kit = preload("res://scripts/hub/kit.gd")

# Sezione «Launcher» della scheda Sistema. `hub` è il menu principale (scripts/hub/hub.gd).
static func build_section(hub: Control, parent: Node) -> void:
	Kit.title(parent,"Launcher per Windows",22)
	if running_installed():
		Kit.paragraph(parent,"SESTRIA è installata su questo computer: la trovi sul desktop, nel menu Start e in «App installate». I tuoi progressi sono al sicuro anche se la disinstalli.",0.0,16,Kit.MUTED)
		Kit.button(parent,"Disinstalla SESTRIA",func():show_uninstall(hub),"danger",260)
	elif not installed_dir().is_empty():
		Kit.paragraph(parent,"SESTRIA è già installata in %s. Puoi aggiornarla con questa versione." % to_windows(installed_dir()),0.0,16,Kit.MUTED)
		Kit.button(parent,"AGGIORNA L'INSTALLAZIONE",func():show_wizard(hub,{"dir":installed_dir()}),"primary",300)
	else:
		Kit.paragraph(parent,"Trasforma questa cartella in un'app vera: SESTRIA si installa sul tuo computer con il collegamento sul desktop e nel menu Start, e si disinstalla da «App installate». Non servono diritti di amministratore.",0.0,16,Kit.MUTED)
		Kit.button(parent,"INSTALLA IL LAUNCHER",func():show_wizard(hub,{}),"primary",300)

static func show_wizard(hub: Control, state: Dictionary, step := 0) -> void:
	state.merge({"dir":default_install_dir(),"desktop":true,"start_menu":true,"launch":true},false)
	var body: VBoxContainer = hub.modal("Installa SESTRIA",640)
	match step:
		0:
			Kit.label(body,"PASSO 1 DI 3 · BENVENUTO",14,Kit.EMBER_LIGHT,false,700)
			Kit.paragraph(body,"Questa procedura installa SESTRIA sul computer, così diventa un gioco con il suo launcher: icona sul desktop, voce nel menu Start, disinstallazione da «App installate». I salvataggi e le impostazioni restano gli stessi.",0.0,16,Kit.MUTED)
			var line := Kit.row(body,10)
			Kit.button(line,"AVANTI",func():show_wizard(hub,state,1),"primary")
			Kit.button(line,"Annulla",hub.close_modal,"ghost")
		1:
			Kit.label(body,"PASSO 2 DI 3 · SCELTE",14,Kit.EMBER_LIGHT,false,700)
			Kit.label(body,"Cartella: "+to_windows(state.dir),16,Kit.TEXT)
			if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
				Kit.button(body,"Cambia cartella…",func():
					DisplayServer.file_dialog_show("Cartella di installazione",state.dir,"",false,DisplayServer.FILE_DIALOG_MODE_OPEN_DIR,PackedStringArray(),func(ok:bool,paths:PackedStringArray,_filter:int):
						if ok and not paths.is_empty():
							state.dir = paths[0].path_join(FOLDER) if not paths[0].get_file().to_lower() == FOLDER.to_lower() else paths[0]
						show_wizard(hub,state,1)),"secondary")
			for entry in [["desktop","Collegamento sul desktop"],["start_menu","Voce nel menu Start"],["launch","Avvia SESTRIA al termine"]]:
				var choice := Kit.setting_row(body,str(entry[1]))
				Kit.toggle(choice,state[entry[0]],func(v):
					state[entry[0]] = v
					show_wizard(hub,state,1))
			var problem := check(state.dir)
			if not problem.is_empty():
				Kit.paragraph(body,problem,0.0,15,Kit.EMBER_LIGHT)
			var line := Kit.row(body,10)
			var go := Kit.button(line,"INSTALLA",func():show_wizard(hub,state,2),"primary")
			go.disabled = not problem.is_empty()
			Kit.button(line,"Indietro",func():show_wizard(hub,state,0),"ghost")
		2:
			Kit.label(body,"PASSO 3 DI 3 · INSTALLAZIONE",14,Kit.EMBER_LIGHT,false,700)
			var status := Kit.label(body,"Preparazione…",17,Kit.TEXT)
			var bar := Kit.meter(body,0.0,1.0,18)
			run_install.call_deferred(hub,state,status,bar)

static func run_install(hub: Control, state: Dictionary, status: Label, bar: Control) -> void:
	var tree: SceneTree = hub.get_tree()
	await tree.process_frame
	var report := func(part: float, text: String):
		if is_instance_valid(bar):
			bar.set_value(part,1.0)
			status.text = text
	var result := install(state.dir,state,report)
	await tree.process_frame
	var body: VBoxContainer = hub.modal("Installazione completata" if result.ok else "Installazione non riuscita",640)
	Kit.paragraph(body,str(result.message),0.0,16,Kit.MUTED)
	var line := Kit.row(body,10)
	if result.ok:
		Kit.sfx("seal")
		if state.launch:
			Kit.button(line,"AVVIA SESTRIA",func():launch_installed(hub,result.exe),"primary")
		Kit.button(line,"Chiudi",func():hub.navigate("options",{"tab":"system"}),"secondary")
	else:
		Kit.sfx("error")
		Kit.button(line,"Riprova",func():show_wizard(hub,state,1),"primary")
		Kit.button(line,"Chiudi",hub.close_modal,"ghost")

static func launch_installed(hub: Control, exe: String) -> void:
	OS.create_process(exe,[])
	hub.get_tree().quit()

static func show_uninstall(hub: Control) -> void:
	var body: VBoxContainer = hub.modal("Disinstalla SESTRIA",600)
	Kit.paragraph(body,"Verranno rimossi il gioco installato, il collegamento sul desktop, la voce nel menu Start e la voce in «App installate». I salvataggi, le statistiche e le impostazioni restano nel tuo profilo. Il gioco si chiuderà.",0.0,16,Kit.MUTED)
	var line := Kit.row(body,10)
	Kit.button(line,"DISINSTALLA",func():
		if start_uninstall():
			hub.get_tree().quit()
		else:
			hub.close_modal(),"danger")
	Kit.button(line,"Annulla",hub.close_modal,"ghost")

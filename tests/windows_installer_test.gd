extends SceneTree
# Collaudo del launcher Windows senza Windows: i comandi di sistema (PowerShell, reg.exe) sono registrati da un finto
# `runner`, i percorsi puntano a una cartella temporanea. Verifica copia, collegamenti, registro, rifiuti e disinstallazione.
const Installer = preload("res://scripts/windows_installer.gd")
var failures := 0
var calls: Array = []
var scripts: Array = []
var powershell_exit := 0
var registry := {}

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func write(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()

func fake_runner(program: String, arguments: Array) -> int:
	calls.append([program,arguments])
	if program == "powershell.exe":
		var path: String = str(arguments[arguments.size()-1]).replace("\\","/")
		if FileAccess.file_exists(path):
			var bytes := FileAccess.get_file_as_bytes(path)
			scripts.append(bytes)
			if powershell_exit == 0:
				# come farebbe WScript.Shell: crea i file .lnk indicati
				var expression := RegEx.new()
				expression.compile("CreateShortcut\\('([^']*)'\\)")
				for found in expression.search_all(bytes.get_string_from_utf8()):
					write(found.get_string(1).replace("\\","/"),"lnk".to_utf8_buffer())
		return powershell_exit
	if program == "reg.exe":
		match arguments[0]:
			"add": registry[arguments[1]] = true
			"delete": registry.erase(arguments[1])
			"query": return 0 if registry.has(arguments[1]) else 1
	return 0

func registry_values() -> Dictionary:
	var values := {}
	for call in calls:
		if call[0] == "reg.exe" and call[1][0] == "add":
			values[call[1][3]] = call[1][7]
	return values

func run() -> void:
	var base := ProjectSettings.globalize_path("res://build/installer-test")
	Installer.remove_tree(base)
	var portable := base+"/Download/Sestria-v4.7-Windows-x64"
	write(portable+"/Sestria.exe",PackedByteArray([77,90,1,2,3,4]))
	write(portable+"/libwebrtc_native.windows.template_release.x86_64.dll",PackedByteArray([1,2,3]))
	write(portable+"/LEGGIMI.txt","Leggimi".to_utf8_buffer())
	Installer.exe_override = portable+"/Sestria.exe"
	Installer.env = {"LOCALAPPDATA":base+"/Local","APPDATA":base+"/Roaming","USERPROFILE":base+"/Home","TEMP":base+"/Temp","SESTRIA_DESKTOP":base+"/Desktop"}
	DirAccess.make_dir_recursive_absolute(base+"/Temp")
	Installer.record_path = base+"/launcher.json"
	Installer.runner = fake_runner
	var target := Installer.default_install_dir()
	check(target.ends_with("Local/Programs/Sestria"),"Cartella predefinita in %LOCALAPPDATA%\\Programs\\Sestria: "+target)
	check(Installer.start_menu_dir().ends_with("Roaming/Microsoft/Windows/Start Menu/Programs"),"Cartella del menu Start")
	check(not Installer.running_installed() and Installer.installed_dir() == "","Nessuna installazione all'inizio")
	check(Installer.check("") != "" and Installer.check(portable) != "","Cartella vuota o uguale alla sorgente rifiutata")
	check(Installer.same_path("C:\\Foo\\Bar\\","c:/foo/bar"),"Confronto dei percorsi senza maiuscole e separatori")
	# installazione
	var steps: Array = []
	var result: Dictionary = Installer.install(target,{"desktop":true,"start_menu":true},func(p,t):steps.append(p))
	check(result.ok,"Installazione riuscita: "+str(result.message))
	check(FileAccess.file_exists(target+"/Sestria.exe") and FileAccess.file_exists(target+"/libwebrtc_native.windows.template_release.x86_64.dll") and FileAccess.file_exists(target+"/LEGGIMI.txt"),"Copiati exe, DLL e LEGGIMI")
	check(FileAccess.get_file_as_bytes(target+"/Sestria.exe") == PackedByteArray([77,90,1,2,3,4]),"L'eseguibile copiato è identico")
	check(FileAccess.file_exists(target+"/"+Installer.MARKER),"Segnalino di installazione scritto")
	check(steps.size() >= 5 and steps[steps.size()-1] == 1.0,"Avanzamento fino al 100%")
	check(Installer.installed_dir() == target,"Installazione ricordata")
	# PowerShell e registro
	var ps: Array = calls.filter(func(c):return c[0] == "powershell.exe")
	check(ps.size() == 1 and "-ExecutionPolicy" in ps[0][1] and "-File" in ps[0][1],"Un solo PowerShell, con -File")
	check(scripts.size() == 1 and scripts[0].slice(0,3) == PackedByteArray([0xEF,0xBB,0xBF]),"Script PowerShell in UTF-8 con BOM")
	var script_text: String = scripts[0].get_string_from_utf8()
	check("CreateShortcut('"+(base+"/Desktop/SESTRIA.lnk").replace("/","\\")+"')" in script_text,"Collegamento sul desktop")
	check("CreateShortcut('"+(base+"/Roaming/Microsoft/Windows/Start Menu/Programs/SESTRIA.lnk").replace("/","\\")+"')" in script_text,"Collegamento nel menu Start")
	check("$s.TargetPath = '"+(target+"/Sestria.exe").replace("/","\\")+"'" in script_text and "IconLocation" in script_text,"Il collegamento punta all'eseguibile installato")
	var values := registry_values()
	check(values.get("DisplayName") == "SESTRIA" and values.get("InstallLocation") == target.replace("/","\\"),"Registro: nome e cartella")
	check(values.get("UninstallString") == "\""+(target+"/Sestria.exe").replace("/","\\")+"\" -- --sestria-uninstall","Registro: comando di disinstallazione")
	check(values.has("DisplayVersion") and values.has("EstimatedSize") and values.has("NoModify"),"Registro: versione, dimensione, nessuna modifica")
	for call in calls:
		if call[0] == "reg.exe":
			check(call[1][1] == Installer.UNINSTALL_KEY and call[1][call[1].size()-1] == "/f","Solo HKCU, senza richiesta di conferma")
	# già installata: l'eseguibile installato non può reinstallarsi
	Installer.exe_override = target+"/Sestria.exe"
	check(Installer.running_installed() and Installer.check(target) != "","Dall'app installata non si reinstalla")
	Installer.exe_override = portable+"/Sestria.exe"
	# aggiornamento sopra un'installazione esistente
	write(portable+"/Sestria.exe",PackedByteArray([77,90,9,9,9]))
	calls.clear()
	scripts.clear()
	var again: Dictionary = Installer.install(target,{"desktop":false,"start_menu":true})
	check(again.ok and FileAccess.get_file_as_bytes(target+"/Sestria.exe") == PackedByteArray([77,90,9,9,9]),"Aggiornamento dell'installazione esistente")
	check(not ("Desktop" in scripts[0].get_string_from_utf8()),"Senza collegamento sul desktop se non richiesto")
	# PowerShell non riesce: ripiego sui file .url
	for path in [base+"/Roaming/Microsoft/Windows/Start Menu/Programs/SESTRIA.lnk"]:
		DirAccess.remove_absolute(path)
	powershell_exit = 1
	var fallback: Dictionary = Installer.install(target,{"desktop":true,"start_menu":false})
	check(fallback.ok and FileAccess.file_exists(base+"/Desktop/SESTRIA.url"),"Ripiego sui collegamenti .url se PowerShell fallisce")
	var url_text := FileAccess.get_file_as_string(base+"/Desktop/SESTRIA.url")
	check("[InternetShortcut]" in url_text and "Sestria.exe" in url_text,"Contenuto del collegamento .url")
	powershell_exit = 0
	# nomi con apostrofi o spazi non rompono lo script
	check(Installer.ps_quote("C:\\O'Brien\\x") == "'C:\\O''Brien\\x'","Apici raddoppiati in PowerShell")
	# disinstallazione
	write(base+"/Desktop/SESTRIA.lnk","x".to_utf8_buffer())
	calls.clear()
	var removed: Dictionary = Installer.finish_uninstall(target)
	check(removed.ok and not DirAccess.dir_exists_absolute(target),"Cartella di installazione rimossa")
	check(not FileAccess.file_exists(base+"/Desktop/SESTRIA.lnk") and not FileAccess.file_exists(base+"/Desktop/SESTRIA.url"),"Collegamenti rimossi")
	check(calls.size() == 1 and calls[0][0] == "reg.exe" and calls[0][1][0] == "delete" and calls[0][1][1] == Installer.UNINSTALL_KEY,"Voce di registro eliminata")
	check(Installer.installed_dir() == "" and not FileAccess.file_exists(base+"/launcher.json"),"Installazione dimenticata")
	check(FileAccess.file_exists(portable+"/Sestria.exe"),"La copia portatile resta intatta")
	# collaudo integrato (quello che si lancia su Windows): con il finto runner non deve dare errori
	Installer.exe_override = portable+"/Sestria.exe"
	Installer.env = {"TEMP":base+"/Temp"}
	var selftest: Dictionary = Installer.selftest()
	check(selftest.failed == 0 and FileAccess.file_exists(base+"/Temp/sestria-selftest.txt"),"Collaudo integrato: "+str(selftest.report))
	Installer.remove_tree(base)
	print("LAUNCHER WINDOWS | installazione, collegamenti, registro, ripiego e disinstallazione simulati | errori %d" % failures)
	quit(1 if failures > 0 else 0)

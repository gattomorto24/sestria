extends SceneTree
# Collaudo del nuovo menu (scheda Campagna, Multigiocatore, Amici, Progressi, Opzioni) e del tavolo.
# Con una finestra reale salva schermate in build/desktop; in modalità headless controlla solo la struttura.
const Store = preload("res://scripts/hub/campaign_store.gd")
var game: Node3D
var failures := 0
var capture := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func settle() -> void:
	for i in 10:
		await process_frame

func snapshot(name: String) -> void:
	await settle()
	if capture:
		await create_timer(.45).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/desktop/"+name+".png")

func inside(control: Control, message: String) -> void:
	var area := control.get_global_rect()
	var view := root.get_visible_rect()
	check(area.position.x >= -1 and area.position.y >= -1 and area.end.x <= view.size.x+1 and area.end.y <= view.size.y+1,message+": "+str(area)+" in "+str(view.size))

func buttons(node: Node, text: String) -> Array:
	return node.find_children("*","Button",true,false).filter(func(b):return b.text == text)

func run() -> void:
	capture = DisplayServer.get_name() != "headless"
	if capture:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/desktop"))
	game = load("res://scenes/table.tscn").instantiate()
	root.add_child(game)
	game.integration = true
	game.music.stop()
	if game.lan and game.lan.online:
		game.lan.online.configure([])
	await settle()
	var hub: Control = game.ui.hub
	check(hub != null and hub.visible and not game.portrait,"Menu aperto, interfaccia orizzontale")
	for name in ["Campagna","Multigiocatore","Amici","Progressi","Opzioni"]:
		check(not buttons(hub.stage,name).is_empty() or not buttons(hub.stage,name+" •").is_empty(),"Scheda "+name)
	check(game.profile != null and game.campaigns != null,"Profilo e campagne caricati")
	await snapshot("hub-campaign")
	# Campagna: nuova campagna, dieci impostazioni, partita al volo
	hub.navigate("campaign",{"view":"new","draft":{"name":"Prova","difficulty":1,"settings":Store.default_settings()}})
	await snapshot("hub-new")
	check(not buttons(hub.stage,"CREA E INIZIA").is_empty(),"Pulsante di creazione della campagna")
	check(hub.stage.find_children("*","Button",true,false).filter(func(b):return b.text in ["3 lanci","Auto","Moneta","Aggressivo"]).size() >= 4,"Le dieci impostazioni sono presenti")
	hub.navigate("campaign",{"selected":"quick"})
	check(not buttons(hub.stage,"GIOCA ORA").is_empty(),"Partita al volo")
	await snapshot("hub-quick")
	# Multigiocatore
	for sub in ["device","lan","online"]:
		hub.navigate("multiplayer",{"sub":sub})
		await snapshot("hub-multi-"+sub)
	hub.navigate("multiplayer",{"sub":"device"})
	check(not buttons(hub.stage,"INIZIA LA PARTITA").is_empty(),"Passa e gioca")
	hub.navigate("multiplayer",{"sub":"lan"})
	game.lan.rooms["192.168.1.9"] = {"ip":"192.168.1.9","name":"Prova","code":"123456","seen":Time.get_ticks_msec()}
	hub.navigate("multiplayer",{"sub":"lan"})
	await settle()
	check(hub.stage.find_children("*","Label",true,false).any(func(l):return l.text == "Prova"),"Stanza LAN vicina mostrata")
	game.lan.rooms.clear()
	hub.navigate("multiplayer",{"sub":"device"})
	check(game.lan.role == "","Lasciando la scheda non resta nessuna stanza")
	# Amici, Progressi
	hub.navigate("friends",{})
	await snapshot("hub-friends")
	hub.navigate("progress",{})
	await snapshot("hub-progress")
	# Opzioni
	OS.set_environment("SESTRIA_FAKE_WINDOWS","1")
	for tab in ["game","screen","graphics","audio","controls","system"]:
		hub.navigate("options",{"tab":tab})
		await snapshot("hub-options-"+tab)
	hub.navigate("options",{"tab":"system"})
	await settle()
	check(not buttons(hub.stage,"ACCEDI CON GOOGLE").is_empty(),"Google Drive: pulsante di accesso")
	game.drive.state = "code"
	game.drive.user_code = "ABCD-EFGH"
	game.drive.code_expires = Time.get_ticks_msec()+600000
	game.drive.verification_url = "https://www.google.com/device"
	hub.navigate("options",{"tab":"system"})
	await snapshot("hub-drive-code")
	check(not buttons(hub.stage,"Apri la pagina di Google").is_empty(),"Google Drive: codice e pagina di Google")
	game.drive.state = "signed_in"
	game.drive.account = {"name":"Prova","email":"prova@example.com"}
	hub.navigate("friends",{})
	await settle()
	check(not buttons(hub.stage,"Sincronizza ora").is_empty(),"Google Drive: collegato, Sincronizza ora")
	game.drive.state = "off"
	var up: Node = game.updater
	for case in [["available","content","AGGIORNA"],["available","package","SCARICA IL PACCHETTO COMPLETO"],["ready","content","RIAVVIA PER APPLICARE"],["ready","package","MOSTRA NELLA CARTELLA DOWNLOAD"]]:
		up.state = case[0]
		up.release = {"mode":case[1],"version":"9.9","notes":"","page":"","name":"x"}
		hub.navigate("options",{"tab":"system"})
		await settle()
		check(buttons(hub.stage,case[2]).size() == 1,"Pulsante «%s» per %s/%s" % [case[2],case[0],case[1]])
	up.state = "idle"
	up.release = {}
	var Installer = preload("res://scripts/windows_installer.gd")
	Installer.show_wizard(hub,{},1)
	await snapshot("hub-launcher")
	check(not buttons(hub.modal_layer,"INSTALLA").is_empty(),"Procedura guidata del launcher")
	hub.close_modal()
	hub.show_tactics()
	await snapshot("hub-tactics")
	check(is_instance_valid(hub.modal_layer),"Finestra delle tattiche")
	hub.close_modal()
	hub.show_profile()
	await snapshot("hub-profile")
	check(is_instance_valid(hub.modal_layer),"Profilo")
	hub.close_modal()
	# Partita
	game.start_quick()
	await snapshot("coin")
	check(not hub.visible,"Il menu si nasconde quando inizia la partita")
	game.ui.close_dialog()
	game.phase = "select"
	game.ui.action("Tocca i dadi da tenere","Conferma",game.confirm_selection)
	await snapshot("table-hud")
	check(is_instance_valid(game.ui.primary_action) and game.ui.action_callback==Callable(game,"confirm_selection"),"Azione primaria registrata")
	game.ui.finish(true)
	await snapshot("finish")
	game.ui.close_dialog()
	game.ui.inspect_die(0,2)
	await snapshot("inspect")
	game.ui.show_settings(1)
	check(hub.visible and hub.page_state.get("overlay",false),"Impostazioni sopra la partita")
	await snapshot("settings-overlay")
	hub.close_overlay()
	check(not hub.visible,"Si torna alla partita")
	print("DESKTOP UI | schede, campagne, multigiocatore, opzioni, aggiornamenti, launcher e tavolo | errori %d" % failures)
	quit(1 if failures else 0)

func _initialize() -> void:
	call_deferred("run")

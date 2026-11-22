extends SceneTree
# Collaudo visivo e funzionale dell'interfaccia desktop orizzontale.
# Con una finestra reale salva schermate in build/desktop; in modalità headless controlla solo la struttura.
var game: Node3D
var failures := 0
var capture := false

func _initialize() -> void:
	call_deferred("run")

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
	await snapshot("menu")
	check(not game.portrait,"Interfaccia desktop orizzontale")
	OS.set_environment("SESTRIA_FAKE_WINDOWS","1")
	var PCSettings = preload("res://scripts/pc_settings.gd")
	var Installer = preload("res://scripts/windows_installer.gd")
	var screens := {
		"launcher-0":func():Installer.show_wizard(PCSettings.open(game.ui,game,"sistema"),{},0),
		"launcher-1":func():Installer.show_wizard(PCSettings.open(game.ui,game,"sistema"),{},1),
		"modes":game.ui.show_play_modes,"pass":game.ui.show_pass,"stats":game.ui.show_statistics,
		"lan":game.ui.show_lan,"online":game.ui.show_online,"updates":game.ui.show_updates,"settings-info":func():game.ui.show_settings(3),"settings-screen":func():game.ui.show_settings(0),"settings-graphics":func():game.ui.show_settings(1),"settings-audio":func():preload("res://scripts/pc_settings.gd").open(game.ui,game,"audio"),"settings-keys":func():game.ui.show_settings(2),
		"tactics":game.ui.show_equipped,"rules":game.ui.show_rules,"difficulty":game.ui.show_difficulty}
	for key in screens:
		screens[key].call()
		await snapshot(key)
		check(is_instance_valid(game.ui.dialog),"Apertura "+key)
		inside(game.ui.dialog.find_children("*","PanelContainer",true,false)[0],"Finestra "+key)
		game.ui.close_dialog()
	check(game.lan.role=="","Chiudere la LAN rilascia la stanza")
	# Aggiornamento dei contenuti: "Aggiorna", poi "Riavvia per applicare"; pacchetto completo: Download.
	var up: Node = game.updater
	for case in [["available","content","AGGIORNA"],["available","package","SCARICA PACCHETTO COMPLETO"],["ready","content","RIAVVIA PER APPLICARE"],["ready","package","MOSTRA NELLA CARTELLA DOWNLOAD"]]:
		up.state = case[0]
		up.release = {"mode":case[1],"version":"9.9","notes":"","page":"","name":"x"}
		game.ui.show_updates()
		await settle()
		var found: Array = game.ui.dialog.find_children("*","Button",true,false).filter(func(b):return b.text==case[2])
		check(found.size()==1,"Pulsante «%s» per %s/%s" % [case[2],case[0],case[1]])
		inside(game.ui.dialog.find_children("*","PanelContainer",true,false)[0],"Finestra aggiornamenti "+case[2])
		game.ui.close_dialog()
	up.state = "idle"
	up.release = {}
	# Una stanza trovata in rete si apre con un solo clic, senza digitare il codice.
	game.lan.rooms["192.168.1.9"] = {"ip":"192.168.1.9","name":"Prova","code":"123456","seen":Time.get_ticks_msec()}
	game.lan.rooms["192.168.1.10"] = {"ip":"192.168.1.10","name":"Vecchia","code":"","seen":Time.get_ticks_msec()}
	game.ui.show_lan()
	await snapshot("lan-rooms")
	var direct: Array = game.ui.dialog.find_children("*","Button",true,false).filter(func(b):return b.text.begins_with("ENTRA"))
	var manual: Array = game.ui.dialog.find_children("*","Button",true,false).filter(func(b):return b.text.ends_with("serve il codice"))
	check(direct.size()==1 and manual.size()==1,"Stanze vicine: ingresso diretto e stanza senza codice")
	game.ui.close_dialog()
	game.lan.rooms.clear()
	# La saga mostra un pannello Pass con la posizione di scorrimento conservata dopo ogni acquisto.
	game.progression.data.xp = 5000
	game.ui.show_pass()
	await settle()
	var scroll: ScrollContainer = game.ui.dialog.find_child("Scroll",true,false)
	scroll.scroll_vertical = 220
	await settle()
	var before := scroll.scroll_vertical
	check(before > 0,"Pass scorrevole su desktop")
	game.ui.close_dialog()
	game.progression.data.xp = 0
	game.progression.data.ranks.clear()
	game.ui.show_menu()
	game.prepare()
	await snapshot("coin")
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
	print("DESKTOP UI | schermate, bordi, scroll e azione primaria | errori %d" % failures)
	quit(1 if failures else 0)

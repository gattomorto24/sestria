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
	await snapshot("menu")
	check(not game.portrait,"Interfaccia desktop orizzontale")
	var screens := {
		"modes":game.ui.show_play_modes,"pass":game.ui.show_pass,"stats":game.ui.show_statistics,
		"lan":game.ui.show_lan,"updates":game.ui.show_updates,"settings-info":func():game.ui.show_settings(3),
		"tactics":game.ui.show_equipped,"rules":game.ui.show_rules,"difficulty":game.ui.show_difficulty}
	for key in screens:
		screens[key].call()
		await snapshot(key)
		check(is_instance_valid(game.ui.dialog),"Apertura "+key)
		inside(game.ui.dialog.find_children("*","PanelContainer",true,false)[0],"Finestra "+key)
		game.ui.close_dialog()
	check(game.lan.role=="","Chiudere la LAN rilascia la stanza")
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

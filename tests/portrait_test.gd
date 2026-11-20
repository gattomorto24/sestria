extends SceneTree

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
	for i in 8:
		await process_frame

func snapshot(name: String) -> void:
	await settle()
	if capture:
		await create_timer(.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/android/"+name+".png")

func fits(control: Control, message: String) -> void:
	var area := control.get_global_rect()
	check(area.position.x >= -1 and area.position.y >= -1 and area.end.x <= root.get_visible_rect().size.x+1 and area.end.y <= root.get_visible_rect().size.y+1,message+": "+str(area))

func run() -> void:
	capture = DisplayServer.get_name() != "headless"
	root.content_scale_size = Vector2i(720,1280)
	root.size = Vector2i(405,720)
	game = load("res://scenes/table.tscn").instantiate()
	root.add_child(game)
	await snapshot("portrait-menu")
	check(game.portrait,"Avvio verticale")
	game.ui.show_equipped()
	await snapshot("portrait-favors")
	for panel in game.ui.dialog.find_children("*","PanelContainer",true,false):
		fits(panel,"Pannello favori dentro lo schermo")
	game.ui.close_dialog()
	game.prepare()
	await snapshot("portrait-coin")
	game.ui.close_dialog()
	game.phase = "select"
	game.pending = []
	for cube in game.cubes[0]:
		game.pending.append(game.Rules.die(cube.die_id,cube.face))
	game.ui.action("Tocca i dadi da tenere", "Conferma",game.confirm_selection)
	await settle()
	check(game.ui.touch_buttons.size()==6,"Sei controlli touch")
	for entry in game.ui.touch_buttons:
		fits(entry,"Dado touch dentro lo schermo")
		check(entry.size.x >= 88 and entry.size.y >= 88,"Bersaglio touch di almeno 88 unità")
	game.ui.touch_die(0)
	check(game.cubes[0][0].selected,"Selezione diretta dalla barra")
	game.ui.touch_die(0)
	check(not game.cubes[0][0].selected,"Deselezione dalla barra")
	game.ui.touch_die(0)
	await snapshot("portrait-table")
	fits(game.ui.prompt,"Pulsante azione dentro lo schermo")
	game.ui.inspect_mode = true
	game.ui.touch_die(0)
	await snapshot("portrait-inspect")
	check(is_instance_valid(game.ui.context_popup),"Ispezione touch")
	fits(game.ui.context_popup,"Ispezione dentro lo schermo")
	game.go_back()
	check(not is_instance_valid(game.ui.context_popup),"Indietro chiude ispezione")
	game.ui.inspect_mode = false
	game.phase = "favor"
	game.ui.favor_stage()
	await snapshot("portrait-favor-stage")
	fits(game.ui.prompt,"Favori e Passa dentro lo schermo")
	game.ui.favor_popup("reserve",true)
	await snapshot("portrait-favor-popup")
	fits(game.ui.context_popup,"Favore dentro lo schermo")
	game.go_back()
	game.ui.show_rules()
	await snapshot("portrait-rules")
	game.go_back()
	game.ui.ask_leave()
	await settle()
	check(paused,"Menu mette in pausa la partita")
	game.ui.show_settings()
	check(paused,"Impostazioni mantengono la pausa")
	game.go_back()
	check(not paused,"Indietro riprende la partita")
	for tab in 3:
		game.ui.show_settings(tab)
		await settle()
		for panel in game.ui.dialog.find_children("*","PanelContainer",true,false):
			fits(panel,"Impostazioni dentro lo schermo")
	game.go_back()
	for side in 2:
		for cube in game.cubes[side]:
			cube.committed = true
	game.phase = "target"
	game.target_limit = 2
	game.targets = []
	game.ui.action("Seconda occasione · scegli due bersagli", "Attiva",game.confirm_targets)
	await snapshot("portrait-targets")
	fits(game.ui.target_tray,"Bersagli Seconda occasione dentro lo schermo")
	game.interact_die_or_favor(game.cubes[1][0],false)
	check(game.targets==[[1,0]],"Selezione bersaglio avversario")
	game.interact_die_or_favor(game.cubes[1][0],false)
	check(game.targets.is_empty(),"Deselezione bersaglio avversario")
	game.phase = "roll"
	root.size = Vector2i(405,900)
	await settle()
	game.ui.match_layout()
	game.ui.stats([15,15],[0,0],1,0)
	game.ui.action("Schermo 20:9", "Lancia",game.roll)
	await snapshot("portrait-tall")
	fits(game.ui.prompt,"Azione sullo schermo 20:9")
	game.menu()
	print("PORTRAIT | controlli touch, ispezione, favori, pannelli e formati 16:9 / 20:9 | errori %d" % failures)
	quit(1 if failures else 0)

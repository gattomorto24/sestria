extends SceneTree
var game: Node3D
var errors := 0
var capture := false
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		errors += 1
		push_error(message)
func settle(frames := 12) -> void:
	for i in frames:
		await process_frame
func shot(name: String) -> void:
	await settle()
	if capture:
		await create_timer(.4).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/android/"+name+".png")
func fits(node: Control, message: String) -> void:
	var rect := node.get_global_rect()
	var size: Vector2 = root.get_visible_rect().size
	check(rect.position.x >= -1 and rect.position.y >= -1 and rect.end.x <= size.x+1 and rect.end.y <= size.y+1,message+str(rect))
func touch_at(pos: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = pos
	event.pressed = down
	root.push_input(event,true)
func run() -> void:
	capture = DisplayServer.get_name() != "headless"
	root.size = Vector2i(405,720)
	var safe_script = load("res://scripts/safe_space.gd")
	var punch: Vector4 = safe_script.measure(Vector2(720,1600),Vector2(1080,2400),Rect2(0,0,1080,2400),[Rect2(480,0,120,90)])
	check(punch.y >= 80,"Hole punch centrale escluso")
	var corner: Vector4 = safe_script.measure(Vector2(720,1600),Vector2(1080,2400),Rect2(0,0,1080,2400),[Rect2(0,20,110,100)])
	check(corner.y >= 100,"Hole punch laterale escluso")
	game = load("res://scenes/table.tscn").instantiate()
	root.add_child(game)
	game.integration = true
	game.music.stop()
	await shot("mobile-menu")
	var hub: Control = game.ui.hub
	check(hub != null and hub.visible and game.portrait,"Menu verticale aperto")
	fits(hub.stage.get_child(0),"Menu dentro lo schermo ")
	for entry in ["campaign","multiplayer","friends","progress","options"]:
		hub.navigate(entry,{})
		await shot("mobile-hub-"+entry)
		fits(hub.stage.get_child(0),"Scheda "+entry+" dentro lo schermo ")
	game.updater.state="checking"
	game.ui.refresh_updates()
	game.updater.state="idle"
	hub.navigate("options",{"tab":"system"})
	await shot("sestria-updates")
	hub.show_profile()
	await shot("mobile-profile")
	check(is_instance_valid(hub.modal_layer),"Profilo")
	hub.close_modal()
	hub.show_tactics()
	await shot("mobile-favors")
	check(is_instance_valid(hub.modal_layer),"Tattiche")
	hub.close_modal()
	game.start_quick()
	await shot("mobile-coin")
	game.toss(0)
	check(not is_instance_valid(game.ui.dialog),"La scelta della moneta chiude il pannello")
	game.generation += 1
	game.phase="select"
	game.current=0
	game.pending=[]
	for cube in game.cubes[0]:
		game.pending.append(game.Rules.die(cube.die_id,cube.face))
	game.ui.action("Tocca i dadi da tenere. Tieni premuto per ispezionare.","Conferma",game.confirm_selection)
	await create_timer(.8).timeout
	await physics_frame
	var cube: Node3D = game.cubes[0][0]
	var point: Vector2 = game.camera.unproject_position(cube.global_position)
	check(game.pick_mobile(point)==cube,"Raycast sul dado 3D")
	touch_at(point,true)
	await settle(2)
	touch_at(point,false)
	await settle()
	check(cube.selected,"Tocco nativo seleziona il dado 3D")
	await shot("mobile-dice")
	fits(game.ui.dock,"Dock dentro lo schermo ")
	point = game.camera.unproject_position(cube.global_position)
	touch_at(point,true)
	game.touch_started = Time.get_ticks_msec()-500
	await settle()
	check(is_instance_valid(game.ui.context_popup),"Pressione prolungata apre ispezione 3D")
	touch_at(point,false)
	await shot("mobile-inspector")
	if is_instance_valid(game.ui.context_popup):
		fits(game.ui.context_popup.get_node("Card"),"Ispezione dentro lo schermo ")
	game.go_back()
	game.ui.ask_leave()
	check(paused,"Pausa effettiva della simulazione")
	game.ui.show_settings()
	await shot("mobile-settings")
	check(paused,"Impostazioni mantengono la pausa")
	fits(game.ui.hub.stage.get_child(0),"Impostazioni dentro lo schermo ")
	game.go_back()
	check(not paused,"Ripresa dalla pausa")
	game.ui.show_rules()
	await shot("mobile-rules")
	check(is_instance_valid(game.ui.hub.modal_layer),"Regole aperte")
	for paragraph in game.ui.hub.modal_layer.find_children("*","Label",true,false):
		if paragraph.autowrap_mode != TextServer.AUTOWRAP_OFF and not paragraph.text.is_empty():
			check(paragraph.size.y >= 28,"Paragrafo leggibile con altezza non nulla")
	game.ui.hub.close_modal()
	game.phase="favor"
	game.rules.gold=[20,20]
	game.visual_board=[[],[]]
	for side in 2:
		for c in game.cubes[side]:
			c.committed=true
			game.visual_board[side].append(game.Rules.die(c.die_id,c.face))
	game.sort_groups()
	game.table.lanes.show()
	game.ui.favor_stage()
	await shot("mobile-table")
	fits(game.ui.dock,"Dock favori dentro lo schermo ")
	game.ui.favor_popup("reserve",true)
	await shot("mobile-invoke")
	fits(game.ui.context_popup.get_node("Card"),"Sacrificio dentro lo schermo ")
	game.go_back()
	game.pick_favor("reroll",0,0)
	await settle()
	await physics_frame
	var target: Node3D = game.cubes[1][0]
	point=game.camera.unproject_position(target.global_position)
	touch_at(point,true)
	await settle(2)
	touch_at(point,false)
	await settle()
	check(game.targets==[[1,0]],"Bersaglio Seconda occasione toccabile sul tavolo 3D")
	await shot("mobile-frigg")
	game.ui.simulated_safe=Vector4(24,104,24,48)
	game.ui.layout()
	await shot("mobile-hole-punch")
	check(game.ui.header.position.y >= 104,"Header fuori dal foro fotocamera")
	fits(game.ui.dock,"Dock fuori barra gesti ")
	root.size=Vector2i(405,900)
	await settle()
	game.ui.layout()
	await shot("mobile-tall")
	fits(game.ui.dock,"Dock formato 20:9 ")
	game.graphics_mode=1
	game.apply_mobile_quality()
	check(Engine.max_fps==30 and not game.table.fill.shadow_enabled,"Profilo risparmio")
	game.graphics_mode=2
	game.apply_mobile_quality()
	check(Engine.max_fps==60 and game.table.fill.shadow_enabled,"Profilo qualità")
	game.menu()
	await settle()
	hub.navigate("progress",{})
	await shot("mobile-pass-tall")
	fits(hub.stage.get_child(0),"Progressi formato 20:9 ")
	game.phase="end"
	game.rules.winner=0
	game.rules.hp=[7,0]
	var reward_path := "res://build/android/progression-ui.json"
	if FileAccess.file_exists(reward_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(reward_path))
	game.progression=load("res://scripts/progression.gd").new(reward_path)
	game.progression.complete_match("ui-reward","solo",true,game.progression.create_run(1))
	game.ui.finish(true)
	await shot("mobile-xp-reward")
	fits(game.ui.dialog.get_node("Card"),"Ricompensa XP dentro lo schermo ")
	check(is_instance_valid(game.ui.dialog),"Schermata finale con la ricompensa")
	print("MOBILE | touch nativo 3D, pressione prolungata, Seconda occasione, pausa, safe area, 16:9, 20:9, profili | errori %d" % errors)
	print("RENDER | draw calls %d | oggetti %d | memoria video %d" % [RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)])
	game.queue_free()
	await settle(2)
	quit(1 if errors else 0)

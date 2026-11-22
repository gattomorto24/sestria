extends SceneTree
# Scorrimento e tocchi sul nuovo menu verticale: un trascinamento che parte da una scheda o da un pulsante fa scorrere
# la lista senza scegliere né acquistare nulla; un tocco semplice sì.
var game: Node3D
var errors := 0
func check(ok: bool, note: String) -> void:
	if not ok:
		errors += 1
		push_error(note)
func _initialize() -> void:
	call_deferred("run")
func ev(point: Vector2, down: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.device = InputEvent.DEVICE_ID_EMULATION
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = point
	e.global_position = point
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	return e
func mv(point: Vector2, rel: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.device = InputEvent.DEVICE_ID_EMULATION
	e.position = point
	e.global_position = point
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	return e
func frames(n: int) -> void:
	for i in n:
		await process_frame
func drag(a: Vector2, b: Vector2) -> void:
	root.push_input(ev(a,true))
	await process_frame
	var last := a
	for i in range(1,15):
		var p := a.lerp(b,i/14.0)
		root.push_input(mv(p,p-last))
		last = p
		await process_frame
	root.push_input(ev(b,false))
	await frames(30)
	OS.delay_msec(300)
func tap(p: Vector2) -> void:
	root.push_input(ev(p,true))
	await process_frame
	root.push_input(ev(p,false))
	await frames(8)
func run() -> void:
	root.size = Vector2i(720,1280)
	Input.set_emulate_touch_from_mouse(true)
	game = load("res://scenes/table.tscn").instantiate()
	root.add_child(game)
	await frames(6)
	game.integration = true
	game.music.stop()
	game.progression.data.xp = 6000
	game.progression.data.ranks.clear()
	game.progression.path = "res://build/android/hub-progression.json"
	var hub: Control = game.ui.hub
	hub.navigate("progress",{})
	await frames(12)
	var area: ScrollContainer = hub.stage.find_children("*","ScrollContainer",true,false)[0]
	check(area.get_v_scroll_bar().max_value > area.get_v_scroll_bar().page+300,"Progressi più alti dello schermo")
	var points: int = game.progression.points()
	var buy: Button
	for b in area.find_children("*","Button",true,false):
		if b.text.begins_with("Acquista") and b.get_global_rect().end.y < area.get_global_rect().end.y-30 and b.get_global_rect().position.y > area.get_global_rect().position.y+30:
			buy = b
			break
	check(buy != null,"Pulsante Acquista visibile")
	var start := buy.get_global_rect().get_center()
	await drag(start,start+Vector2(0,-360))
	check(area.scroll_vertical > 120,"Scorrimento partendo da un pulsante: %d" % area.scroll_vertical)
	check(game.progression.points() == points,"Il trascinamento non acquista")
	area.scroll_vertical = 0
	await frames(4)
	for b in area.find_children("*","Button",true,false):
		if b.text.begins_with("Acquista") and b.get_global_rect().end.y < area.get_global_rect().end.y-30 and b.get_global_rect().position.y > area.get_global_rect().position.y+30:
			buy = b
			break
	await tap(buy.get_global_rect().get_center())
	check(game.progression.points() < points,"Il tocco su Acquista funziona")
	# Campagna: trascinare dalle schede non sceglie nulla
	hub.navigate("campaign",{"selected":"quick"})
	await frames(12)
	var before: int = game.difficulty
	var cards: Array = hub.stage.find_children("*","PanelContainer",true,false).filter(func(c):return c.get_script() != null and c.has_signal("chosen"))
	check(cards.size() >= 3,"Schede di scelta presenti")
	if cards.size() >= 3:
		var c: Control = cards[cards.size()-1]
		var p := c.get_global_rect().get_center()
		await drag(p,p+Vector2(0,-200))
		check(game.difficulty == before,"Trascinare dalla scheda non cambia la sfida")
	print("MENU TOUCH | scorrimento da pulsanti e schede, tocchi | errori %d" % errors)
	quit(1 if errors else 0)

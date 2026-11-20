extends SceneTree
# Trascinamenti reali sul percorso GUI di Godot: pressione, movimenti e rilascio del mouse emulato dal tocco.
# Verifica che le finestre scorrano partendo da testo, schede e pulsanti, senza attivare acquisti,
# e che tocchi, cursori e posizione dopo i rinnovi del pannello continuino a funzionare.
var game: Node3D
var errors := 0
var checks := 0

func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(note)

func _initialize() -> void:
	call_deferred("run")

func event_button(point: Vector2, down: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.device = InputEvent.DEVICE_ID_EMULATION
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	return event

func event_motion(point: Vector2, relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.device = InputEvent.DEVICE_ID_EMULATION
	event.position = point
	event.global_position = point
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	return event

func frames(count: int) -> void:
	for i in count:
		await process_frame

func drag(from: Vector2, to: Vector2, steps := 14, settle := 40) -> void:
	root.push_input(event_button(from,true))
	await process_frame
	var last := from
	for i in range(1,steps+1):
		var point := from.lerp(to,float(i)/steps)
		root.push_input(event_motion(point,point-last))
		last = point
		await process_frame
	root.push_input(event_button(to,false))
	await frames(settle)
	OS.delay_msec(320)

func tap(point: Vector2, jitter := Vector2.ZERO) -> void:
	root.push_input(event_button(point,true))
	await process_frame
	if jitter != Vector2.ZERO:
		root.push_input(event_motion(point+jitter,jitter))
		await process_frame
	root.push_input(event_button(point+jitter,false))
	await frames(6)

func open_sheet() -> ScrollContainer:
	await frames(8)
	var dialog: Control = game.ui.context_popup if is_instance_valid(game.ui.context_popup) else game.ui.dialog
	return dialog.get_node("Card/Scroll")

func visible_center(control: Control, scroll: ScrollContainer) -> Vector2:
	var area := control.get_global_rect()
	var view := scroll.get_global_rect()
	var top := maxf(area.position.y,view.position.y)
	var bottom := minf(area.end.y,view.end.y)
	return Vector2(area.get_center().x,(top+bottom)*.5)

func first_button(scroll: ScrollContainer, prefix: String) -> Button:
	for item in scroll.find_children("*","Button",true,false):
		var node: Button = item
		var area := node.get_global_rect()
		if node.text.begins_with(prefix) and area.end.y < scroll.get_global_rect().end.y-30 and area.position.y > scroll.get_global_rect().position.y+30:
			return node
	return null

func run() -> void:
	root.size = Vector2i(720,1280)
	Input.set_emulate_touch_from_mouse(true)
	game = load("res://scenes/table.tscn").instantiate()
	root.add_child(game)
	await frames(4)
	game.integration = true
	game.music.stop()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	game.progression.data.xp = 6000
	game.progression.data.ranks.clear()
	game.progression.path = "res://build/android/scroll-progression.json"

	# 1. Pass: scorrimento da un pulsante di acquisto.
	game.ui.show_pass()
	var scroll := await open_sheet()
	check(scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page+400,"Il Pass è più alto dello schermo")
	var points: int = game.progression.points()
	var buy := first_button(scroll,"ACQUISTA")
	check(buy != null,"Pulsante di acquisto visibile")
	var start := visible_center(buy,scroll)
	await drag(start,start+Vector2(0,-420))
	check(scroll.scroll_vertical > 150,"Scorrimento verso il basso partendo da un pulsante: %d" % scroll.scroll_vertical)
	check(game.progression.points() == points,"Il trascinamento da un pulsante non acquista")

	# 2. Direzione opposta, partendo da una scheda.
	var before := scroll.scroll_vertical
	await drag(Vector2(360,640),Vector2(360,980))
	check(scroll.scroll_vertical < before-100,"Scorrimento verso l’alto da una scheda: %d → %d" % [before,scroll.scroll_vertical])
	check(game.progression.points() == points,"Il trascinamento da una scheda non cambia i punti")

	# 3. Trascinamento lento partendo dal testo.
	scroll.scroll_vertical = 0
	await frames(3)
	await drag(Vector2(180,300),Vector2(180,60),24,40)
	check(scroll.scroll_vertical > 100,"Scorrimento lento da un testo: %d" % scroll.scroll_vertical)

	# 4. Tocco semplice e tocco con minimo spostamento attivano il pulsante sotto il dito.
	scroll.scroll_vertical = 0
	await frames(4)
	buy = first_button(scroll,"ACQUISTA")
	await tap(visible_center(buy,scroll))
	check(game.progression.points() < points,"Il tocco su Acquista funziona")
	points = game.progression.points()
	scroll = await open_sheet()
	buy = first_button(scroll,"ACQUISTA")
	await tap(visible_center(buy,scroll),Vector2(5,4))
	check(game.progression.points() < points,"Un tocco con piccolo tremolio funziona")

	# 5. Dopo l’acquisto il pannello si ricostruisce senza perdere la posizione.
	game.ui.show_pass()
	scroll = await open_sheet()
	scroll.scroll_vertical = 500
	await frames(4)
	var pos := scroll.scroll_vertical
	game.ui.show_pass(pos)
	scroll = await open_sheet()
	await frames(14)
	check(absi(scroll.scroll_vertical-pos) < 4,"Posizione conservata dopo il rinnovo: %d / %d" % [scroll.scroll_vertical,pos])

	# 6. Toccare per fermare una spinta non deve acquistare nulla.
	game.ui.show_pass()
	scroll = await open_sheet()
	points = game.progression.points()
	var flick_from := Vector2(360,900)
	root.push_input(event_button(flick_from,true))
	await process_frame
	for i in 6:
		root.push_input(event_motion(flick_from+Vector2(0,-60*(i+1)),Vector2(0,-60)))
		await process_frame
	root.push_input(event_button(flick_from+Vector2(0,-360),false))
	await frames(3)
	var moving := scroll.scroll_vertical
	buy = first_button(scroll,"ACQUISTA")
	if buy:
		await tap(visible_center(buy,scroll))
	check(game.progression.points() == points,"Il tocco che interrompe la spinta non acquista (scorrimento %d)" % moving)
	OS.delay_msec(320)

	# 7. Impostazioni: il cursore si muove in orizzontale senza scorrere la finestra.
	game.ui.show_settings()
	scroll = await open_sheet()
	var slider: HSlider = scroll.find_children("*","HSlider",true,false)[0]
	var level := slider.value
	var row := slider.get_global_rect()
	await drag(row.position+Vector2(40,row.size.y*.5),row.position+Vector2(row.size.x-40,row.size.y*.5),10,10)
	check(slider.value != level,"Il cursore audio resta utilizzabile")
	check(scroll.scroll_vertical == 0,"Il cursore non scorre la finestra")

	# 8. Impostazioni: scorrere, cambiare una voce e restare nello stesso punto.
	scroll.scroll_vertical = 360
	await frames(4)
	var toggle := first_button(scroll,"Risparmio")
	if toggle == null:
		toggle = first_button(scroll,"Bilanciata")
	await tap(visible_center(toggle,scroll))
	scroll = await open_sheet()
	await frames(14)
	check(scroll.scroll_vertical > 300,"Le impostazioni conservano la posizione dopo la modifica: %d" % scroll.scroll_vertical)

	# 9. Ispettore: il trascinamento ruota il dado e non scorre la finestra.
	game.phase = "select"
	game.ui.inspect_die(0,2)
	scroll = await open_sheet()
	var container: SubViewportContainer = scroll.find_children("*","SubViewportContainer",true,false)[0]
	var spot := container.get_global_rect().get_center()
	var cube: Node3D = container.get_child(0).find_children("*","RigidBody3D",true,false)[0]
	var rotation_before := cube.basis
	await drag(spot,spot+Vector2(160,40),10,6)
	check(not cube.basis.is_equal_approx(rotation_before),"L’ispettore 3D continua a ruotare con il dito")
	check(scroll.scroll_vertical == 0,"La rotazione non scorre la finestra")
	game.ui.close_context()
	Input.set_emulate_touch_from_mouse(false)
	print("SCORRIMENTO | %d controlli: trascinamento, tocchi, cursori, spinta, posizione e ispettore | errori %d" % [checks,errors])
	quit(1 if errors else 0)

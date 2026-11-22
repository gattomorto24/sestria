extends SceneTree
# Collaudo delle impostazioni per i computer: pulizia dei valori, livelli grafici, FSR, risoluzioni, salvataggio,
# comandi da tastiera e applicazione reale su viewport e ambiente del tavolo.
const PC = preload("res://scripts/pc_video.gd")
const Bindings = preload("res://scripts/input_bindings.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func key_event(code: int, alt := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.alt_pressed = alt
	return event

func run() -> void:
	# valori
	var d := PC.defaults()
	check(d.preset == "alta" and d.window_mode == "window" and d.msaa == 4 and d.ssao == "medium" and d.scaling == "native","Predefiniti = aspetto di sempre (Alta)")
	var dirty := PC.clean({"window_mode":"evil","vsync":7,"fps_cap":13,"msaa":3,"aa":"x","scaling":"dlss","ui_scale":9.0,"render_scale":.1,"sharpness":-4.0,"resolution":"abc","monitor":-5,"ssao":"max","aniso":3,"preset":"boh"})
	check(dirty.window_mode == "window" and dirty.vsync == "on" and dirty.fps_cap == 0 and dirty.msaa == 4 and dirty.aa == "none" and dirty.scaling == "native","Valori sconosciuti ripuliti")
	check(dirty.ui_scale == 1.5 and dirty.render_scale == .5 and dirty.sharpness == 0.0 and dirty.resolution == "1280x800" and dirty.monitor == 0 and dirty.ssao == "medium" and dirty.aniso == 8 and dirty.preset == "custom","Intervalli e risoluzione ripuliti")
	check(PC.clean({"ui_scale":1}).ui_scale == 1.0,"Interi accettati dove si aspetta un decimale")
	for name in PC.PRESETS:
		check(PC.detect_preset(PC.with_preset(PC.defaults(),name)) == name,"Livello riconosciuto: "+name)
	check(PC.detect_preset(PC.with_preset(PC.defaults(),"alta").merged({"glow":false},true)) == "custom","Una modifica porta a «Personalizzata»")
	var fsr2 := PC.defaults().merged({"scaling":"fsr2"},true)
	check(PC.normalized(fsr2).msaa == 0 and PC.normalized(PC.defaults().merged({"aa":"taa"},true)).msaa == 0 and PC.normalized(PC.defaults()).msaa == 4,"FSR 2 e TAA escludono l'MSAA")
	check(PC.parse_resolution("1920x1080") == Vector2i(1920,1080) and PC.parse_resolution("0x0") == Vector2i.ZERO and PC.parse_resolution("99999x1") == Vector2i.ZERO and PC.parse_resolution("1920") == Vector2i.ZERO,"Risoluzioni valide e non")
	var options := PC.resolution_options(Vector2i(1920,1080))
	check(options.has(Vector2i(1280,720)) and options.has(Vector2i(1920,1080)) and not options.has(Vector2i(2560,1440)),"Risoluzioni adatte allo schermo")
	check(PC.resolution_options(Vector2i(2000,1200)).back() == Vector2i(2000,1200),"Aggiunge la risoluzione nativa")
	# salvataggio
	var config := ConfigFile.new()
	var custom := PC.with_preset(PC.defaults(),"ultra").merged({"window_mode":"borderless","resolution":"1920x1080","vsync":"mailbox","fps_cap":144,"scaling":"fsr1","fsr_quality":"balanced","fps_counter":true},true)
	PC.save_to(config,custom)
	check(PC.load_from(config) == PC.clean(custom),"Salvataggio e lettura coincidono")
	check(PC.load_from(ConfigFile.new()) == PC.defaults(),"Senza file: predefiniti")
	# comandi
	Bindings.reset()
	check(Bindings.action_for(key_event(KEY_SPACE)) == "confirm" and Bindings.action_for(key_event(KEY_ENTER)) == "confirm" and Bindings.action_for(key_event(KEY_ESCAPE)) == "back","Tasti predefiniti: Spazio, Invio, Esc")
	check(Bindings.action_for(key_event(KEY_ENTER,true)) == "fullscreen" and Bindings.action_for(key_event(KEY_F11)) == "fullscreen","Alt+Invio e F11: schermo intero")
	check(Bindings.action_for(key_event(KEY_3)) == "die3" and Bindings.action_for(key_event(KEY_W)) == "tactic2" and Bindings.action_for(key_event(KEY_Z)) == "","Dadi 1-6 e tattiche Q W E")
	check(Bindings.action_for(key_event(KEY_SPACE,true)) == "" ,"Con Alt non scatta altro")
	check(Bindings.assign("confirm",KEY_R) == "" and Bindings.action_for(key_event(KEY_R)) == "confirm" and Bindings.action_for(key_event(KEY_SPACE)) == "","Rimappatura")
	check(Bindings.assign("back",KEY_R) == "" and Bindings.key_for("confirm") == KEY_ESCAPE and Bindings.key_for("back") == KEY_R,"Tasto già usato: le due azioni si scambiano")
	check(Bindings.assign("back",KEY_ENTER) != "" and Bindings.assign("back",KEY_CTRL) != "" and Bindings.assign("nulla",KEY_R) != "","Tasti riservati e azioni sconosciute rifiutati")
	var keys := ConfigFile.new()
	Bindings.save_to(keys)
	Bindings.reset()
	Bindings.load_from(keys)
	check(Bindings.key_for("confirm") == KEY_ESCAPE and Bindings.key_for("back") == KEY_R,"Comandi salvati e riletti")
	keys.set_value(Bindings.SECTION,"die1",KEY_ESCAPE)
	keys.set_value(Bindings.SECTION,"die2",KEY_ESCAPE)
	keys.set_value(Bindings.SECTION,"die3","x")
	Bindings.load_from(keys)
	var seen := {}
	for id in Bindings.current:
		check(not seen.has(Bindings.current[id]),"Nessun tasto doppio dopo il caricamento ("+id+")")
		seen[Bindings.current[id]] = true
	Bindings.reset()
	# applicazione reale al tavolo
	var game: Node3D = load("res://scenes/table.tscn").instantiate()
	root.add_child(game)
	game.integration = true
	game.music.stop()
	for i in 5:
		await process_frame
	check(not game.pc.is_empty(),"Impostazioni caricate nel gioco")
	var graded := {}
	for name in PC.PRESETS:
		game.change_pc(PC.with_preset(game.pc,name),false)
		graded[name] = [game.table.env.ssao_enabled,game.table.key.shadow_enabled,root.msaa_3d,game.reduced]
		await process_frame
	check(graded.bassa[3] and not graded.bassa[0] and not graded.bassa[1],"Bassa: niente SSAO né ombre")
	check(graded.alta[0] and graded.alta[1] and graded.alta[2] == Viewport.MSAA_4X and not graded.alta[3],"Alta: SSAO, ombre e MSAA 4x come sempre")
	check(graded.ultra[2] == Viewport.MSAA_8X,"Ultra: MSAA 8x")
	for mode in ["native","bilinear","fsr1","fsr2"]:
		game.change_pc(game.pc.merged({"scaling":mode,"fsr_quality":"performance","render_scale":.7},true),false)
		await process_frame
		var expected = {"native":Viewport.SCALING_3D_MODE_BILINEAR,"bilinear":Viewport.SCALING_3D_MODE_BILINEAR,"fsr1":Viewport.SCALING_3D_MODE_FSR,"fsr2":Viewport.SCALING_3D_MODE_FSR2}[mode]
		check(root.scaling_3d_mode == expected,"Upscaling "+mode)
		var scale = {"native":1.0,"bilinear":.7,"fsr1":.5,"fsr2":.5}[mode]
		check(is_equal_approx(root.scaling_3d_scale,scale),"Scala di rendering "+mode+": "+str(root.scaling_3d_scale))
	check(root.msaa_3d == Viewport.MSAA_DISABLED and not root.use_taa,"FSR 2: MSAA spento e TAA del motore spento (FSR 2 ha il suo)")
	game.change_pc(PC.defaults(),false)
	await process_frame
	check(root.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR and root.scaling_3d_scale == 1.0 and not root.use_taa,"Ritorno ai predefiniti")
	print("IMPOSTAZIONI PC | pulizia, livelli, FSR, risoluzioni, salvataggio, comandi e applicazione | errori %d" % failures)
	quit(1 if failures > 0 else 0)

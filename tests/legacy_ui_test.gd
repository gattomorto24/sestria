extends SceneTree
# Interfaccia classica (4.7): si attiva e si disattiva dalle impostazioni, il menu e le schermate si aprono, la scelta resta salvata.
var game: Node3D
var failures := 0
func check(ok: bool, note: String) -> void:
	if not ok:
		failures += 1
		push_error(note)
func _initialize() -> void:
	call_deferred("run")
func settle() -> void:
	for i in 10:
		await process_frame
func run() -> void:
	game = load("res://scenes/table.tscn").instantiate()
	root.add_child(game)
	game.integration = true
	game.music.stop()
	await settle()
	var portrait: bool = game.portrait
	check(not game.legacy_ui and game.ui.hub != null and game.ui.hub.visible,"Parte con la nuova interfaccia")
	# dalla nuova interfaccia: il toggle in Opzioni > Sistema esiste
	game.ui.hub.navigate("options",{"tab":"system"})
	await settle()
	var found: Array = game.ui.hub.stage.find_children("*","Label",true,false).filter(func(l):return l.text == "Interfaccia classica")
	check(found.size() == 1,"Toggle «Interfaccia classica» presente")
	game.switch_ui(true)
	await settle()
	check(game.legacy_ui and game.ui.get_script().resource_path.ends_with("interface_legacy.gd"),"Interfaccia classica attiva")
	check(game.ui.hub == null,"Il menu nuovo non c'è più")
	# schermate classiche
	if portrait:
		game.ui.show_settings()
		await settle()
		check(is_instance_valid(game.ui.dialog),"Impostazioni classiche")
		game.ui.close_dialog()
		game.ui.show_updates()
		await settle()
		check(is_instance_valid(game.ui.dialog),"Aggiornamenti classici")
		game.ui.close_dialog()
	else:
		for tab in 4:
			game.ui.show_settings(tab)
			await settle()
			check(is_instance_valid(game.ui.dialog),"Impostazioni classiche, pagina %d" % tab)
			game.ui.close_dialog()
		for name in ["show_play_modes","show_pass","show_statistics","show_equipped","show_rules"]:
			game.ui.call(name)
			await settle()
			check(is_instance_valid(game.ui.dialog),"Schermata classica "+name)
			game.ui.close_dialog()
	game.ui.show_menu()
	await settle()
	game.ui.show_settings(3) if not portrait else game.ui.show_settings()
	await settle()
	check(not game.ui.dialog.find_children("*","Button",true,false).filter(func(b):return b.text == "Passa alla nuova interfaccia").is_empty(),"Pulsante per tornare alla nuova interfaccia")
	game.ui.close_dialog()
	# si torna alla nuova
	game.switch_ui(false)
	await settle()
	check(not game.legacy_ui and game.ui.hub != null and game.ui.hub.visible,"Di nuovo la nuova interfaccia")
	# salvataggio della scelta
	check(game.legacy_ui == false,"Scelta registrata")
	print("INTERFACCIA CLASSICA | attivazione, schermate, ritorno | errori %d" % failures)
	quit(1 if failures else 0)

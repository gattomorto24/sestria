extends Node
var game: Node3D
func fail(note: String) -> void:
	push_error("ANDROID_LAN_FAIL: "+note)
	get_tree().quit(1)
func save_screen(name: String) -> void:
	await get_tree().create_timer(.35).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://"+name+".png")
func _ready() -> void:
	game=load("res://scenes/table.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await get_tree().process_frame
	game.integration=true
	game.music.stop()
	if not Engine.has_singleton("SestriaLAN") or not Engine.has_singleton("SestriaUpdates") or not game.account.available():
		fail("plugin Android mancanti")
		return
	for cycle in 40:
		game.ui.show_lan()
		var create: Button
		for node in game.ui.dialog.find_children("*","Button",true,false):
			if node.text=="CREA STANZA":create=node
		if not is_instance_valid(create):
			fail("pulsante stanza non disponibile")
			return
		create.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		if game.lan.role!="host":
			fail("creazione stanza")
			return
		game.ui.close_dialog()
		await get_tree().process_frame
		if game.lan.server.is_listening() or game.lan.discovery.is_bound():
			fail("risorse stanza non rilasciate")
			return
	print("ANDROID_LOBBY_OK: 40 aperture, creazioni e chiusure tramite UI")
	game.ui.show_menu()
	await save_screen("sestria-menu")
	game.ui.show_updates()
	await save_screen("sestria-updates")
	game.ui.close_dialog()
	game.lan.host_room()
	game.lan.room_code="762481"
	game.ui.show_lan()
	print("ANDROID_HOST_READY: 762481")
	await save_screen("sestria-host-lobby")
	if not await play_round(true):return
	game.menu()
	await get_tree().create_timer(1).timeout
	game.lan.join_room("10.0.2.2","762481")
	print("ANDROID_GUEST_CONNECTING")
	if not await play_round(false):return
	game.menu()
	game.ui.show_diagnostics()
	await save_screen("sestria-diagnostics")
	print("ANDROID_NETWORK_COMPLETE: creatore e partecipante, stanza, connessione, moneta e manche completati")
func play_round(host: bool) -> bool:
	var deadline := Time.get_ticks_msec()+90000
	var began := false
	while Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
		if game.lan.active and not game.lan.started and host and not began:
			began=true
			game.lan.start_match()
			await get_tree().process_frame
			game.toss(0)
		if not game.lan.started:continue
		match game.phase:
			"roll":game.roll()
			"select":
				for die in game.cubes[0]:
					if not die.committed:die.select(true)
				game.confirm_selection()
			"favor":game.resolve({})
			"between","end":
				print("ANDROID_ROUND_OK role=",game.lan.role," hp=",game.rules.hp," gold=",game.rules.gold)
				await save_screen("sestria-round-"+("host" if host else "guest"))
				return true
	fail("manche non completata: "+game.lan.role+" / "+game.phase)
	return false

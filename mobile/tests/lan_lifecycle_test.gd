extends SceneTree
var errors := 0
func check(ok: bool,note: String) -> void:
	if not ok:
		errors+=1
		push_error(note)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game=load("res://scenes/table.tscn").instantiate()
	root.add_child(game)
	game.integration=true
	game.music.stop()
	for cycle in 60:
		game.ui.show_lan()
		var create: Button
		for node in game.ui.hub.stage.find_children("*","Button",true,false):
			if node.text=="CREA UNA STANZA":create=node
		check(is_instance_valid(create),"Pulsante creazione stanza presente")
		if is_instance_valid(create):create.pressed.emit()
		await process_frame
		await process_frame
		check(game.lan.role=="host" and game.lan.server.is_listening(),"Stanza creata dal vero callback UI")
		game.ui.hub.leave_room_if_needed()
		game.ui.hub.navigate("multiplayer",{"sub":"device"})
		await process_frame
		check(game.lan.role=="" and not game.lan.server.is_listening() and not game.lan.discovery.is_bound(),"Chiusura rilascia TCP e ricerca UDP")
	game.prepare()
	var valid: Dictionary=game.lan.snapshot()
	check(game.lan.valid_state(valid),"Stato originale valido")
	for change in [["first",-1],["first",2],["current",3],["hp",[99,1]],["gold",[-1,0]],["board",[{},[]]],["attempts",[4,0]],["dice",[{},[]]],["pending",[{}]],["round",0]]:
		var bad:=valid.duplicate(true)
		bad[change[0]]=change[1]
		check(not game.lan.valid_state(bad),"Stato incompleto rifiutato prima del renderer: "+str(change))
	var bad:=valid.duplicate(true)
	bad.dice[0][0].q=[0,0,0,0]
	check(not game.lan.valid_state(bad),"Rotazione nulla respinta")
	game.menu()
	game.queue_free()
	await process_frame
	print("LAN CICLO VITA | 60 aperture/creazioni/chiusure dal menu + stati incompleti | errori %d" % errors)
	quit(1 if errors else 0)

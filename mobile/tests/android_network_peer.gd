extends SceneTree
var game: Node3D
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	game=load("res://scenes/table.tscn").instantiate()
	root.add_child(game)
	game.integration=true
	game.music.stop()
	game.lan.join_room("127.0.0.1","762481")
	if not await play_round(false):return
	print("DESKTOP_PEER_GUEST_FINISHED")
	game.menu()
	if OS.has_environment("SESTRIA_ADB"):
		OS.execute(OS.get_environment("SESTRIA_ADB"),["-s","emulator-5554","forward","--remove","tcp:32640"])
	game.lan.host_room()
	game.lan.room_code="762481"
	print("DESKTOP_PEER_HOST_READY")
	if not await play_round(true):return
	await create_timer(3).timeout
	game.menu()
	game.queue_free()
	await process_frame
	quit()
func play_round(host: bool) -> bool:
	var deadline := Time.get_ticks_msec()+100000
	var began := false
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if game.lan.active and not game.lan.started and host and not began:
			began=true
			game.lan.start_match()
			await process_frame
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
				print("DESKTOP_ROUND_OK role=",game.lan.role," hp=",game.rules.hp," gold=",game.rules.gold)
				await create_timer(1).timeout
				return true
	push_error("DESKTOP_PEER_TIMEOUT: "+game.phase)
	quit(1)
	return false

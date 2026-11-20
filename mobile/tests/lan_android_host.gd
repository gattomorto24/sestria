extends SceneTree
var game: Node3D
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	game=load("res://scenes/table.tscn").instantiate()
	root.add_child(game)
	game.integration=true
	game.music.stop()
	game.lan.host_room()
	game.lan.room_code="762481"
	Engine.max_fps=120
	print("ANDROID_LAN_HOST_READY 762481")
	var began := false
	var tick := 0
	while tick<24000:
		await process_frame
		tick+=1
		if game.lan.active and not game.lan.started and not began:
			began=true
			game.lan.start_match()
			await process_frame
			game.toss(0)
		if began:
			match game.phase:
				"roll":game.roll()
				"select":
					for die in game.cubes[0]:
						if not die.committed:die.select(true)
					game.confirm_selection()
				"favor":game.resolve({})
				"between":
					print("HOST_LAN_ROUND_OK round=",game.rules.round_no," hp=",game.rules.hp," gold=",game.rules.gold)
					await create_timer(10).timeout
					quit()
					return
				"end":
					print("ANDROID_LAN_COMPLETE ",game.rules.hp)
					await create_timer(2).timeout
					quit()
					return
	quit()

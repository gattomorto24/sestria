extends Node
var game: Node3D
func save_screen(name: String) -> void:
	await get_tree().create_timer(.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://"+name+".png")
func _ready() -> void:
	game=load("res://scenes/table.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await get_tree().process_frame
	game.integration=true
	game.music.stop()
	if not Engine.has_singleton("SestriaGoogle") or not Engine.has_singleton("SestriaLAN") or not game.account.available():
		push_error("ANDROID_CHECKS: plugin nativi o client OAuth mancanti")
		get_tree().quit(1)
		return
	print("ANDROID_CHECKS: plugin Google, LAN e client OAuth pronti")
	var stats=load("res://scripts/statistics.gd").new("user://smoke-statistics.json")
	stats.start("lan",1)
	stats.rolled()
	stats.finish(true,[6,0])
	var saved=load("res://scripts/statistics.gd").new("user://smoke-statistics.json")
	if saved.data.played<1 or saved.data.wins<1:
		push_error("ANDROID_CHECKS: statistiche non persistite")
		get_tree().quit(1)
		return
	game.stats_store=saved
	if OS.has_feature("progression_smoke"):
		await check_progression()
		return
	game.ui.show_statistics()
	await save_screen("android-statistics")
	game.ui.close_dialog()
	game.ui.show_profile()
	await save_screen("android-google-profile")
	game.ui.close_dialog()
	game.ui.show_lan()
	await save_screen("android-lan-lobby")
	game.ui.close_dialog()
	game.lan.join_room("10.0.2.2","762481")
	var started_at := Time.get_ticks_msec()
	var actions := {}
	while Time.get_ticks_msec()-started_at<180000:
		await get_tree().process_frame
		if game.lan.started:
			match game.phase:
				"roll":game.roll()
				"select":
					for die in game.cubes[0]:
						if not die.committed:die.select(true)
					game.confirm_selection()
				"favor":game.resolve({})
				"between","end":
					print("ANDROID_LAN_ROUND_OK round=",game.rules.round_no," hp=",game.rules.hp," gold=",game.rules.gold)
					await save_screen("android-lan-round")
					game.lan.close()
					game.menu()
					game.ui.show_statistics()
					print("ANDROID_CHECKS_COMPLETE")
					return
		elif Time.get_ticks_msec()-started_at>15000:
			break
	push_error("ANDROID_CHECKS: connessione LAN o manche non completata")

func check_progression() -> void:
	const Progress = preload("res://scripts/progression.gd")
	var path := "user://smoke-progression.json"
	for file in [path,path+".tmp"]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	var progress := Progress.new(path)
	progress.complete_match("android-first","solo",true,progress.create_run(1))
	game.progression=Progress.new(path)
	if game.progression.level()!=2 or game.progression.points()!=2:
		push_error("ANDROID_PROGRESSION: ricompensa non persistita")
		return
	game.ui.show_menu()
	await save_screen("android-saga-menu")
	game.ui.show_pass()
	await save_screen("android-pass")
	game.ui.buy_upgrade("provisions")
	await save_screen("android-pass-purchased")
	game.progression=Progress.new(path)
	if game.progression.rank_of("provisions")!=1 or game.progression.points()!=0:
		push_error("ANDROID_PROGRESSION: acquisto non persistito")
		return
	game.ui.close_pass()
	game.integration=false
	game.prepare()
	game.integration=true
	game.toss(0)
	for frame in 6:
		await get_tree().process_frame
	if game.rules.gold[0]!=1:
		push_error("ANDROID_PROGRESSION: scorta non applicata")
		return
	await save_screen("android-saga-buff")
	game.generation+=1
	game.rules.winner=0
	game.rules.hp=[7,0]
	game.integration=false
	game.record_match_result()
	game.integration=true
	game.phase="end"
	game.ui.finish(true)
	await save_screen("android-xp-reward")
	if game.progression.level()!=3 or game.progression.points()!=2 or game.progression.last_reward.get("xp")!=130:
		push_error("ANDROID_PROGRESSION: risultato reale non accreditato")
		return
	print("ANDROID_PROGRESSION_OK: XP persistiti, livello 3, 2 punti, acquisto UI, bonus dopo la moneta e risultato reale")

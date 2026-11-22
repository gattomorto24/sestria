extends SceneTree
# Salva schermate del nuovo menu (finestra reale) in build/desktop/hub-*.png.  Uso: godot --path . --script res://tests/hub_capture.gd
const Store = preload("res://scripts/hub/campaign_store.gd")
var game: Node3D
func _initialize() -> void:
	call_deferred("run")
func shot(name: String) -> void:
	for i in 14:
		await process_frame
	await create_timer(.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/desktop/hub-"+name+".png")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/desktop"))
	game = load("res://scenes/table.tscn").instantiate()
	root.add_child(game)
	game.integration = true
	game.music.stop()
	game.change_pc(preload("res://scripts/pc_video.gd").defaults(),true)
	var hub: Control = game.ui.hub
	var item: Dictionary = game.campaigns.create("La via del bosco",2,{"first":"bot","hints":true})
	game.campaigns.record(item.id,true,130)
	await shot("campaign")
	hub.navigate("campaign",{"view":"new","draft":{"name":"Prova","difficulty":1,"settings":Store.default_settings()}})
	await shot("new")
	for sub in ["device","lan","online"]:
		hub.navigate("multiplayer",{"sub":sub})
		await shot("multi-"+sub)
	hub.navigate("friends",{})
	game.friends.store.receive_request({"id":"ABCDEFGHJKMN","name":"Alba","emblem":4,"color":2})
	game.friends.store.friends.append({"id":"PQRSTUVWXYZ2","name":"Bruno","emblem":2,"color":1,"seen":0,"time":0})
	hub.navigate("friends",{})
	await shot("friends")
	hub.navigate("progress",{})
	await shot("progress")
	for tab in ["game","screen","graphics","audio","controls","system"]:
		hub.navigate("options",{"tab":tab})
		await shot("options-"+tab)
	hub.show_tactics()
	await shot("tactics")
	hub.show_profile()
	await shot("profile")
	game.campaigns.remove(item.id)
	quit()

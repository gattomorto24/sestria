extends SceneTree
# Salva schermate del nuovo menu (finestra reale) in build/desktop/hub-*.png.  Uso: godot --path . --script res://tests/hub_capture.gd [-- --portrait]
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
	await shot("campaign")
	var hub: Control = game.ui.hub
	hub.navigate("campaign",{"selected":"quick"})
	await shot("quick")
	hub.navigate("campaign",{"view":"new","draft":{"name":"Prova","difficulty":1,"settings":preload("res://scripts/hub/campaign_store.gd").default_settings()}})
	await shot("new")
	var item: Dictionary = game.campaigns.create("La via del bosco",2,{"first":"bot","hints":true})
	hub.navigate("campaign",{"selected":item.id})
	await shot("detail")
	hub.show_profile()
	await shot("profile")
	game.campaigns.remove(item.id)
	quit()

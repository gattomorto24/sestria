extends SceneTree
# Prova dal vivo con Google vero (serve una persona che digiti il codice su google.com/device). Non fa parte dei collaudi
# automatici. Uso: godot --headless --path . --script res://tests/drive_live.gd
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game: Node3D = load("res://scenes/table.tscn").instantiate()
	root.add_child(game)
	game.integration = true
	game.music.stop()
	for i in 10:
		await process_frame
	var drive: Node = game.drive
	print("LIVE disponibile: ",drive.available())
	drive.state = "off"
	drive.start_sign_in()
	while drive.state != "code":
		await create_timer(.3).timeout
		if not drive.busy and drive.state == "off" and drive.message != "Contatto Google…":
			print("LIVE errore: ",drive.message)
			quit(1)
			return
	print("LIVE CODICE ",drive.user_code," ",drive.verification_url)
	var end := Time.get_ticks_msec()+300000
	while drive.state == "code" and Time.get_ticks_msec() < end:
		await create_timer(.5).timeout
	print("LIVE stato ",drive.state," account ",drive.account)
	if drive.state != "signed_in":
		quit(1)
		return
	game.campaigns.create("Prova dal vivo",1,{})
	await create_timer(1.0).timeout
	drive.sync(true)
	var t := Time.get_ticks_msec()+60000
	while (drive.busy or not drive.message.begins_with("Sincronizzato")) and Time.get_ticks_msec() < t:
		await create_timer(.3).timeout
	print("LIVE sincronizzazione: ",drive.message," file ",drive.file_id)
	drive.file_id = ""
	await drive.find_file()
	print("LIVE file ritrovato su Drive: ",not drive.file_id.is_empty())
	var remote: Dictionary = await drive.download()
	print("LIVE contiene la campagna: ",str(remote.get("campaigns",{}).get("items",[])).contains("Prova dal vivo"))
	# pulizia: elimina il file di prova da Drive e scollega (revoca il token)
	var gone: Dictionary = await drive.request(drive.endpoints.drive+"/files/"+drive.file_id,HTTPClient.METHOD_DELETE,drive.auth_header(),"")
	print("LIVE file eliminato da Drive: ",gone.code)
	game.campaigns.remove(game.campaigns.campaigns[game.campaigns.campaigns.size()-1].id)
	drive.sign_out()
	await create_timer(2.0).timeout
	print("LIVE FINE")
	quit(0)

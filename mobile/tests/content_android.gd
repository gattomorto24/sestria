extends Node
# Prova su Android (emulatore o telefono) dell'aggiornamento dei contenuti, in due avvii:
# 1) scarica da un server locale (10.0.2.2) il pacchetto, lo verifica e riavvia l'app con restartApp del plugin nativo;
# 2) al nuovo avvio monta il pacchetto e avvia il vero boot.gd. Risultati nel logcat con prefisso CONTENT_E2E.
# Preset "Android Content Smoke"; il server si avvia con tools/content/fake_release_server.py <cartella> v4.6 55192.
const Content = preload("res://scripts/content_pack.gd")
const Updates = preload("res://scripts/updater.gd")
const SERVER := "http://10.0.2.2:55192"

func _ready() -> void:
	var record := Content.installed_record()
	print("CONTENT_E2E avvio pid=%d contenuti=%s base=%s pacchetto=%s" % [OS.get_process_id(),Content.running_version(),Content.base_version(),str(record.get("version","nessuno"))])
	if not record.is_empty():
		# Secondo avvio: il vero boot.gd monta il pacchetto e carica il gioco.
		var boot: Node = load("res://scenes/boot.tscn").instantiate()
		add_child(boot)
		await get_tree().create_timer(12).timeout
		var game := get_tree().current_scene
		var final := Content.installed_record()
		print("CONTENT_E2E contenuti=%s stato=%s stato_avvio=%s scena=%s" % [Content.running_version(),str(final.get("status")),Content.boot_status,str(game)])
		var ok: bool = Content.running_version()=="4.6" and final.get("status")=="confirmed" and game!=null and game.get("ui")!=null
		print("CONTENT_E2E %s dopo il riavvio" % ("PASS" if ok else "FAIL"))
		return
	var update := Updates.new()
	update.api = SERVER+"/api/latest"
	update.releases = SERVER+"/releases"
	add_child(update)
	await get_tree().process_frame
	update.check_updates()
	await wait_for(update,["available","current","error"])
	print("CONTENT_E2E verifica: %s %s %s [%s]" % [update.state,update.release.get("mode",""),update.message,update.fallback_reason])
	if update.state!="available" or update.release.get("mode")!="content":
		print("CONTENT_E2E FAIL verifica")
		return
	update.download_update()
	await wait_for(update,["ready","error"])
	print("CONTENT_E2E download: %s %s" % [update.state,update.message])
	if update.state!="ready":
		print("CONTENT_E2E FAIL download")
		return
	print("CONTENT_E2E riavvio dell'app…")
	update.restart_to_apply()

func wait_for(update: Node, states: Array) -> void:
	var deadline := Time.get_ticks_msec()+120000
	while not update.state in states and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame

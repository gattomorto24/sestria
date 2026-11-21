extends SceneTree
# Prova reale dell'aggiornatore desktop contro un server locale che imita le API delle release GitHub
# (vedi docs/releases.md). Variabili: SESTRIA_UPDATE_API, SESTRIA_UPDATE_RELEASES (solo build di sviluppo).
# Scarica il pacchetto contenuti, lo verifica e lo installa in user://updates/content; l'app esportata lo monta al riavvio.
const Updates = preload("res://scripts/desktop_updater.gd")
const Content = preload("res://scripts/content_pack.gd")
var errors := 0
func check(ok: bool, note: String) -> void:
	if not ok:
		errors+=1
		push_error(note)
func wait_for(update: Node, states: Array) -> void:
	var deadline := Time.get_ticks_msec()+120000
	while not update.state in states and Time.get_ticks_msec()<deadline:
		await process_frame
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	if "--mount" in OS.get_cmdline_user_args():
		# come boot.gd all'avvio dell'app: monta il pacchetto installato prima di creare l'aggiornatore
		print("E2E montaggio: ",Content.apply_at_boot()," · ",Content.running_version())
	var update := Updates.new()
	root.add_child(update)
	await process_frame
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--pretend="):
			# Verifica reale contro GitHub da un computer di sviluppo: finge di essere una versione precedente.
			update.current_version = argument.trim_prefix("--pretend=")
			update.base_version = update.current_version
	print("E2E versione contenuti ",update.current_version," · base ",update.base_version," · API ",update.api)
	update.check_updates()
	await wait_for(update,["available","current","error","ready"])
	print("E2E verifica -> ",update.state," · ",update.release.get("mode","")," · ",update.message)
	if "--expect-package" in OS.get_cmdline_user_args():
		check(update.state=="available" and update.release.get("mode")=="package","Atteso il ripiego sul pacchetto completo")
		check(not update.fallback_reason.is_empty(),"Il ripiego spiega il motivo")
		print("E2E ripiego: ",update.fallback_reason)
	elif "--expect-current" in OS.get_cmdline_user_args():
		check(update.state=="current","Dopo l'aggiornamento non viene riproposto")
	else:
		check(update.state=="available" and update.release.get("mode")=="content","Atteso l'aggiornamento dei contenuti")
		if update.state=="available":
			update.download_update()
			await wait_for(update,["ready","error"])
			print("E2E download -> ",update.state," · ",update.message)
			check(update.state=="ready","Download e verifica riusciti")
			check(Content.staged_version()==str(update.release.version),"Aggiornamento in attesa di riavvio")
			# una nuova verifica non lo scarica di nuovo
			update.check_updates()
			await wait_for(update,["available","current","error","ready"])
			check(update.state=="ready","Nessun nuovo download dello stesso aggiornamento")
	print("E2E AGGIORNATORE | errori %d" % errors)
	quit(1 if errors else 0)

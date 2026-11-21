extends SceneTree
# Controlla un set di file della release prima di pubblicarlo: godot --headless --script res://tests/content_release_check.gd -- <cartella> <versione>
# Verifica manifest (firma con la chiave pubblica incorporata nell'app), nome, dimensione, SHA-256 e motore di ogni pacchetto.
const Content = preload("res://scripts/content_pack.gd")
func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size()<2:
		push_error("Uso: -- <cartella> <versione>")
		quit(2)
		return
	var folder: String = arguments[0]
	var version: String = arguments[1]
	var problems: Array[String] = []
	var text := FileAccess.get_file_as_string(folder.path_join(Content.manifest_name(version)))
	var verdict := Content.verify_manifest(text)
	if not verdict.ok:
		push_error("MANIFEST: "+str(verdict.error))
		quit(1)
		return
	var manifest: Dictionary = verdict.manifest
	if str(manifest.version)!=version:
		problems.append("versione del manifest %s ≠ %s" % [manifest.version,version])
	if str(manifest.engine)!=Content.engine_label():
		problems.append("motore del manifest %s ≠ %s" % [manifest.engine,Content.engine_label()])
	for key in ["macos","windows","android"]:
		var entry := Content.pack_entry(manifest,key)
		if entry.is_empty():
			problems.append("manca il pacchetto "+key)
			continue
		var path := folder.path_join(str(entry.name))
		if entry.name!="Sestria-v%s-%s-content.pck" % [version,key]:
			problems.append("nome inatteso "+str(entry.name))
		elif not FileAccess.file_exists(path) or FileAccess.get_file_as_bytes(path).size()!=int(entry.size):
			problems.append("dimensione errata o file mancante: "+str(entry.name))
		elif FileAccess.get_sha256(path)!=str(entry.sha256):
			problems.append("SHA-256 errata: "+str(entry.name))
		elif Content.pack_engine(path)!=str(manifest.engine):
			problems.append("intestazione del motore errata: "+str(entry.name))
		else:
			print("OK %s · %.1f MB · min_base %s · %s" % [entry.name,float(entry.size)/1048576.0,entry.min_base,str(entry.sha256).left(12)])
	for problem in problems:
		push_error(problem)
	print("RELEASE CONTENUTI %s | %s" % [version,"valida: firma e pacchetti verificati" if problems.is_empty() else "NON valida"])
	quit(1 if problems else 0)

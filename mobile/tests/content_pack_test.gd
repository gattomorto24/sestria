extends SceneTree
# Pacchetto contenuti: manifest firmato, compatibilità, installazione atomica, avvio con rollback e montaggio reale di un .pck.
const Content = preload("res://scripts/content_pack.gd")
const SECRET_DIR := "user://content_pack_test"
var errors := 0
var checks := 0
var crypto := Crypto.new()
var key: CryptoKey

func check(ok: bool, note: String) -> void:
	checks+=1
	if not ok:
		errors+=1
		push_error(note)

func _initialize() -> void:
	call_deferred("run")

func signed(body: String, signer: CryptoKey) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(body.to_utf8_buffer())
	return body+"\n"+Marshalls.raw_to_base64(crypto.sign(HashingContext.HASH_SHA256,hashing.finish(),signer))+"\n"

func make_pack(path: String, version: String, extra := "") -> void:
	var source := path+".src"
	var file := FileAccess.open(source,FileAccess.WRITE)
	file.store_string(JSON.stringify({"content":version,"min_base":"4.5"})+extra)
	file.close()
	var packer := PCKPacker.new()
	packer.pck_start(path)
	packer.add_file("res://content.json",source)
	packer.flush()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(source))

func manifest_for(version: String, pack: String, min_base := "4.5", engine := Content.engine_label()) -> Dictionary:
	return {"schema":1,"version":version,"engine":engine,"packs":{Content.platform_key():{"name":"Sestria-v%s-%s-content.pck" % [version,Content.platform_key()],"size":FileAccess.open(pack,FileAccess.READ).get_length(),"sha256":FileAccess.get_sha256(pack),"min_base":min_base}}}

func reset_dir() -> void:
	var folder := DirAccess.open(Content.dir)
	if folder:
		for name in folder.get_files():
			folder.remove(name)

func run() -> void:
	var BUILTIN := Content.builtin_version()
	Content.dir = SECRET_DIR
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SECRET_DIR))
	reset_dir()
	# versioni e informazioni integrate
	check(Content.newer("4.6","4.5") and not Content.newer("4.5","4.5") and not Content.newer("4.4","4.5") and not Content.newer("evil","4.5"),"Confronto delle versioni")
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	check(presets.contains('version/name="%s"' % Content.running_version()),"content.json coincide con la versione dell'APK (aggiornala a ogni release)")
	check(Content.base_version()==Content.builtin_version(),"Versione base dell'app (senza plugin nativo)")
	var embedded := CryptoKey.new()
	check(embedded.load_from_string(Content.PUBLIC_KEY_PEM,true)==OK,"Chiave pubblica incorporata valida")
	# manifest firmato
	key = crypto.generate_rsa(2048)
	var public_pem := key.save_to_string(true)
	var body := JSON.stringify({"schema":1,"version":"9.9","engine":Content.engine_label(),"packs":{"macos":{"name":"Sestria-v9.9-macos-content.pck","size":1000,"sha256":"a".repeat(64),"min_base":"4.5"}}})
	var good := signed(body,key)
	check(Content.verify_manifest(good,public_pem).ok,"Manifest firmato accettato")
	check(not Content.verify_manifest(good).ok,"Manifest firmato con un'altra chiave respinto (chiave incorporata)")
	check(not Content.verify_manifest(good.replace("9.9","9.8"),public_pem).ok,"Manifest manomesso respinto")
	check(not Content.verify_manifest(body,public_pem).ok and not Content.verify_manifest(body+"\n",public_pem).ok and not Content.verify_manifest("",public_pem).ok,"Manifest senza firma respinto")
	check(not Content.verify_manifest(body+"\nAAAA",public_pem).ok,"Firma non valida respinta")
	check(not Content.verify_manifest(signed('{"schema":2,"version":"9.9","packs":{}}',key),public_pem).ok,"Schema sconosciuto respinto")
	var manifest: Dictionary = Content.verify_manifest(good,public_pem).manifest
	check(Content.pack_entry(manifest,"macos").get("name","")=="Sestria-v9.9-macos-content.pck","Voce del pacchetto per piattaforma")
	check(Content.pack_entry(manifest,"windows").is_empty(),"Nessun pacchetto per una piattaforma assente")
	for mutation in [["name","../evil.pck"],["name","Sestria-v9.9-macos-content.pck/../x"],["name","x.pck"],["size",0],["size",Content.MAX_PACK+1],["sha256","bad"],["min_base","x"]]:
		var bad: Dictionary = manifest.duplicate(true)
		bad.packs.macos[mutation[0]] = mutation[1]
		check(Content.pack_entry(bad,"macos").is_empty(),"Voce non valida respinta "+str(mutation))
	# compatibilità
	var entry: Dictionary = Content.pack_entry(manifest,"macos")
	check(Content.incompatibility(manifest,entry,"4.5")=="","Compatibile con la base 4.5")
	var future: Dictionary = entry.duplicate()
	future.min_base = "4.7"
	check(Content.incompatibility(manifest,future,"4.5")!="","Richiede una base più recente: serve il pacchetto completo")
	check(Content.incompatibility(manifest,entry,"4.5","3.9")!="","Motore diverso: serve il pacchetto completo")
	# asset della release
	var info := {"assets":[{"name":"Sestria-v9.9-content.json","state":"uploaded","size":300,"digest":"sha256:"+"c".repeat(64),"browser_download_url":"https://github.com/o/r/releases/download/v9.9/Sestria-v9.9-content.json"}]}
	check(not Content.find_asset(info,Content.manifest_name("9.9"),"https://github.com/o/r/releases","v9.9").is_empty(),"Asset del manifest trovato")
	check(Content.find_asset(info,Content.manifest_name("9.9"),"https://github.com/altro/r/releases","v9.9").is_empty(),"Asset di un altro repository respinto")
	info.assets[0].state = "starter"
	check(Content.find_asset(info,Content.manifest_name("9.9"),"https://github.com/o/r/releases","v9.9").is_empty(),"Asset non completato respinto")
	# installazione
	var part := Content.part_path("Sestria-v9.9-%s-content.pck" % Content.platform_key())
	make_pack(part,"9.9")
	var real := manifest_for("9.9",part)
	var real_entry: Dictionary = Content.pack_entry(real)
	check(not real_entry.is_empty(),"Voce reale valida")
	check(Content.install_downloaded(part,real,real_entry,"f".repeat(64))!="" and not FileAccess.file_exists(part),"Digest GitHub diverso: pacchetto scartato")
	make_pack(part,"9.9")
	var bad_size := real_entry.duplicate()
	bad_size.size += 1
	check(Content.install_downloaded(part,real,bad_size)!="","Dimensione errata respinta")
	make_pack(part,"9.9")
	var bad_hash := real_entry.duplicate()
	bad_hash.sha256 = "0".repeat(64)
	check(Content.install_downloaded(part,real,bad_hash)!="" and Content.installed_record().is_empty(),"SHA-256 errata respinta, nessuno stato scritto")
	make_pack(part,"9.9")
	var wrong_engine: Dictionary = real.duplicate(true)
	wrong_engine.engine = "3.9"
	check(Content.install_downloaded(part,wrong_engine,real_entry)!="","Intestazione del motore diversa respinta")
	make_pack(part,"4.5")
	var old := manifest_for("4.5",part)
	check(Content.install_downloaded(part,old,Content.pack_entry(old))!="","Versione già inclusa nell'app respinta")
	make_pack(part,"9.9")
	check(Content.install_downloaded(part,real,real_entry,real_entry.sha256)=="","Pacchetto valido installato")
	check(Content.installed_record().status=="pending" and Content.staged_version()=="9.9","Installato, in attesa di riavvio")
	check(not FileAccess.file_exists(part),"File temporaneo rinominato (scrittura atomica)")
	var installed_file: String = SECRET_DIR.path_join(str(Content.installed_record().file))
	# 1) file corrotto: ignorato, cancellato, avvio non bloccato
	var original := FileAccess.get_file_as_bytes(installed_file)
	var corrupt := original.duplicate()
	corrupt[corrupt.size()-1] = (corrupt[corrupt.size()-1]+1)%256
	var file := FileAccess.open(installed_file,FileAccess.WRITE)
	file.store_buffer(corrupt)
	file.close()
	check(Content.apply_at_boot()=="discarded" and not FileAccess.file_exists(installed_file) and Content.installed_record().is_empty(),"Pacchetto corrotto scartato senza bloccare l'avvio")
	check("9.9" in Content.rejected_versions(),"Versione corrotta ricordata come respinta")
	# 2) file troncato e file assente
	file = FileAccess.open(installed_file,FileAccess.WRITE)
	file.store_buffer(original.slice(0,100))
	file.close()
	Content.write_state({"installed":{"version":"9.9","file":installed_file.get_file(),"sha256":real_entry.sha256,"size":original.size(),"min_base":"4.5","status":"confirmed","boots":0}})
	check(Content.apply_at_boot()=="discarded","Pacchetto troncato scartato")
	Content.write_state({"installed":{"version":"9.9","file":"manca.pck","sha256":real_entry.sha256,"size":10,"min_base":"4.5","status":"confirmed","boots":0}})
	check(Content.apply_at_boot()=="discarded","Pacchetto assente: si usano i file integrati")
	# 3) non più necessario o richiede una base più recente
	reset_dir()
	file = FileAccess.open(installed_file,FileAccess.WRITE)
	file.store_buffer(original)
	file.close()
	Content.write_state({"installed":{"version":"4.5","file":installed_file.get_file(),"sha256":real_entry.sha256,"size":original.size(),"min_base":"4.5","status":"confirmed","boots":0}})
	check(Content.apply_at_boot()=="discarded" and Content.rejected_versions().is_empty(),"Pacchetto non più recente dell'app cancellato senza essere respinto")
	file = FileAccess.open(installed_file,FileAccess.WRITE)
	file.store_buffer(original)
	file.close()
	Content.write_state({"installed":{"version":"9.9","file":installed_file.get_file(),"sha256":real_entry.sha256,"size":original.size(),"min_base":"99.0","status":"confirmed","boots":0}})
	check(Content.apply_at_boot()=="discarded","Base troppo vecchia: pacchetto scartato")
	# 4) rollback: l'avvio precedente non è stato confermato
	reset_dir()
	file = FileAccess.open(installed_file,FileAccess.WRITE)
	file.store_buffer(original)
	file.close()
	Content.write_state({"installed":{"version":"9.9","file":installed_file.get_file(),"sha256":real_entry.sha256,"size":original.size(),"min_base":"4.5","status":"pending","boots":1}})
	check(Content.apply_at_boot()=="discarded" and Content.running_version()==Content.builtin_version() and "9.9" in Content.rejected_versions(),"Avvio non confermato: rollback ai file integrati")
	# 5) avvio normale: il pacchetto si monta davvero, si conferma e non viene ripetuto
	reset_dir()
	file = FileAccess.open(installed_file,FileAccess.WRITE)
	file.store_buffer(original)
	file.close()
	Content.write_state({"installed":{"version":"9.9","file":installed_file.get_file(),"sha256":real_entry.sha256,"size":original.size(),"min_base":"4.5","status":"pending","boots":0}})
	check(Content.staged_version()=="9.9","Aggiornamento in attesa riconosciuto")
	check(Content.apply_at_boot(true)=="none" and Content.running_version()==BUILTIN,"Opzione --no-content-pack: nessun montaggio")
	check(Content.apply_at_boot()=="applied","Pacchetto montato all'avvio")
	check(Content.running_version()=="9.9" and Content.builtin_version()==BUILTIN,"Il pacchetto sostituisce i file integrati (versione in esecuzione 9.9, integrata 4.5)")
	check(Content.installed_record().boots==1 and Content.staged_version()=="","Avvio registrato; non più in attesa")
	Content.confirm_boot()
	check(Content.installed_record().status=="confirmed","Avvio confermato")
	check(Content.apply_at_boot()=="applied","Riavvio successivo: ancora montato (aggiornamento non ripetuto)")
	reset_dir()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SECRET_DIR))
	check(Content.macos_bundle("/Applications/Sestria.app/Contents/MacOS/Sestria")=="/Applications/Sestria.app" and Content.macos_bundle("/tmp/godot")=="","Percorso del bundle .app per il riavvio")
	print("PACCHETTO CONTENUTI | %d controlli: firma, compatibilità, integrità, installazione atomica, rollback e montaggio | errori %d" % [checks,errors])
	quit(1 if errors else 0)

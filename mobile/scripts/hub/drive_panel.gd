extends RefCounted
# Pannello «Salvataggio su Google Drive»: collega l'account con il codice, mostra lo stato e permette di sincronizzare o scollegare.
const Kit = preload("res://scripts/hub/kit.gd")

static func build(hub: Control, parent: Node) -> void:
	var game: Node3D = hub.game
	var drive: Node = game.drive
	Kit.title(parent,"Google Drive",22)
	if drive == null or not drive.available():
		var web: bool = OS.has_feature("web")
		Kit.paragraph(parent,"Su questo sito il salvataggio su Google Drive arriva con una prossima versione. Su Mac, Windows e Android è già disponibile: collega lì il tuo account e ritroverai i dati." if web else "Il salvataggio su Google Drive non è configurato in questa versione.",0.0,15,Kit.MUTED)
		return
	match drive.state:
		"signed_in":
			Kit.paragraph(parent,"Collegato come %s. Progressi, campagne, profilo, amici e statistiche si salvano da soli su Drive (in un file «SESTRIA - salvataggio») e arrivano su tutti i tuoi dispositivi." % ((str(drive.account.get("name","")) + " · " + str(drive.account.get("email",""))).strip_edges()),0.0,15,Kit.TEXT)
			if not drive.last_sync.is_empty():
				Kit.label(parent,"Ultima sincronizzazione · "+drive.last_sync,13,Kit.DIM)
			Kit.label(parent,str(drive.message),14,Kit.MOSS if str(drive.message).begins_with("Sincronizzato") else Kit.MUTED,false,600)
			var line := Kit.row(parent,10)
			var sync_button := Kit.button(line,"Sincronizza ora",func():drive.sync(true),"primary")
			sync_button.disabled = drive.busy
			Kit.button(line,"Scollega",func():
				hub.confirm("Scollegare Google Drive?","SESTRIA smette di salvare su Drive. I dati restano su questo dispositivo e su Drive.","Scollega",func():
					drive.sign_out()),"ghost")
		"code":
			Kit.paragraph(parent,"1. Apri la pagina di Google. 2. Accedi e digita questo codice. 3. Torna qui: il collegamento si completa da solo.",0.0,15,Kit.MUTED)
			var box := Kit.panel(parent,"parchment",16,0)
			var code := Kit.label(box,str(drive.user_code),30,Kit.INK,false,800)
			code.remove_theme_color_override("font_shadow_color")
			code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			Kit.label(parent,str(drive.verification_url),15,Kit.EMBER_LIGHT,false,600)
			var line := Kit.row(parent,10)
			Kit.button(line,"Apri la pagina di Google",func():OS.shell_open(str(drive.verification_url)),"primary")
			Kit.button(line,"Copia il codice",func():
				DisplayServer.clipboard_set(str(drive.user_code))
				hub.toast("Codice copiato"),"secondary")
			Kit.button(line,"Annulla",func():drive.cancel(),"ghost")
		_:
			Kit.paragraph(parent,"Collega il tuo account Google per salvare progressi, campagne, profilo e amici su Drive e ritrovarli su ogni dispositivo. SESTRIA vede solo il file che crea lei, non gli altri tuoi file.",0.0,15,Kit.MUTED)
			if not str(drive.message).is_empty():
				Kit.label(parent,str(drive.message),14,Kit.EMBER_LIGHT,false,600)
			var connect := Kit.button(parent,"ACCEDI CON GOOGLE",func():drive.start_sign_in(),"primary",280)
			connect.disabled = drive.busy

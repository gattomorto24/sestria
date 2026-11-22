extends RefCounted
# Scheda Progressi (il vecchio Pass): livello, XP, punti, potenziamenti acquistabili e statistiche di gioco.
const Kit = preload("res://scripts/hub/kit.gd")
const Rules = preload("res://scripts/rules.gd")

static func build(hub: Control, parent: VBoxContainer) -> void:
	var game: Node3D = hub.game
	var progression: RefCounted = game.progression
	var area := Kit.scroll(parent,16)
	var level: int = progression.level()
	var hero := Kit.panel(area,"glass",24,26)
	var hero_column := Kit.column(hero,10)
	var head := Kit.row(hero_column,14)
	var level_box := Kit.column(head,0)
	level_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Kit.label(level_box,"LIVELLO",12,Kit.DIM,false,700)
	Kit.label(level_box,str(level),46,Kit.EMBER_LIGHT,false,700)
	var points_box := Kit.column(head,0)
	Kit.label(points_box,"PUNTI DISPONIBILI",12,Kit.DIM,false,700)
	Kit.label(points_box,str(progression.points()),46,Kit.MINT,false,700)
	var xp: int = progression.xp_in_level()
	var needed: int = progression.xp_required(level)
	Kit.meter(hero_column,xp,needed,14)
	Kit.label(hero_column,"%s / %s XP al prossimo livello · +2 punti ad ogni avanzamento" % [Kit.format_number(xp),Kit.format_number(needed)],14,Kit.MUTED)
	if hub.page_state.has("note"):
		Kit.label(hero_column,str(hub.page_state.note),15,Kit.MINT,false,600)
	Kit.label(area,"POTENZIAMENTI",13,Kit.DIM,false,700)
	Kit.paragraph(area,"Valgono nelle campagne e nelle partite al volo, non nel multigiocatore. Ogni grado resta attivo e puoi riassegnare tutti i punti gratis.",0.0,14,Kit.MUTED)
	var grid := GridContainer.new()
	grid.columns = 1 if hub.portrait else 2
	grid.add_theme_constant_override("h_separation",roundi(Kit.scale(14)))
	grid.add_theme_constant_override("v_separation",roundi(Kit.scale(14)))
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area.add_child(grid)
	for id: String in progression.ORDER:
		upgrade_card(hub,grid,progression,id)
	if progression.spent_points() > 0:
		Kit.button(area,"Riassegna i punti (%d)" % progression.spent_points(),func():
			hub.confirm("Riassegnare i punti?","Restituisci i %d punti spesi e azzeri i gradi. Livello e XP restano invariati." % progression.spent_points(),"Restituisci",func():
				var error: Error = progression.refund()
				hub.navigate("progress",{"note":"Punti restituiti. Scegli il tuo nuovo percorso." if error == OK else "Riassegnazione non salvata."})),"secondary")
	Kit.label(area,"IL BOT DIVENTA PIÙ FORTE",13,Kit.DIM,false,700)
	Kit.paragraph(area,"Livello 4: bot almeno Guerriero, +1 gettone iniziale. Livello 8: almeno Maestro, +2 gettoni. Livello 12: Maestro con più analisi tattica, +3 gettoni. XP per vittoria: 100 / 130 / 160 secondo la sfida, +10 per ogni soglia raggiunta, più Esperienza sul campo e il moltiplicatore della campagna.",0.0,14,Kit.MUTED)
	build_statistics(hub,area)

static func upgrade_card(hub: Control, parent: Node, progression: RefCounted, id: String) -> void:
	var upgrade: Dictionary = progression.UPGRADES[id]
	var rank: int = progression.rank_of(id)
	var total: int = upgrade.costs.size()
	var card := Kit.panel(parent,"raised",18,20)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := Kit.column(card,8)
	var head := Kit.row(column,10)
	Kit.chip(head,str(upgrade.rune),Kit.EMBER)
	var name := Kit.label(head,str(upgrade.name),18,Kit.TEXT,false,600)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pips := Kit.row(head,4)
	for index in total:
		var dot := ColorRect.new()
		dot.color = Kit.EMBER if index < rank else Kit.HIGH
		dot.custom_minimum_size = Vector2(Kit.scale(16),Kit.scale(6))
		pips.add_child(dot)
	Kit.paragraph(column,str(upgrade.description),0.0,14,Kit.MUTED)
	if rank >= total:
		Kit.label(column,"Tutti i gradi acquisiti",14,Kit.MINT,false,600)
		return
	var status: String = progression.purchase_status(id)
	Kit.label(column,"Prossimo grado · %d punti · livello %d" % [upgrade.costs[rank],upgrade.levels[rank]],13,Kit.DIM)
	var buy := Kit.button(column,"Acquista · %d punti" % upgrade.costs[rank] if status.is_empty() else status,func():
		var error: Error = progression.purchase(id)
		hub.navigate("progress",{"note":"%s · grado %d acquisito. Attivo dalla prossima partita." % [upgrade.name,progression.rank_of(id)] if error == OK else "Acquisto non salvato. Nessun punto speso."}),"primary" if status.is_empty() else "secondary")
	buy.disabled = not status.is_empty()

static func build_statistics(hub: Control, parent: Node) -> void:
	var game: Node3D = hub.game
	var data: Dictionary = game.stats_store.data
	Kit.label(parent,"LE TUE STATISTICHE",13,Kit.DIM,false,700)
	var grid := GridContainer.new()
	grid.columns = 2 if hub.portrait else 5
	grid.add_theme_constant_override("h_separation",roundi(Kit.scale(10)))
	grid.add_theme_constant_override("v_separation",roundi(Kit.scale(10)))
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(grid)
	for pair in [["Partite",str(int(data.played))],["Vittorie",str(int(data.wins))],["% vittorie","%d%%" % game.stats_store.win_rate()],["Serie migliore",str(int(data.best_streak))],["Lanci",str(int(data.rolls))],["Danni inflitti",str(int(data.damage_dealt))],["Danni subiti",str(int(data.damage_taken))],["Attacchi parati",str(int(data.blocked))],["Gettoni rubati",str(int(data.tokens_stolen))],["Tempo di gioco","%d min" % (int(data.seconds)/60)]]:
		var tile := Kit.panel(grid,"raised",12,14)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var column := Kit.column(tile,2)
		Kit.label(column,pair[1],24,Kit.TEXT,false,700)
		Kit.label(column,pair[0],12,Kit.DIM,false,600)
	if not data.favors.is_empty():
		Kit.label(parent,"TATTICHE INVOCATE",13,Kit.DIM,false,700)
		var chips := HFlowContainer.new()
		chips.add_theme_constant_override("h_separation",roundi(Kit.scale(8)))
		chips.add_theme_constant_override("v_separation",roundi(Kit.scale(8)))
		parent.add_child(chips)
		for id in data.favors:
			Kit.chip(chips,"%s · %d" % [Rules.FAVOR[id][0] if Rules.FAVOR.has(id) else id,data.favors[id]],Kit.AZURE)
	Kit.label(parent,"ULTIME PARTITE",13,Kit.DIM,false,700)
	if data.history.is_empty():
		Kit.paragraph(parent,"La tua prima impresa deve ancora essere scritta.",0.0,14,Kit.MUTED)
	for entry in data.history.slice(0,10):
		var line := Kit.panel(parent,"raised",10,14)
		var row := Kit.row(line,12)
		Kit.chip(row,"VITTORIA" if entry.victory else "SCONFITTA",Kit.MINT if entry.victory else Kit.ROSE)
		var mode: String = {"lan":"LAN","online":"Online","hotseat":"Passa e gioca"}.get(str(entry.mode),"Bot")
		var text := Kit.label(row,"%s · %d manche · %d:%02d" % [mode,entry.rounds,int(entry.seconds)/60,int(entry.seconds)%60],14,Kit.MUTED)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL

extends RefCounted
# Scheda Campagna: elenco dei salvataggi, dettaglio, creazione di una nuova campagna (nome, sfida e dieci
# impostazioni) e «Partita al volo» contro il bot con premio XP.
const Kit = preload("res://scripts/hub/kit.gd")
const Store = preload("res://scripts/hub/campaign_store.gd")
const DIFFICULTY_TEXT := ["Per imparare il rituale: il bot sbaglia spesso.","Una sfida equilibrata.","Nessuna concessione: il bot calcola a fondo."]
const DIFFICULTY_COLORS := [Kit.MINT,Kit.EMBER,Kit.ROSE]
const DIFFICULTY_ICONS := ["I","II","III"]

static func build(hub: Control, parent: VBoxContainer) -> void:
	var state: Dictionary = hub.page_state
	if state.get("view","list") == "new":
		build_new(hub,parent)
	else:
		build_list(hub,parent)

# ---- Elenco e dettaglio ----

static func build_list(hub: Control, parent: VBoxContainer) -> void:
	var game: Node3D = hub.game
	var store: RefCounted = game.campaigns
	var state: Dictionary = hub.page_state
	var selected: String = str(state.get("selected",""))
	var items: Array = store.sorted()
	if selected != "quick" and (selected.is_empty() or store.find(selected) < 0):
		selected = str(items[0].id) if not items.is_empty() else "quick"
	var layout: BoxContainer = Kit.row(parent,18) if not hub.portrait else Kit.column(parent,12)
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left := Kit.column(layout,12)
	left.custom_minimum_size.x = 0.0 if hub.portrait else 410.0
	if hub.portrait:
		left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	else:
		left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Kit.label(left,"LE TUE CAMPAGNE",13,Kit.DIM,false,700)
	var list := Kit.scroll(left,10) if not hub.portrait else Kit.column(left,10)
	for entry in items:
		var tier := Store.tier_for(int(entry.chapter))
		var subtitle := "%s · capitolo %d · %d vittorie" % [Store.DIFFICULTIES[int(entry.difficulty)],int(entry.chapter),int(entry.wins)]
		Kit.card(list,str(entry.name),subtitle,selected == entry.id,func():hub.navigate("campaign",{"selected":entry.id}),DIFFICULTY_COLORS[int(entry.difficulty)])
	if items.size() < Store.MAX_CAMPAIGNS:
		Kit.card(list,"+  Nuova campagna","Scegli nome, sfida e dieci impostazioni.",false,func():
			hub.navigate("campaign",{"view":"new","draft":{"name":"Campagna %d" % (items.size()+1),"difficulty":game.difficulty,"settings":Store.default_settings()}}),Kit.AZURE)
	Kit.card(list,"⚡  Partita al volo","Una sfida contro il bot, con premio XP.",selected == "quick",func():hub.navigate("campaign",{"selected":"quick"}),Kit.VIOLET)
	var right := Kit.panel(layout,"wood",24,26)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var detail := Kit.scroll(right,14)
	if selected == "quick":
		build_quick(hub,detail)
	else:
		build_detail(hub,detail,store.campaigns[store.find(selected)])

static func stat_tile(parent: Node, caption: String, value: String, color := Kit.TEXT) -> void:
	var tile := Kit.panel(parent,"raised",12,14)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := Kit.column(tile,2)
	Kit.label(column,value,28,color,false,700)
	Kit.label(column,caption,12,Kit.DIM,false,600)

static func build_detail(hub: Control, parent: VBoxContainer, campaign: Dictionary) -> void:
	var game: Node3D = hub.game
	var setup: Dictionary = Store.match_setup(campaign)
	var header := Kit.row(parent,10)
	var title := Kit.label(header,str(campaign.name),Kit.scale(36)/Kit.scale(1.0),Kit.TEXT,true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Kit.chip(header,Store.DIFFICULTIES[int(campaign.difficulty)].to_upper(),DIFFICULTY_COLORS[int(campaign.difficulty)])
	Kit.label(parent,Store.chapter_title(int(campaign.chapter)),18,Kit.EMBER_LIGHT,false,500)
	Kit.paragraph(parent,"Avversario: bot di livello %d · gettoni iniziali %d contro %d · premio XP ×%.2f" % [int(setup.ai_level)+1,int(setup.player_gold),int(setup.enemy_gold),Store.xp_multiplier(campaign.settings)],0.0,15,Kit.MUTED)
	var tiles: Container = Kit.row(parent,10) if not hub.portrait else GridContainer.new()
	if hub.portrait:
		(tiles as GridContainer).columns = 2
		parent.add_child(tiles)
	stat_tile(tiles,"VITTORIE",str(int(campaign.wins)),Kit.MINT)
	stat_tile(tiles,"SCONFITTE",str(int(campaign.losses)),Kit.ROSE)
	stat_tile(tiles,"SERIE",str(int(campaign.streak)),Kit.EMBER_LIGHT)
	stat_tile(tiles,"XP GUADAGNATI",Kit.format_number(int(campaign.xp)),Kit.AZURE)
	Kit.label(parent,"IMPOSTAZIONI",12,Kit.DIM,false,700)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation",roundi(Kit.scale(8)))
	chips.add_theme_constant_override("v_separation",roundi(Kit.scale(8)))
	parent.add_child(chips)
	for entry in Store.SETTINGS:
		var value: Variant = campaign.settings[entry.id]
		var label_text := ""
		for option in entry.options:
			if typeof(option[0]) == typeof(value) and option[0] == value:
				label_text = str(option[1])
		var changed: bool = value != entry.default
		Kit.chip(chips,"%s: %s" % [str(entry.name).replace("I tuoi ","").to_lower(),label_text],Kit.EMBER if changed else Kit.DIM)
	var actions := Kit.row(parent,10)
	var play := Kit.button(actions,"CONTINUA LA CAMPAGNA",func():game.start_campaign(str(campaign.id)),"primary",260)
	play.custom_minimum_size.y = Kit.scale(54)
	Kit.button(actions,"Tattiche",func():hub.show_tactics(),"secondary")
	Kit.button(actions,"Rinomina",func():rename(hub,campaign),"secondary")
	Kit.button(actions,"Elimina",func():
		hub.confirm("Eliminare la campagna?","«%s» e i suoi progressi verranno cancellati. L'XP già guadagnato resta tuo." % campaign.name,"Elimina",func():
			game.campaigns.remove(str(campaign.id))
			hub.navigate("campaign",{})),"danger")

static func rename(hub: Control, campaign: Dictionary) -> void:
	var body: VBoxContainer = hub.modal("Rinomina la campagna",460)
	var field := LineEdit.new()
	field.text = str(campaign.name)
	field.max_length = 24
	field.custom_minimum_size.y = Kit.scale(46)
	hub.style_field(field)
	body.add_child(field)
	var save := func():
		hub.game.campaigns.rename(str(campaign.id),field.text)
		hub.navigate("campaign",{"selected":campaign.id})
	field.text_submitted.connect(func(_t):save.call())
	Kit.button(body,"Salva",save,"primary")

static func build_quick(hub: Control, parent: VBoxContainer) -> void:
	var game: Node3D = hub.game
	Kit.label(parent,"Partita al volo",36,Kit.TEXT,true)
	Kit.paragraph(parent,"Una partita singola contro il bot, senza creare una campagna. Se vinci ottieni XP, che fanno salire il tuo livello e ti danno punti per i potenziamenti dei Progressi.",0.0,16,Kit.MUTED)
	Kit.label(parent,"SFIDA",12,Kit.DIM,false,700)
	var cards: BoxContainer = Kit.row(parent,10) if not hub.portrait else Kit.column(parent,10)
	for index in 3:
		var card := Kit.card(cards,Store.DIFFICULTIES[index],DIFFICULTY_TEXT[index],game.difficulty == index,func():
			game.difficulty = index
			game.save_settings()
			hub.navigate("campaign",{"selected":"quick"}),DIFFICULTY_COLORS[index],DIFFICULTY_ICONS[index])
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var run: Dictionary = game.progression.create_run(game.difficulty)
	Kit.paragraph(parent,"%s · avversario di livello %d · premio per la vittoria: %d XP" % [game.progression.TITLES[run.tier],int(run.ai_level)+1,game.progression.victory_xp(run)],0.0,15,Kit.EMBER_LIGHT)
	var line := Kit.row(parent,10)
	var play := Kit.button(line,"GIOCA ORA",func():game.start_quick(),"primary",240)
	play.custom_minimum_size.y = Kit.scale(54)
	Kit.button(line,"Tattiche",func():hub.show_tactics(),"secondary")

# ---- Nuova campagna ----

static func build_new(hub: Control, parent: VBoxContainer) -> void:
	var game: Node3D = hub.game
	var draft: Dictionary = hub.page_state.draft
	var multiplier := Store.xp_multiplier(draft.settings)
	var header: BoxContainer = Kit.row(parent,12) if not hub.portrait else Kit.column(parent,6)
	var top := Kit.row(header,12)
	Kit.button(top,"‹  Indietro",func():hub.navigate("campaign",{}),"ghost")
	var title := Kit.title(top,"Nuova campagna",30 if not hub.portrait else 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	Kit.chip(header if hub.portrait else top,"PREMIO XP ×%.2f" % multiplier,Kit.MOSS if multiplier >= 1.0 else Kit.EMBER)
	var holder: Control = parent
	if hub.portrait:
		holder = Kit.scroll(parent,12)
	var layout: BoxContainer = Kit.row(holder,18) if not hub.portrait else Kit.column(holder,12)
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left := Kit.panel(layout,"wood",22,24)
	left.custom_minimum_size.x = 0.0 if hub.portrait else 400.0
	var form := Kit.column(left,12)
	Kit.label(form,"NOME",12,Kit.DIM,false,700)
	var field := LineEdit.new()
	field.text = str(draft.name)
	field.max_length = 24
	field.custom_minimum_size.y = Kit.scale(48)
	hub.style_field(field)
	field.text_changed.connect(func(value):draft.name = value)
	form.add_child(field)
	Kit.label(form,"SFIDA",12,Kit.DIM,false,700)
	for index in 3:
		var card := Kit.card(form,Store.DIFFICULTIES[index],DIFFICULTY_TEXT[index],int(draft.difficulty) == index,func():
			draft.difficulty = index
			draft.name = field.text
			hub.navigate("campaign",{"view":"new","draft":draft}),DIFFICULTY_COLORS[index],DIFFICULTY_ICONS[index])
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not hub.portrait:
		Kit.spacer(form,true)
	var create := Kit.button(form,"CREA E INIZIA",func():
		var item: Dictionary = game.campaigns.create(field.text,int(draft.difficulty),draft.settings)
		if item.is_empty():
			hub.toast("Hai raggiunto il massimo di campagne.")
		else:
			game.start_campaign(str(item.id)),"primary")
	create.custom_minimum_size.y = Kit.scale(54)
	var right := Kit.panel(layout,"wood",22,24)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL if not hub.portrait else Control.SIZE_SHRINK_BEGIN
	var settings: VBoxContainer = Kit.scroll(right,12) if not hub.portrait else Kit.column(right,12)
	Kit.label(settings,"DIECI IMPOSTAZIONI",12,Kit.DIM,false,700)
	for entry in Store.SETTINGS:
		build_setting(hub,settings,entry,draft,field)

static func build_setting(hub: Control, parent: Node, entry: Dictionary, draft: Dictionary, field: LineEdit) -> void:
	var line := Kit.setting_row(parent,str(entry.name),str(entry.hint))
	var labels: Array = []
	var active := 0
	for index in entry.options.size():
		labels.append(entry.options[index][1])
		if typeof(entry.options[index][0]) == typeof(draft.settings[entry.id]) and entry.options[index][0] == draft.settings[entry.id]:
			active = index
	if hub.portrait:
		# in verticale la riga è su due livelli: titolo sopra, segmenti sotto
		line.get_parent().remove_child(line)
		var column := Kit.column(parent,6)
		column.add_child(line)
		Kit.segments(column,labels,active,func(index):change(hub,draft,entry,index,field))
	else:
		Kit.segments(line,labels,active,func(index):change(hub,draft,entry,index,field))
	Kit.divider(parent)

static func change(hub: Control, draft: Dictionary, entry: Dictionary, index: int, field: LineEdit) -> void:
	draft.settings[entry.id] = entry.options[index][0]
	draft.name = field.text
	hub.navigate("campaign",{"view":"new","draft":draft})

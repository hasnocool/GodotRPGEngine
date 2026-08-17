# ui/Main.gd
extends Control

const C_BG := Color("0b0f16")
const C_SURFACE := Color("151b26")
const C_SURFACE_2 := Color("1c2431")
const C_BORDER := Color("303b4c")
const C_TEXT := Color("e8edf4")
const C_MUTED := Color("8f9bad")
const C_ACCENT := Color("d6ad68")
const C_BLUE := Color("6bb7ff")
const C_GOOD := Color("66c995")
const C_BAD := Color("e46f61")

var page_root: Control
var toast_layer: VBoxContainer
var campaign_list: ItemList
var server_input: LineEdit
var game_world: WorldView
var inspector_box: VBoxContainer
var party_box: VBoxContainer
var event_log: RichTextLabel
var connection_label: Label
var world_status_label: Label
var selected_campaigns: Array = []
var character_catalog: Dictionary = {}
var hero_dialog: AcceptDialog
var hero_name: LineEdit
var hero_class: OptionButton
var hero_species: LineEdit
var hero_background: LineEdit
var hero_stats: Dictionary = {}
var hero_equipment: ItemList

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_apply_theme()
	_build_toast_layer()
	_connect_client_signals()
	_show_lobby()

func _connect_client_signals() -> void:
	RPGClient.campaigns_received.connect(_on_campaigns_received)
	RPGClient.campaign_created.connect(_on_campaign_created)
	RPGClient.state_received.connect(_on_state_received)
	RPGClient.event_received.connect(_on_event_received)
	RPGClient.characters_received.connect(_on_characters_received)
	RPGClient.character_catalog_received.connect(_on_character_catalog_received)
	RPGClient.character_created.connect(_on_character_created)
	RPGClient.request_failed.connect(_on_request_failed)
	RPGClient.connection_state_changed.connect(_on_connection_state_changed)
	AppState.selection_changed.connect(_on_selection_changed)
	AppState.player_changed.connect(_on_player_changed)

func _apply_theme() -> void:
	var theme := Theme.new()
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", C_TEXT)
	theme.set_color("font_color", "Button", C_TEXT)
	theme.set_color("font_color", "LineEdit", C_TEXT)
	theme.set_color("font_color", "OptionButton", C_TEXT)
	theme.set_color("font_color", "RichTextLabel", C_TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", C_MUTED)
	theme.set_stylebox("normal", "Button", _style(C_SURFACE_2, C_BORDER, 10))
	theme.set_stylebox("hover", "Button", _style(Color("263244"), C_ACCENT, 10))
	theme.set_stylebox("pressed", "Button", _style(Color("101722"), C_ACCENT, 10))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_stylebox("normal", "LineEdit", _style(Color("101621"), C_BORDER, 9))
	theme.set_stylebox("focus", "LineEdit", _style(Color("111925"), C_BLUE, 9))
	theme.set_stylebox("normal", "OptionButton", _style(Color("101621"), C_BORDER, 9))
	theme.set_stylebox("normal", "ItemList", _style(Color("0f151e"), C_BORDER, 10))
	theme.set_stylebox("panel", "PanelContainer", _style(C_SURFACE, C_BORDER, 12))
	theme.set_color("font_selected_color", "ItemList", C_TEXT)
	theme.set_color("font_hovered_color", "ItemList", C_TEXT)
	theme.set_color("guide_color", "ItemList", Color(0, 0, 0, 0))
	theme.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.45))
	theme.set_constant("outline_size", "Label", 0)
	self.theme = theme

func _style(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box

func _clear_page() -> void:
	if page_root and is_instance_valid(page_root):
		page_root.queue_free()
	page_root = Control.new()
	page_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(page_root)
	move_child(page_root, 0)

func _build_toast_layer() -> void:
	toast_layer = VBoxContainer.new()
	toast_layer.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	toast_layer.offset_left = -430
	toast_layer.offset_right = -24
	toast_layer.offset_top = 24
	toast_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast_layer)

func _toast(message: String, bad := false) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color("351b1e") if bad else Color("152b26"), C_BAD if bad else C_GOOD, 9))
	var label := Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)
	toast_layer.add_child(panel)
	var tween := create_tween()
	tween.tween_interval(4.0)
	tween.tween_property(panel, "modulate:a", 0.0, 0.35)
	tween.tween_callback(panel.queue_free)

func _show_lobby() -> void:
	RPGClient.disconnect_campaign()
	AppState.set_screen("lobby")
	_clear_page()
	var background := ColorRect.new()
	background.color = C_BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page_root.add_child(background)

	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", 72)
	outer.add_theme_constant_override("margin_right", 72)
	outer.add_theme_constant_override("margin_top", 54)
	outer.add_theme_constant_override("margin_bottom", 54)
	page_root.add_child(outer)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 46)
	outer.add_child(columns)

	var intro := VBoxContainer.new()
	intro.custom_minimum_size = Vector2(470, 0)
	intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intro.add_theme_constant_override("separation", 18)
	columns.add_child(intro)

	var eyebrow := Label.new()
	eyebrow.text = "AUTHORITATIVE TACTICAL RPG CLIENT"
	eyebrow.add_theme_color_override("font_color", C_ACCENT)
	eyebrow.add_theme_font_size_override("font_size", 14)
	intro.add_child(eyebrow)

	var title := Label.new()
	title.text = "Enter the world.\nShape the story."
	title.add_theme_font_size_override("font_size", 52)
	intro.add_child(title)

	var description := Label.new()
	description.text = "A modern Godot front end for your deterministic D&D RPG engine. Campaign state, rules, combat, movement, AI, progression and visibility remain authoritative on the server."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color", C_MUTED)
	description.add_theme_font_size_override("font_size", 18)
	description.custom_minimum_size.y = 100
	intro.add_child(description)

	var feature_panel := PanelContainer.new()
	feature_panel.add_theme_stylebox_override("panel", _style(Color("101722"), Color("273349"), 14))
	var feature_text := Label.new()
	feature_text.text = "TACTICAL MAP  •  LIVE EVENTS  •  HERO CREATOR\nMULTIPLAYER IDENTITY  •  RECONNECT  •  SERVER-DRIVEN RULES"
	feature_text.add_theme_color_override("font_color", Color("aab8ca"))
	feature_text.add_theme_font_size_override("font_size", 13)
	feature_panel.add_child(feature_text)
	intro.add_child(feature_panel)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(580, 0)
	card.add_theme_stylebox_override("panel", _style(Color("121924"), Color("334055"), 18))
	columns.add_child(card)
	var card_margin := MarginContainer.new()
	card_margin.add_theme_constant_override("margin_left", 24)
	card_margin.add_theme_constant_override("margin_right", 24)
	card_margin.add_theme_constant_override("margin_top", 24)
	card_margin.add_theme_constant_override("margin_bottom", 24)
	card.add_child(card_margin)
	var lobby := VBoxContainer.new()
	lobby.add_theme_constant_override("separation", 14)
	card_margin.add_child(lobby)

	var lobby_title := Label.new()
	lobby_title.text = "Campaign Library"
	lobby_title.add_theme_font_size_override("font_size", 28)
	lobby.add_child(lobby_title)

	var server_row := HBoxContainer.new()
	server_row.add_theme_constant_override("separation", 8)
	lobby.add_child(server_row)
	server_input = LineEdit.new()
	server_input.text = AppState.api_base
	server_input.placeholder_text = "http://127.0.0.1:8000"
	server_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	server_row.add_child(server_input)
	var refresh := _button("Refresh", false)
	refresh.pressed.connect(_refresh_campaigns)
	server_row.add_child(refresh)

	campaign_list = ItemList.new()
	campaign_list.custom_minimum_size = Vector2(0, 350)
	campaign_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	campaign_list.item_activated.connect(func(_index: int) -> void: _play_selected_campaign())
	lobby.add_child(campaign_list)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	lobby.add_child(actions)
	var create := _button("＋ New Campaign", false)
	create.pressed.connect(_show_campaign_create_dialog)
	actions.add_child(create)
	var heroes := _button("Hero Creator", false)
	heroes.pressed.connect(_open_hero_for_selected_campaign)
	actions.add_child(heroes)
	var play := _button("Play Campaign  →", true)
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play.pressed.connect(_play_selected_campaign)
	actions.add_child(play)

	var identity := Label.new()
	identity.text = "Client identity: %s" % (AppState.client_id if not AppState.client_id.is_empty() else "assigned on campaign creation/join")
	identity.add_theme_color_override("font_color", C_MUTED)
	identity.add_theme_font_size_override("font_size", 12)
	lobby.add_child(identity)

	_refresh_campaigns()

func _button(text_value: String, accent := false) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size.y = 44
	if accent:
		button.add_theme_stylebox_override("normal", _style(Color("8a6732"), Color("e4c17c"), 10))
		button.add_theme_stylebox_override("hover", _style(Color("a67b38"), Color("f0d79b"), 10))
		button.add_theme_color_override("font_color", Color("fff5df"))
	return button

func _refresh_campaigns() -> void:
	AppState.set_server_base(server_input.text if server_input else AppState.api_base)
	if campaign_list:
		campaign_list.clear()
		campaign_list.add_item("Loading campaigns…")
	RPGClient.list_campaigns()

func _on_campaigns_received(campaigns: Array) -> void:
	selected_campaigns = campaigns
	if not campaign_list:
		return
	campaign_list.clear()
	if campaigns.is_empty():
		campaign_list.add_item("No campaigns yet — create your first world")
		campaign_list.set_item_disabled(0, true)
		return
	for campaign in campaigns:
		if campaign is Dictionary:
			var id := str(campaign.get("id", campaign.get("campaign_id", "")))
			var name := str(campaign.get("name", id))
			var mode := str(campaign.get("time_mode", "hybrid")).replace("_", " ").capitalize()
			var index := campaign_list.add_item("%s\n%s  •  %s" % [name, mode, id.left(12)])
			campaign_list.set_item_metadata(index, {"id": id, "name": name})

func _selected_campaign() -> Dictionary:
	if not campaign_list:
		return {}
	var indexes := campaign_list.get_selected_items()
	if indexes.is_empty():
		if campaign_list.item_count > 0 and not campaign_list.is_item_disabled(0):
			campaign_list.select(0)
			indexes = PackedInt32Array([0])
		else:
			return {}
	var metadata: Variant = campaign_list.get_item_metadata(indexes[0])
	return metadata if metadata is Dictionary else {}

func _show_campaign_create_dialog() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Create Campaign"
	dialog.ok_button_text = "Create World"
	var form := VBoxContainer.new()
	form.custom_minimum_size = Vector2(430, 140)
	var name := LineEdit.new()
	name.placeholder_text = "Campaign name"
	name.text = "New Adventure"
	form.add_child(name)
	var mode := OptionButton.new()
	for value in ["hybrid", "turn_based", "timed_turn_based", "real_time", "real_time_with_pause"]:
		mode.add_item(value.replace("_", " ").capitalize())
		mode.set_item_metadata(mode.item_count - 1, value)
	form.add_child(mode)
	dialog.add_child(form)
	page_root.add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		var selected_mode := str(mode.get_item_metadata(mode.selected))
		RPGClient.create_campaign(name.text.strip_edges(), selected_mode)
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _on_campaign_created(campaign: Dictionary) -> void:
	_toast("Campaign created")
	var id := str(campaign.get("id", campaign.get("campaign_id", AppState.campaign_id)))
	var name := str(campaign.get("name", AppState.campaign_name))
	if not id.is_empty():
		AppState.set_campaign(id, name)
		RPGClient.get_character_catalog(id)
		_open_hero_creator()

func _open_hero_for_selected_campaign() -> void:
	var selected := _selected_campaign()
	if selected.is_empty():
		_toast("Select a campaign first", true)
		return
	AppState.set_campaign(str(selected.id), str(selected.name))
	RPGClient.get_character_catalog(AppState.campaign_id)

func _on_character_catalog_received(catalog: Dictionary) -> void:
	character_catalog = catalog
	_open_hero_creator()

func _open_hero_creator() -> void:
	if hero_dialog and is_instance_valid(hero_dialog):
		hero_dialog.queue_free()
	hero_dialog = AcceptDialog.new()
	hero_dialog.title = "Create Character / Hero"
	hero_dialog.ok_button_text = "Create Hero"
	hero_dialog.dialog_hide_on_ok = false
	hero_dialog.min_size = Vector2i(760, 650)
	page_root.add_child(hero_dialog)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(720, 560)
	hero_dialog.add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 12)
	scroll.add_child(form)

	var heading := Label.new()
	heading.text = "Forge a hero for %s" % (AppState.campaign_name if not AppState.campaign_name.is_empty() else "this campaign")
	heading.add_theme_font_size_override("font_size", 26)
	form.add_child(heading)
	var note := Label.new()
	note.text = "Classes and starting equipment are loaded from the campaign's active lifecycle catalog. The engine validates and persists the final build."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", C_MUTED)
	form.add_child(note)

	hero_name = _labeled_line(form, "Name", "Arden")
	hero_class = OptionButton.new()
	var classes: Dictionary = character_catalog.get("classes", {})
	for class_id in classes:
		var class_data: Dictionary = classes[class_id]
		hero_class.add_item(str(class_data.get("name", class_id)))
		hero_class.set_item_metadata(hero_class.item_count - 1, str(class_id))
	if hero_class.item_count == 0:
		hero_class.add_item("No classes exposed by lifecycle")
		hero_class.disabled = true
	_add_labeled_control(form, "Class", hero_class)
	hero_species = _labeled_line(form, "Species / Ancestry ID", "")
	hero_background = _labeled_line(form, "Background ID", "")

	var stats_title := Label.new()
	stats_title.text = "Ability Scores"
	stats_title.add_theme_font_size_override("font_size", 19)
	form.add_child(stats_title)
	var stat_grid := GridContainer.new()
	stat_grid.columns = 3
	stat_grid.add_theme_constant_override("h_separation", 12)
	stat_grid.add_theme_constant_override("v_separation", 10)
	form.add_child(stat_grid)
	hero_stats.clear()
	for stat in ["strength", "dexterity", "constitution", "intelligence", "wisdom", "charisma"]:
		var block := VBoxContainer.new()
		var label := Label.new()
		label.text = stat.left(3).to_upper()
		label.add_theme_color_override("font_color", C_MUTED)
		block.add_child(label)
		var spin := SpinBox.new()
		spin.min_value = 1
		spin.max_value = 40
		spin.value = 10
		spin.custom_minimum_size.x = 200
		block.add_child(spin)
		stat_grid.add_child(block)
		hero_stats[stat] = spin

	var equip_label := Label.new()
	equip_label.text = "Starting Equipment"
	equip_label.add_theme_font_size_override("font_size", 19)
	form.add_child(equip_label)
	hero_equipment = ItemList.new()
	hero_equipment.select_mode = ItemList.SELECT_MULTI
	hero_equipment.custom_minimum_size.y = 150
	form.add_child(hero_equipment)
	var equipment: Dictionary = character_catalog.get("equipment", {})
	for item_id in equipment:
		var data: Dictionary = equipment[item_id]
		var index := hero_equipment.add_item(str(data.get("name", item_id)))
		hero_equipment.set_item_metadata(index, str(item_id))

	hero_dialog.confirmed.connect(_submit_hero)
	hero_dialog.popup_centered_ratio(0.75)

func _labeled_line(parent: VBoxContainer, caption: String, placeholder: String) -> LineEdit:
	var line := LineEdit.new()
	line.placeholder_text = placeholder
	_add_labeled_control(parent, caption, line)
	return line

func _add_labeled_control(parent: VBoxContainer, caption: String, control: Control) -> void:
	var label := Label.new()
	label.text = caption
	label.add_theme_color_override("font_color", C_MUTED)
	parent.add_child(label)
	parent.add_child(control)

func _submit_hero() -> void:
	if hero_name.text.strip_edges().is_empty() or hero_class.disabled:
		_toast("Hero needs a name and an available class", true)
		return
	var stats := {}
	for stat in hero_stats:
		stats[stat] = int((hero_stats[stat] as SpinBox).value)
	var equipment: Array = []
	for index in hero_equipment.get_selected_items():
		equipment.append(str(hero_equipment.get_item_metadata(index)))
	var build := {
		"name": hero_name.text.strip_edges(),
		"class_id": str(hero_class.get_item_metadata(hero_class.selected)),
		"owner_id": AppState.client_id if not AppState.client_id.is_empty() else null,
		"controller": "human",
		"species_id": hero_species.text.strip_edges() if not hero_species.text.strip_edges().is_empty() else null,
		"background_id": hero_background.text.strip_edges() if not hero_background.text.strip_edges().is_empty() else null,
		"stats": stats,
		"starting_level": 1,
		"starting_xp": 0,
		"starting_equipment": equipment,
		"tags": ["hero"],
	}
	RPGClient.create_character(build)

func _on_character_created(payload: Dictionary) -> void:
	var character: Dictionary = payload.get("character", payload)
	var actor_id := str(character.get("id", ""))
	if not actor_id.is_empty():
		AppState.set_player_actor(actor_id)
	if hero_dialog and is_instance_valid(hero_dialog):
		hero_dialog.hide()
	_toast("Hero created: %s" % str(character.get("name", "Hero")))
	if AppState.current_screen == "lobby":
		_show_game()
		RPGClient.connect_campaign(AppState.campaign_id, AppState.client_id)

func _play_selected_campaign() -> void:
	var selected := _selected_campaign()
	if selected.is_empty():
		_toast("Select a campaign to play", true)
		return
	AppState.set_campaign(str(selected.id), str(selected.name))
	_show_game()
	RPGClient.connect_campaign(AppState.campaign_id, AppState.client_id)
	RPGClient.list_characters(AppState.campaign_id)

func _show_game() -> void:
	AppState.set_screen("game")
	_clear_page()
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page_root.add_child(bg)

	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page_root.add_child(layout)
	layout.add_child(_build_top_bar())

	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 1)
	layout.add_child(content)
	content.add_child(_build_left_rail())
	content.add_child(_build_center_game())
	content.add_child(_build_right_rail())

func _build_top_bar() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 64
	panel.add_theme_stylebox_override("panel", _style(Color("101620"), Color("273245"), 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	var back := _button("← Campaigns", false)
	back.pressed.connect(_show_lobby)
	row.add_child(back)
	var title := Label.new()
	title.text = AppState.campaign_name if not AppState.campaign_name.is_empty() else AppState.campaign_id
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	world_status_label = Label.new()
	world_status_label.text = "Waiting for world state…"
	world_status_label.add_theme_color_override("font_color", C_MUTED)
	row.add_child(world_status_label)
	connection_label = Label.new()
	connection_label.text = "● CONNECTING"
	connection_label.add_theme_color_override("font_color", C_ACCENT)
	row.add_child(connection_label)
	return panel

func _build_left_rail() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 265
	panel.add_theme_stylebox_override("panel", _style(Color("111721"), Color("273245"), 0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var title := Label.new()
	title.text = "PARTY"
	title.add_theme_color_override("font_color", C_ACCENT)
	title.add_theme_font_size_override("font_size", 13)
	box.add_child(title)
	party_box = VBoxContainer.new()
	party_box.add_theme_constant_override("separation", 8)
	box.add_child(party_box)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var hero := _button("Character / Hero", false)
	hero.pressed.connect(func() -> void: RPGClient.get_character_catalog(AppState.campaign_id))
	box.add_child(hero)
	var center := _button("Center on Hero", false)
	center.pressed.connect(func() -> void:
		if game_world: game_world.center_on_player()
	)
	box.add_child(center)
	return panel

func _build_center_game() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	game_world = WorldView.new()
	game_world.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game_world.size_flags_vertical = Control.SIZE_EXPAND_FILL
	game_world.entity_selected.connect(func(entity_id: String) -> void: AppState.set_selected_entity(entity_id))
	game_world.command_requested.connect(_send_game_command)
	box.add_child(game_world)
	box.add_child(_build_hotbar())
	return box

func _build_hotbar() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 86
	panel.add_theme_stylebox_override("panel", _style(Color("0e141d"), Color("293548"), 0))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var attack := _hotbar_button("1", "Attack")
	attack.pressed.connect(_attack_selected)
	row.add_child(attack)
	var interact := _hotbar_button("E", "Interact")
	interact.pressed.connect(_interact_selected)
	row.add_child(interact)
	var wait := _hotbar_button("Space", "Wait")
	wait.pressed.connect(_wait_turn)
	row.add_child(wait)
	var inspect := _hotbar_button("C", "Hero")
	inspect.pressed.connect(func() -> void: RPGClient.get_character_catalog(AppState.campaign_id))
	row.add_child(inspect)
	return panel

func _hotbar_button(key: String, title: String) -> Button:
	var button := _button("[%s]  %s" % [key, title], false)
	button.custom_minimum_size = Vector2(150, 54)
	return button

func _build_right_rail() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 330
	panel.add_theme_stylebox_override("panel", _style(Color("111721"), Color("273245"), 0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var title := Label.new()
	title.text = "INSPECTOR"
	title.add_theme_color_override("font_color", C_ACCENT)
	title.add_theme_font_size_override("font_size", 13)
	box.add_child(title)
	inspector_box = VBoxContainer.new()
	inspector_box.custom_minimum_size.y = 245
	box.add_child(inspector_box)
	var divider := HSeparator.new()
	box.add_child(divider)
	var log_title := Label.new()
	log_title.text = "LIVE STORY"
	log_title.add_theme_color_override("font_color", C_ACCENT)
	log_title.add_theme_font_size_override("font_size", 13)
	box.add_child(log_title)
	event_log = RichTextLabel.new()
	event_log.bbcode_enabled = true
	event_log.fit_content = false
	event_log.scroll_active = true
	event_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	event_log.add_theme_color_override("default_color", Color("b6c0ce"))
	box.add_child(event_log)
	_refresh_inspector()
	return panel

func _on_state_received(state: Dictionary) -> void:
	AppState.current_state = state
	if not game_world:
		return
	game_world.apply_state(state)
	_refresh_party()
	_refresh_inspector()
	var campaign: Dictionary = state.get("campaign", {})
	var sim_time := float(campaign.get("simulation_time", state.get("simulation_time", 0.0)))
	var weather := str(state.get("weather", campaign.get("weather", "clear"))).capitalize()
	var time_mode := str(state.get("time_mode", campaign.get("time_mode", "hybrid"))).replace("_", " ").capitalize()
	world_status_label.text = "%s  •  %s  •  %.1fs" % [weather, time_mode, sim_time]

func _refresh_party() -> void:
	if not party_box:
		return
	for child in party_box.get_children():
		child.queue_free()
	var entities := AppState.get_entities()
	var humans := 0
	for entity_id in entities:
		var entity: Dictionary = entities[entity_id]
		if str(entity.get("kind", "")) != "player" and str(entity.get("controller", "")) != "human":
			continue
		humans += 1
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = _entity_summary(entity)
		button.pressed.connect(AppState.set_selected_entity.bind(str(entity_id)))
		if str(entity_id) == AppState.player_actor_id:
			button.add_theme_color_override("font_color", C_BLUE)
		party_box.add_child(button)
	if humans == 0:
		var empty := Label.new()
		empty.text = "No visible heroes yet.\nUse Character / Hero to create one."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", C_MUTED)
		party_box.add_child(empty)

func _entity_summary(entity: Dictionary) -> String:
	var resources: Dictionary = entity.get("resources", {})
	var hp := resources.get("hp", "—")
	var max_hp := resources.get("max_hp", "—")
	return "%s\nHP %s / %s" % [str(entity.get("name", "Unknown")), hp, max_hp]

func _refresh_inspector() -> void:
	if not inspector_box:
		return
	for child in inspector_box.get_children():
		child.queue_free()
	var entity_id := AppState.selected_entity_id
	if entity_id.is_empty():
		entity_id = AppState.player_actor_id
	var entity := AppState.get_entity(entity_id)
	if entity.is_empty():
		var label := Label.new()
		label.text = "Select a creature, hero or NPC on the map."
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_color_override("font_color", C_MUTED)
		inspector_box.add_child(label)
		return
	var name := Label.new()
	name.text = str(entity.get("name", entity_id))
	name.add_theme_font_size_override("font_size", 24)
	inspector_box.add_child(name)
	var kind := Label.new()
	kind.text = "%s  •  %s" % [str(entity.get("kind", "entity")).capitalize(), str(entity.get("controller", "none")).capitalize()]
	kind.add_theme_color_override("font_color", C_MUTED)
	inspector_box.add_child(kind)
	var resources: Dictionary = entity.get("resources", {})
	var hp := Label.new()
	hp.text = "HP  %s / %s" % [resources.get("hp", "—"), resources.get("max_hp", "—")]
	hp.add_theme_font_size_override("font_size", 18)
	inspector_box.add_child(hp)
	var stats: Dictionary = entity.get("stats", {})
	if not stats.is_empty():
		var stats_label := Label.new()
		stats_label.text = "STR %s   DEX %s   CON %s\nINT %s   WIS %s   CHA %s" % [stats.get("strength", 10), stats.get("dexterity", 10), stats.get("constitution", 10), stats.get("intelligence", 10), stats.get("wisdom", 10), stats.get("charisma", 10)]
		stats_label.add_theme_color_override("font_color", Color("c3ccd8"))
		inspector_box.add_child(stats_label)
	var tags: Array = entity.get("tags", [])
	if not tags.is_empty():
		var tags_label := Label.new()
		tags_label.text = "Tags: " + ", ".join(tags)
		tags_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tags_label.add_theme_color_override("font_color", C_MUTED)
		inspector_box.add_child(tags_label)

func _on_selection_changed(entity_id: String) -> void:
	if game_world:
		game_world.set_selected(entity_id)
	_refresh_inspector()

func _on_player_changed(_actor_id: String) -> void:
	if game_world and not AppState.current_state.is_empty():
		game_world.apply_state(AppState.current_state)
	_refresh_party()
	_refresh_inspector()

func _send_game_command(command: Dictionary) -> void:
	RPGClient.send_command(command, true)

func _attack_selected() -> void:
	var target := AppState.selected_entity_id
	if target.is_empty() or target == AppState.player_actor_id:
		_toast("Select an enemy or target first", true)
		return
	_send_game_command({"type": "attack", "actor_id": AppState.player_actor_id, "target_id": target, "action_id": "basic_attack"})

func _interact_selected() -> void:
	var target := AppState.selected_entity_id
	if target.is_empty():
		_toast("Select something to interact with", true)
		return
	_send_game_command({"type": "interact", "actor_id": AppState.player_actor_id, "target_id": target, "interaction": "default"})

func _wait_turn() -> void:
	if AppState.player_actor_id.is_empty():
		return
	_send_game_command({"type": "wait", "actor_id": AppState.player_actor_id})

func _unhandled_input(event: InputEvent) -> void:
	if AppState.current_screen != "game" or event is not InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1: _attack_selected()
		KEY_E: _interact_selected()
		KEY_SPACE: _wait_turn()
		KEY_C: RPGClient.get_character_catalog(AppState.campaign_id)
		KEY_ESCAPE: _show_lobby()

func _on_event_received(event: Dictionary) -> void:
	if not event_log:
		return
	var text := _event_text(event)
	if text.is_empty():
		return
	event_log.append_text("[color=#7d8998]%s[/color]  %s\n" % [str(event.get("type", "event")), text])
	event_log.scroll_to_line(maxi(0, event_log.get_line_count() - 1))

func _event_text(event: Dictionary) -> String:
	var event_type := str(event.get("type", ""))
	var payload: Dictionary = event.get("payload", {})
	if event_type == "narration":
		return str(payload.get("text", ""))
	var actor := AppState.get_entity(str(event.get("actor_id", "")))
	var target := AppState.get_entity(str(event.get("target_id", "")))
	var actor_name := str(actor.get("name", event.get("actor_id", "Someone")))
	var target_name := str(target.get("name", event.get("target_id", "")))
	match event_type:
		"combat.attack_resolved":
			if bool(payload.get("hit", false)):
				return "%s hits %s for %s damage." % [actor_name, target_name, payload.get("damage", 0)]
			return "%s misses %s." % [actor_name, target_name]
		"combat.entity_defeated": return "%s is defeated." % target_name
		"spell.cast_started": return "%s begins casting %s." % [actor_name, payload.get("spell_id", "a spell")]
		"spell.resolved": return "%s resolves %s." % [actor_name, payload.get("spell_id", "a spell")]
		"quest.started": return "Quest started: %s" % payload.get("quest_id", "unknown")
		"quest.completed": return "Quest completed: %s" % payload.get("quest_id", "unknown")
		"weather.changed": return "Weather shifts to %s." % str(payload.get("weather", "clear")).capitalize()
		"timeline.actor_ready": return "%s is ready to act." % actor_name
		"entity.moved": return "%s moves." % actor_name
		_:
			return str(payload.get("text", payload.get("message", event_type.replace(".", " ").capitalize())))

func _on_characters_received(characters: Array) -> void:
	if AppState.player_actor_id.is_empty():
		for character in characters:
			if character is Dictionary:
				var owner := str(character.get("owner_id", ""))
				if owner.is_empty() or owner == AppState.client_id:
					AppState.set_player_actor(str(character.get("id", "")))
					break

func _on_connection_state_changed(state: RPGClient.ConnectionState) -> void:
	if not connection_label:
		return
	match state:
		RPGClient.ConnectionState.CONNECTED:
			connection_label.text = "● LIVE"
			connection_label.add_theme_color_override("font_color", C_GOOD)
		RPGClient.ConnectionState.CONNECTING:
			connection_label.text = "● CONNECTING"
			connection_label.add_theme_color_override("font_color", C_ACCENT)
		RPGClient.ConnectionState.RECONNECTING:
			connection_label.text = "● RECONNECTING"
			connection_label.add_theme_color_override("font_color", C_ACCENT)
		RPGClient.ConnectionState.DISCONNECTED:
			connection_label.text = "● OFFLINE"
			connection_label.add_theme_color_override("font_color", C_BAD)

func _on_request_failed(context: String, message: String) -> void:
	_toast("%s: %s" % [context.replace("_", " ").capitalize(), message], true)

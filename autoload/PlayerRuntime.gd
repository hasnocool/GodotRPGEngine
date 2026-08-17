# autoload/PlayerRuntime.gd
extends CanvasLayer

## Player-facing runtime surface backed entirely by dnd-rpg-engine state and
## lifecycle APIs. This layer never calculates trusted rules locally.

const C_BG := Color("101620")
const C_PANEL := Color("151d29")
const C_PANEL_2 := Color("1d2837")
const C_BORDER := Color("34445b")
const C_TEXT := Color("edf2f8")
const C_MUTED := Color("95a4b7")
const C_ACCENT := Color("d6ad68")
const C_GOOD := Color("6fd39d")
const C_BAD := Color("e6796d")
const C_BLUE := Color("73bbff")

var _root: Control
var _dock: PanelContainer
var _sheet: PanelContainer
var _summary_label: RichTextLabel
var _turn_label: Label
var _sheet_title: Label
var _sheet_text: RichTextLabel
var _action_box: VBoxContainer
var _rest_select: OptionButton
var _equipment_select: OptionButton
var _resource_select: OptionButton
var _level_select: OptionButton
var _level_button: Button

var _active_actor_id := ""
var _character_detail: Dictionary = {}
var _catalog: Dictionary = {}
var _runtime: Dictionary = {}
var _last_refresh_msec := 0
var _sheet_open := false

func _ready() -> void:
	layer = 90
	_build_ui()
	RPGClient.state_received.connect(_on_state_received)
	RPGClient.event_received.connect(_on_event_received)
	RPGClient.connection_state_changed.connect(_on_connection_state_changed)
	RPGClient.request_failed.connect(_on_request_failed)
	AppState.player_changed.connect(_on_player_changed)
	AppState.campaign_changed.connect(_on_campaign_changed)
	set_process_unhandled_input(true)

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)

	_dock = PanelContainer.new()
	_dock.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_dock.offset_left = -490
	_dock.offset_right = 490
	_dock.offset_top = -128
	_dock.offset_bottom = -20
	_dock.mouse_filter = Control.MOUSE_FILTER_STOP
	_dock.add_theme_stylebox_override("panel", _style(C_PANEL, C_BORDER, 14))
	_root.add_child(_dock)

	var dock_margin := MarginContainer.new()
	dock_margin.add_theme_constant_override("margin_left", 16)
	dock_margin.add_theme_constant_override("margin_right", 16)
	dock_margin.add_theme_constant_override("margin_top", 12)
	dock_margin.add_theme_constant_override("margin_bottom", 12)
	_dock.add_child(dock_margin)

	var dock_row := HBoxContainer.new()
	dock_row.add_theme_constant_override("separation", 14)
	dock_margin.add_child(dock_row)

	_summary_label = RichTextLabel.new()
	_summary_label.bbcode_enabled = true
	_summary_label.fit_content = true
	_summary_label.scroll_active = false
	_summary_label.custom_minimum_size = Vector2(300, 78)
	_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dock_row.add_child(_summary_label)

	var turn_panel := VBoxContainer.new()
	turn_panel.custom_minimum_size.x = 250
	turn_panel.add_theme_constant_override("separation", 6)
	dock_row.add_child(turn_panel)
	var turn_heading := _label("AUTHORITATIVE TURN STATE", 11, C_MUTED)
	turn_panel.add_child(turn_heading)
	_turn_label = _label("Waiting for runtime state", 14, C_TEXT)
	_turn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	turn_panel.add_child(_turn_label)

	var controls := VBoxContainer.new()
	controls.custom_minimum_size.x = 190
	controls.add_theme_constant_override("separation", 6)
	dock_row.add_child(controls)
	var sheet_button := _button("Character Sheet  [Tab]", true)
	sheet_button.pressed.connect(_toggle_sheet)
	controls.add_child(sheet_button)
	var refresh_button := _button("Refresh Runtime")
	refresh_button.pressed.connect(func() -> void: _refresh_authoritative_data(true))
	controls.add_child(refresh_button)

	_sheet = PanelContainer.new()
	_sheet.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_sheet.offset_left = -570
	_sheet.offset_right = -20
	_sheet.offset_top = 20
	_sheet.offset_bottom = 0
	_sheet.custom_minimum_size = Vector2(550, 690)
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	_sheet.add_theme_stylebox_override("panel", _style(C_BG, C_BORDER, 16))
	_sheet.visible = false
	_root.add_child(_sheet)

	var sheet_margin := MarginContainer.new()
	sheet_margin.add_theme_constant_override("margin_left", 18)
	sheet_margin.add_theme_constant_override("margin_right", 18)
	sheet_margin.add_theme_constant_override("margin_top", 16)
	sheet_margin.add_theme_constant_override("margin_bottom", 16)
	_sheet.add_child(sheet_margin)

	var sheet_column := VBoxContainer.new()
	sheet_column.add_theme_constant_override("separation", 10)
	sheet_margin.add_child(sheet_column)

	var sheet_header := HBoxContainer.new()
	sheet_column.add_child(sheet_header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_header.add_child(titles)
	_sheet_title = _label("Player Runtime", 25, C_TEXT)
	titles.add_child(_sheet_title)
	titles.add_child(_label("Server-owned character lifecycle • presentation-only client", 11, C_MUTED))
	var close := _button("×")
	close.custom_minimum_size = Vector2(44, 40)
	close.pressed.connect(_toggle_sheet)
	sheet_header.add_child(close)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 340)
	sheet_column.add_child(scroll)
	var scroll_column := VBoxContainer.new()
	scroll_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_column.add_theme_constant_override("separation", 10)
	scroll.add_child(scroll_column)

	_sheet_text = RichTextLabel.new()
	_sheet_text.bbcode_enabled = true
	_sheet_text.fit_content = true
	_sheet_text.scroll_active = false
	_sheet_text.custom_minimum_size.x = 480
	scroll_column.add_child(_sheet_text)

	var action_heading := _label("AVAILABLE ACTIONS", 12, C_ACCENT)
	scroll_column.add_child(action_heading)
	_action_box = VBoxContainer.new()
	_action_box.add_theme_constant_override("separation", 5)
	scroll_column.add_child(_action_box)

	scroll_column.add_child(_separator())
	scroll_column.add_child(_label("LIFECYCLE CONTROLS", 12, C_ACCENT))
	scroll_column.add_child(_label("Every control below calls the authoritative lifecycle API; no HP, equipment, resource, or level state is changed locally.", 11, C_MUTED))

	var rest_row := HBoxContainer.new()
	rest_row.add_theme_constant_override("separation", 8)
	scroll_column.add_child(rest_row)
	_rest_select = OptionButton.new()
	_rest_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rest_row.add_child(_rest_select)
	var rest_button := _button("Rest")
	rest_button.pressed.connect(_rest_selected)
	rest_row.add_child(rest_button)

	var equipment_row := HBoxContainer.new()
	equipment_row.add_theme_constant_override("separation", 8)
	scroll_column.add_child(equipment_row)
	_equipment_select = OptionButton.new()
	_equipment_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equipment_row.add_child(_equipment_select)
	var equip_button := _button("Equip")
	equip_button.pressed.connect(func() -> void: _equipment_action(true))
	equipment_row.add_child(equip_button)
	var unequip_button := _button("Unequip")
	unequip_button.pressed.connect(func() -> void: _equipment_action(false))
	equipment_row.add_child(unequip_button)

	var resource_row := HBoxContainer.new()
	resource_row.add_theme_constant_override("separation", 8)
	scroll_column.add_child(resource_row)
	_resource_select = OptionButton.new()
	_resource_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resource_row.add_child(_resource_select)
	var spend_button := _button("Spend 1")
	spend_button.pressed.connect(_spend_resource)
	resource_row.add_child(spend_button)

	var level_row := HBoxContainer.new()
	level_row.add_theme_constant_override("separation", 8)
	scroll_column.add_child(level_row)
	_level_select = OptionButton.new()
	_level_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_row.add_child(_level_select)
	_level_button = _button("Level Up")
	_level_button.pressed.connect(_level_up)
	level_row.add_child(_level_button)

func _style(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box

func _label(text_value: String, size := 14, color := C_TEXT) -> Label:
	var value := Label.new()
	value.text = text_value
	value.add_theme_font_size_override("font_size", size)
	value.add_theme_color_override("font_color", color)
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return value

func _button(text_value: String, accent := false) -> Button:
	var value := Button.new()
	value.text = text_value
	value.custom_minimum_size.y = 38
	value.add_theme_stylebox_override("normal", _style(Color("202b3b") if not accent else Color("72572f"), C_BORDER if not accent else C_ACCENT, 8))
	value.add_theme_stylebox_override("hover", _style(Color("2b394d") if not accent else Color("8c6b38"), C_BLUE if not accent else Color("efd18f"), 8))
	value.add_theme_color_override("font_color", C_TEXT)
	return value

func _separator() -> HSeparator:
	var value := HSeparator.new()
	value.add_theme_color_override("separator", C_BORDER)
	return value

func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		_toggle_sheet()
		get_viewport().set_input_as_handled()

func _on_campaign_changed(_campaign_id: String) -> void:
	_active_actor_id = ""
	_character_detail.clear()
	_catalog.clear()
	_runtime.clear()
	_root.visible = false
	_sheet.visible = false
	_sheet_open = false

func _on_connection_state_changed(state: RPGClient.ConnectionState) -> void:
	if state == RPGClient.ConnectionState.DISCONNECTED:
		_root.visible = false

func _on_player_changed(actor_id: String) -> void:
	_active_actor_id = actor_id
	if actor_id.is_empty():
		_root.visible = false
		return
	_root.visible = true
	_refresh_authoritative_data(true)

func _on_state_received(_state: Dictionary) -> void:
	var actor_id := AppState.player_actor_id
	if actor_id.is_empty():
		_root.visible = false
		return
	if _active_actor_id != actor_id:
		_active_actor_id = actor_id
		_character_detail.clear()
		_runtime.clear()
	_root.visible = true
	_render()
	var now := Time.get_ticks_msec()
	if now - _last_refresh_msec >= 1200:
		_refresh_authoritative_data(false)

func _on_event_received(event: Dictionary) -> void:
	if _active_actor_id.is_empty():
		return
	var actor_id := str(event.get("actor_id", ""))
	var target_id := str(event.get("target_id", ""))
	if actor_id == _active_actor_id or target_id == _active_actor_id:
		_refresh_authoritative_data(false)

func _on_request_failed(context: String, _message: String) -> void:
	# World-platform runtime is optional. Character lifecycle errors are already
	# surfaced by the main client toast; keep this overlay usable in advanced mode.
	if context == "player_runtime_snapshot":
		_runtime.clear()
		_render()

func _toggle_sheet() -> void:
	_sheet_open = not _sheet_open
	_sheet.visible = _sheet_open
	if _sheet_open:
		_refresh_authoritative_data(true)

func _refresh_authoritative_data(force: bool) -> void:
	if _active_actor_id.is_empty() or AppState.campaign_id.is_empty():
		return
	var now := Time.get_ticks_msec()
	if not force and now - _last_refresh_msec < 350:
		return
	_last_refresh_msec = now
	_request_character()
	_request_catalog()
	_request_runtime()

func _request_character() -> void:
	var actor_id := _active_actor_id
	_rest("GET", _character_path(actor_id), {}, "player_character", func(payload: Variant) -> void:
		if actor_id != _active_actor_id:
			return
		_character_detail = payload if payload is Dictionary else {}
		_render()
	)

func _request_catalog() -> void:
	if not _catalog.is_empty():
		return
	_rest("GET", "/api/v1/campaigns/%s/characters/catalog" % AppState.campaign_id.uri_encode(), {}, "player_catalog", func(payload: Variant) -> void:
		_catalog = payload if payload is Dictionary else {}
		_render()
	)

func _request_runtime() -> void:
	var actor_id := _active_actor_id
	var path := "/api/v1/campaigns/%s/runtime?actor_id=%s" % [AppState.campaign_id.uri_encode(), actor_id.uri_encode()]
	_rest("GET", path, {}, "player_runtime_snapshot", func(payload: Variant) -> void:
		if actor_id != _active_actor_id:
			return
		_runtime = payload if payload is Dictionary else {}
		_render()
	)

func _character_path(actor_id: String) -> String:
	return "/api/v1/campaigns/%s/characters/%s" % [AppState.campaign_id.uri_encode(), actor_id.uri_encode()]

func _render() -> void:
	if not _root or not _root.visible or _active_actor_id.is_empty():
		return
	var entity := _current_entity()
	if entity.is_empty():
		return
	var name := str(entity.get("name", _active_actor_id))
	var pools: Dictionary = entity.get("resources", {})
	var hp := int(pools.get("hp", 0))
	var max_hp := int(pools.get("max_hp", 0))
	var progress: Dictionary = _character_detail.get("progress", entity.get("components", {}).get("character", {}))
	var level := _total_level(progress)
	var classes := _class_summary(progress)
	_summary_label.text = "[color=#d6ad68][b]%s[/b][/color]\nLevel %s%s\n[color=#6fd39d]HP %s / %s[/color]" % [name, level, " • " + classes if not classes.is_empty() else "", hp, max_hp]
	_turn_label.text = _turn_summary(entity)
	_sheet_title.text = "%s — Character Runtime" % name
	_sheet_text.text = _sheet_markup(entity, progress)
	_render_actions(entity)
	_populate_lifecycle_controls(entity, progress)

func _current_entity() -> Dictionary:
	var from_detail: Dictionary = _character_detail.get("entity", {})
	if not from_detail.is_empty():
		return from_detail
	return AppState.get_entity(_active_actor_id)

func _sheet_markup(entity: Dictionary, progress: Dictionary) -> String:
	var stats: Dictionary = entity.get("stats", {})
	var pools: Dictionary = entity.get("resources", {})
	var lines: Array[String] = []
	lines.append("[color=#d6ad68][b]VITALS[/b][/color]")
	lines.append("HP  %s / %s    Temp HP  %s    Energy  %s / %s" % [
		int(pools.get("hp", 0)), int(pools.get("max_hp", 0)), int(pools.get("temp_hp", 0)),
		int(pools.get("energy", 0)), int(pools.get("max_energy", 0))])
	lines.append("")
	lines.append("[color=#d6ad68][b]IDENTITY & PROGRESSION[/b][/color]")
	lines.append("Species  %s    Background  %s" % [str(progress.get("species_id", "—")), str(progress.get("background_id", "—"))])
	lines.append("Classes  %s    XP  %s    Level ready  %s" % [_class_summary(progress), int(progress.get("xp", 0)), "YES" if bool(_character_detail.get("level_ready", false)) else "No"])
	lines.append("")
	lines.append("[color=#d6ad68][b]ABILITY SCORES[/b][/color]")
	for key in ["strength", "dexterity", "constitution", "intelligence", "wisdom", "charisma"]:
		if stats.has(key):
			var score := int(stats[key])
			var modifier := floori((score - 10) / 2.0)
			lines.append("%-13s %2d   modifier %+d" % [key.capitalize(), score, modifier])

	lines.append("")
	lines.append("[color=#d6ad68][b]TRACKED RESOURCES[/b][/color]")
	var tracked: Dictionary = _character_detail.get("resources", {})
	if tracked.is_empty():
		lines.append("No class resources exposed by this character.")
	else:
		for resource_id in tracked:
			var resource: Dictionary = tracked[resource_id]
			lines.append("%s  %s / %s" % [str(resource_id).replace("_", " ").capitalize(), int(resource.get("current", 0)), int(resource.get("maximum", 0))])

	lines.append("")
	lines.append("[color=#d6ad68][b]EQUIPMENT[/b][/color]")
	var equipment: Dictionary = _character_detail.get("equipment", entity.get("components", {}).get("equipment", {}))
	var slots: Dictionary = equipment.get("slots", {})
	if slots.is_empty():
		lines.append("Nothing equipped.")
	else:
		for slot in slots:
			lines.append("%s  →  %s" % [str(slot).replace("_", " ").capitalize(), str(slots[slot])])

	lines.append("")
	lines.append("[color=#d6ad68][b]INVENTORY[/b][/color]")
	var inventory: Dictionary = entity.get("components", {}).get("inventory", {})
	var items: Dictionary = inventory.get("items", {})
	if items.is_empty():
		lines.append("Inventory is empty.")
	else:
		for item_id in items:
			lines.append("%s  ×%s" % [_item_name(str(item_id)), int(items[item_id])])

	lines.append("")
	lines.append("[color=#d6ad68][b]CONDITIONS[/b][/color]")
	var conditions: Variant = entity.get("conditions", entity.get("components", {}).get("conditions", {}))
	if conditions is Dictionary and not conditions.is_empty():
		for condition_id in conditions:
			lines.append("• %s" % str(condition_id).replace("_", " ").capitalize())
	elif conditions is Array and not conditions.is_empty():
		for condition in conditions:
			lines.append("• %s" % str(condition))
	else:
		lines.append("No active conditions.")

	lines.append("")
	lines.append("[color=#d6ad68][b]WORLD RUNTIME[/b][/color]")
	if _runtime.is_empty():
		lines.append("WorldPlatform runtime snapshot unavailable; lifecycle state remains active.")
	else:
		lines.append("Map  %s    Simulation  %.2fs    Sequence  %s" % [str(_runtime.get("active_map_id", "—")), float(_runtime.get("simulation_time", 0.0)), int(_runtime.get("sequence", 0))])
		var facts: Dictionary = _runtime.get("facts", {})
		var journal := _journal_fact_lines(facts)
		if not journal.is_empty():
			lines.append("")
			lines.append("[color=#d6ad68][b]JOURNAL / KNOWN WORLD FACTS[/b][/color]")
			lines.append_array(journal)
	return "\n".join(lines)

func _turn_summary(entity: Dictionary) -> String:
	var components: Dictionary = entity.get("components", {})
	var action_state: Dictionary = components.get("action_economy", components.get("turn", {}))
	if action_state.is_empty():
		var state_campaign: Dictionary = AppState.current_state.get("campaign", {})
		var time_mode := str(state_campaign.get("time_mode", AppState.current_state.get("time_mode", "authoritative")))
		return "%s mode\nActions update from server events and snapshots." % time_mode.replace("_", " ").capitalize()
	var parts: Array[String] = []
	for key in ["action", "bonus_action", "reaction", "movement", "movement_remaining"]:
		if action_state.has(key):
			parts.append("%s: %s" % [key.replace("_", " ").capitalize(), str(action_state[key])])
	return "  •  ".join(parts)

func _render_actions(entity: Dictionary) -> void:
	for child in _action_box.get_children():
		child.queue_free()
	var actions := _available_actions(entity)
	if actions.is_empty():
		_action_box.add_child(_label("No explicit action descriptors are exposed in this snapshot. Existing tactical controls remain available; this panel will light up automatically when a ruleset publishes available_actions/action_palette metadata.", 11, C_MUTED))
		return
	for action in actions.slice(0, 10):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_action_box.add_child(row)
		var descriptor: Dictionary = action
		var name := str(descriptor.get("name", descriptor.get("id", "Action")))
		var detail := str(descriptor.get("cost", descriptor.get("action_type", "")))
		var range_text := str(descriptor.get("range", descriptor.get("range_ft", "")))
		var label_text := name
		if not detail.is_empty():
			label_text += " • " + detail
		if not range_text.is_empty():
			label_text += " • range " + range_text
		var action_label := _label(label_text, 12, C_TEXT)
		action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(action_label)
		var command: Variant = descriptor.get("command", null)
		var use_button := _button("Use")
		use_button.disabled = command is not Dictionary
		if command is Dictionary:
			var command_copy: Dictionary = command.duplicate(true)
			if not command_copy.has("actor_id"):
				command_copy["actor_id"] = _active_actor_id
			use_button.pressed.connect(func() -> void: RPGClient.send_command(command_copy))
		else:
			use_button.tooltip_text = "The server described this action but did not publish a command envelope, so the client will not guess how to execute it."
		row.add_child(use_button)

func _available_actions(entity: Dictionary) -> Array[Dictionary]:
	var candidates: Array = []
	var components: Dictionary = entity.get("components", {})
	for key in ["available_actions", "action_palette", "actions"]:
		if components.has(key):
			candidates.append(components[key])
	var facts: Dictionary = _runtime.get("facts", {})
	for key in ["available_actions", "action_palette", "actions"]:
		if facts.has(key):
			candidates.append(facts[key])
	var normalized: Array[Dictionary] = []
	for candidate in candidates:
		if candidate is Array:
			for item in candidate:
				if item is Dictionary:
					normalized.append(item)
				else:
					normalized.append({"id": str(item), "name": str(item)})
		elif candidate is Dictionary:
			for action_id in candidate:
				var raw: Variant = candidate[action_id]
				if raw is Dictionary:
					var descriptor: Dictionary = raw.duplicate(true)
					descriptor["id"] = str(descriptor.get("id", action_id))
					normalized.append(descriptor)
				else:
					normalized.append({"id": str(action_id), "name": str(action_id)})
	if normalized.size() > 1:
		normalized.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("name", a.get("id", ""))).naturalnocasecmp_to(str(b.get("name", b.get("id", "")))) < 0)
	return normalized

func _journal_fact_lines(facts: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for fact_id in facts:
		var lowered := str(fact_id).to_lower()
		if not ("quest" in lowered or "objective" in lowered or "journal" in lowered or "dialogue" in lowered or "scene" in lowered):
			continue
		var fact: Variant = facts[fact_id]
		if fact is Dictionary:
			var value := fact.get("value", fact.get("summary", fact.get("state", "known")))
			lines.append("• %s — %s" % [str(fact_id).replace("_", " ").capitalize(), str(value)])
		else:
			lines.append("• %s — %s" % [str(fact_id).replace("_", " ").capitalize(), str(fact)])
		if lines.size() >= 10:
			break
	return lines

func _populate_lifecycle_controls(entity: Dictionary, progress: Dictionary) -> void:
	_populate_rest_profiles()
	_populate_equipment(entity)
	_populate_resources()
	_populate_classes(progress)
	_level_button.disabled = not bool(_character_detail.get("level_ready", false)) or AppState.owner_client_id.is_empty()
	_level_button.tooltip_text = "Level-up is an owner-authorized lifecycle operation." if AppState.owner_client_id.is_empty() else ""

func _populate_rest_profiles() -> void:
	var current := _rest_select.get_selected_id() if _rest_select.item_count > 0 else -1
	_rest_select.clear()
	var profiles: Dictionary = _catalog.get("rest_profiles", {})
	for profile_id in profiles:
		var profile: Dictionary = profiles[profile_id]
		_rest_select.add_item(str(profile.get("id", profile_id)).replace("_", " ").capitalize())
		_rest_select.set_item_metadata(_rest_select.item_count - 1, str(profile_id))
	if _rest_select.item_count == 0:
		_rest_select.add_item("Long Rest")
		_rest_select.set_item_metadata(0, "long_rest")
	if current >= 0 and current < _rest_select.item_count:
		_rest_select.select(current)

func _populate_equipment(entity: Dictionary) -> void:
	var selected_metadata := ""
	if _equipment_select.item_count > 0:
		selected_metadata = str(_equipment_select.get_item_metadata(_equipment_select.selected))
	_equipment_select.clear()
	var inventory: Dictionary = entity.get("components", {}).get("inventory", {})
	var items: Dictionary = inventory.get("items", {})
	var definitions: Dictionary = _catalog.get("equipment", {})
	for item_id in items:
		if not definitions.has(item_id):
			continue
		_equipment_select.add_item("%s ×%s" % [_item_name(str(item_id)), int(items[item_id])])
		_equipment_select.set_item_metadata(_equipment_select.item_count - 1, str(item_id))
		if str(item_id) == selected_metadata:
			_equipment_select.select(_equipment_select.item_count - 1)
	if _equipment_select.item_count == 0:
		_equipment_select.add_item("No equippable inventory items")
		_equipment_select.set_item_disabled(0, true)

func _populate_resources() -> void:
	var selected_metadata := ""
	if _resource_select.item_count > 0:
		selected_metadata = str(_resource_select.get_item_metadata(_resource_select.selected))
	_resource_select.clear()
	var tracked: Dictionary = _character_detail.get("resources", {})
	for resource_id in tracked:
		var resource: Dictionary = tracked[resource_id]
		_resource_select.add_item("%s  %s/%s" % [str(resource_id).replace("_", " ").capitalize(), int(resource.get("current", 0)), int(resource.get("maximum", 0))])
		_resource_select.set_item_metadata(_resource_select.item_count - 1, str(resource_id))
		if str(resource_id) == selected_metadata:
			_resource_select.select(_resource_select.item_count - 1)
	if _resource_select.item_count == 0:
		_resource_select.add_item("No tracked class resources")
		_resource_select.set_item_disabled(0, true)

func _populate_classes(progress: Dictionary) -> void:
	var selected_metadata := ""
	if _level_select.item_count > 0:
		selected_metadata = str(_level_select.get_item_metadata(_level_select.selected))
	_level_select.clear()
	var classes: Dictionary = progress.get("classes", {})
	for class_id in classes:
		_level_select.add_item("%s (%s)" % [str(class_id).replace("_", " ").capitalize(), int(classes[class_id])])
		_level_select.set_item_metadata(_level_select.item_count - 1, str(class_id))
		if str(class_id) == selected_metadata:
			_level_select.select(_level_select.item_count - 1)
	if _level_select.item_count == 0:
		_level_select.add_item("No class")
		_level_select.set_item_disabled(0, true)

func _rest_selected() -> void:
	if _rest_select.item_count == 0 or _rest_select.is_item_disabled(_rest_select.selected):
		return
	_lifecycle_post("rest", {"profile_id": str(_rest_select.get_item_metadata(_rest_select.selected))})

func _equipment_action(equip: bool) -> void:
	if _equipment_select.item_count == 0 or _equipment_select.is_item_disabled(_equipment_select.selected):
		return
	var item_id := str(_equipment_select.get_item_metadata(_equipment_select.selected))
	_lifecycle_post("equip" if equip else "unequip", {"item_id": item_id})

func _spend_resource() -> void:
	if _resource_select.item_count == 0 or _resource_select.is_item_disabled(_resource_select.selected):
		return
	_lifecycle_post("resources/spend", {"resource_id": str(_resource_select.get_item_metadata(_resource_select.selected)), "amount": 1})

func _level_up() -> void:
	if _level_select.item_count == 0 or _level_select.is_item_disabled(_level_select.selected):
		return
	_lifecycle_post("level-up", {"class_id": str(_level_select.get_item_metadata(_level_select.selected))})

func _lifecycle_post(operation: String, body: Dictionary) -> void:
	if _active_actor_id.is_empty():
		return
	var path := "%s/%s" % [_character_path(_active_actor_id), operation]
	_rest("POST", path, body, "player_lifecycle_%s" % operation.replace("/", "_"), func(payload: Variant) -> void:
		if payload is Dictionary and payload.has("character"):
			var current := _character_detail.duplicate(true)
			current["entity"] = payload["character"]
			_character_detail = current
		RPGClient.request_state()
		_refresh_authoritative_data(true)
	)

func _total_level(progress: Dictionary) -> int:
	var total := 0
	var classes: Dictionary = progress.get("classes", {})
	for class_id in classes:
		total += int(classes[class_id])
	return total

func _class_summary(progress: Dictionary) -> String:
	var pieces: Array[String] = []
	var classes: Dictionary = progress.get("classes", {})
	for class_id in classes:
		pieces.append("%s %s" % [str(class_id).replace("_", " ").capitalize(), int(classes[class_id])])
	return ", ".join(pieces)

func _item_name(item_id: String) -> String:
	var definitions: Dictionary = _catalog.get("equipment", {})
	if definitions.has(item_id) and definitions[item_id] is Dictionary:
		return str(definitions[item_id].get("name", item_id))
	return item_id.replace("_", " ").capitalize()

func _rest(method: String, path: String, body: Dictionary, context: String, callback: Callable) -> void:
	var request := HTTPRequest.new()
	request.timeout = 15.0
	add_child(request)
	request.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, response_body: PackedByteArray) -> void:
		var text := response_body.get_string_from_utf8()
		request.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			RPGClient.request_failed.emit(context, "Network request failed (%s)" % result)
			return
		var payload: Variant = JSON.parse_string(text) if not text.is_empty() else {}
		if response_code < 200 or response_code >= 300:
			var detail := text
			if payload is Dictionary:
				detail = str(payload.get("detail", payload.get("message", text)))
			RPGClient.request_failed.emit(context, "HTTP %s: %s" % [response_code, detail])
			return
		callback.call(payload)
	)
	var headers := PackedStringArray(["Accept: application/json"])
	var identity := AppState.owner_client_id if not AppState.owner_client_id.is_empty() else AppState.client_id
	if not identity.is_empty():
		headers.append("X-RPG-Client-ID: %s" % identity)
	var http_method := HTTPClient.METHOD_GET
	match method:
		"POST": http_method = HTTPClient.METHOD_POST
		"PATCH": http_method = HTTPClient.METHOD_PATCH
		"DELETE": http_method = HTTPClient.METHOD_DELETE
	if method != "GET" and method != "DELETE":
		headers.append("Content-Type: application/json")
	var request_body := JSON.stringify(body) if method != "GET" and method != "DELETE" else ""
	var error := request.request(AppState.api_base + path, headers, http_method, request_body)
	if error != OK:
		request.queue_free()
		RPGClient.request_failed.emit(context, "Could not start request: %s" % error_string(error))

# game/WorldView.gd
class_name WorldView
extends Control

signal entity_selected(entity_id: String)
signal ground_action(world_position: Vector2)
signal command_requested(command: Dictionary)

const GRID_STEP := 64.0
const MIN_ZOOM := 0.45
const MAX_ZOOM := 2.25

var state: Dictionary = {}
var entities: Dictionary = {}
var player_actor_id := ""
var selected_entity_id := ""
var hovered_entity_id := ""
var camera_world := Vector2.ZERO
var zoom := 1.0
var _dragging := false
var _drag_origin := Vector2.ZERO
var _camera_origin := Vector2.ZERO
var _initialized_camera := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)

func apply_state(new_state: Dictionary) -> void:
	state = new_state
	var campaign: Dictionary = state.get("campaign", {})
	entities = campaign.get("entities", {})
	player_actor_id = AppState.player_actor_id
	if not _initialized_camera and entities.has(player_actor_id):
		camera_world = _entity_position(entities[player_actor_id])
		_initialized_camera = true
	queue_redraw()

func set_selected(entity_id: String) -> void:
	selected_entity_id = entity_id
	queue_redraw()

func center_on_player() -> void:
	if entities.has(player_actor_id):
		camera_world = _entity_position(entities[player_actor_id])
		queue_redraw()

func _process(_delta: float) -> void:
	var next_hover := _entity_at(get_local_mouse_position())
	if next_hover != hovered_entity_id:
		hovered_entity_id = next_hover
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not hovered_entity_id.is_empty() else Control.CURSOR_ARROW
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, 1.12)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, 0.89)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
			if event.pressed:
				_drag_origin = event.position
				_camera_origin = camera_world
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var entity_id := _entity_at(event.position)
			if not entity_id.is_empty():
				selected_entity_id = entity_id
				entity_selected.emit(entity_id)
			else:
				var world := screen_to_world(event.position)
				ground_action.emit(world)
				_request_move(world)
			queue_redraw()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var entity_id := _entity_at(event.position)
			if not entity_id.is_empty() and entity_id != player_actor_id:
				selected_entity_id = entity_id
				entity_selected.emit(entity_id)
				_request_attack(entity_id)
			queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		camera_world = _camera_origin - (event.position - _drag_origin) / (GRID_STEP * zoom)
		queue_redraw()
		accept_event()

func _zoom_at(screen_position: Vector2, factor: float) -> void:
	var before := screen_to_world(screen_position)
	zoom = clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	var after := screen_to_world(screen_position)
	camera_world += before - after
	queue_redraw()

func world_to_screen(world_position: Vector2) -> Vector2:
	return size * 0.5 + (world_position - camera_world) * GRID_STEP * zoom

func screen_to_world(screen_position: Vector2) -> Vector2:
	return camera_world + (screen_position - size * 0.5) / (GRID_STEP * zoom)

func _draw() -> void:
	_draw_backdrop()
	_draw_grid()
	_draw_entities()
	_draw_vignette()

func _draw_backdrop() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("121722"), true)
	var horizon := Rect2(0, size.y * 0.56, size.x, size.y * 0.44)
	draw_rect(horizon, Color("10141d"), true)
	# Subtle pools make an asset-free map feel less sterile.
	for i in range(8):
		var p := Vector2(
			fmod(173.0 * float(i + 2) - camera_world.x * 17.0, size.x + 300.0) - 150.0,
			fmod(109.0 * float(i + 4) - camera_world.y * 13.0, size.y + 260.0) - 130.0
		)
		draw_circle(p, 120.0 + float((i * 31) % 90), Color(0.08, 0.12, 0.16, 0.24))

func _draw_grid() -> void:
	var pixels := GRID_STEP * zoom
	if pixels < 22.0:
		return
	var origin := world_to_screen(Vector2.ZERO)
	var x := fmod(origin.x, pixels)
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.32, 0.39, 0.46, 0.105), 1.0)
		x += pixels
	var y := fmod(origin.y, pixels)
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.32, 0.39, 0.46, 0.105), 1.0)
		y += pixels

func _draw_entities() -> void:
	var current_area := _current_area()
	for entity_id in entities:
		var entity: Dictionary = entities[entity_id]
		if not bool(entity.get("alive", true)):
			continue
		var position_data: Dictionary = entity.get("position", {})
		if not current_area.is_empty() and str(position_data.get("area_id", current_area)) != current_area:
			continue
		var pos := world_to_screen(_entity_position(entity))
		if pos.x < -80 or pos.y < -80 or pos.x > size.x + 80 or pos.y > size.y + 80:
			continue
		_draw_entity(str(entity_id), entity, pos)

func _draw_entity(entity_id: String, entity: Dictionary, pos: Vector2) -> void:
	var is_player := entity_id == player_actor_id
	var is_selected := entity_id == selected_entity_id
	var is_hovered := entity_id == hovered_entity_id
	var kind := str(entity.get("kind", "npc"))
	var tags: Array = entity.get("tags", [])
	var hostile := "hostile" in tags or "enemy" in tags or str(entity.get("faction", "")) == "hostile"
	var base_color := Color("d8614c") if hostile else Color("5cc8a1")
	if kind == "creature":
		base_color = Color("d98455") if not hostile else Color("e45f4d")
	if is_player:
		base_color = Color("75b9ff")

	var radius := 21.0 * clampf(zoom, 0.75, 1.25)
	if is_selected or is_hovered:
		draw_circle(pos, radius + 10.0, Color(base_color, 0.13))
		draw_arc(pos, radius + 7.0, 0, TAU, 48, Color(base_color, 0.95), 2.2)
	if is_player:
		draw_arc(pos, radius + 13.0, -PI * 0.85, PI * 0.15, 28, Color("d7b56d"), 3.0)

	# Token shadow and body.
	draw_circle(pos + Vector2(0, 5), radius + 2.0, Color(0, 0, 0, 0.38))
	draw_circle(pos, radius, Color("252d3a"))
	draw_circle(pos, radius - 3.0, base_color)
	draw_circle(pos - Vector2(radius * 0.28, radius * 0.32), radius * 0.24, Color(1, 1, 1, 0.16))

	var name := str(entity.get("name", entity_id))
	var font := ThemeDB.fallback_font
	var font_size := 13
	var text_size := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, pos + Vector2(-text_size.x * 0.5, radius + 22), name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("e8edf4"))
	_draw_health(entity, pos + Vector2(-28, radius + 28), 56.0)

func _draw_health(entity: Dictionary, top_left: Vector2, width: float) -> void:
	var resources: Dictionary = entity.get("resources", {})
	var hp_value: Variant = resources.get("hp", resources.get("health", {}))
	var current := 0.0
	var maximum := 0.0
	if hp_value is Dictionary:
		current = float(hp_value.get("current", hp_value.get("value", 0)))
		maximum = float(hp_value.get("max", hp_value.get("maximum", current)))
	elif hp_value != null:
		current = float(hp_value)
		maximum = float(resources.get("max_hp", entity.get("max_hp", current)))
	if maximum <= 0.0:
		return
	var ratio := clampf(current / maximum, 0.0, 1.0)
	draw_rect(Rect2(top_left, Vector2(width, 5)), Color(0.04, 0.05, 0.07, 0.9), true)
	draw_rect(Rect2(top_left + Vector2(1, 1), Vector2((width - 2) * ratio, 3)), Color("62c681") if ratio > 0.35 else Color("e06455"), true)

func _draw_vignette() -> void:
	var edge := 34.0
	draw_rect(Rect2(0, 0, size.x, edge), Color(0.02, 0.025, 0.035, 0.30), true)
	draw_rect(Rect2(0, size.y - edge, size.x, edge), Color(0.02, 0.025, 0.035, 0.30), true)

func _entity_at(screen_position: Vector2) -> String:
	var nearest := ""
	var nearest_distance := 38.0
	for entity_id in entities:
		var entity: Dictionary = entities[entity_id]
		if not bool(entity.get("alive", true)):
			continue
		var distance := world_to_screen(_entity_position(entity)).distance_to(screen_position)
		if distance < nearest_distance:
			nearest = str(entity_id)
			nearest_distance = distance
	return nearest

func _entity_position(entity: Dictionary) -> Vector2:
	var p: Dictionary = entity.get("position", {})
	return Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))

func _current_area() -> String:
	if entities.has(player_actor_id):
		return str(entities[player_actor_id].get("position", {}).get("area_id", ""))
	return ""

func _request_move(world_position: Vector2) -> void:
	if player_actor_id.is_empty():
		return
	var command := {
		"type": "move",
		"actor_id": player_actor_id,
		"map_id": _current_area(),
		"x": world_position.x,
		"y": world_position.y,
		"z": 0.0,
	}
	command_requested.emit(command)

func _request_attack(target_id: String) -> void:
	if player_actor_id.is_empty():
		return
	command_requested.emit({
		"type": "attack",
		"actor_id": player_actor_id,
		"target_id": target_id,
		"action_id": "basic_attack",
	})

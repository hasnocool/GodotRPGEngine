# game/WorldView.gd
class_name WorldView
extends Control

signal entity_selected(entity_id: String)
signal ground_action(world_position: Vector2)
signal command_requested(command: Dictionary)

const GRID_STEP := 64.0
const MIN_ZOOM := 0.45
const MAX_ZOOM := 2.25
const EFFECT_LIFETIME := 1.15

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
var _texture_cache: Dictionary = {}
var _effects: Array[Dictionary] = []
var _transition_alpha := 0.0
var _transition_map_id := ""
var _ambience_player: AudioStreamPlayer
var _ambience_path := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	VisualRuntime.snapshot_changed.connect(_on_visual_snapshot_changed)
	VisualRuntime.map_changed.connect(_on_visual_map_changed)
	VisualRuntime.visual_event.connect(_on_visual_event)

func apply_state(new_state: Dictionary) -> void:
	state = new_state
	player_actor_id = AppState.player_actor_id
	_sync_entities()
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

func _on_visual_snapshot_changed(_snapshot: Dictionary) -> void:
	_sync_entities()
	_sync_ambience()
	queue_redraw()

func _on_visual_map_changed(current_map_id: String, _previous_map_id: String) -> void:
	_transition_map_id = current_map_id
	_transition_alpha = 1.0
	_initialized_camera = false
	_sync_entities()
	if entities.has(player_actor_id):
		camera_world = _entity_position(entities[player_actor_id])
		_initialized_camera = true
	queue_redraw()

func _on_visual_event(event: Dictionary) -> void:
	var event_type := str(event.get("type", event.get("event_type", "event")))
	var effect := {
		"type": event_type,
		"actor_id": str(event.get("actor_id", "")),
		"target_id": str(event.get("target_id", "")),
		"started": Time.get_ticks_msec() / 1000.0,
		"duration": EFFECT_LIFETIME,
		"text": _effect_text(event_type),
	}
	_effects.append(effect)
	if _effects.size() > 18:
		_effects.pop_front()
	var payload: Variant = event.get("payload", {})
	if payload is Dictionary:
		var sound := str(payload.get("audio", payload.get("sound", "")))
		if VisualRuntime.resource_path_is_safe(sound):
			_play_one_shot(sound)
	queue_redraw()

func _process(delta: float) -> void:
	var next_hover := _entity_at(get_local_mouse_position())
	if next_hover != hovered_entity_id:
		hovered_entity_id = next_hover
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not hovered_entity_id.is_empty() else Control.CURSOR_ARROW
		queue_redraw()

	var now := Time.get_ticks_msec() / 1000.0
	var changed := false
	for index in range(_effects.size() - 1, -1, -1):
		var effect := _effects[index]
		if now - float(effect.get("started", now)) > float(effect.get("duration", EFFECT_LIFETIME)):
			_effects.remove_at(index)
			changed = true
	if not _effects.is_empty():
		changed = true
	if _transition_alpha > 0.0:
		_transition_alpha = maxf(0.0, _transition_alpha - delta * 1.35)
		changed = true
	if changed:
		queue_redraw()

func _sync_entities() -> void:
	player_actor_id = AppState.player_actor_id
	if VisualRuntime.has_snapshot():
		# RuntimeSnapshot is already knowledge scoped by the server. Never merge
		# hidden campaign entities back into this collection.
		entities = VisualRuntime.get_entities()
	else:
		var campaign: Dictionary = state.get("campaign", {})
		entities = campaign.get("entities", {})

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
	_draw_authoritative_path()
	_draw_entities()
	_draw_fog()
	_draw_effects()
	_draw_runtime_badge()
	_draw_vignette()
	_draw_scene_transition()

func _draw_backdrop() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("121722"), true)
	var horizon := Rect2(0, size.y * 0.56, size.x, size.y * 0.44)
	draw_rect(horizon, Color("10141d"), true)
	for i in range(8):
		var p := Vector2(
			fmod(173.0 * float(i + 2) - camera_world.x * 17.0, size.x + 300.0) - 150.0,
			fmod(109.0 * float(i + 4) - camera_world.y * 13.0, size.y + 260.0) - 130.0
		)
		draw_circle(p, 120.0 + float((i * 31) % 90), Color(0.08, 0.12, 0.16, 0.24))

	var visual := VisualRuntime.get_map_visual()
	if visual.is_empty():
		return
	var texture_path := str(visual.get("texture", visual.get("background", visual.get("sprite", ""))))
	var texture := _texture(texture_path)
	if texture == null:
		return
	var rect := _map_visual_rect(visual)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		rect = Rect2(Vector2.ZERO, size)
	var tint := _color_from_variant(visual.get("tint", "ffffff"), Color.WHITE)
	draw_texture_rect(texture, rect, false, tint)

func _map_visual_rect(visual: Dictionary) -> Rect2:
	var world_rect: Variant = visual.get("world_rect", visual.get("bounds", null))
	if world_rect is Dictionary:
		var data: Dictionary = world_rect
		var x := float(data.get("x", data.get("min_x", 0.0)))
		var y := float(data.get("y", data.get("min_y", 0.0)))
		var width := float(data.get("width", float(data.get("max_x", x)) - x))
		var height := float(data.get("height", float(data.get("max_y", y)) - y))
		var a := world_to_screen(Vector2(x, y))
		var b := world_to_screen(Vector2(x + width, y + height))
		return Rect2(a, b - a)
	if world_rect is Array and world_rect.size() >= 4:
		var a := world_to_screen(Vector2(float(world_rect[0]), float(world_rect[1])))
		var b := world_to_screen(Vector2(float(world_rect[0]) + float(world_rect[2]), float(world_rect[1]) + float(world_rect[3])))
		return Rect2(a, b - a)
	return Rect2()

func _draw_grid() -> void:
	var visual := VisualRuntime.get_map_visual()
	if bool(visual.get("hide_grid", false)):
		return
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

func _draw_authoritative_path() -> void:
	var descriptor := VisualRuntime.get_path_descriptor()
	if descriptor.is_empty():
		return
	var raw_points: Variant = descriptor.get("points", descriptor.get("path", []))
	if raw_points is not Array or raw_points.size() < 2:
		return
	var points := PackedVector2Array()
	for raw in raw_points:
		var point := _point_from_variant(raw)
		if point != null:
			points.append(world_to_screen(point))
	if points.size() < 2:
		return
	var color := Color("d6ad68") if bool(descriptor.get("authoritative", true)) else Color("73bbff")
	draw_polyline(points, Color(color, 0.85), 3.0, true)
	for point in points:
		draw_circle(point, 4.0, color)

func _draw_entities() -> void:
	var current_area := _current_area()
	for entity_id in entities:
		var entity: Dictionary = entities[entity_id]
		if not bool(entity.get("alive", true)):
			continue
		var position_data: Dictionary = entity.get("position", {})
		var entity_area := str(position_data.get("area_id", position_data.get("map_id", current_area)))
		if not current_area.is_empty() and not entity_area.is_empty() and entity_area != current_area:
			continue
		var pos := world_to_screen(_entity_position(entity))
		if pos.x < -100 or pos.y < -100 or pos.x > size.x + 100 or pos.y > size.y + 100:
			continue
		_draw_entity(str(entity_id), entity, pos)

func _draw_entity(entity_id: String, entity: Dictionary, pos: Vector2) -> void:
	var is_player := entity_id == player_actor_id
	var is_selected := entity_id == selected_entity_id
	var is_hovered := entity_id == hovered_entity_id
	var kind := str(entity.get("kind", "npc"))
	var tags: Variant = entity.get("tags", [])
	var hostile := (tags is Array and ("hostile" in tags or "enemy" in tags)) or str(entity.get("faction", "")) == "hostile"
	var base_color := Color("d8614c") if hostile else Color("5cc8a1")
	if kind == "creature":
		base_color = Color("d98455") if not hostile else Color("e45f4d")
	if is_player:
		base_color = Color("75b9ff")

	var binding := VisualRuntime.get_binding(entity_id)
	var metadata: Dictionary = binding.get("metadata", {}) if binding.get("metadata", {}) is Dictionary else {}
	var radius := float(metadata.get("token_radius", 21.0)) * clampf(zoom, 0.75, 1.25)
	if is_selected or is_hovered:
		draw_circle(pos, radius + 10.0, Color(base_color, 0.13))
		draw_arc(pos, radius + 7.0, 0, TAU, 48, Color(base_color, 0.95), 2.2)
	if is_player:
		draw_arc(pos, radius + 13.0, -PI * 0.85, PI * 0.15, 28, Color("d7b56d"), 3.0)

	var texture := _binding_texture(binding)
	if texture != null:
		var scale_value := float(metadata.get("scale", 1.0))
		var pixel_size := float(metadata.get("sprite_size", 52.0)) * clampf(zoom, 0.65, 1.55) * scale_value
		var texture_rect := Rect2(pos - Vector2.ONE * pixel_size * 0.5, Vector2.ONE * pixel_size)
		draw_circle(pos + Vector2(0, 5), radius + 3.0, Color(0, 0, 0, 0.30))
		var tint := _color_from_variant(metadata.get("tint", "ffffff"), Color.WHITE)
		draw_texture_rect(texture, texture_rect, false, tint)
	else:
		draw_circle(pos + Vector2(0, 5), radius + 2.0, Color(0, 0, 0, 0.38))
		draw_circle(pos, radius, Color("252d3a"))
		draw_circle(pos, radius - 3.0, base_color)
		draw_circle(pos - Vector2(radius * 0.28, radius * 0.32), radius * 0.24, Color(1, 1, 1, 0.16))

	var name := str(entity.get("name", entity_id))
	var font := ThemeDB.fallback_font
	var font_size := int(metadata.get("name_font_size", 13))
	var text_size := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, pos + Vector2(-text_size.x * 0.5, radius + 22), name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("e8edf4"))
	_draw_health(entity, pos + Vector2(-28, radius + 28), 56.0)

func _binding_texture(binding: Dictionary) -> Texture2D:
	if binding.is_empty():
		return null
	var metadata: Dictionary = binding.get("metadata", {}) if binding.get("metadata", {}) is Dictionary else {}
	var raw_frames: Variant = metadata.get("animation_frames", [])
	if raw_frames is Dictionary:
		var animation_name := str(binding.get("animation_set", metadata.get("animation", "default")))
		raw_frames = raw_frames.get(animation_name, raw_frames.get("default", []))
	if raw_frames is Array and not raw_frames.is_empty():
		var fps := maxf(0.1, float(metadata.get("animation_fps", 6.0)))
		var frame := int(floor((Time.get_ticks_msec() / 1000.0) * fps)) % raw_frames.size()
		var animated := _texture(str(raw_frames[frame]))
		if animated != null:
			return animated
	return _texture(str(binding.get("sprite", "")))

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

func _draw_fog() -> void:
	var fog := VisualRuntime.get_fog_descriptor()
	if fog.is_empty():
		return
	var cell_size := float(fog.get("cell_size", 1.0))
	var hidden_cells: Variant = fog.get("hidden_cells", fog.get("unknown_cells", []))
	if hidden_cells is Array:
		for raw in hidden_cells:
			var point := _point_from_variant(raw)
			if point == null:
				continue
			var a := world_to_screen(point)
			var b := world_to_screen(point + Vector2(cell_size, cell_size))
			draw_rect(Rect2(a, b - a), Color(0.015, 0.02, 0.03, 0.78), true)
	var regions: Variant = fog.get("hidden_regions", fog.get("unknown_regions", []))
	if regions is Array:
		for raw in regions:
			if raw is not Dictionary:
				continue
			var region: Dictionary = raw
			var a := world_to_screen(Vector2(float(region.get("x", 0.0)), float(region.get("y", 0.0))))
			var b := world_to_screen(Vector2(float(region.get("x", 0.0)) + float(region.get("width", 1.0)), float(region.get("y", 0.0)) + float(region.get("height", 1.0))))
			draw_rect(Rect2(a, b - a), Color(0.015, 0.02, 0.03, float(region.get("alpha", 0.82))), true)

func _draw_effects() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for effect in _effects:
		var started := float(effect.get("started", now))
		var duration := maxf(0.01, float(effect.get("duration", EFFECT_LIFETIME)))
		var progress := clampf((now - started) / duration, 0.0, 1.0)
		var fade := 1.0 - progress
		var actor_id := str(effect.get("actor_id", ""))
		var target_id := str(effect.get("target_id", ""))
		var source_pos := _entity_screen_position(actor_id)
		var target_pos := _entity_screen_position(target_id)
		var event_type := str(effect.get("type", ""))
		if source_pos != null:
			draw_arc(source_pos, 22.0 + progress * 26.0, 0, TAU, 36, Color(0.45, 0.73, 1.0, fade * 0.75), 2.0)
		if source_pos != null and target_pos != null and ("attack" in event_type or "spell" in event_type or "damage" in event_type):
			draw_line(source_pos, target_pos, Color(0.84, 0.68, 0.41, fade * 0.9), 3.0)
			draw_circle(target_pos, 8.0 + progress * 18.0, Color(0.90, 0.45, 0.36, fade * 0.22))
		var label_pos: Variant = target_pos if target_pos != null else source_pos
		if label_pos != null and not str(effect.get("text", "")).is_empty():
			draw_string(ThemeDB.fallback_font, label_pos + Vector2(10, -24 - progress * 24), str(effect.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.95, 0.98, fade))

func _draw_runtime_badge() -> void:
	if not VisualRuntime.has_snapshot():
		return
	var map_id := VisualRuntime.get_active_map_id()
	var label := "AUTHORITATIVE VISUAL RUNTIME"
	if not map_id.is_empty():
		label += "  •  " + map_id
	draw_string(ThemeDB.fallback_font, Vector2(18, 26), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("9cabbc"))

func _draw_vignette() -> void:
	var edge := 34.0
	draw_rect(Rect2(0, 0, size.x, edge), Color(0.02, 0.025, 0.035, 0.30), true)
	draw_rect(Rect2(0, size.y - edge, size.x, edge), Color(0.02, 0.025, 0.035, 0.30), true)

func _draw_scene_transition() -> void:
	if _transition_alpha <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.025, 0.035, _transition_alpha * 0.82), true)
	if _transition_map_id.is_empty():
		return
	var title := _transition_map_id.replace("_", " ").capitalize()
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 28)
	draw_string(font, size * 0.5 - Vector2(text_size.x * 0.5, 0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.94, 0.87, 0.72, _transition_alpha))

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

func _entity_screen_position(entity_id: String) -> Variant:
	if entity_id.is_empty() or not entities.has(entity_id):
		return null
	return world_to_screen(_entity_position(entities[entity_id]))

func _current_area() -> String:
	var runtime_map := VisualRuntime.get_active_map_id()
	if not runtime_map.is_empty():
		return runtime_map
	if entities.has(player_actor_id):
		var position_data: Dictionary = entities[player_actor_id].get("position", {})
		return str(position_data.get("area_id", position_data.get("map_id", "")))
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

func _texture(path: String) -> Texture2D:
	if not VisualRuntime.resource_path_is_safe(path):
		return null
	if _texture_cache.has(path):
		var cached: Variant = _texture_cache[path]
		return cached if cached is Texture2D else null
	var resource := ResourceLoader.load(path)
	if resource is Texture2D:
		_texture_cache[path] = resource
		return resource
	_texture_cache[path] = null
	return null

func _point_from_variant(raw: Variant) -> Variant:
	if raw is Dictionary:
		return Vector2(float(raw.get("x", 0.0)), float(raw.get("y", 0.0)))
	if raw is Array and raw.size() >= 2:
		return Vector2(float(raw[0]), float(raw[1]))
	return null

func _color_from_variant(raw: Variant, fallback: Color) -> Color:
	if raw is Color:
		return raw
	return Color.from_string(str(raw), fallback)

func _effect_text(event_type: String) -> String:
	if "spell" in event_type:
		return "Spell"
	if "attack" in event_type:
		return "Attack"
	if "move" in event_type:
		return "Move"
	if "heal" in event_type or "restore" in event_type:
		return "Recovered"
	return ""

func _sync_ambience() -> void:
	var path := VisualRuntime.get_ambience_path()
	if path == _ambience_path:
		return
	_ambience_path = path
	if _ambience_player and is_instance_valid(_ambience_player):
		_ambience_player.stop()
		_ambience_player.queue_free()
		_ambience_player = null
	if path.is_empty():
		return
	var resource := ResourceLoader.load(path)
	if resource is not AudioStream:
		return
	_ambience_player = AudioStreamPlayer.new()
	_ambience_player.stream = resource
	_ambience_player.volume_db = -12.0
	add_child(_ambience_player)
	_ambience_player.play()

func _play_one_shot(path: String) -> void:
	if not VisualRuntime.resource_path_is_safe(path):
		return
	var resource := ResourceLoader.load(path)
	if resource is not AudioStream:
		return
	var player := AudioStreamPlayer.new()
	player.stream = resource
	player.volume_db = -5.0
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

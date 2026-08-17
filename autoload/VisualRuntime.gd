# autoload/VisualRuntime.gd
extends Node

## Actor-scoped visual runtime adapter for dnd-rpg-engine WorldPlatformEngine.
##
## This service consumes RuntimeSnapshot payloads and exposes only presentation
## data to Godot. It never calculates visibility, movement validity, combat
## outcomes, pathfinding, or any other trusted rules locally.

signal snapshot_changed(snapshot: Dictionary)
signal map_changed(current_map_id: String, previous_map_id: String)
signal visual_event(event: Dictionary)
signal availability_changed(available: bool)

const MIN_REFRESH_MSEC := 650

var snapshot: Dictionary = {}
var available := false
var last_error := ""

var _actor_id := ""
var _campaign_id := ""
var _last_request_msec := 0
var _request_in_flight := false
var _snapshot_hash := ""

func _ready() -> void:
	RPGClient.state_received.connect(_on_state_received)
	RPGClient.event_received.connect(_on_event_received)
	RPGClient.connection_state_changed.connect(_on_connection_state_changed)
	AppState.player_changed.connect(_on_player_changed)
	AppState.campaign_changed.connect(_on_campaign_changed)
	AppState.screen_changed.connect(_on_screen_changed)

func _on_screen_changed(screen: String) -> void:
	if screen == "game":
		refresh(true)

func _on_campaign_changed(campaign_id: String) -> void:
	_campaign_id = campaign_id
	_actor_id = ""
	_clear_snapshot()

func _on_player_changed(actor_id: String) -> void:
	_actor_id = actor_id
	refresh(true)

func _on_connection_state_changed(state: RPGClient.ConnectionState) -> void:
	if state == RPGClient.ConnectionState.CONNECTED:
		refresh(true)
	elif state == RPGClient.ConnectionState.DISCONNECTED:
		_set_available(false)

func _on_state_received(_state: Dictionary) -> void:
	if _actor_id.is_empty():
		_actor_id = AppState.player_actor_id
	refresh(false)

func _on_event_received(event: Dictionary) -> void:
	if AppState.current_screen != "game":
		return
	visual_event.emit(event)
	var event_actor := str(event.get("actor_id", ""))
	var event_target := str(event.get("target_id", ""))
	if event_actor == _actor_id or event_target == _actor_id:
		refresh(false)

func refresh(force := false) -> void:
	if AppState.current_screen != "game":
		return
	if AppState.campaign_id.is_empty() or AppState.player_actor_id.is_empty():
		return
	if _request_in_flight:
		return
	var now := Time.get_ticks_msec()
	if not force and now - _last_request_msec < MIN_REFRESH_MSEC:
		return
	_campaign_id = AppState.campaign_id
	_actor_id = AppState.player_actor_id
	_last_request_msec = now
	_request_runtime_snapshot()

func has_snapshot() -> bool:
	return available and not snapshot.is_empty() and str(snapshot.get("campaign_id", "")) == AppState.campaign_id

func get_entities() -> Dictionary:
	if not has_snapshot():
		return {}
	var value: Variant = snapshot.get("entities", {})
	return value if value is Dictionary else {}

func get_facts() -> Dictionary:
	if not has_snapshot():
		return {}
	var value: Variant = snapshot.get("facts", {})
	return value if value is Dictionary else {}

func get_bindings() -> Dictionary:
	if not has_snapshot():
		return {}
	var value: Variant = snapshot.get("bindings", {})
	return value if value is Dictionary else {}

func get_binding(entity_id: String) -> Dictionary:
	var bindings := get_bindings()
	var value: Variant = bindings.get(entity_id, {})
	return value if value is Dictionary else {}

func get_active_map_id() -> String:
	return str(snapshot.get("active_map_id", "")) if has_snapshot() else ""

func get_fact_value(key: String, default_value: Variant = null) -> Variant:
	var facts := get_facts()
	if not facts.has(key):
		return default_value
	return unwrap_fact(facts[key], default_value)

func find_first_fact(keys: Array[String], default_value: Variant = null) -> Variant:
	var facts := get_facts()
	for key in keys:
		if facts.has(key):
			return unwrap_fact(facts[key], default_value)
	return default_value

func get_map_visual() -> Dictionary:
	var raw := find_first_fact(["map_visual", "visual_map", "map_presentation"], {})
	return raw if raw is Dictionary else {}

func get_fog_descriptor() -> Dictionary:
	var raw := find_first_fact(["fog_of_war", "fog", "visibility_mask"], {})
	return raw if raw is Dictionary else {}

func get_path_descriptor() -> Dictionary:
	var raw := find_first_fact(["movement_path", "path_preview", "authoritative_path"], {})
	if raw is Array:
		return {"points": raw, "authoritative": true}
	return raw if raw is Dictionary else {}

func get_ambience_path() -> String:
	var raw := find_first_fact(["ambience", "ambient_audio", "map_ambience"], "")
	if raw is Dictionary:
		raw = raw.get("path", raw.get("audio", ""))
	var path := str(raw)
	return path if resource_path_is_safe(path) else ""

func resource_path_is_safe(path: String) -> bool:
	if path.is_empty() or not path.begins_with("res://"):
		return false
	if ".." in path or "\\" in path:
		return false
	return ResourceLoader.exists(path)

func unwrap_fact(value: Variant, default_value: Variant = null) -> Variant:
	if value is not Dictionary:
		return value
	var row: Dictionary = value
	for key in ["value", "data", "state", "payload"]:
		if row.has(key):
			return row[key]
	return row if not row.is_empty() else default_value

func _request_runtime_snapshot() -> void:
	_request_in_flight = true
	var request := HTTPRequest.new()
	request.timeout = 12.0
	add_child(request)
	request.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, response_body: PackedByteArray) -> void:
		_request_in_flight = false
		var text := response_body.get_string_from_utf8()
		request.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			last_error = "runtime network request failed (%s)" % result
			_set_available(false)
			return
		var payload: Variant = JSON.parse_string(text) if not text.is_empty() else {}
		if response_code < 200 or response_code >= 300:
			# AdvancedGameEngine without WorldPlatform support returns 409. Treat
			# that as a graceful fallback to the legacy state renderer.
			last_error = "HTTP %s" % response_code
			_set_available(false)
			return
		if payload is not Dictionary:
			last_error = "unexpected runtime snapshot payload"
			_set_available(false)
			return
		_apply_snapshot(payload)
	)
	var identity := AppState.owner_client_id if not AppState.owner_client_id.is_empty() else AppState.client_id
	var headers := PackedStringArray(["Accept: application/json"])
	if not identity.is_empty():
		headers.append("X-RPG-Client-ID: %s" % identity)
	var path := "/api/v1/campaigns/%s/runtime?actor_id=%s" % [_campaign_id.uri_encode(), _actor_id.uri_encode()]
	var error := request.request(AppState.api_base + path, headers, HTTPClient.METHOD_GET)
	if error != OK:
		_request_in_flight = false
		request.queue_free()
		last_error = "could not start runtime request: %s" % error_string(error)
		_set_available(false)

func _apply_snapshot(payload: Dictionary) -> void:
	if str(payload.get("campaign_id", "")) != AppState.campaign_id:
		return
	var previous_map := get_active_map_id()
	var next_hash := str(payload.get("snapshot_hash", ""))
	var next_map := str(payload.get("active_map_id", ""))
	snapshot = payload.duplicate(true)
	_snapshot_hash = next_hash
	last_error = ""
	_set_available(true)
	if next_map != previous_map:
		map_changed.emit(next_map, previous_map)
	# Sequence may change even if a backend does not expose a hash, so always
	# notify after a successful authoritative snapshot.
	snapshot_changed.emit(snapshot)

func _set_available(value: bool) -> void:
	if available == value:
		return
	available = value
	availability_changed.emit(value)

func _clear_snapshot() -> void:
	var had_snapshot := not snapshot.is_empty()
	snapshot.clear()
	_snapshot_hash = ""
	last_error = ""
	_set_available(false)
	if had_snapshot:
		snapshot_changed.emit({})

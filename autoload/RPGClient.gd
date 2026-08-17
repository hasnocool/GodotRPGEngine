# autoload/RPGClient.gd
extends Node

enum ConnectionState { DISCONNECTED, CONNECTING, CONNECTED, RECONNECTING }

signal campaigns_received(campaigns: Array)
signal campaign_created(campaign: Dictionary)
signal campaign_joined(identity: Dictionary)
signal characters_received(characters: Array)
signal character_catalog_received(catalog: Dictionary)
signal character_created(character: Dictionary)
signal state_received(state: Dictionary)
signal event_received(event: Dictionary)
signal command_acknowledged(payload: Dictionary)
signal request_failed(context: String, message: String)
signal connection_state_changed(state: ConnectionState)

var _socket := WebSocketPeer.new()
var _connection_state := ConnectionState.DISCONNECTED
var _campaign_id := ""
var _client_id := ""
var _request_counter := 0
var _pending_commands: Dictionary = {}
var _reconnect_attempt := 0
var _next_reconnect_at := 0.0
var _state_dirty := false
var _next_state_request_at := 0.0

func _ready() -> void:
	set_process(true)

func get_connection_state() -> ConnectionState:
	return _connection_state

func is_connected_to_campaign() -> bool:
	return _connection_state == ConnectionState.CONNECTED

func list_campaigns() -> void:
	_rest("GET", "/api/v1/campaigns", {}, "campaigns", func(payload: Variant) -> void:
		var campaigns: Array = []
		if payload is Array:
			campaigns = payload
		elif payload is Dictionary:
			campaigns = payload.get("campaigns", payload.get("items", []))
		campaigns_received.emit(campaigns)
	)

func create_campaign(name: String, time_mode: String = "hybrid") -> void:
	var body := {
		"name": name,
		"owner_id": AppState.user_id,
		"time_mode": time_mode,
	}
	_rest("POST", "/api/v1/campaigns", body, "create_campaign", func(payload: Variant) -> void:
		if payload is not Dictionary:
			request_failed.emit("create_campaign", "Engine returned an unexpected campaign payload")
			return
		var campaign: Dictionary = payload
		var campaign_id := str(campaign.get("id", campaign.get("campaign_id", "")))
		var owner_client_id := str(campaign.get("owner_client_id", ""))
		if not campaign_id.is_empty():
			AppState.set_campaign(campaign_id, str(campaign.get("name", name)))
		if not owner_client_id.is_empty():
			AppState.owner_client_id = owner_client_id
			AppState.set_client_id(owner_client_id)
		campaign_created.emit(campaign)
	)

func join_campaign(campaign_id: String, user_id: String = AppState.user_id, display_name: String = AppState.display_name) -> void:
	_join_identity(campaign_id, user_id, display_name, Callable())

func _join_identity(campaign_id: String, user_id: String, display_name: String, callback: Callable) -> void:
	var body := {
		"user_id": user_id,
		"display_name": display_name,
		"role": "player",
		"actor_ids": [],
	}
	_rest("POST", "/api/v1/campaigns/%s/join" % campaign_id.uri_encode(), body, "join_campaign", func(payload: Variant) -> void:
		if payload is not Dictionary:
			request_failed.emit("join_campaign", "Engine returned an unexpected session identity")
			return
		var identity: Dictionary = payload
		var joined_client_id := str(identity.get("client_id", ""))
		if joined_client_id.is_empty():
			request_failed.emit("join_campaign", "Engine did not return a client ID")
			return
		AppState.set_client_id(joined_client_id)
		if str(identity.get("role", "")) == "owner":
			AppState.owner_client_id = joined_client_id
		campaign_joined.emit(identity)
		if callback.is_valid():
			callback.call(identity)
	)

func list_characters(campaign_id: String = AppState.campaign_id) -> void:
	_rest("GET", "/api/v1/campaigns/%s/characters" % campaign_id.uri_encode(), {}, "characters", func(payload: Variant) -> void:
		var characters: Array = []
		if payload is Array:
			characters = payload
		elif payload is Dictionary:
			characters = payload.get("characters", payload.get("items", []))
		characters_received.emit(characters)
	)

func get_character_catalog(campaign_id: String = AppState.campaign_id) -> void:
	_rest("GET", "/api/v1/campaigns/%s/characters/catalog" % campaign_id.uri_encode(), {}, "character_catalog", func(payload: Variant) -> void:
		character_catalog_received.emit(payload if payload is Dictionary else {})
	)

func create_character(build: Dictionary, campaign_id: String = AppState.campaign_id) -> void:
	var normalized_build := build.duplicate(true)
	normalized_build["owner_id"] = AppState.user_id
	_join_identity(campaign_id, AppState.user_id, AppState.display_name, func(_identity: Dictionary) -> void:
		_rest("POST", "/api/v1/campaigns/%s/characters" % campaign_id.uri_encode(), normalized_build, "create_character", func(payload: Variant) -> void:
			if payload is Dictionary:
				character_created.emit(payload)
			else:
				request_failed.emit("create_character", "Engine returned an unexpected character payload")
		)
	)

func connect_campaign(campaign_id: String, _client_id_hint: String = "") -> void:
	disconnect_campaign()
	_campaign_id = campaign_id
	_set_connection_state(ConnectionState.CONNECTING)
	_join_identity(campaign_id, AppState.user_id, AppState.display_name, func(identity: Dictionary) -> void:
		_client_id = str(identity.get("client_id", ""))
		if _client_id.is_empty():
			request_failed.emit("websocket", "Join did not return a usable client ID")
			_set_connection_state(ConnectionState.DISCONNECTED)
			return
		_reconnect_attempt = 0
		_open_websocket()
	)

func _open_websocket() -> void:
	_socket = WebSocketPeer.new()
	var url := "%s/api/v1/campaigns/%s/ws?client_id=%s" % [AppState.ws_base, _campaign_id.uri_encode(), _client_id.uri_encode()]
	_set_connection_state(ConnectionState.CONNECTING)
	var error := _socket.connect_to_url(url)
	if error != OK:
		request_failed.emit("websocket", "Could not connect to campaign: %s" % error_string(error))
		_schedule_reconnect()

func disconnect_campaign() -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.close(1000, "client navigation")
	_socket = WebSocketPeer.new()
	_pending_commands.clear()
	_state_dirty = false
	_reconnect_attempt = 0
	_set_connection_state(ConnectionState.DISCONNECTED)

func send_command(command: Dictionary, narrate: bool = true) -> String:
	if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		request_failed.emit("command", "The campaign connection is not open")
		return ""
	_request_counter += 1
	var request_id := "godot_%s_%s" % [Time.get_ticks_usec(), _request_counter]
	var envelope := {
		"kind": "command",
		"request_id": request_id,
		"command": command,
		"narrate": narrate,
	}
	_pending_commands[request_id] = {"sent_at": Time.get_ticks_msec(), "command": command}
	_socket.send_text(JSON.stringify(envelope))
	return request_id

func request_state() -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify({"kind": "state"}))

func _process(_delta: float) -> void:
	var ready_state := _socket.get_ready_state()
	if ready_state == WebSocketPeer.STATE_CONNECTING or ready_state == WebSocketPeer.STATE_OPEN:
		_socket.poll()
		ready_state = _socket.get_ready_state()

	if ready_state == WebSocketPeer.STATE_OPEN:
		if _connection_state != ConnectionState.CONNECTED:
			_reconnect_attempt = 0
			_set_connection_state(ConnectionState.CONNECTED)
			request_state()
		while _socket.get_available_packet_count() > 0:
			var raw := _socket.get_packet().get_string_from_utf8()
			var parsed: Variant = JSON.parse_string(raw)
			if parsed is Dictionary:
				_handle_ws_message(parsed)
		var now := Time.get_ticks_msec() / 1000.0
		if _state_dirty and now >= _next_state_request_at:
			_state_dirty = false
			_next_state_request_at = now + 0.12
			request_state()
	elif ready_state == WebSocketPeer.STATE_CLOSED and _connection_state in [ConnectionState.CONNECTED, ConnectionState.CONNECTING]:
		_schedule_reconnect()

	if _connection_state == ConnectionState.RECONNECTING:
		var reconnect_now := Time.get_ticks_msec() / 1000.0
		if reconnect_now >= _next_reconnect_at:
			_open_websocket()

func _handle_ws_message(message: Dictionary) -> void:
	match str(message.get("kind", "")):
		"state":
			var state: Dictionary = message.get("state", message.get("payload", {}))
			AppState.current_state = state
			_resolve_player_actor(state)
			state_received.emit(state)
		"event":
			var event: Dictionary = message.get("event", message.get("payload", {}))
			event_received.emit(event)
			_mark_state_dirty()
		"ack":
			var request_id := str(message.get("request_id", ""))
			_pending_commands.erase(request_id)
			command_acknowledged.emit(message)
			_mark_state_dirty()
		"error":
			var request_id := str(message.get("request_id", ""))
			_pending_commands.erase(request_id)
			request_failed.emit("command", str(message.get("detail", "Unknown engine error")))

func _mark_state_dirty() -> void:
	_state_dirty = true

func _resolve_player_actor(state: Dictionary) -> void:
	var campaign: Dictionary = state.get("campaign", {})
	var entities: Dictionary = campaign.get("entities", {})
	for entity_id in entities:
		var entity: Dictionary = entities[entity_id]
		if str(entity.get("controller", "")) != "human":
			continue
		var owner_id := str(entity.get("owner_id", entity.get("owner_client_id", "")))
		if owner_id.is_empty() or owner_id == AppState.user_id or owner_id == _client_id:
			AppState.set_player_actor(str(entity_id))
			return

func _schedule_reconnect() -> void:
	if _campaign_id.is_empty():
		_set_connection_state(ConnectionState.DISCONNECTED)
		return
	_reconnect_attempt += 1
	if _reconnect_attempt > 8:
		_set_connection_state(ConnectionState.DISCONNECTED)
		request_failed.emit("websocket", "Campaign connection could not be restored")
		return
	_set_connection_state(ConnectionState.RECONNECTING)
	var delay := minf(pow(2.0, float(_reconnect_attempt - 1)), 20.0) + randf_range(0.0, 0.75)
	_next_reconnect_at = Time.get_ticks_msec() / 1000.0 + delay

func _set_connection_state(value: ConnectionState) -> void:
	if _connection_state == value:
		return
	_connection_state = value
	connection_state_changed.emit(value)

func _rest(method: String, path: String, body: Dictionary, context: String, callback: Callable) -> void:
	var request := HTTPRequest.new()
	request.timeout = 15.0
	add_child(request)
	request.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, response_body: PackedByteArray) -> void:
		var text := response_body.get_string_from_utf8()
		request.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			request_failed.emit(context, "Network request failed (%s)" % result)
			return
		var payload: Variant = JSON.parse_string(text) if not text.is_empty() else {}
		if response_code < 200 or response_code >= 300:
			var detail := text
			if payload is Dictionary:
				detail = str(payload.get("detail", payload.get("message", text)))
			request_failed.emit(context, "HTTP %s: %s" % [response_code, detail])
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
		request_failed.emit(context, "Could not start request: %s" % error_string(error))

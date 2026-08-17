# autoload/AppState.gd
extends Node

signal screen_changed(screen: String)
signal campaign_changed(campaign_id: String)
signal player_changed(actor_id: String)
signal selection_changed(entity_id: String)

const DEFAULT_API_BASE := "http://127.0.0.1:8000"
const DEFAULT_WS_BASE := "ws://127.0.0.1:8000"

var api_base: String = DEFAULT_API_BASE
var ws_base: String = DEFAULT_WS_BASE
var client_id: String = ""
var owner_client_id: String = ""
var campaign_id: String = ""
var campaign_name: String = ""
var player_actor_id: String = ""
var selected_entity_id: String = ""
var current_state: Dictionary = {}
var current_screen: String = "lobby"

func _ready() -> void:
	_load_preferences()

func set_server_base(value: String) -> void:
	var clean := value.strip_edges().trim_suffix("/")
	if clean.is_empty():
		clean = DEFAULT_API_BASE
	api_base = clean
	if clean.begins_with("https://"):
		ws_base = "wss://" + clean.trim_prefix("https://")
	elif clean.begins_with("http://"):
		ws_base = "ws://" + clean.trim_prefix("http://")
	else:
		api_base = "http://" + clean
		ws_base = "ws://" + clean
	_save_preferences()

func set_campaign(id: String, display_name: String = "") -> void:
	campaign_id = id
	campaign_name = display_name
	selected_entity_id = ""
	campaign_changed.emit(id)

func set_player_actor(actor_id: String) -> void:
	if player_actor_id == actor_id:
		return
	player_actor_id = actor_id
	player_changed.emit(actor_id)

func set_selected_entity(entity_id: String) -> void:
	if selected_entity_id == entity_id:
		return
	selected_entity_id = entity_id
	selection_changed.emit(entity_id)

func set_screen(screen: String) -> void:
	if current_screen == screen:
		return
	current_screen = screen
	screen_changed.emit(screen)

func reset_campaign() -> void:
	campaign_id = ""
	campaign_name = ""
	owner_client_id = ""
	player_actor_id = ""
	selected_entity_id = ""
	current_state = {}

func get_entities() -> Dictionary:
	var campaign: Dictionary = current_state.get("campaign", {})
	return campaign.get("entities", {})

func get_entity(entity_id: String) -> Dictionary:
	return get_entities().get(entity_id, {})

func _load_preferences() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://client.cfg") != OK:
		return
	api_base = str(cfg.get_value("network", "api_base", DEFAULT_API_BASE))
	ws_base = str(cfg.get_value("network", "ws_base", DEFAULT_WS_BASE))
	client_id = str(cfg.get_value("identity", "client_id", ""))

func _save_preferences() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("network", "api_base", api_base)
	cfg.set_value("network", "ws_base", ws_base)
	cfg.set_value("identity", "client_id", client_id)
	cfg.save("user://client.cfg")

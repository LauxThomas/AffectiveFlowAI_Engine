# Autoload "PilotUploadService" (see project.godot [autoload]). No class_name
# - would collide with the autoload's own global identifier.
#
# Off by default and inert until a researcher fills in a Supabase URL + anon
# key in Settings. Deliberately narrow scope: only self-report check-ins
# (ui/self_report_overlay.gd) are ever uploaded, never the per-150ms tick
# log SessionLogger writes locally - a check-in is a handful of ratings the
# player chose to submit, not a continuous behavioral stream, so this is the
# only thing that should leave the device even in a pilot build. This is an
# addition on top of local logging, not a replacement for it - SessionLogger
# itself still writes nothing but user:// and makes no network calls.
extends Node

const CONFIG_PATH := "user://pilot_config.json"
const TABLE_PATH := "/rest/v1/pilot_sessions"

# Baked-in defaults for this project's own pilot Supabase instance, so
# testers don't have to type these in by hand. This is a "publishable" key
# by Supabase's own naming (sb_publishable_...), explicitly meant to be
# shipped client-side - it's safe here only because the `pilot_sessions`
# table's Row Level Security policy grants `anon` insert-only, never
# select/update/delete (see docs/TECHNICAL_BRIEF.md §7). Still requires the
# Settings checkbox to be turned on - baked-in config alone doesn't start
# uploading anything.
const DEFAULT_URL := "https://ivkxtgqvgabephdfsalc.supabase.co"
const DEFAULT_ANON_KEY := "sb_publishable_RgUhWgWXC5y_s7BLhf7z8w_szkIcoIM"

var _http: HTTPRequest
var _url: String = DEFAULT_URL
var _anon_key: String = DEFAULT_ANON_KEY
var _enabled: bool = false
var _participant_id: String = ""

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_participant_id = _load_or_create_participant_id()
	_load_config()   # a saved user:// config (e.g. pointed at a different project) still wins over the baked-in default

func set_config(url: String, anon_key: String) -> void:
	_url = url.strip_edges()
	_anon_key = anon_key.strip_edges()
	_save_config()

func get_url() -> String:
	return _url

func get_anon_key() -> String:
	return _anon_key

func is_configured() -> bool:
	return not _url.is_empty() and not _anon_key.is_empty()

func set_enabled(value: bool) -> void:
	_enabled = value
	_save_config()

func is_enabled() -> bool:
	return _enabled and is_configured()

func upload_self_report(
	ratings: Dictionary,
	state: AffectiveTypes.CognitiveState,
	load: float,
	confidence: float,
	features: Dictionary
) -> void:
	if not is_enabled():
		return
	var body: Dictionary = {
		"session_id": _participant_id,
		"kind": "self_report",
		"payload": {
			"t": Time.get_ticks_usec(),
			"ratings": ratings,
			"predicted_state": int(state),
			"load": load,
			"confidence": confidence,
			"features": features,
		},
	}
	var headers := PackedStringArray([
		"apikey: %s" % _anon_key,
		"Authorization: Bearer %s" % _anon_key,
		"Content-Type: application/json",
		"Prefer: return=minimal",
	])
	# Fire-and-forget: a dropped upload (offline, request already in flight,
	# misconfigured project) should never affect gameplay or block the
	# already-succeeded local save. HTTPRequest can only hold one request at
	# a time, but check-ins are player-paced (seconds apart at minimum), so
	# ERR_BUSY in practice shouldn't happen.
	_http.request(_url.trim_suffix("/") + TABLE_PATH, headers, HTTPClient.METHOD_POST, JSON.stringify(body))

func _load_or_create_participant_id() -> String:
	var path := "user://pilot_participant_id.txt"
	if FileAccess.file_exists(path):
		var existing: String = FileAccess.get_file_as_string(path).strip_edges()
		if not existing.is_empty():
			return existing
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var parts: Array[String] = []
	for i in 4:
		parts.append("%08x" % rng.randi())
	var new_id := "-".join(parts)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(new_id)
		file.close()
	return new_id

func _save_config() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"url": _url, "anon_key": _anon_key, "enabled": _enabled}))
	file.close()

func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var config := parsed as Dictionary
	# Empty saved values fall back to the baked-in default rather than
	# clearing it - only a genuinely different, explicitly-saved URL/key
	# should override the default.
	var saved_url := String(config.get("url", ""))
	var saved_key := String(config.get("anon_key", ""))
	if not saved_url.is_empty():
		_url = saved_url
	if not saved_key.is_empty():
		_anon_key = saved_key
	_enabled = bool(config.get("enabled", false))

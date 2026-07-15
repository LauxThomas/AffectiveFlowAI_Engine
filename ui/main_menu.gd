extends Control

@onready var play_button: Button = $PlayButton
@onready var edit_content_button: Button = $EditContentButton
@onready var settings_button: Button = $SettingsButton
@onready var settings_panel: PanelContainer = $SettingsPanel
@onready var obstacles_check: CheckBox = $SettingsPanel/SettingsScroll/SettingsContent/ObstaclesCheck
@onready var question_interval_spin: SpinBox = $SettingsPanel/SettingsScroll/SettingsContent/QuestionIntervalRow/QuestionIntervalSpin
@onready var consent_check: CheckBox = $SettingsPanel/SettingsScroll/SettingsContent/ConsentCheck
@onready var sessions_status_label: Label = $SettingsPanel/SettingsScroll/SettingsContent/SessionsStatusLabel
@onready var export_sessions_button: Button = $SettingsPanel/SettingsScroll/SettingsContent/SessionButtons/ExportSessionsButton
@onready var delete_sessions_button: Button = $SettingsPanel/SettingsScroll/SettingsContent/SessionButtons/DeleteSessionsButton
@onready var export_sessions_dialog: FileDialog = $SettingsPanel/ExportSessionsDialog
@onready var delete_sessions_confirm: ConfirmationDialog = $SettingsPanel/DeleteSessionsConfirm
@onready var pilot_url_edit: LineEdit = $SettingsPanel/SettingsScroll/SettingsContent/PilotUrlEdit
@onready var pilot_key_edit: LineEdit = $SettingsPanel/SettingsScroll/SettingsContent/PilotKeyEdit
@onready var save_pilot_config_button: Button = $SettingsPanel/SettingsScroll/SettingsContent/SavePilotConfigButton
@onready var pilot_upload_check: CheckBox = $SettingsPanel/SettingsScroll/SettingsContent/PilotUploadCheck
@onready var pilot_status_label: Label = $SettingsPanel/SettingsScroll/SettingsContent/PilotStatusLabel

func _ready() -> void:
	settings_panel.visible = false
	play_button.pressed.connect(_on_play_pressed)
	edit_content_button.pressed.connect(_on_edit_content_pressed)
	settings_button.pressed.connect(_on_settings_pressed)

	obstacles_check.button_pressed = GameSession.obstacles_enabled
	obstacles_check.toggled.connect(_on_obstacles_toggled)

	question_interval_spin.value = GameSession.question_interval_sec
	question_interval_spin.value_changed.connect(_on_question_interval_changed)

	consent_check.button_pressed = AffectiveEngine.is_logging_enabled()
	consent_check.toggled.connect(_on_consent_toggled)
	export_sessions_button.pressed.connect(_on_export_sessions_pressed)
	delete_sessions_button.pressed.connect(_on_delete_sessions_pressed)

	export_sessions_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_sessions_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_sessions_dialog.filters = PackedStringArray(["*.json ; JSON Files"])
	export_sessions_dialog.file_selected.connect(_on_export_sessions_file_selected)
	if OS.get_name() == "Web":
		export_sessions_button.disabled = true
		export_sessions_button.tooltip_text = "Needs a browser file API (JavaScriptBridge) - TODO"

	delete_sessions_confirm.confirmed.connect(_on_delete_sessions_confirmed)

	pilot_url_edit.text = PilotUploadService.get_url()
	pilot_key_edit.text = PilotUploadService.get_anon_key()
	pilot_upload_check.button_pressed = PilotUploadService.is_enabled()
	save_pilot_config_button.pressed.connect(_on_save_pilot_config_pressed)
	pilot_upload_check.toggled.connect(_on_pilot_upload_toggled)
	_refresh_pilot_status()

	_refresh_sessions_status()

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://game/main.tscn")

func _on_edit_content_pressed() -> void:
	get_tree().change_scene_to_file("res://editor/content_editor.tscn")

func _on_settings_pressed() -> void:
	settings_panel.visible = not settings_panel.visible
	if settings_panel.visible:
		_refresh_sessions_status()

func _on_obstacles_toggled(enabled: bool) -> void:
	GameSession.obstacles_enabled = enabled

func _on_question_interval_changed(value: float) -> void:
	GameSession.question_interval_sec = value

func _on_consent_toggled(enabled: bool) -> void:
	AffectiveEngine.set_logging_consent(enabled)

func _refresh_sessions_status() -> void:
	sessions_status_label.text = "%d session(s) on disk" % SessionLogger.list_sessions().size()

func _on_export_sessions_pressed() -> void:
	export_sessions_dialog.popup_centered(Vector2i(480, 400))

func _on_export_sessions_file_selected(path: String) -> void:
	var bundle: Array = []
	for session_id in SessionLogger.list_sessions():
		bundle.append({"session_id": session_id, "content": SessionLogger.export_session(session_id)})
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(bundle))
	file.close()

func _on_delete_sessions_pressed() -> void:
	delete_sessions_confirm.popup_centered()

func _on_delete_sessions_confirmed() -> void:
	SessionLogger.delete_all_sessions()
	_refresh_sessions_status()

func _on_save_pilot_config_pressed() -> void:
	PilotUploadService.set_config(pilot_url_edit.text, pilot_key_edit.text)
	_refresh_pilot_status()

func _on_pilot_upload_toggled(enabled: bool) -> void:
	PilotUploadService.set_enabled(enabled)
	_refresh_pilot_status()

func _refresh_pilot_status() -> void:
	if not PilotUploadService.is_configured():
		pilot_status_label.text = "Not configured"
	elif PilotUploadService.is_enabled():
		pilot_status_label.text = "Configured - uploading check-ins"
	else:
		pilot_status_label.text = "Configured - upload off"

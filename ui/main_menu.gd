extends Control

@onready var play_button: Button = $PlayButton
@onready var edit_content_button: Button = $EditContentButton
@onready var settings_button: Button = $SettingsButton
@onready var settings_panel: PanelContainer = $SettingsPanel

func _ready() -> void:
	settings_panel.visible = false
	play_button.pressed.connect(_on_play_pressed)
	edit_content_button.pressed.connect(_on_edit_content_pressed)
	settings_button.pressed.connect(_on_settings_pressed)

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://game/main.tscn")

func _on_edit_content_pressed() -> void:
	get_tree().change_scene_to_file("res://editor/content_editor.tscn")

func _on_settings_pressed() -> void:
	settings_panel.visible = not settings_panel.visible

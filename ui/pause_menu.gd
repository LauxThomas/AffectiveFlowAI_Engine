# In-game pause overlay, toggled with ESC. process_mode ALWAYS so this node
# (and its buttons) keep receiving input while the rest of the tree is
# paused - everything else (obstacles/coins/AffectiveEngine's tick) freezes
# as expected.
extends CanvasLayer

@onready var panel: PanelContainer = $Panel
@onready var resume_button: Button = $Panel/VBoxContainer/ResumeButton
@onready var menu_button: Button = $Panel/VBoxContainer/MenuButton
@onready var _question_overlay: Node = get_node_or_null("../QuestionOverlay")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 90
	panel.visible = false
	resume_button.pressed.connect(_on_resume_pressed)
	menu_button.pressed.connect(_on_menu_pressed)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
			# Don't let ESC fight with an active question overlay - it
			# manages its own pause/resume lifecycle.
			if _question_overlay != null and _question_overlay.has_method("is_showing") and _question_overlay.is_showing():
				return
			_toggle_pause()

func _toggle_pause() -> void:
	panel.visible = not panel.visible
	get_tree().paused = panel.visible

func _on_resume_pressed() -> void:
	_toggle_pause()

func _on_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")

# Paused-game question overlay. process_mode ALWAYS so it (and its
# buttons) keep receiving input/timers while the rest of the tree is
# paused - main.gd pauses the tree before calling show_question().
#
# Scaffolding is driven by AdaptationParams.hint_level, snapshotted at the
# moment the question is shown (same pattern as the old lane-hint beacon):
#   0: full answer set, no hints
#   1: full answer set, plus the optional per-question "hint" text, plus a
#      subtle highlight on the correct answer
#   2: same as 1, and one random wrong answer is removed entirely
extends CanvasLayer
class_name QuestionOverlay

signal answer_chosen(correct: bool, question_id: String, time_to_answer_ms: float)

const FEEDBACK_DELAY_SEC := 1.2

@onready var panel: PanelContainer = $Panel
@onready var question_label: Label = $Panel/VBoxContainer/QuestionLabel
@onready var hint_label: Label = $Panel/VBoxContainer/HintLabel
@onready var feedback_label: Label = $Panel/VBoxContainer/FeedbackLabel

var _answer_buttons: Array[Button] = []
var _question_id: String = ""
var _start_usec: int = 0
var _shown_original_index: Array[int] = []   # button slot -> original answers[] index
var _correct_original_index: int = -1
var _resolved := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 95
	panel.visible = false
	var container := $Panel/VBoxContainer/AnswersContainer
	for i in 3:
		var btn := container.get_node("AnswerButton%d" % i) as Button
		btn.pressed.connect(_on_answer_pressed.bind(i))
		_answer_buttons.append(btn)

func is_showing() -> bool:
	return panel.visible

func show_question(item: Dictionary, hint_level: int) -> void:
	_resolved = false
	feedback_label.visible = false

	_question_id = String(item.get("question", ""))
	question_label.text = _question_id
	_correct_original_index = int(item.get("correct_index", 0))
	var answers: Array = item.get("answers", []) as Array
	var hint_text: String = String(item.get("hint", ""))

	var indices: Array[int] = []
	for i in answers.size():
		indices.append(i)
	if hint_level >= 2 and indices.size() > 2:
		var wrong_indices: Array[int] = indices.filter(func(i: int) -> bool: return i != _correct_original_index)
		wrong_indices.shuffle()
		indices.erase(wrong_indices[0])
	indices.shuffle()
	_shown_original_index = indices

	hint_label.visible = hint_level >= 1 and not hint_text.is_empty()
	hint_label.text = hint_text

	for i in _answer_buttons.size():
		var btn := _answer_buttons[i]
		if i < indices.size():
			btn.visible = true
			btn.disabled = false
			btn.text = String(answers[indices[i]])
			if hint_level >= 1 and indices[i] == _correct_original_index:
				_apply_scaffold_style(btn)
			else:
				_clear_scaffold_style(btn)
		else:
			btn.visible = false

	_start_usec = Time.get_ticks_usec()
	panel.visible = true

# Gold border, not the FLOW-state green - a scaffolded answer means "this is
# emphasized," and reusing the state color there would read as "you're in
# flow" instead. Buttons are reused across questions, so the non-highlighted
# ones must have this explicitly cleared each time, not just left alone.
func _apply_scaffold_style(btn: Button) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = AppTheme.INK_3
	style.border_color = AppTheme.GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10.0)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("focus", style)

func _clear_scaffold_style(btn: Button) -> void:
	btn.remove_theme_stylebox_override("normal")
	btn.remove_theme_stylebox_override("hover")
	btn.remove_theme_stylebox_override("focus")

func _on_answer_pressed(button_index: int) -> void:
	if _resolved:
		return
	_resolved = true
	var chosen_original_index: int = _shown_original_index[button_index]
	var correct: bool = chosen_original_index == _correct_original_index
	var time_to_answer_ms: float = float(Time.get_ticks_usec() - _start_usec) / 1000.0

	feedback_label.visible = true
	feedback_label.text = "Correct!" if correct else "Not quite."
	feedback_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5) if correct else Color(0.9, 0.3, 0.3))
	for btn in _answer_buttons:
		btn.disabled = true

	await get_tree().create_timer(FEEDBACK_DELAY_SEC).timeout

	panel.visible = false
	answer_chosen.emit(correct, _question_id, time_to_answer_ms)

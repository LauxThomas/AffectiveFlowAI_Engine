extends Area2D
class_name AnswerToken

signal resolved(correct: bool, question_id: String, question_start_usec: int)

var body_width := 130.0
var body_height := 90.0
var answer_text: String = ""
var is_correct: bool = false
var _question_id: String = ""
var _question_start_usec: int = 0
var _resolved := false

func setup(text: String, correct: bool, question_id: String, question_start_usec: int) -> void:
	answer_text = text
	is_correct = correct
	_question_id = question_id
	_question_start_usec = question_start_usec

func _ready() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(body_width, body_height)
	var cs := $CollisionShape2D as CollisionShape2D
	cs.shape = shape
	area_entered.connect(_on_area_entered)
	queue_redraw()

func _on_area_entered(_a: Area2D) -> void:
	if _resolved:
		return   # jeden Token nur einmal zählen (same idiom as Obstacle._hit/Coin._taken)
	_resolved = true
	queue_redraw()
	resolved.emit(is_correct, _question_id, _question_start_usec)

# Deliberately neutral before resolution - revealing correctness up front
# would defeat the point of the question. Only the separate hint beacon
# (player.gd, driven by AdaptationParams.hint_level) is allowed to reveal
# the correct lane, as an explicit scaffold.
func _draw() -> void:
	var w := body_width
	var h := body_height
	var bg := Color("2b3a4a")
	if _resolved:
		bg = Color("2f9e5c") if is_correct else Color("9e2f3d")
	draw_rect(Rect2(-w * 0.5, -h * 0.5, w, h), bg)
	draw_rect(Rect2(-w * 0.5, -h * 0.5, w, h), Color("f0c419"), false, 3.0)

	var font := ThemeDB.fallback_font
	var font_size := 32
	var text_size: Vector2 = font.get_string_size(answer_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	draw_string(font, Vector2(-text_size.x * 0.5, text_size.y * 0.3), answer_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)

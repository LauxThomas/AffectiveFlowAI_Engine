extends Area2D
class_name Obstacle

signal hit

var body_width := 130.0
var body_height := 150.0
var _hit := false

func _ready() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(body_width, body_height)
	var cs := $CollisionShape2D as CollisionShape2D
	cs.shape = shape
	area_entered.connect(_on_area_entered)
	queue_redraw()

func _on_area_entered(_a: Area2D) -> void:
	if _hit:
		return                # jeden Block nur einmal zählen
	_hit = true
	modulate.a = 0.7
	queue_redraw()
	hit.emit()

func _draw() -> void:
	var c := Color("d15b2b")
	if _hit:
		c = Color("8a8a8a")
	var w := body_width
	var h := body_height
	# Körper
	draw_rect(Rect2(-w * 0.5, -h * 0.5, w, h), c)
	# gelbe Kanten oben/unten
	draw_rect(Rect2(-w * 0.5, -h * 0.5, w, 10), Color("f0c419"))
	draw_rect(Rect2(-w * 0.5, h * 0.5 - 10, w, 10), Color("f0c419"))
	# Warnstreifen
	var sx := -w * 0.5 + 10.0
	while sx < w * 0.5 - 14.0:
		draw_rect(Rect2(sx, -h * 0.5 + 16.0, 10.0, h - 32.0), Color("2b2b2b"))
		sx += 26.0

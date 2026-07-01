extends Area2D
class_name Coin

signal collected

var _taken := false

func _ready() -> void:
	area_entered.connect(_on_area_entered)

func _on_area_entered(_a: Area2D) -> void:
	if _taken:
		return
	_taken = true
	collected.emit()
	queue_free()

func _draw() -> void:
	draw_circle(Vector2.ZERO, 24.0, Color("c99a12"))   # Rand
	draw_circle(Vector2.ZERO, 20.0, Color("f0c419"))   # Münze
	draw_circle(Vector2.ZERO, 9.0, Color("ffe680"))    # Glanz

extends Area2D

const SLIDE_SPEED := 1600.0   # px/s beim Lane-Wechsel
const SWIPE_MIN := 40.0       # Mindest-Swipe-Distanz in px

var lane_x: Array[float] = []
var current_lane := 1
var _target_x := 0.0
var _run_t := 0.0
var _touch_start := Vector2.ZERO
var _touching := false

func setup(lanes: Array[float], start_lane: int) -> void:
	lane_x = lanes
	current_lane = clampi(start_lane, 0, lane_x.size() - 1)
	position.x = lane_x[current_lane]
	_target_x = position.x

func _input(event: InputEvent) -> void:
	# Tastatur: A/D oder Pfeiltasten
	if event is InputEventKey:
		if event.pressed and not event.echo:
			match event.keycode:
				KEY_A, KEY_LEFT:
					_move_lane(-1)
				KEY_D, KEY_RIGHT:
					_move_lane(1)
	# Touch-Swipe
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touch_start = event.position
			_touching = true
		elif _touching:
			_touching = false
			_handle_swipe(event.position - _touch_start)
	# Maus-Drag (Swipe-Ersatz am Desktop)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_touch_start = event.position
				_touching = true
			elif _touching:
				_touching = false
				_handle_swipe(event.position - _touch_start)

func _handle_swipe(swipe: Vector2) -> void:
	if absf(swipe.x) < SWIPE_MIN:
		return
	if absf(swipe.x) <= absf(swipe.y):
		return   # eher vertikal -> ignorieren
	_move_lane(1 if swipe.x > 0.0 else -1)

func _move_lane(dir: int) -> void:
	if lane_x.is_empty():
		return
	current_lane = clampi(current_lane + dir, 0, lane_x.size() - 1)
	_target_x = lane_x[current_lane]

func _process(delta: float) -> void:
	if not lane_x.is_empty():
		position.x = move_toward(position.x, _target_x, SLIDE_SPEED * delta)
	_run_t += delta
	queue_redraw()

func flash() -> void:
	modulate = Color(1.0, 0.4, 0.4)
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color.WHITE, 0.35)

# ─── Läufer von hinten (rennt in den Bildschirm) ───────────
func _draw() -> void:
	var body := Color("3d7fd6")
	var dark := Color("2f63a8")
	var skin := Color("e8b58c")
	var bob := sin(_run_t * 16.0) * 3.0        # Wippen
	var swing := sin(_run_t * 16.0) * 8.0      # Arm/Bein-Schwung

	# Beine (gegenläufig)
	draw_rect(Rect2(-18, 20 + bob, 14, 24), dark)
	draw_rect(Rect2(4, 20 - bob, 14, 24), dark)
	# Körper
	draw_rect(Rect2(-22, -24 + bob, 44, 48), body)
	# Rucksack
	draw_rect(Rect2(-14, -16 + bob, 28, 30), dark)
	# Arme
	draw_rect(Rect2(-30, -18 + swing, 10, 30), body)
	draw_rect(Rect2(20, -18 - swing, 10, 30), body)
	# Kopf
	draw_circle(Vector2(0, -40 + bob), 14, skin)
	# Mütze
	draw_rect(Rect2(-14, -54 + bob, 28, 10), Color("d94f4f"))

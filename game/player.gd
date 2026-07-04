extends Area2D

const SLIDE_SPEED := 1600.0   # px/s beim Lane-Wechsel
const SWIPE_MIN := 40.0       # Mindest-Swipe-Distanz in px
const MAX_TOUCH_POINTS := 40  # cap against a pathological held-drag
const IDLE_THRESHOLD_USEC := 3_000_000   # 3s of no meaningful input

signal lane_switched(dir: int, usec: int)

var lane_x: Array[float] = []
var current_lane := 1
var _target_x := 0.0
var _run_t := 0.0
var _touch_start := Vector2.ZERO
var _touching := false
var _touch_points: Array[Vector2] = []
var _touch_start_usec := 0
var _last_input_usec := 0
var _idle_reported := false

func setup(lanes: Array[float], start_lane: int) -> void:
	lane_x = lanes
	current_lane = clampi(start_lane, 0, lane_x.size() - 1)
	position.x = lane_x[current_lane]
	_target_x = position.x
	_last_input_usec = Time.get_ticks_usec()

func _input(event: InputEvent) -> void:
	# Tastatur: A/D oder Pfeiltasten
	if event is InputEventKey:
		if event.pressed and not event.echo:
			_mark_input_active()
			match event.keycode:
				KEY_A, KEY_LEFT:
					_move_lane(-1)
				KEY_D, KEY_RIGHT:
					_move_lane(1)
	# Touch-Swipe
	elif event is InputEventScreenTouch:
		if event.pressed:
			_start_touch(event.position)
		elif _touching:
			_touching = false
			_handle_swipe(event.position - _touch_start, Time.get_ticks_usec() - _touch_start_usec)
	elif event is InputEventScreenDrag and _touching:
		_track_touch_point(event.position)
	# Maus-Drag (Swipe-Ersatz am Desktop)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_start_touch(event.position)
			elif _touching:
				_touching = false
				_handle_swipe(event.position - _touch_start, Time.get_ticks_usec() - _touch_start_usec)
	elif event is InputEventMouseMotion and _touching:
		_track_touch_point(event.position)

func _start_touch(pos: Vector2) -> void:
	_mark_input_active()
	_touch_start = pos
	_touch_start_usec = Time.get_ticks_usec()
	_touch_points = [pos]
	_touching = true

func _track_touch_point(pos: Vector2) -> void:
	if _touch_points.size() < MAX_TOUCH_POINTS:
		_touch_points.append(pos)

func _mark_input_active() -> void:
	_last_input_usec = Time.get_ticks_usec()
	_idle_reported = false

func _handle_swipe(swipe: Vector2, duration_usec: int) -> void:
	var accepted := absf(swipe.x) >= SWIPE_MIN and absf(swipe.x) > absf(swipe.y)
	var duration_sec: float = maxf(float(duration_usec) / 1_000_000.0, 0.001)
	var velocity: float = swipe.length() / duration_sec
	AffectiveEngine.report_event(AffectiveTypes.EventType.SWIPE, {
		"accepted": accepted,
		"velocity": velocity,
		"straightness": _path_straightness(),
		"duration_usec": duration_usec,
	})
	if not accepted:
		return   # eher vertikal oder zu kurz -> ignorieren
	_move_lane(1 if swipe.x > 0.0 else -1)

func _path_straightness() -> float:
	if _touch_points.size() < 3:
		return 1.0
	var path_len := 0.0
	for i in range(1, _touch_points.size()):
		path_len += _touch_points[i].distance_to(_touch_points[i - 1])
	var straight_len: float = _touch_points[0].distance_to(_touch_points[_touch_points.size() - 1])
	return 1.0 if path_len < 0.001 else clampf(straight_len / path_len, 0.0, 1.0)

func _move_lane(dir: int) -> void:
	if lane_x.is_empty():
		return
	current_lane = clampi(current_lane + dir, 0, lane_x.size() - 1)
	_target_x = lane_x[current_lane]
	var now_usec := Time.get_ticks_usec()
	AffectiveEngine.report_event(AffectiveTypes.EventType.LANE_SWITCH, {"dir": dir, "lane": current_lane})
	lane_switched.emit(dir, now_usec)

func _process(delta: float) -> void:
	if not lane_x.is_empty():
		position.x = move_toward(position.x, _target_x, SLIDE_SPEED * delta)
	_run_t += delta
	queue_redraw()
	if not _idle_reported and Time.get_ticks_usec() - _last_input_usec > IDLE_THRESHOLD_USEC:
		AffectiveEngine.report_event(AffectiveTypes.EventType.IDLE, {})
		_idle_reported = true

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

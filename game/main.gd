extends Node2D

# ─── Tuning ────────────────────────────────────────────────
const LANE_COUNT  := 3
const START_SPEED := 430.0   # vertikale Scrollgeschwindigkeit (px/s)
const MAX_SPEED   := 1050.0
const SPEED_GAIN  := 14.0     # wird über Zeit schneller
const HIT_FACTOR  := 0.6      # speed *= HIT_FACTOR bei Treffer
const MIN_SPEED   := 190.0    # Untergrenze -> stoppt nie
const SCORE_RATE  := 0.02

const OBSTACLE := preload("res://game/obstacle.tscn")
const COIN     := preload("res://game/coin.tscn")

# Hindernis-Presets: Breite / Höhe (Breite < Lane-Breite!)
const OB_PRESETS := [
	{ "w": 130, "h": 150 },   # "Zug"
	{ "w": 130, "h": 74 },    # Barriere
	{ "w": 96,  "h": 96 },    # Kiste
]

# ─── State ─────────────────────────────────────────────────
var speed := START_SPEED
var score := 0.0
var hits := 0
var coins := 0
var _dist_ob := 340.0
var _dist_coin := 220.0
var _scroll := 0.0
var _player_y := 0.0
var _lanes: Array[float] = []

@onready var player: Node2D = $Player
@onready var score_label: Label = $UI/ScoreLabel
@onready var coins_label: Label = $UI/CoinsLabel
@onready var hits_label: Label = $UI/HitsLabel

func _ready() -> void:
	randomize()
	var vp := get_viewport_rect().size
	_player_y = vp.y - 150.0
	for i in LANE_COUNT:
		_lanes.append(_lane_x(i, vp.x))
	player.position = Vector2(_lanes[1], _player_y)
	if player.has_method("setup"):
		player.setup(_lanes, 1)
	_update_ui()

func _lane_x(i: int, w: float) -> float:
	return w * (float(i) + 0.5) / float(LANE_COUNT)

func _process(delta: float) -> void:
	speed = minf(speed + SPEED_GAIN * delta, MAX_SPEED)
	var move := speed * delta
	score += move * SCORE_RATE
	_scroll += move
	var vp := get_viewport_rect().size

	# alles Scrollende nach unten bewegen + aufräumen
	for node in get_tree().get_nodes_in_group("scroll"):
		var n := node as Node2D
		if n == null:
			continue
		n.position.y += move
		if n.position.y > vp.y + 160.0:
			n.queue_free()

	# Hindernisse
	_dist_ob -= move
	if _dist_ob <= 0.0:
		_spawn_obstacles()
		var gap: float = maxf(240.0, speed * 0.55)
		_dist_ob = gap + randf_range(40.0, 220.0)

	# Münzen
	_dist_coin -= move
	if _dist_coin <= 0.0:
		_spawn_coin()
		_dist_coin = randf_range(150.0, 300.0)

	_update_ui()
	queue_redraw()

func _spawn_obstacles() -> void:
	# 1 oder 2 Lanes blockieren -> es bleibt IMMER mind. 1 Lane frei
	var count := 1 if randf() < 0.6 else 2
	var lanes: Array[int] = [0, 1, 2]
	lanes.shuffle()
	for k in count:
		var lane := lanes[k]
		var p: Dictionary = OB_PRESETS.pick_random()
		var ob := OBSTACLE.instantiate() as Obstacle
		ob.body_width = float(p.w)
		ob.body_height = float(p.h)
		ob.position = Vector2(_lanes[lane], -float(p.h))
		ob.add_to_group("scroll")
		ob.hit.connect(_on_obstacle_hit)
		add_child(ob)

func _spawn_coin() -> void:
	var lane := randi() % LANE_COUNT
	var c := COIN.instantiate() as Coin
	c.position = Vector2(_lanes[lane], -40.0)
	c.add_to_group("scroll")
	c.collected.connect(_on_coin_collected)
	add_child(c)

func _on_obstacle_hit() -> void:
	hits += 1
	speed = maxf(speed * HIT_FACTOR, MIN_SPEED)   # abbremsen statt stoppen
	if player.has_method("flash"):
		player.flash()
	_update_ui()

func _on_coin_collected() -> void:
	coins += 1
	_update_ui()

func _update_ui() -> void:
	score_label.text = "Score: %d" % int(score)
	coins_label.text = "Coins: %d" % coins
	hits_label.text = "Treffer: %d  |  %d px/s" % [hits, int(speed)]

# ─── Straße zeichnen ───────────────────────────────────────
func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color("343841"))          # Asphalt
	draw_rect(Rect2(0, 0, 6, vp.y), Color("f0c419"))             # Rand links
	draw_rect(Rect2(vp.x - 6, 0, 6, vp.y), Color("f0c419"))      # Rand rechts

	# gestrichelte Lane-Trenner, nach unten scrollend
	var period := 74.0
	var off := fmod(_scroll, period)
	for d in range(1, LANE_COUNT):
		var line_x := vp.x * float(d) / float(LANE_COUNT)
		var y := -period + off
		while y < vp.y:
			draw_rect(Rect2(line_x - 3.0, y, 6.0, 44.0), Color("cfd3da"))
			y += period

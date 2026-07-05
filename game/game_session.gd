# Autoload "GameSession" (see project.godot [autoload]). No class_name - same
# collision rule as AffectiveEngine. Tiny bit of cross-scene state so the
# Content Editor's Play-test button (C11) can hand a specific pack to the
# runner without a scene-parameter-passing mechanism.
extends Node

var forced_pack_id: String = ""
var active_pack_id: String = "math_basics"

# Off by default (removed for less on-screen clutter); toggled in
# Settings. Math Tunnels answer-gates still provide the core decision/
# error signal without them.
var obstacles_enabled: bool = false

func consume_forced_pack() -> String:
	var result: String = forced_pack_id
	forced_pack_id = ""
	return result

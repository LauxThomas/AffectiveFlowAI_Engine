# Autoload "GameSession" (see project.godot [autoload]). No class_name - same
# collision rule as AffectiveEngine. Tiny bit of cross-scene state so the
# Content Editor's Play-test button (C11) can hand a specific pack to the
# runner without a scene-parameter-passing mechanism.
extends Node

var forced_pack_id: String = ""
var active_pack_id: String = "math_basics"

func consume_forced_pack() -> String:
	var result: String = forced_pack_id
	forced_pack_id = ""
	return result

# AffectiveFlowAI MVP — build log

Running log of what's implemented, appended per commit. See project plan for
the full spec and acceptance criteria.

## C0 — Reorg
Moved the 4 existing runner scripts/scenes into `game/`. No behavior change.

## C1 — AffectiveEngine stub + Debug HUD skeleton
Added the `AffectiveEngine` autoload (façade, no `class_name` — would collide
with its own autoload name), `AffectiveTypes` (state/event enums), and
`AdaptationParams` (typed, clamped struct). Added the Debug HUD (`ui/`),
toggled with F3, showing a hardcoded FLOW state and neutral params — nothing
live yet, this lands in C3/C4. `AffectiveEngine`'s telemetry/estimator/policy
pipeline is empty on purpose; wired up incrementally in later commits.

## C2 — Telemetry instrumentation (report-only)
Added `TelemetryCollector` (capped ring buffer + lifetime counter). Instrumented
`player.gd`: lane switches and swipes (now tracking real duration, velocity,
path straightness via `InputEventScreenDrag`/`InputEventMouseMotion`), and
idle detection (no meaningful input for 3s). Instrumented `main.gd`: HIT
events on obstacle collision, plus a "decision zone" mechanic that reuses the
existing `"scroll"` group loop to time reaction latency and count direction
reversals (hesitation) as obstacles approach the player row — bundled into
one DECISION event per obstacle, fired at collision or off-screen escape.
Zero new fields on `obstacle.gd`/`coin.gd`; zone bookkeeping lives entirely in
`main.gd` via node metadata. Nothing consumes this data yet (no FeatureWindow
until C3) — the Debug HUD's new raw event counter is the only visible effect.

## C3 — FeatureWindow + live tick
Added `FeatureWindow` (6s/20-event rolling window -> 8 normalized [0,1]
features) and a child `Timer` (150ms) inside `AffectiveEngine` that pulls new
events each tick and re-extracts the feature vector. No estimator yet (state
is still hardcoded FLOW, that's C4) - this commit is purely "raw telemetry in,
normalized numbers out." The Debug HUD now shows a live bar per feature,
visibly reacting to swipe speed/hesitation/hits/idling in real time.

## C4 — HeuristicLoadModel + dwell-gated state
Added `ICognitiveLoadModel` (swappable seam) and `HeuristicLoadModel`: fuses
the normalized features into a Cognitive Load Index via documented weights,
squashes through a sigmoid to get `load`, and classifies BOREDOM/FLOW/OVERWHELM
from load level + idle ratio (a documented v1 simplification of the full
challenge/skill 2D balance, which needs a difficulty history that only exists
once C6 wires AdaptationParams into gameplay). No personal baseline yet (C5)
- features feed the formula directly. `AffectiveEngine` now dwell-gates state
transitions (a predicted state must hold for ~600ms before it's accepted),
satisfying "sustained condition, not per-frame flicker" without a full HMM.
The Debug HUD's state label now really changes color, and shows a live load
meter + confidence percentage (confidence scales with window sample count).

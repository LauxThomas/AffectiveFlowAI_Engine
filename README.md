# Lane Runner — AffectiveFlowAI Engine

A 3-lane, vertical-scroll endless runner (Godot 4.7, GDScript) with a real-time
cognitive-load estimator and adaptive-difficulty layer built on top of it.
Same no-fail core as a Dino-style runner — obstacles come from above, you
switch lanes to dodge, a hit slows you down rather than ending the run — but
instead of a flat difficulty curve, the game reads *how* you're playing
(swipe dynamics, reaction latency, hesitation, error rate) and keeps you in a
flow state while teaching real content (currently Cognitive Load Theory,
through the game that's measuring it).

For the deeper technical/scientific writeup (architecture, current model
status, path to a trained model, privacy posture), see
[`docs/TECHNICAL_BRIEF.md`](docs/TECHNICAL_BRIEF.md). For a running,
commit-by-commit build log, see [`docs/MVP_SPEC.md`](docs/MVP_SPEC.md).

## Setup

1. Clone the repo.
2. Open Godot **4.7**, choose **Import**, select `project.godot`.
3. Press **F5** to run. No external assets needed — everything is drawn with
   `_draw()` or built from Godot's built-in `Theme` system.

## Controls

- **A / D** or **← / →** — switch lane
- **Swipe left/right** (touch) — switch lane
- **Mouse drag** left/right — swipe substitute on desktop

## What's actually running

- Telemetry (lane switches, swipes, reaction latency, hesitation) feeds a
  rolling 6-second feature window, fused into a `{state, load, confidence}`
  reading roughly every 150ms, personalized against your own rolling
  baseline (not a fixed global threshold).
- That reading drives live difficulty (speed, spawn density, hints) and
  gates a periodic paused overlay with Cognitive Load Theory questions,
  scaffolded (hints, answer elimination) by how loaded you currently are.
- A small "Check-in" button in the run HUD opens an optional, manual
  self-report (lightweight NASA-TLX) — never on a timer, only when you tap
  it — used to build real ground-truth labels for a future trained model.
- Session logging (the full behavioral stream) is opt-in, off by default,
  anonymous, and on-device only — see Settings in the main menu.

The estimator and adaptation policy are documented v1 heuristics behind
swappable interfaces (`ICognitiveLoadModel`, `IAdaptationPolicy`), not a
trained model yet — `docs/TECHNICAL_BRIEF.md` §4–5 is explicit about this.

## Project structure

```
affective/   Game-agnostic engine: telemetry, feature extraction, the
             estimator (models/), the adaptation policy (policy/), the
             per-user baseline, session logging, optional pilot upload.
             Talks to game/ only through the AffectiveEngine autoload.
game/        The runner itself: main scene/loop, player, obstacles, coins.
ui/          Main menu, Settings, Debug HUD (F3), pause menu, the question
             and self-report overlays, the app-wide Theme.
editor/      In-app content editor for authoring question packs.
content/     Bundled question packs (JSON).
docs/        TECHNICAL_BRIEF.md (external-facing) and MVP_SPEC.md (build log).
```

## Tuning knobs (`game/main.gd`)

| Constant | Effect |
|---|---|
| `LANE_COUNT` | Number of lanes (default 3) |
| `HIT_FACTOR` | Speed penalty on a hit |
| `MIN_SPEED` | Floor — the run never fully stops |
| `SPEED_GAIN` | Natural acceleration over time |
| `MAX_SPEED` | Speed ceiling |
| `OB_PRESETS` | Obstacle sizes |

Lane-switch slide speed: `SLIDE_SPEED` in `game/player.gd`.
Swipe sensitivity: `SWIPE_MIN` in `game/player.gd`.
Question-overlay interval and obstacle toggle: Settings, in-game.

## Technical notes

- Collision uses `Area2D`: only the player is `monitorable`, obstacles and
  coins are `monitoring` with `collision_mask = 1` — so they detect the
  player but never each other.
- Obstacle spawns never block all lanes at once (max. 2 of 3) — at least
  one lane is always open, so the run is always solvable.
- Everything scrolling belongs to the `scroll` group and is moved/cleaned
  up centrally in `main.gd`.
- No threads anywhere (the Web export preset has `thread_support=false`);
  the estimator ticks on a plain `Timer`, not a per-frame accumulator.

## Deployment

Pushes to `main` build a Web export and deploy it to GitHub Pages via
`.github/workflows/deploy.yml` (also runnable manually from the Actions
tab, or `gh workflow run deploy.yml`).

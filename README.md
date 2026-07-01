# Lane Runner (Godot 4.x) – Subway-Surfers-Style

3-Lane-Endlessrunner mit **vertikalem Scrolling**. Hindernisse kommen von oben,
du wechselst die Lane, um auszuweichen. Gleiche Kernmechanik wie beim Dino:
**kein Game-Over** – bei Kontakt zählt ein **Treffer-Counter** hoch und die
**Geschwindigkeit sinkt** (mit Untergrenze). Zusätzlich sammelst du **Coins**.

## Setup
1. Ordner anlegen, alle Dateien hineinkopieren.
2. Godot → **Import** → `project.godot` → öffnen → F5.
3. Keine externen Assets nötig (alles per `_draw()`).

## Steuerung
- **A / D** oder **← / →** = Lane wechseln
- **Swipe links/rechts** (Touch) = Lane wechseln
- **Maus-Drag** links/rechts = Swipe-Ersatz am Desktop

## Dateien
- `project.godot` – Konfig (Portrait 540×960)
- `main.tscn` / `main.gd`         – Lanes, Scrolling, Spawner, Score/Coins/Treffer
- `player.tscn` / `player.gd`     – Läufer: Lane-Wechsel (Tasten + Swipe) + Slide
- `obstacle.tscn` / `obstacle.gd` – Hindernis (Area2D, Kollision ohne Stopp)
- `coin.tscn` / `coin.gd`         – Münze (Area2D, einsammelbar)

## Stellschrauben (`main.gd`)
| Konstante     | Wirkung                                  |
|---------------|------------------------------------------|
| `LANE_COUNT`  | Anzahl Lanes (Standard 3)                |
| `HIT_FACTOR`  | Bremsstärke pro Treffer                  |
| `MIN_SPEED`   | Untergrenze – stoppt nie                 |
| `SPEED_GAIN`  | Beschleunigung über Zeit                 |
| `MAX_SPEED`   | Tempo-Obergrenze                         |
| `OB_PRESETS`  | Größen der Hindernisse                   |

Slide-Tempo beim Lane-Wechsel: `SLIDE_SPEED` in `player.gd`.
Swipe-Empfindlichkeit: `SWIPE_MIN` in `player.gd`.

## Technik-Notizen
- Kollision läuft über `Area2D`: nur der Spieler ist `monitorable`, Hindernisse
  und Coins `monitoring` mit `collision_mask = 1`. Dadurch erkennen sie den
  Spieler, aber nicht sich gegenseitig.
- Beim Spawnen werden nie alle 3 Lanes blockiert (max. 2), es bleibt immer eine
  freie Lane – das Spiel ist also immer lösbar.
- Alle scrollenden Objekte liegen in der Gruppe `scroll` und werden zentral
  bewegt/aufgeräumt.

# CreativeJam26 — Architecture Guide

A 2D action platformer built in **Godot 4.7** (GDScript, Forward+). The player runs, jumps, dashes and slashes through single-screen levels (Hollow Knight-style). The core mechanic is **Recall**: press `R` to rewind the whole level about 5 seconds. Each rewind leaves an **Echo** enemy behind where you were.

All visuals are placeholder `ColorRect`s. There are no sprites or animations yet.

---

## 1. Folder map

```
project.godot              Engine config: main scene, autoloads, input map, physics layers
scripts/
  autoload/
    game_manager.gd        GLOBAL: tick clocks, level flow, player/enemy registry, key logic
    recall.gd              GLOBAL: the rewind system (undo stack + playback)
  level.gd                 Root script of every level scene (class Level)
  player.gd                Player controller (class Player)
  platform.gd              @tool solid block with editable size (class Platform)
  level_exit.gd            Exit door (locked until key collected)
  key.gd                   Key pickup dropped by the level's strongest enemy
  ui/hud.gd                Debug HUD text
  enemies/
    enemy.gd               Base class Enemy (health, hit, death, recall hooks)
    walker.gd              Walker   extends Enemy  — patrols, turns at walls/ledges
    knight.gd              Knight   extends Walker — shield + sword swing
    backup_dancer.gd       BackupDancer extends Walker — pauses & puffs up periodically
    boss.gd                Boss     extends Walker — dying completes the level
    dragon.gd              Dragon   extends Enemy  — flies, shoots Fireballs
    dj.gd                  DJ       extends Enemy  — throws Vinyls, spawns BackupDancers
    fireball.gd, vinyl.gd  Projectiles (Area2D, not enemies)
scenes/
  levels/level_1..3.tscn, boss_level.tscn    The playable levels, in order
  player.tscn, platform.tscn, key.tscn, level_exit.tscn
  enemies/*.tscn           One scene per enemy/projectile (echo.tscn = walker.gd, dark color)
  ui/hud.tscn              HUD (autoload)
  recall_overlay.tscn      Full-screen ColorRect with the negative shader (autoload)
shaders/negative.gdshader  Inverts screen colors during recall freeze
```

Every `.gd` has a matching `.gd.uid` file. Godot generates these, so commit them and don't edit them.

---

## 2. Startup and autoloads

`project.godot` sets `run/main_scene = res://scenes/levels/level_1.tscn`. There is no menu yet.

Four **autoloads** (singletons) live under `/root` and survive scene changes:

| Name | Source | Role |
|---|---|---|
| `GameManager` | `scripts/autoload/game_manager.gd` | Clocks, registries, level transitions, key/exit state |
| `Hud` | `scenes/ui/hud.tscn` | On-screen debug label, reads from GameManager/Recall every frame |
| `Recall` | `scripts/autoload/recall.gd` | Records history and runs the rewind |
| `RecallOverlay` | `scenes/recall_overlay.tscn` | Screen-inversion overlay; `Recall` toggles `/root/RecallOverlay/CanvasLayer/RecallNegative` |

Any script can reach these by name, for example `GameManager.player` or `Recall.record(...)`.

### Physics processing order (important)

Each physics frame runs in this order:

1. **`GameManager`** (`process_physics_priority = -1000`) advances the clocks first.
2. **Gameplay nodes** (player, enemies, projectiles) run at default priority.
3. **`Recall`** (`process_physics_priority = 1000`) runs last. It records samples, or drives the rewind.

---

## 3. How everything links together

```
                 ┌──────────────── project.godot ────────────────┐
                 │ main_scene=level_1   autoloads   input map    │
                 └───────────────────────────────────────────────┘
                                   │ loads
                                   ▼
   Level scene (Node2D + level.gd)
   ├─ Camera2D (static, centered at 320,180)
   ├─ Geometry/   Platform instances (world, layer 1)
   ├─ Player      (player.tscn, layer 2)
   ├─ Enemies/    enemy instances (layer 3)   ◄── runtime spawns go here too
   └─ LevelExit

   Level._ready() ──► GameManager.register_level(self)
        • timeline_tick = 0
        • finds Player in group "player"  → connects died, recall_split
        • finds Enemies in group "enemies" → picks key_enemy (highest max_health)
        • emits level_started ──► Recall._on_level_started (clears stack, baselines)

   Player ──take_hit()──► Enemy            Enemy/projectile ──take_damage()──► Player
   Enemy.die() ──► GameManager.notify_enemy_died, drop_key() if key_enemy
   Key (picked up) ──► GameManager.collect_key()
   LevelExit (touched & unlocked) ──► GameManager.complete_level() ──► next LEVELS entry
   Player.died ──► GameManager.restart_level() (reload scene)
   Boss.die() ──► GameManager.complete_level()

   Player/Enemy damage & death ──► Recall.record(target, kind, undo_callable)
   Recall (R pressed) ──► freezes level, rewinds, Player.recall_split
                      ──► GameManager spawns Echo at the split point
   Hud._process ──► reads GameManager + Recall each frame
```

### Groups used for discovery

| Group | Who joins | Used by |
|---|---|---|
| `"player"` | `Player._ready` | `GameManager.register_level` |
| `"enemies"` | `Enemy._ready` | `GameManager.register_level` |
| `"recordable"` | `Player._ready`, `Enemy._ready` | `Recall` (samples, rewind, callbacks) |

### Physics layers (`project.godot` → `[layer_names]`)

| Layer | Bit value | Name | Who is on it |
|---|---|---|---|
| 1 | 1 | world | Platforms |
| 2 | 2 | player | Player body |
| 3 | 4 | enemies | All enemy bodies |

Masks worth knowing:
- Player `Hurtbox` and `SlashArea` mask = 4, so they detect enemies.
- Knight `SwordArea`, `Key` and `LevelExit` mask = 2, so they detect the player.
- `Fireball` and `Vinyl` mask = 3 (world + player), so they hit the player or vanish on walls.
- `Dragon` mask = 0, so it flies through everything.

---

## 4. The time model (read this before writing gameplay code)

**Gameplay code never keeps its own float timers.** Store the *tick* at which something happened, then compare it against the clock:

```gdscript
attack_start_tick = GameManager.timeline_tick
...
if GameManager.ticks_since(attack_start_tick) < GameManager.seconds_to_ticks(0.3):
    # still attacking
```

- `GameManager.real_tick`: never rewinds or resets. Use it for UI, run timers and recall phase timing.
- `GameManager.timeline_tick`: resets to 0 on level start and **runs backwards during recall**. All gameplay uses this clock.
- `GameManager.NEVER` (`-1_000_000_000`): the stamp for "hasn't happened". `ticks_since(NEVER)` is huge, so any "active within N seconds" check returns false.
- Helpers: `seconds_to_ticks`, `ticks_to_seconds`, `ticks_since`, `seconds_since`, `level_time_seconds`.

Why use ticks instead of float timers? Recall can move time backwards. A stamp stays valid as the clock rewinds. A decrementing float timer would not.

After a recall, any stamp **greater than** `timeline_tick` is "from the undone future". Every recordable's `on_recall_finished()` resets those stamps to `NEVER`. Subclasses in the repo repeat this pattern for their own stamps; see `knight.gd`, `dragon.gd` and `dj.gd`.

---

## 5. Recall system (`scripts/autoload/recall.gd`)

### Recording (while `_phase == NONE`)
- **Samples**: every `sample_interval` (0.2 s), each `"recordable"` node's `recall_sample()` dictionary is read. If it changed since the last sample, a `sample` event is pushed onto `_stack`.
- **Discrete events**: gameplay calls `Recall.record(target, kind, undo)` just before changing state. `undo` is a `Callable` that restores the prior state, usually a private method with `.bind(old_values)`. Current users:
  - `Player.take_damage` records `&"damaged"`, which restores health and hurt_tick.
  - `Enemy.take_hit` records `&"damaged"`, which restores health and last_hit_tick.
  - `Enemy.die` records `&"died"`, which runs `_set_alive(true)` (revives it).

### Recalling (four phases, timed with `real_tick`)
1. **FREEZE** (`freeze_before_seconds`): the level gets `process_mode = DISABLED` and the screen is inverted by the negative shader.
2. **REWIND**: the cursor moves back `_rewind_step` ticks per frame toward `now - recall_seconds` (5 s, clamped to 0), taking about `playback_seconds` (1.5 s). Events newer than the cursor are popped. Sample events become interpolated *segments* for smooth movement. Discrete events run their `undo`. `timeline_tick` is set to the cursor.
3. **HOLD** (`catchup_pause_seconds`): a short pause.
4. **CATCHUP** (`catchup_seconds`): the player's body slides from where it froze to its afterimage. At the start of this phase, `Player.recall_split` fires and **GameManager spawns an Echo** (`echo.tscn`, a dark Walker) at the old position, facing the slide direction.

After CATCHUP, `_finish_recall` calls `on_recall_finished()` on every recordable and re-enables the level.

### Recordable interface

```gdscript
func recall_sample() -> Dictionary            # e.g. {"position": ..., "facing": ...}
func apply_recall_sample(sample: Dictionary) -> void
func on_recall_finished() -> void             # clear future stamps, velocity, etc.
# optional (Player only today):
func begin_recall_visual() -> void
func begin_recall_catchup() -> void
func set_recall_catchup(t: float) -> void     # t: 0 → 1
```

`Recall` only interpolates the `"position"` key. Other keys, such as `facing` and `direction`, snap to the older value.

### What is *not* rewound
- **Runtime spawns** (Echoes, DJ's Backup Dancers, the Key) stay when you rewind past their spawn. They just record normally afterward.
- **Projectiles** (Fireball, Vinyl) and the **Key** are not recordables. They freeze with the level, because they're children of it, and resume afterward.
- Dead enemies are **never freed**. `die()` hides the enemy, zeroes its collision layers and disables processing, so an undo can revive it.

---

## 6. Level flow and the key/exit loop

`GameManager.LEVELS` defines the order: `level_1 → level_2 → level_3 → boss_level`, then it loops back to `level_1` and emits `game_completed`.

1. On `register_level`, the enemy with the highest `max_health` becomes `key_enemy`.
2. When it dies, `Enemy.die()` calls `GameManager.drop_key(position)`. The `_key_dropped` flag stops a revived-and-rekilled enemy from dropping a second key.
3. When the player touches the Key, `collect_key()` runs and `LevelExit` changes from red to white.
4. When the player touches an unlocked `LevelExit`, `complete_level()` runs and the scene changes via `call_deferred`.
5. A level with no enemies is unlocked from the start.
6. `boss_level` has no exit. `Boss.die()` calls `complete_level()` directly.

When the player dies (HP 0), `GameManager.restart_level()` reloads the current scene. The `_transitioning` flag prevents double loads.

---

## 7. Player (`scripts/player.gd`)

All tuning values are `@export`s grouped in the Inspector (Run / Jump / Dash / Attack / Health).

- **Movement**: acceleration and friction, instant snap-turn, coyote time, jump buffer, variable jump height (jump cut), 1 air jump, 1 horizontal air dash.
- **Attack**: `SlashPivot` rotates to up, down (only in the air) or facing. The hitbox stays active for `attack_active_time`, and each enemy can be hit only once per swing (`_swing_hits`). A down-slash that hits **pogos** the player and refreshes air jump and dash.
- **Damage**: contact via the `Hurtbox` overlapping enemies (`enemy.contact_damage`), plus knockback, stun, i-frames with blinking, and a knockback-momentum window.
- **Falling off**: below `kill_y`, the player respawns at `spawn_position` and takes 1 damage.
- Body colour shows state: white while dashing, grey when out of dashes.
- **Signals**: `health_changed`, `died`, `recall_split`.

---

## 8. Enemies

```
Enemy (enemy.gd)            health, take_hit, die/revive, hit-stun, hit flash, gravity
├── Walker                  patrol; turns on is_on_wall() or LedgeCheck raycast miss
│   ├── Knight              engage → face player, shield blocks frontal hits; swing = vulnerable
│   ├── BackupDancer        every move_interval, stops & scales up (hitbox too)
│   ├── Boss                placeholder; die() → complete_level()
│   └── (Echo scene)        plain Walker spawned on recall
├── Dragon                  flying (no gravity, mask 0), chases in x, telegraphed Fireball
└── DJ                      stationary, telegraphed Vinyl throw, spawns 2 dancers per cycle
                            at Marker2D children listed in dancer_spawn_points
```

**Enemy scene contract.** `enemy.gd` expects a `Body` ColorRect child. `Walker` and its subclasses also need a `LedgeCheck` RayCast2D. The Knight, Dragon and DJ need their extra named children (`SwordArea`, `ShieldVisual`, `Glow`, `DeckGlow`). Match the existing `.tscn` files.

**Extending.** Override `_behave(delta)` for movement. It's called only when the enemy isn't stunned. If you override `_physics_process` (as Dragon and DJ do), redo gravity, the stun check, `move_and_slide()` and `_update_visuals()` yourself. Add new tick stamps to `on_recall_finished()`, and call `super()` there.

---

## 9. Common dev tasks

### Add a new level
1. Duplicate an existing level `.tscn`, or create a `Node2D` root with `scripts/level.gd` and set `level_name`.
2. Add a `Camera2D` at (320,180), `Geometry/` with `platform.tscn` instances (set `size` in the Inspector; the `@tool` script updates the editor preview live), a `Player` instance, `Enemies/`, and a `LevelExit`.
3. Add its path to `GameManager.LEVELS` in the order you want.

The base viewport is 640×360 with `canvas_items` stretch. Levels are single-screen with a static camera.

### Add a new enemy
1. Create `scripts/enemies/foo.gd` with `class_name Foo extends Enemy` (or `Walker`) and override `_behave`.
2. Create `scenes/enemies/foo.tscn`: a `CharacterBody2D` with `collision_layer = 4`, a `CollisionShape2D`, a `Body` ColorRect, and a `LedgeCheck` if it's a Walker.
3. Use tick stamps with `NEVER`. Clear future stamps in `on_recall_finished()`.
4. To spawn at runtime, prefer `GameManager.spawn_enemy(scene, pos)`. It registers the enemy and calls `Recall.track`.

### Add something recall should undo
- For **continuous state**, add it to `recall_sample()` and `apply_recall_sample()`.
- For **one-off changes**, call `Recall.record(self, &"kind", _restore.bind(old_state))` *before* mutating the state.

### Input actions (Project Settings → Input Map)
`move_left/right/up/down` (WASD / arrows / d-pad / left stick), `jump` (Space, C, pad A), `dash` (Shift, X, pad RB/R1), `attack` (Z, J, pad X), `recall` (R, pad Y).

---

## 10. Known gotchas / cleanup candidates

- **DJ spawn schedule vs. recall**: dancers aren't undone by recall, so the DJ listens to `Recall.recall_started` and shifts its next-spawn ticks back by the amount rewound in `on_recall_finished`. Use the same pattern for any other "not undone" scheduler.
- **Projectiles use `Timer` nodes** for their lifetime, not tick stamps. That's fine because they freeze with the level, but it's the one exception to the tick rule.
- Keep level nodes under `Geometry/`, `Decor/` or `Enemies/`, not loose at the level root.
- The HUD is a debug readout. The controls hint is hard-coded in `hud.gd`.

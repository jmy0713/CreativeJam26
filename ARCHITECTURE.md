# CreativeJam26 — Architecture Guide

A 2D action platformer built in **Godot 4.7** (GDScript, Forward+). The player runs, jumps, dashes and slashes through single-screen levels (Hollow Knight-style). The core mechanic is **Recall**: press `R` to rewind the whole level by `Recall.recall_seconds` (2 s today). Each rewind leaves an **Echo** enemy behind where you were.

The player is a 15-animation pixel sprite (`player_sheet.png`, 64x64 frames, see 11); most enemies are still placeholder `ColorRect`s, plus a code-drawn sword (`SwordSwing`) for the Knight. Level 1's **Slime** is the exception: a Knight under the hood, wearing the 32x32 `slime` / `slimesword` frames and casting a code-drawn `MagicBarrier` instead of holding a shield. Sprites live in `scenes/assets/` (32 px tiles). `tileset5.png` holds the key (used by `key.tscn`), the door (used by `level_exit.tscn`) and three 64×64 disco ball frames, wired up as the 3 fps `sparkle` animation in `disco_ball_frames.tres`.

The secondary mechanic is **Parry**: press `V`/`K` just before an enemy attack lands to deflect it and freeze every enemy for 1 s (screen negative) while you keep moving.

---

## 1. Folder map

```
project.godot              Engine config: main scene, autoloads, input map, physics layers
scripts/
  autoload/
    game_manager.gd        GLOBAL: tick clocks, level flow, player/enemy registry, key logic
    recall.gd              GLOBAL: the rewind system (undo stack + playback)
    time_stop.gd           GLOBAL: parry time stop (freezes enemies + projectiles)
    recall_overlay.gd      Script on the RecallOverlay autoload: negative screen on/off per source
    scene_transition.gd    GLOBAL: time-warp and 3 s loading screen, run together, between levels
    game_over.gd           GLOBAL: the game over card — 2.5 s, then back to the title screen
  level.gd                 Root script of every level scene (class Level)
  player.gd                Player controller (class Player)
  platform.gd              @tool solid block with editable size (class Platform)
  level_exit.gd            Exit door (locked until key collected)
  key.gd                   Key pickup dropped by the level's strongest enemy
  sword_swing.gd           SwordSwing: code-drawn blade + arc trail, posed from tick stamps (Knight only)
  pixel_draw.gd            PixelDraw: grid snap + ordered dither, shared by the effects drawn as pixel art
  magic_barrier.gd         MagicBarrier: the Slime's two dithered guard panels, frame-stepped off the level clock
  slash_arc.gd             SlashArc: the white slice of air a player swing throws, rasterised as pixel art over 3 frames
  puff_cloud.gd            PuffCloud: the cloud a double jump kicks out, a ring of blobs that expands and dithers away
  blob_shadow.gd           BlobShadow: the player's drop shadow, one rasterised round blob
  dash_ghosts.gd           DashGhosts: the trail of flat silhouettes a dash leaves behind
  sprite_clock.gd          SpriteClock: turns a tick stamp into a frame index (Player + Echo)
  main_menu.gd             Title screen: Play / Quit
  ui/hud.gd                Debug HUD text + dev-mode gating + hiding the HUD off-level
  ui/health_bar.gd         HealthBar: pixel health bar (dissolve, trail, shake)
  ui/time_search_bar.gd    Loading bar for level transitions: the player binary-searching a timeline (used by SceneTransition)
  enemies/
    enemy.gd               Base class Enemy (health, hit, death, recall hooks)
    walker.gd              Walker   extends Enemy  — patrols, turns at walls/ledges
    knight.gd              Knight   extends Walker — shield + sword swing
    slime.gd               Slime    extends Knight — level 1; same fight, slime art + MagicBarrier + SlashArc sweep
    backup_dancer.gd       BackupDancer extends Walker — pauses & puffs up periodically
    boss.gd                Boss     extends Walker — dying completes the level
    dragon.gd              Dragon   extends Enemy  — patrols high points, spits Fireballs that leave FirePatches
    dj.gd                  DJ       extends Enemy  — throws Vinyls, spawns BackupDancers
    disco_ball.gd          DiscoBall extends DJ   — level 2 boss; DJ attacks for now, sprite visuals
    echo.gd                Echo     extends Walker — the clone a recall leaves behind
    robot.gd               Robot    extends Walker — level 3 regular; guard + parryable punch
    robot_boss.gd          RobotBoss extends Robot — level 3 mini-boss; adds the reflectable Laser
    fire_patch.gd          FirePatch extends Area2D — lingering fire left by a Fireball
    projectile.gd          Projectile extends Area2D — recordable base for enemy shots
    fireball.gd, vinyl.gd, laser.gd  extend Projectile (not enemies)
scenes/
  levels/level_1..4.tscn, boss_level.tscn    The playable levels, in order
  player.tscn, platform.tscn, key.tscn, level_exit.tscn
  enemies/*.tscn           One scene per enemy/projectile (echo.tscn wears the player sheet, inverted, squashed to match)
  ui/hud.tscn              HUD (autoload): debug Label + HealthBar
  main_menu.tscn           Title screen — the project's main scene
  assets/health_bar.png    Health bar atlas, 128x32, 4x2 grid of 32x16 stages
  assets/player_sheet.png  Player sprite sheet, 64x64 frames, one animation per row
  assets/player_frames.tres  SpriteFrames over that sheet, one entry per animation
  assets/echo_sheet.png    The same frames with colours inverted, worn by the Echo
  assets/echo_frames.tres  SpriteFrames over the inverted sheet
  assets/slime/, slimesword/  Level 1 slime, 4 frames each, 32x32 (same silhouette, one with the blade inside)
  assets/slime_frames.tres SpriteFrames over both: the `blob` and `guard` loops
  recall_overlay.tscn      Full-screen ColorRect with the negative shader (autoload)
tools/
  make_player_sprites.py   Rebuilds both of those from the high-res renders (see 11)
shaders/negative.gdshader  Inverts screen colors during recall freeze
shaders/silhouette.gdshader  Flattens a sprite to one opaque colour (used by DashGhosts)
shaders/health_bar.gdshader  Dithered cross-dissolve between health bar stages
shaders/time_tunnel.gdshader  The time tunnel itself (clock hands turn clockwise going to a later level, counter-clockwise when looping back), drawn small into its own viewport
shaders/time_warp.gdshader  Level-transition composite: the screen twisted into a growing portal with the tunnel behind it
```

Every `.gd` has a matching `.gd.uid` file. Godot generates these, so commit them and don't edit them.

---

## 2. Startup and autoloads

`project.godot` sets `run/main_scene` to `scenes/main_menu.tscn`: the title screen, whose Play button jumps straight into `level_1`. A run ends back here, either by dying (see 6) or by finishing the last level.

Seven **autoloads** (singletons) live under `/root` and survive scene changes:

| Name | Source | Role |
|---|---|---|
| `GameManager` | `scripts/autoload/game_manager.gd` | Clocks, registries, level transitions, key/exit state |
| `Hud` | `scenes/ui/hud.tscn` | Health bar, plus an on-screen debug label that only exists in dev mode |
| `Recall` | `scripts/autoload/recall.gd` | Records history and runs the rewind |
| `RecallOverlay` | `scenes/recall_overlay.tscn` | Screen-inversion overlay. `set_source(name, on)`: stays negative while any source (`&"recall"`, `&"time_stop"`) is on |
| `TimeStop` | `scripts/autoload/time_stop.gd` | Parry time stop: `start(seconds)`, `stop()`, `is_active()` |
| `SceneTransition` | `scripts/autoload/scene_transition.gd` | Time-warp level transition: `warp_to_scene(path, title)`, `is_active()` |
| `GameOver` | `scripts/autoload/game_over.gd` | The game over card: `play()`, `is_active()` |

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
| `"projectiles"` | `Projectile._ready` | `TimeStop` (frozen during a parry) |

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

### Recalling (five phases, timed with `real_tick`)
1. **FREEZE** (`freeze_before_seconds`): the level gets `process_mode = DISABLED` and the screen is inverted by the negative shader.
2. **REWIND**: the cursor moves back `_rewind_step` ticks per frame toward `now - recall_seconds` (2 s, clamped to 0), taking about `playback_seconds` (1.5 s). Events newer than the cursor are popped. Sample events become interpolated *segments* for smooth movement. Discrete events run their `undo`. `timeline_tick` is set to the cursor.
3. **HOLD** (`catchup_pause_seconds`): a short pause.
4. **CATCHUP** (`catchup_seconds`): the player's body slides from where it froze to its afterimage. At the start of this phase, `Player.recall_split` fires and **GameManager spawns an Echo** (`echo.tscn`) at the old position, facing the slide direction.
5. **END_FREEZE** (`freeze_after_seconds`): the screen inverts again for a last beat before the level resumes.

After END_FREEZE, `_finish_recall` calls `on_recall_finished()` on every recordable and re-enables the level.

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
- **Projectiles** (Fireball, Vinyl) are recordables: their position is sampled, so a rewind flies them backwards. Hitting something, being slashed or timing out hides them and pushes a `vanished` undo instead of freeing, so they reappear when rewound past it. Rewinding past the launch hides them, and they're freed when the recall finishes.
- The **Key** is not a recordable. It freezes with the level, because it's a child of it, and resumes afterward.
- Dead enemies are **never freed**. `die()` hides the enemy, zeroes its collision layers and disables processing, so an undo can revive it.

---

## 5a. Level transitions (`scripts/autoload/scene_transition.gd`)

`GameManager.load_level(index)` (used by `complete_level()`, so by the exit door, the boss and the `N` cheat) calls `SceneTransition.warp_to_scene(path, title)` instead of swapping the scene directly. The game is **paused** (`get_tree().paused = true`) for the whole transition, and two beats play over it:

1. **TRAVEL** (`LOADING_SECONDS`, 3 s): the warp and the loading screen run **together**. `time_warp.gdshader` twists the last frame while a portal opens from the centre and fills the screen with a time tunnel (rings, warp streaks, a clock whose hands turn clockwise heading to a later level, counter-clockwise when looping back to level 1). That takes `WARP_SECONDS` (1.4 s). The loading card is on screen from the first frame (title from `GameManager.level_title(index)`, plus the search bar below), and once the tunnel covers everything the next level is swapped in behind it (read ahead with `ResourceLoader.load_threaded_request`).
2. **REVEAL** (`REVEAL_SECONDS`, 0.8 s): the tunnel collapses and the new level flies out of it, then the tree is unpaused.

**The loading bar** (`scripts/ui/time_search_bar.gd`) is the player binary-searching a timeline. The bar is every level laid out from past (left) to future (right), with a tick per level. The player starts on the level being left and, in 8 probes, hops to the middle of the window still being searched. Each landing says "too early" (search later) or "too late" (search earlier) and rules out half of it, so the bright window halves each time until it's a sliver on the destination tick, then the bar locks on ("TIME FOUND"). The whole search is planned in `setup()` and replayed from a 0..1 progress value, so it always ends exactly when loading does. The figure hopping along it is **the player himself**, drawn straight off `player_sheet.png` at 1:1 (`HOP_POSES` picks a jump/fall/idle frame per hop step, and he faces the way he is going) — the bar's `HEIGHT` and `TRACK_Y` are sized around him, so changing one means changing the other. Level positions are offset from the middle of their slot so no level lands dead on a probe and ends the search early.

Notes:
- The layer is 100 (above the HUD's 10) and `process_mode = ALWAYS`, so it keeps animating while everything else is frozen. Because the tree is paused, `real_tick` does not advance during a transition.
- `TimeStop.stop()` is called first so a parry negative never sits under the tunnel.
- `restart_level()` (death) does **not** warp, and neither does the startup jump in `GameManager._ready` (`load_level(3, false)`). Call `load_level(i, false)` any time you want a plain swap.
- All timings are constants at the top of `scene_transition.gd` (keep `WARP_SECONDS` <= `LOADING_SECONDS`). The number of probes is `STEPS` in `time_search_bar.gd`, and the tunnel palette lives at the top of the shader. The card is built in code, so there is no scene to edit.

### The transition is pixel art too, and drawn in two passes

A shader on a full-screen rect renders at the **window's** resolution, not the 640x360 the game is drawn at — which is how the tunnel first came out looking like smooth vector art laid over the sprites, and why it was expensive. Splitting it fixes both at once:

- **`time_tunnel.gdshader`** draws the tunnel alone into `_tunnel_viewport`, sized to the game's resolution divided by `TUNNEL_PIXEL` (2, so 320x180 — deliberately chunkier than the sprites, so it reads as a backdrop). One texel there **is** one pixel-art cell, so there is no snapping to do, and all the expensive work (an `atan`, a hash and a fistful of `sin`/`cos` per pixel) runs on ~58,000 pixels instead of the window's few million. Colour comes from a six-tone palette shaded in four flat steps, with no alpha and no glow anywhere.
- **`_step_tunnel()`** redraws that viewport **only when the frame clock ticks over** (`TUNNEL_FPS`, 12/s) by handing it that frame's `anim_time` and asking for one `UPDATE_ONCE`. The tunnel is a hand-animated thing on a frame clock like the slash and the puff, so animating it any smoother would be wrong as well as slower.
- **`time_warp.gdshader`** composites that over the live screen at full resolution. Inside the portal — which is the whole screen for most of the 3 s — that is a single texture read and an early `return`. Outside it, the old level is twisted into the middle in 3 kept-not-averaged ghosts, tinted with a colour read out of the tunnel itself, and flattened onto fewer and fewer tones. The warp grows in `WARP_STEPS` (16) jumps, the level drops from its own resolution onto the tunnel's grid in one hard jump at `RES_DROP`, and the portal's edge is cut with the same 4x4 ordered dither as `PixelDraw.BAYER` rather than cross-faded.
- **The bar** puts every rect through `_fill()`, which rounds it onto whole pixels, uses dim opaque tones where it used to use alpha, steps the hop (`HOP_FRAMES`) and the lock-on bracket (`LOCK_FRAMES`) through a few frames instead of sliding, and only calls `queue_redraw()` when one of those steps actually changes. The canvas scale blows whole game pixels up with nearest filtering exactly like the sprites, so staying on the grid is all it has to do.
- **The card's text is the deliberate exception.** It is a plain `Control` on the layer, so its labels render at the window's resolution like the HUD's. 7px glyphs rasterised at 640x360 are unreadable, and crisp UI text over a pixel backdrop is the convention the HUD already set.

To make the tunnel blockier or finer, change `TUNNEL_PIXEL`; to change how it animates, `TUNNEL_FPS`. Nothing else needs to move for either.

---

## 5b. Parry and time stop (`scripts/autoload/time_stop.gd`)

- **Getting past a guard**: the Knight's shield and the Robot's guard both cover the body's own silhouette and nothing else, so a hit landing more than `overhead_height` above the origin (a down slash) or more than `underfoot_height` below it (an up slash at something standing on a platform over you) lands unparried. `RobotBoss._guard_covers_overhead()` closes both ends, so the parry is the only way into it.
- **Parry**: `parry` opens `Player.parry_window` (0.2 s; `parry_cooldown` 0.5 s press to press). An enemy attack about to deal damage calls `player.try_parry()` first; if it returns true the attack is cancelled instead (see `Knight._update_attack` / `_on_parried`, and `Echo._update_swing`) and `TimeStop.start(parry_time_stop)` runs. For the Knight the parry is also the only way in: it drops the shield for the freeze plus `shield_break_time` after it. Any new attack that should be parryable just needs that same `try_parry()` check.
- **Freeze**: every alive `"enemies"` node and every `"projectiles"` node gets `process_mode = DISABLED` for 1 s of `real_tick`. Enemies keep their physics body (`DISABLE_MODE_KEEP_ACTIVE`) so the player can still slash them (normal rules, e.g. the Knight's shield); projectiles leave physics. `Player._check_hurt` skips contact damage while a stop is active. `TimeStop` keeps calling `refresh_visuals()` on frozen enemies so hit flashes still show.
- **Stamps**: the timeline keeps running during the stop. When it ends, every frozen enemy gets `on_time_stop_ended(frozen_ticks)` and pushes its stamps forward with `_shift_stamp()`. Hits taken while frozen are moved to the resume tick, so their stun and knockback play when time restarts. **New enemy stamps must be shifted there too** (as well as cleared in `on_recall_finished`).
- **Recall** calls `TimeStop.stop()` before it freezes the level, so the two never overlap.

## 6. Level flow and the key/exit loop

`GameManager.LEVELS` defines the order: `level_1 → level_2 → level_3 → level_4 → boss_level`, then it loops back to `level_1` and emits `game_completed`.

1. On `register_level`, the enemy with the highest `max_health` becomes `key_enemy`.
2. When it dies, `Enemy.die()` calls `GameManager.drop_key(position)`. The `_key_dropped` flag stops a revived-and-rekilled enemy from dropping a second key.
3. When the player touches the Key, `collect_key()` runs and `LevelExit` changes from red to white.
4. When the player touches an unlocked `LevelExit`, `complete_level()` runs and `SceneTransition` plays the time-warp and loading card before the next scene appears (see 5a).
5. A level with no enemies is unlocked from the start.
6. `boss_level` has no exit. `Boss.die()` calls `complete_level()` directly.

When the player dies (HP 0), `GameManager.game_over()` runs. It hands over to the `GameOver` autoload, which pauses the tree, holds a "GAME OVER" card for `HOLD_SECONDS` (2.5 s) and then calls `GameManager.return_to_menu()` — the run ends at the title screen rather than restarting the level. Like `restart_level()` (still there, unused), it deliberately skips the time-warp: the warp is for travelling between levels. The `_transitioning` flag prevents double loads.

`GameOver` builds its card in code on a `CanvasLayer` at layer 90 — above the HUD, below the warp — with `process_mode = ALWAYS` so it runs out its own clock while the tree underneath it is paused. The fade steps in `FADE_STEPS` jumps rather than sliding, like the loading card's, and the backdrop lands fully opaque.

---

## 7. Player (`scripts/player.gd`)

All tuning values are `@export`s grouped in the Inspector (Run / Jump / Drop through / Dash / Attack / Health).

- **Movement**: acceleration and friction, instant snap-turn, coyote time, jump buffer, variable jump height (release early = jump cut; holding = reduced gravity for `jump_hold_time`, for a higher max jump), 1 air jump, 1 horizontal air dash.
- **Drop through**: pressing `move_down` while standing on a jump-through `Platform` (`one_way`, see 6 and `platform.gd`) steps off it. Godot's one-way surface would catch the player again on the way down, so `_try_drop_through()` collision-**excepts** the platforms actually underfoot — found from the previous frame's slide collisions, floor-facing normals only — and `_expire_drop_through()` hands them back `drop_through_time` (0.35 s) later, by which point the fall has cleared their underside. The drop also clears the coyote window and any buffered jump, or down-then-jump would hop straight back on. A recall or a hazard respawn clears the exceptions outright.
- **Parry**: see 5b. The sprite plays its `parry` animation while the window is open.
- **Attack**: `SlashPivot` rotates to up, down (only in the air) or facing; the `SlashArea` hitbox hangs off it at 23.4 px and is 28.6x36.4, and the `SlashFx` `SlashArc` throws its white slice of air for `slash_fx_time` (it takes the pivot's angle as data rather than hanging off it — see below). The hitbox stays active for `attack_active_time`, and each enemy can be hit only once per swing (`_swing_hits`). Slashing a projectile destroys it. A down-slash that hits an enemy or a projectile **pogos** the player and refreshes air jump and dash. `_start_attack()` also picks the animation for the swing (`_attack_animation()`): up and down have ground/air variants and side slashes alternate `slash` / `thrust`, or `dash_slash` / `dash_thrust` when they start during a dash.
- **Damage**: contact via the `Hurtbox` overlapping enemies (`enemy.contact_damage`), plus knockback, stun, i-frames with blinking, and a knockback-momentum window.
- **Falling off**: below `kill_y`, the player respawns at `spawn_position` and takes 1 damage.
- Sprite `modulate` shows state: overbright while dashing, dimmed when out of dashes, blinking while invincible.
- **Dash**: the dash leaves a `DashGhosts` trail — three flat silhouettes of the player standing where he was, each stepping down a tone ramp as it ages. There is no history buffer: a dash runs at a constant velocity, so each ghost's position is arithmetic on `dash_start_tick` and `_dash_start_position`, which is what makes the trail rewind and freeze with the clock like everything else. A dash cancelled by a hit clears the stamp and the trail goes with it.
- **Shadow**: the `Shadow` `BlobShadow` under the feet is shown only while `is_on_floor()` (and hidden with the invincibility blink) — it has no idea what is below it, so in the air there is nothing for it to lie on. Its `color` carries the only alpha in any of these effects, because a shadow darkens the floor rather than painting over it.
- **Double jump**: the air jump stamps `air_jump_tick` and drops a `PuffCloud` at the boots, held there by world position so it stays where the jump happened while the player rises away from it.
- **Signals**: `health_changed`, `died`, `recall_split`.

### Effects drawn as pixel art

`SlashArc` (the swing's slice of air), `PuffCloud` (the double jump's cloud),
`BlobShadow` (the drop shadow) and `MagicBarrier` (the Slime's guard) are all
**pixel art drawn in code**, and every rule below exists to keep them that way. `PixelDraw` holds the two that
are easiest to get wrong — the grid snap and the dither.

Taking the slice of air as the worked example:

* **A frame clock, not a tween.** `slash_fx_time` is cut into `frames` (3)
  steps and the shape snaps between them. A crescent lerped smoothly across
  the swing reads as a vector shape sliding over pixel art; a hand-drawn slash
  is one solid strike pose plus a couple of aftermath frames, so that is what
  this draws. Radius, width, span and angle all move per step, so no two
  frames are the same.
* **Rasterised, never smoothed.** `_draw_crescent()` walks the crescent's
  bounding box a pixel at a time and emits opaque 1-px-tall runs (`_fill()`),
  so the edges are hard. There is no alpha and no antialiasing anywhere: the
  colours come from the `tones` ramp, and each frame starts one tone further
  down it.
* **It fades by losing pixels.** A 4x4 ordered dither (`PixelDraw.dither()`) cuts the
  slice away instead of a fade to transparent, and `keep_core` / `keep_edge`
  make it eat the thin edges of the band well before the core, so the shape
  comes apart ragged rather than turning into an even screen door. Sparks —
  single pixels — come off the leading edge once it starts to break up.
* **The node is never rotated.** A rotated node rasterises its rects off the
  pixel grid and they come out soft, so `SlashFx` hangs off the player rather
  than off `SlashPivot` and takes the swing's angle as an argument to
  `set_pose()`. `PixelDraw.snap()` keeps every rect's corners on whole world
  pixels, however fractional the player's position is.
* `lean` tips the crescent up off the attack direction, turning a side swing
  into a chop that starts behind the head and finishes near the boots instead
  of buried in the floor.

**None of the three carries a `z_index`, and none of them may.** They have to
layer with the player, and the levels put their foreground tilemaps on z 0
(level 2 goes up to 3), so an effect on a negative z vanishes behind the
floor — which is exactly what happened to the shadow and the slice the first
time round. Tree order alone does the whole job: `Shadow`, `Puff` and
`SlashFx` sit **before** `Sprite` under `Player`, which draws them in front of
the level and behind the character, so a swing's tips pass behind his head and
feet and wrap around him.

It only re-rasterises when the frame or the angle actually changes, so a swing
costs three redraws rather than one per physics frame.

`MagicBarrier` is the same recipe applied to something that *persists*, which
is where the "half transparent" in the brief had to be reinterpreted. It draws
two curved panels, one on each side of the slime, and the see-through is an
even 4x4 dither cutting each panel's interior away — opaque pixels with holes,
not an alpha. How much survives is the `keep` the owner passes with every pose
(`Slime.guard_solidity`, 0.5, is the even checker that reads as half
transparent). A real alpha would blend against
whatever is behind it and go soft at the edges, putting the only smooth-shaded
thing in the game next to the sharpest. The outer rim skips the dither while
`rim_keep` is 1, so a standing panel keeps a hard bright outline around the
screen-door middle; dropping `rim_keep` takes the outline apart too, which is
how a dismissed guard comes off screen — `Slime.guard_fade_time` (0.14 s) cut
into `guard_fade_steps` (3) poses that eat the interior and then the outline,
so the panels dissolve where they stood instead of blinking out. The dissolve
starts from whatever `keep` was on screen when the guard dropped, so a guard
spent on a windup goes out from its charged thickness rather than snapping
down to the resting one first. The shimmer
is `steps` (4) poses that the owner clocks off
`GameManager.level_time_seconds()` — each pushes the wall a pixel in or out and
slides the dither — so a guard held for seconds flickers like a spell instead
of sitting there static, and still rewinds and freezes with everything else.
`Slime` swaps that `keep` on its own state: thicker through the windup (the
panels *are* the telegraph now that no sword is raised), and gone altogether
for the sweep — which is a gameplay rule, not just a look. See 8.

`DashGhosts` is the odd one out: its ghosts are copies of the player's own
`AnimatedSprite2D` rather than something rasterised, so they wear
`shaders/silhouette.gdshader`, which discards every pixel below an alpha
cutoff and paints the rest one flat colour. `modulate` cannot do this — it
only multiplies, so it tints the sprite instead of flattening it, and only
pure black comes out flat. The ghosts still obey the rest of the rules: fully
opaque, hard-edged, and fading by stepping down `tones` rather than by going
transparent.

`PuffCloud` is the same recipe with a different shape: a ring of lumpy blobs
(`LUMP` / `WOBBLE` are fixed tables, because anything rolled in `_draw()`
would crawl between frames instead of holding still) that starts solid, opens
into a ring as `spread` grows, and dithers away over four frames. `BlobShadow`
has no animation at all, so it only re-rasterises when the player crosses a
pixel boundary — it watches its own transform for that.

---

## 8. Enemies

```
Enemy (enemy.gd)            health, take_hit, die/revive, hit-stun, hit flash, gravity
├── Walker                  patrol; turns on is_on_wall() or LedgeCheck raycast miss
│   ├── Knight              engage → face player, shield blocks every hit except ones from overhead
│   │                        (`overhead_height`) or underfoot (`underfoot_height`, i.e. an up slash
│   │                        from a lower platform); parry drops it for the punish
│   │   └── Slime            level 1's regular enemy. The Knight's fight with ONE rule changed: the guard is
│   │                        a spell, not a plate, so winding up to swing spends it — shield_up() is
│   │                        `super() and not _is_guard_spent()`, which opens guard_drop_lead (0.15 s)
│   │                        BEFORE the sweep and closes at the end of it. A hit landed in that window
│   │                        gets through UNPARRIED (a Knight's only opening is the parry). Parrying still
│   │                        works and still buys the longer shield_break_time window. Visuals: defending
│   │                        raises a two-sided MagicBarrier and plays the `guard` loop (the slimesword
│   │                        frames, blade held inside the blob); the panels then burst apart over
│   │                        guard_fade_time part-way through the windup — the dissolve is the telegraph,
│   │                        and it lands a beat before the blade. The body drops to the plain `blob`
│   │                        loop stretched over windup +
│   │                        sweep, and throws the player's own SlashArc instead of a held sword. Its
│   │                        swing is longer and slower than a Knight's (0.5 windup / 0.4 sweep, reach
│   │                        out to 36 px). The slime art faces LEFT, so _pose_sprite flips on
│   │                        `direction > 0` — the mirror of every other sprite here. Overrides
│   │                        _update_combat_visuals /
│   │                        _position_combat_parts, which are the only places the Knight touches its
│   │                        `Swing` and `ShieldVisual` — both are get_node_or_null, so a subclass may
│   │                        leave them out of its scene.
│   ├── BackupDancer        every move_interval, stops & scales up (hitbox too)
│   ├── Boss                placeholder; die() → complete_level()
│   ├── Robot               level 3's regular enemy: engage → face player, fists up; guard blocks every
│   │   │                   hit except ones from overhead or underfoot (same two heights as the
│   │   │                   Knight's, and RobotBoss closes both) and a parried punch, which BREAKS
│   │   │                   the guard for guard_break_time
│   │   └── RobotBoss       level 3's mini-boss (bigger Robot, guards the exit). Same guard/punch, plus a
│   │                       telegraphed Laser fired at the player's position when the charge started.
│   │                       Slashing a Laser REFLECTS it (Laser.destroy()) instead of destroying it like
│   │                       a normal projectile; a reflected Laser that reaches the boss hits through the
│   │                       guard (hit_through_guard()) — the intended way to punish it between punches.
│   └── Echo                spawned on recall; chases, jumps, double speed. Fights with the player's
│                            own moveset: telegraphed, parryable sword swing (SwordArea), alternating
│                            slash/thrust. Wears the player's frames as a negative
├── Dragon                  flying (no gravity, mask 0), patrols PATROL_OFFSETS (patrol_dwell_time hover at each),
│                           telegraphed Fireball → launch_to_ground() → `landed` spawns a FirePatch;
│                           AnimatedSprite2D Body (fly_red / fly_gold), flipped to face its direction
└── DJ                      stationary, telegraphed Vinyl throw, spawns 2 dancers per cycle
    │                       at Marker2D children listed in dancer_spawn_points
    └── DiscoBall           level 2's boss (replaces the DJ scene there). Same attacks for now;
                            sparkle animation speeds up as the throw telegraph

Projectile (projectile.gd, extends Area2D, not Enemy) — recordable base for enemy shots
├── Fireball, Vinyl         straight-line shots; slashing them just destroys them
└── Laser                   RobotBoss's shot; slashing it REFLECTS it instead (see RobotBoss above)
```

**Enemy scene contract.** `enemy.gd` expects a `Body` child: a ColorRect (hit flash sets its colour to white), or a Sprite2D / AnimatedSprite2D (hit flash overbrightens `modulate`). `Walker` and its subclasses also need a `LedgeCheck` RayCast2D. The Knight and Dragon need their extra named children (`SwordArea`, `ShieldVisual`, `Swing`, `Glow`) — though `ShieldVisual` and `Swing` are optional, and the Slime has neither: it needs `SwordArea`, an AnimatedSprite2D `Body`, a `Barrier` (MagicBarrier) and a `SlashFx` (SlashArc), with `SlashFx` **before** `Body` in the tree and `Barrier` after it, so the sweep passes behind the blob and the guard sits in front of it; the Echo needs a `SwordArea` and an AnimatedSprite2D `Body`. Robot (and RobotBoss) need `FistArea`, `Fist`, `GuardVisual`, `Eye`, `DizzyMark`. The DJ's `DeckGlow` and RobotBoss's `LaserTelegraph` (a `Line2D`) are optional. Match the existing `.tscn` files.

**Extending.** Override `_behave(delta)` for movement. It's called only when the enemy isn't stunned, and **gravity has already been applied** by `Enemy._physics_process` before it runs — don't apply it again. If you override `_physics_process` (as Dragon and DJ do), redo gravity, the stun check, `move_and_slide()` and `_update_visuals()` yourself. Add new tick stamps to `on_recall_finished()`, and call `super()` there.

`Enemy` gives every subclass three things so they don't restate them:

| Helper | Use |
|---|---|
| `NEVER` | The "hasn't happened" stamp. Don't redeclare it — a subclass `const NEVER` shadows this one. |
| `_ticks(seconds)` | `GameManager.seconds_to_ticks`, shortened. |
| `_expire_future(stamp)` | Returns `NEVER` if `stamp` is in the future a recall just undid, else `stamp`. One line per stamp in `on_recall_finished()`. |

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
3. Use tick stamps with `NEVER`. Clear future stamps in `on_recall_finished()`, and shift them in `on_time_stop_ended()`.
4. To spawn at runtime, prefer `GameManager.spawn_enemy(scene, pos)`. It registers the enemy and calls `Recall.track`.

### Add something recall should undo
- For **continuous state**, add it to `recall_sample()` and `apply_recall_sample()`.
- For **one-off changes**, call `Recall.record(self, &"kind", _restore.bind(old_state))` *before* mutating the state.

### Input actions (Project Settings → Input Map)
`move_left/right/up/down` (WASD / arrows / d-pad / left stick; `move_down` also drops through a jump-through platform, and aims a slash in the air), `jump` (Space, C, pad A), `dash` (Shift, X, pad RB/R1), `attack` (Z, J, pad X), `parry` (V, K, pad LB/L1), `recall` (R, pad Y). Debug cheats: `cheat_invincible` (I) toggles `GameManager.cheat_invincible` (player takes no damage, falls still respawn), `cheat_skip_level` (N) calls `GameManager.complete_level()`.

---

## 10. HUD and the health bar

`Hud` (autoload) holds two things: the debug `Label` and the `HealthBar`.

The whole layer is hidden whenever no level is in the tree (`GameManager.has_active_level()`), so the title screen and the game over card have no health bar over them. It's polled in `_process` rather than driven by a signal: there are several ways out of a level and only one of them announces itself, while the freed `current_level` reference answers for all of them. The gap between two levels is under the warp anyway, so nothing blinks.

### Dev mode

`GameManager.dev_mode` gates everything that shouldn't ship — the debug
readout, the controls hint and the cheat keys (`I`, `N`). No key is bound to
it yet; flip the variable, or call `GameManager.set_dev_mode(false)` from a
menu. `Hud` listens to `dev_mode_changed`, hides the label and slides the bar
up into the freed space. Leaving dev mode also clears `cheat_invincible`, so
you can't get stuck invincible.

### Health bar (`scripts/ui/health_bar.gd` + `shaders/health_bar.gdshader`)

`scenes/assets/health_bar.png` is the stage atlas: a 4x2 grid (`atlas_grid`)
of stage sprites, fullest first, read left to right then top to bottom, 5 of
the 8 cells used for 5/5 down to 1/5. Frame index 5 means "nothing left" and
is what 0 HP draws. `_frame_for()` maps health to a stage as a ratio, so it
survives `max_health` changing away from 5.

One cell's pixel size is **derived from the texture** in `_bind_atlas()`, not
hard-coded, so re-exporting the art at a different scale needs no changes. It
only feeds the dither's resolution — get the grid wrong and you get the wrong
cells, but get the scale wrong and nothing breaks.

The shader samples its own `atlas` uniform rather than the built-in `TEXTURE`,
and tints with its own `tint` uniform rather than `MODULATE`. Both built-ins
fail to compile here: `TEXTURE` is not reachable from inside a user-defined
function, and `MODULATE` does not exist in the fragment stage. A canvas_item
shader that fails to compile silently falls back to drawing the raw texture,
which for an atlas looks like every stage on screen at once.

The bar binds to the player on `level_started` (the Hud outlives levels) and
animates off `Player.health_changed`. Three effects, all `@export`-tuned:

| Effect | How |
|---|---|
| **Dissolve** | The shader holds two stage frames and gives every pixel a stable *flip point* from its x position plus a 4x4 Bayer dither. `dissolve` sweeps a wavefront across those flip points, so one stage crumbles into the next instead of snapping. `sweep_dir` runs the wipe from the tip inward on damage, and the other way on a heal. |
| **Trail** | Pixels the bar had at `frame_ghost` and no longer has are painted in the level's secondary colour, then crumbled by a second wavefront `trail_hold_time` later. Red that survives a hit — the ragged tip of a stage — is never touched. Back-to-back hits keep the *oldest* silhouette, so a burst leaves one trail rather than several. |
| **Shake** | A quadratic-decay jitter on the node's `position`, re-aimed once per physics tick and rounded to whole screen pixels so it stays crisp. Scales with damage amount. |

`TRAIL_COLORS` in `health_bar.gd` is the secondary colour per entry in
`GameManager.LEVELS` — one theme colour per level, edit it there.

Timing uses `real_tick` stamps, not float timers (see section 4). That clock
keeps running while a recall has the level frozen, and `Player._restore_health`
re-emits `health_changed`, so the bar rewinds along with everything else.

---

## 11. The player sprite

`scenes/player.tscn` draws the player with one `AnimatedSprite2D` (`Sprite`)
over `player_frames.tres`. There is no `AnimationPlayer` and nothing calls
`play()`: `Player._pose_sprite()` chooses the animation from the current state
and `_frame_for()` derives the frame index from a tick stamp, so the sprite
obeys recall and time stop for free like every other visual here. Looping
animations (`idle`, `run`) run off `GameManager.level_time_seconds()`;
one-shots count from their own stamp and hold the last frame once they run
out. `_anim_seconds()` reads the length back out of the resource, so frame
counts and fps live in the sheet alone.

The `Echo` wears the same frames negated, as `echo_frames.tres` over
`echo_sheet.png`, squashed and shrunk to the same 0.8 as the player — it is a
clone of him, so the two have to stand the same height. That inversion is **baked** by the same script that builds
the player's sheet, not applied with a runtime shader: a canvas_item shader
that fails to compile renders the sprite normally and the echo silently comes
out un-inverted, and a baked sheet also leaves `enemy.gd`'s modulate hit flash
working on it like on any other sprite enemy. A happy side effect is that the
echo is the one thing on screen that looks *un*-inverted while a recall's
negative overlay is up. `Echo._pose_sprite()` follows the same rules
as the player's over the states it has, and its swing is the one animation
*not* played at the clip's own speed: `SpriteClock.frame_over()` stretches it
across `attack_windup + attack_active` so what telegraphs on screen is exactly
the window you have to parry in. Its air stamps live in
`_update_visuals()` rather than `_behave()`, which `Enemy` skips while an enemy
is hit-stunned — a stunned echo still falls.

**Actions outlast their animations.** An attack holds its last frame for the
rest of `attack_cooldown` and a parry for the whole `parry` clip, not just the
0.2 s window, so a swing never snaps back to idle mid-recovery. Whichever
action started most recently wins, which is what lets a dash out of an
attack's recovery read as a dash. Air poses use two stamps: `air_tick` (left
the floor, or the last air jump — a pogo restarts it) drives `jump`, and
`fall_tick` (the descent began) drives `fall`, so the fall starts at the apex
instead of being over before the player drops.

The frames are 64x64 with the character ~32px tall, anchored at the feet at
(26, 46) — left of centre, because the sprite faces right and the sword needs
the room. `Sprite` sits at `(0, 9.6)` (the collision box's feet) with
`offset = (6, -14)`, which puts that anchor pixel on the node origin so
`scale.x = facing` mirrors around the character rather than the frame.

The character is drawn **squashed to 0.8x height**: `Sprite.scale = (1, 0.8)`,
and the body and hurtbox shrink to match (12x19.2 and 10x17.6, feet 9.6 px
below the origin). The scale is around that feet anchor, so the squash takes
the head down and leaves the boots on the floor. `_pose_sprite()` only ever
writes `scale.x` (`= facing`), which is what keeps the y squash in the scene
where it can be re-tuned; the `Afterimage` sprite carries the same transform.

`tools/make_player_sprites.py` regenerates the sheet and the resource from the
high-res renders (1280x720 PNGs, one folder per animation). Those renders are
**not in this repo** — pass the folder:

```
python3 tools/make_player_sprites.py ~/Downloads/spriteSheets
```

Edit `ANIMATIONS` in that script to change which source frames are kept, the
fps, or whether an animation loops. Two things about the renders it has to
correct for, both measured per animation over the whole source folder (never
just the frames that get kept — `fall` is a slice of the jump render that
never touches the ground):

* **Framing.** `thrust` sits ~200px left of `idle`, `up_slash` ~27px lower.
  Each animation is re-anchored on a shared ground line and leg centre taken
  from the dark armour. The blade's grip and guard are dark too, so a row only
  counts as the body's bottom once `MIN_FOOT_RUN` pixels of it are dark —
  without that, the blade sweeping past the boots in `slash` reads as a floor
  118px too low and the whole swing floats up. `NUDGE` takes hand corrections
  in final pixels.
* **Camera distance.** The character is only ~65% as tall in `slash` and
  `up_slash` as in `idle`, so each animation gets a zoom correction from the
  median armour area (`_anchor`). Without it the player visibly shrinks for
  the length of a swing. `ZOOM` overrides a measurement that guesses wrong.

Splitting one render across two animations (`jump` / `fall`) is a `span`
apart: mind that `fall` must not run into the landing frames, or a long drop
holds a standing pose in mid-air.

---

## 12. Known gotchas / cleanup candidates

- **DJ spawn schedule vs. recall**: dancers aren't undone by recall, so the DJ listens to `Recall.recall_started` and shifts its next-spawn ticks back by the amount rewound in `on_recall_finished`. Use the same pattern for any other "not undone" scheduler.
- Keep level nodes under `Geometry/`, `Decor/` or `Enemies/`, not loose at the level root.
- `GameManager._ready` calls `load_level(3, false)`, which jumps straight to `level_4` on startup (a dev shortcut, and it skips the warp). `level_4.tscn` also has `level_name = "Level 3"`, same as `level_3.tscn`. The loading card uses `GameManager.level_title()` rather than `level_name`, so it isn't affected.
- The controls hint is hard-coded in `hud.gd`, and the whole debug readout disappears with `dev_mode`.
- `scenes/assets/health_bar.png` is a 128x32 atlas (32x16 cells). Re-exporting at a different scale needs no code changes — the cell size is derived from the texture — but keep the **filename**: `hud.tscn` references it by path, so a drop-in under a different name silently breaks the bar.

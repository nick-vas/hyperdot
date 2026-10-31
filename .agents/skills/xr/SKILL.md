---
name: xr
description: Use when a Godot game targets a VR or AR headset (OpenXR, Meta Quest, SteamVR), adds hand or controller input, locomotion, throwing or passthrough to one, or when a headset player gets sick, throws wrongly or loses tracking.
---

# XR in Godot 4 (OpenXR)

From the Godot XR manual and the Half-Life: Alyx developer commentary as the repository's `docs/valve.md` (section 7) holds
it. Sources, what the fixture proved and what it could not: `${CLAUDE_PLUGIN_ROOT}/docs/xr.md`. Hands, the action map and
passthrough: [hands.md](hands.md). The code is GDScript; C# names are the same members in PascalCase (`UseXR`, `FindInterface`,
`IsInitialized`, as the manual's own C# tabs write them). No headset ran any of this: tracking, how comfortable a setting
feels and passthrough are listed as not run in `docs/roadmap.md`.

## 1. Decide first, at `concept.decisions`

- [ ] Headsets and runtimes: standalone (Quest, an Android export with the OpenXR vendors plugin), a PC headset through a
      runtime such as SteamVR, or both. The Mobile renderer is the manual's recommendation for either; Forward+ runs, but
      the manual says it "isn't well optimized for XR right now".
- [ ] Play space: seated, standing or room scale. Room scale changes how the player's body works (section 4).
- [ ] Input: controllers (the action map), optical hand tracking, or both. Controllers are the reliable path; runtimes differ a lot in hand
      tracking (`hands.md`).
- [ ] Locomotion: teleport, stick movement or physical walking only, and which of them are on by default (section 5).
- [ ] One controller: can the game be finished holding one? Alyx's team found it changed "controller bindings to game logic
      to level design", so decide it before the levels exist (section 7).
- [ ] No headset: what the game does when none is found. A CI machine and most of the team's day have none (section 3).
- [ ] Tests: which numbers are unit-tested (section 8) and which comfort settings a headset playtest must judge.

## 2. Set up

- Project Settings: `xr/openxr/enabled` (OpenXR must be on when Godot starts, so a change needs a restart) and
  `xr/shaders/enabled`. Post-processing effects not updated for stereo "will have adverse effects".
- Scene: an `XROrigin3D` with an `XRCamera3D` and one `XRController3D` per hand as children. The nodes under the origin are
  placed by tracking. Set each controller's `XRNode3D.tracker` to `left_hand` or `right_hand`, and its `XRNode3D.pose` to the
  action map's pose (`grip` for a held object, `aim` for a pointer).
- Start: `XRServer.find_interface("OpenXR")`, then `XRInterface.is_initialized()` (OpenXR starts before the project loads; other
  interfaces need `initialize`), then `Viewport.use_xr` on the main viewport. A registered interface is not a working one:
  handle the failure. Never initialize twice when levels each carry an XR rig.
- Match the headset. V-sync is ignored (OpenXR times frames), and physics defaults to 60 Hz, which stutters held objects:
  on `OpenXRInterface.session_begun` read `OpenXRInterface.get_display_refresh_rate()`, pick the best of
  `OpenXRInterface.get_available_display_refresh_rates()` and set `Engine.physics_ticks_per_second` to it. On Vulkan renderers
  set `Viewport.vrs_mode` to `Viewport.VRS_XR` for foveation; on Compatibility set `xr/openxr/foveation_level`.
- Pause when the player takes the headset off or opens the system menu: `OpenXRInterface.session_visible` and
  `OpenXRInterface.session_focussed`, disabling processing on the game's root and enabling it again on focus.
  `OpenXRInterface.pose_recentered` asks the game to face the player forward: `XRServer.center_on_hmd()` is often enough.
- The manual's "A better XR start script" has all of this in one reusable script; copy that rather than rewrite it. XR Tools
  ships a version too.

## 3. Test with no headset

Godot runs the XR classes with no runtime: `XRServer.primary_interface` is null, `XRServer.find_interface("OpenXR")` is found
but not initialized, and every `XRController3D` answers (`XRController3D.is_button_pressed()` false,
`XRController3D.get_float()` 0, `XRNode3D.get_has_tracking_data()` false). So:

- Keep game logic out of the headset path. `${CLAUDE_PLUGIN_ROOT}/ci/godot/templates/xr_rig.gd` is the script for the
  `XROrigin3D`: it starts in flat mode when no interface starts, finds each hand by tracker name, and keeps the throw samples.
  Copy it with `xr_math.gd` into the game.
- Stand in for a controller with a tracker: a new `XRPositionalTracker` with `type` `XRServer.TRACKER_CONTROLLER`, `name`
  `right_hand` and `hand` `XRPositionalTracker.TRACKER_HAND_RIGHT`, added with `XRServer.add_tracker()`, then
  `XRPositionalTracker.set_pose()`. The `XRController3D` of that tracker moves to the pose and `XRNode3D.get_pose()` returns
  its `XRPose.linear_velocity`. The fixture does this (section 8).
- Run the game's own flows against that rig. Whatever only a headset can show goes on a playtest list, not in a test.

## 4. The player's body is not the origin

`XROrigin3D` is the middle of the tracking space, not the player. The player walks around inside it and the `XRCamera3D`
moves with them (a "disembodied head", the manual says), so one `CharacterBody3D` over the rig fails three ways: it collides
where the player is not, a turn swings a player who stands away from the room's middle around the room, and a blocked
player can still walk through the wall in the real room. The manual gives two ways out, and XR Tools' `PlayerBody` uses the first:

- Origin-centric: a top-level `CharacterBody3D` that is moved each physics frame to the point on the floor under the head
  (`XrMath.body_position`), then turned and moved by input, and the origin follows by the same amount.
- Character-centric: the body is the root, the origin its child; each frame the body is moved to the player and the origin
  moved back by what the body really moved.
- Turn the origin about the player, not about itself: `XrMath.rotate_origin_about(origin, body_position, angle)` keeps that
  point where it is.
- When the body cannot follow the head, do not pin the player: not replicating a real step "will cause nausea". The manual's
  answer is to measure the gap between the player and the body and black the screen out as it grows past a few centimetres,
  allowing input while it is small and keeping gravity on (`XrMath.blackout(gap)`).
- On load the player may stand far from the middle of the tracking space. Ask the player to press a button when ready, in a
  large neutral place, and record the camera's position and height then (the manual says XR Tools does this).
- Test standing and walking early: the manual says that developers who build seated find room-scale problems "don't show
  themselves until it is too late".
- Never move the player to make room for a character or prop: Alyx's playtesters found it "made players feel deeply
  uncomfortable or disoriented" (Steve Kalning, `docs/valve.md` 54).
- `XROrigin3D.world_scale` changes the size of the world against the player; the current origin sets `XRServer.world_scale`.
  Pick one scale for the game and keep it.

## 5. Locomotion and comfort

Moving the view while the player stands still is what makes people sick, newcomers most. The manual says to keep the
conservative defaults and "offer features in game to enable less comfortable settings for more experienced users".

| Do | Not |
|---|---|
| Snap turning on by default (steps of a set angle), smooth turning as an option. XR Tools' defaults: 20 degrees and 0.2 s between steps; the kit's `XrMath.SnapTurn` uses 30 degrees and needs the stick released before the next | Smooth turning on by default |
| Teleport as a mode next to stick movement, and let the player choose | Only stick movement |
| A vignette that closes at once when the game moves the player and opens after a rest (`XrMath.Vignette`; XR Tools' `XRToolsVignette` is the ready-made one) | Closing it for the player's own walking: it is theirs |
| Keep a frame of reference in view during forced motion: Alyx's vehicle has a window small enough that "the player's field of view is always dominated by the vehicle interior" (Eric Kirchmer, 53) | A moving camera with no fixed surround |
| Every locomotion mode leaves the same trail for the AI: Alyx leaves "a breadcrumb trail of invisible visual proxies, which the enemy AI can see" (Bob Buehler, 55) | An enemy that only reacts to walking |
| A comfort menu: turning mode and angle, vignette strength, movement mode, dominant hand, height | Comfort settings only in a config file |

The numbers in `xr_math.gd` are first guesses (turn angle 30, vignette minimum radius 0.35, hold 0.5 s, open over 1 s). They
need a headset and a player who gets motion sick; the tests only hold their shape (closes at once, never opens while
moving, the same at 60 and 144 fps, a held stick turns once, twelve turns are a circle).

## 6. Hands and input

Controllers come through the OpenXR action map (`hands.md`). Read them on the `XRController3D`:
`XRController3D.button_pressed`, `XRController3D.input_float_changed`, `XRController3D.get_float()`,
`XRController3D.get_vector2()`. A game that also takes mouse and keyboard has two input systems: the action map is not the
`InputMap`. Haptics go out through `XRNode3D.trigger_haptic_pulse()`.

## 7. Throwing and one-controller play

- A throw leaves at the fastest hand speed of the last ten frames, not the speed of the release frame (Tony Cox, Alyx,
  `docs/valve.md` 56): the hand slows as the fingers open. `XrMath.peak_velocity(samples)` takes the peak and keeps its
  direction; the rig samples `XRNode3D.get_pose()`'s `XRPose.linear_velocity` every physics frame (positions when a pose has
  no velocity) and `xr_rig.gd`'s `release_velocity()` returns it in world space, plus the speed of whatever carries the
  player. XR Tools' pickup averages 5 velocity samples (`velocity_samples`, its `XRToolsVelocityAverager`), which throws
  softer than the flick; use it for a held object that only follows the hand.
- A hand that loses tracking forgets its samples, so it never throws with the speed it had before.
- Make catching generous: "A generous catch range and subtle haptic feedback" lands a grab from a distance in the hand
  (Jane Ng, 56). Check that a thrown object leaves the hand's collision before it starts to move.
- One controller: bind everything the game does to whichever hand is tracked (`XrMath.active_hand()`; the rig's
  `active_hand()`), put both hands' actions on one in the action map, and let the other hand's duties (inventory, menu) move
  to a button or a gesture. This is level design as much as input: no puzzle that needs both hands at once.

## 8. Prove it

`${CLAUDE_PLUGIN_ROOT}/tests/Test-Xr.ps1` runs `tests/xr-fixture` with the `gut` runner in `test`, so a game can copy the
shape (a rig scene, `res://xr_math.gd`, `res://xr_rig.gd`). Held without a headset:

- [ ] every engine name this skill quotes exists in Godot 4.7.2 (`ClassDB`, `ProjectSettings`)
- [ ] a scene with an `XROrigin3D` loads and runs with no interface, and `XRServer.primary_interface` is null
- [ ] a tracker added to `XRServer` moves an `XRController3D` and gives it a velocity
- [ ] the throw takes the peak of the last ten frames; a lost hand throws nothing
- [ ] a snap turn fires once per push, twelve of 30 degrees make a circle
- [ ] turning the origin about the body leaves the body where it is; turning about the origin does not
- [ ] the vignette closes in one frame, opens after the hold, and opens in the same time at 60 and 144 fps
- [ ] one tracked controller is the active hand

Not run here, so list them in the game's plan for a headset playtest: tracking quality, hand tracking on any runtime,
passthrough, refresh-rate changes, whether any comfort number is right, and the Android export.

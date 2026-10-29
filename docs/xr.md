# XR: sources and measurements

The research behind the `godot-xr` skill and the two templates it ships (`ci/godot/templates/xr_math.gd` and `xr_rig.gd`),
gathered on 2026-10-29. Checks ran headless on Godot 4.7.2 (standard build) with no headset and no XR runtime; `tests/Test-Xr.ps1`
repeats them.

## Sources

| Source | What it gave |
|---|---|
| Godot manual, `tutorials/xr` (the `godotengine/godot-docs` repository, master branch, read as files: the documentation site did not resolve from this session) | Setting up XR, the better start script, room scale, basic locomotion, the action map, hand tracking, AR passthrough, XR Tools; every "the manual says" in the skill |
| Godot 4.7.2 `ClassDB` and `ProjectSettings`, read by `tests/xr-fixture` | Every class, property, method, signal and constant the skill names; `XRServer.primary_interface` null, OpenXR registered but not initialized, `xr/openxr/*` settings |
| [GodotVR/godot-xr-tools](https://github.com/GodotVR/godot-xr-tools), shallow clone of the default branch | MIT code, CC0 images and hand models (`LICENSE`, `hands/License.md`), `plugin.cfg` version 4.6.0, the scenes it provides, `velocity_samples` 5 in `function_pickup.gd`, snap turn defaults (20 degrees, 0.2 s), the vignette's properties |
| Half-Life: Alyx developer commentary, as `docs/valve.md` section 7 quotes it (items 53 to 58; checked word for word against the fan-wiki transcript on 2026-10-22) | The vehicle window, not moving the player for a character, the AI's breadcrumb trail, the peak of the last ten frames for throws, the generous catch range, one-controller play changing "controller bindings to game logic to level design" |

## Measurements (Godot 4.7.2, no headset)

| What | Result |
|---|---|
| `XRServer.primary_interface`, `XRServer.world_scale`, interfaces listed | null, 1.0, "Native mobile" and "OpenXR" |
| `XRServer.find_interface("OpenXR")` then `is_initialized()` | found; false |
| `XRController3D` with no tracker: `get_has_tracking_data()`, `is_button_pressed()`, `get_float()` | false, false, 0 |
| A tracker added with `XRServer.add_tracker()` and `set_pose()` | The `XRController3D` of that `tracker` name moves to the pose within a frame and `get_pose().linear_velocity` returns the velocity; `invalidate_pose()` clears `get_has_tracking_data()` |
| `XROrigin3D.world_scale = 2` on the current origin | `XRServer.world_scale` is 2 |
| `XRCamera3D`, `XRController3D` and the origin in a scene with no interface | Load and run; no errors |
| 57 names the skill quotes | All exist in `ClassDB` or `ProjectSettings`. A made-up name fails the test by name |

The numbers in `xr_math.gd` (turn angle 30 degrees, a vignette minimum radius of 0.35 that closes at once and opens after
0.5 s over 1 s, a blackout from 3 cm to 15 cm of gap) are the kit's own first guesses; the tests hold their shape, not their
value. The "peak of the last ten frames" is Valve's; XR Tools' pickup averages 5 samples instead.

## Not confirmed

- Everything that needs a headset: tracking quality and latency, hand tracking on any runtime, passthrough, refresh-rate
  changes, foveation, the Android export, and whether any comfort number is right for players. They are in the roadmap's list of
  what was not run.
- Whether Godot XR Tools works on Godot 4.7.2: its README table was read (4.5.x needs 4.4 at least), the add-on was not
  loaded.
- The documentation site (`docs.godotengine.org`), the fan wiki with the Alyx commentary (`combineoverwiki.net`) and Road to VR
  did not resolve from this session, so the Alyx quotes are the ones `docs/valve.md` already holds, not re-read; the Valve
  items are cited by their number there.
- Valve's published VR talks (not looked for beyond the commentary), and Meta's, Sony's and Valve's own comfort guidelines.
- `XROrigin3D.world_scale` against `XRServer.world_scale` when the origin is not current, and how pose velocities scale with it.

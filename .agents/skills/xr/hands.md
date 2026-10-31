# Hands, the action map, passthrough and XR Tools

Side file of `xr`. Everything here is from the Godot XR manual (the `godot-docs` repository, `tutorials/xr`, read
2026-10-29) and the XR Tools repository, except where it says the fixture checked it. None of it ran on a headset.

## 1. The action map

OpenXR hands the game parsed actions, not raw buttons, so the XR action map is separate from the `InputMap`: no rebinding at
runtime, no device ids, and a game that mixes both has two systems.

- Replace the default action map. The manual calls it "not a good example": it binds every known input on every controller
  to an action one to one, to ease porting from Godot 3.
- One action set to start (`my_first_action_set`); more only for contexts that bind the same input to different actions
  (walking, vehicle, menu). Only one of them should be active; with several, the highest priority wins an input. Switch with
  `OpenXRInterface.set_action_set_active()`; ask with `OpenXRInterface.is_action_set_active()`.
- Action types: Bool, Float, Vector2, Pose and Haptic. The runtime converts Bool and Float into each other, but "not all XR
  Runtimes currently apply sensible thresholds": use Float for triggers and grips and apply the game's own threshold. Bool is
  fine for A, B, X, Y.
- Poses: `aim` (in front of the controller, for pointers and muzzles), `grip` (where the hand holds it; its orientation
  differs per controller and runtime) and `palm` (not on every runtime). Name the actions for what they do (`grab`, `shoot`),
  not for the hand: one action bound to both hands makes the right `XRController3D` emit.
- Haptics: `XRNode3D.trigger_haptic_pulse()`. Offer a strength setting for them (XR Tools' user settings has `haptics_scale`).
- Profiles: add the controllers you can test and let the runtime pick the closest for the rest. The game cannot know which
  controller the player holds, and a player or runtime may rebind: do not assume movement is on the right stick.
- Read results on the node: `XRController3D.button_pressed`, `XRController3D.button_released`,
  `XRController3D.input_float_changed`, `XRController3D.input_vector2_changed`, and `XRController3D.profile_changed` when the
  profile in use changes.

## 2. Hand tracking

Controllers go through the action map; optical hand tracking goes through its own API, and runtimes disagree on what they
give. Plan for a controller fallback and test on each runtime you ship to.

- Enable it in Project Settings (`xr/openxr/extensions/hand_tracking`), and in the export preset on standalone devices.
- Three parts per hand: an `XRNode3D` under the origin with `XRNode3D.tracker` `/user/hand_tracker/left` or
  `/user/hand_tracker/right` and `XRNode3D.pose` left on `default`; a hand mesh skinned to the Godot Humanoid skeleton; and an
  `XRHandModifier3D` under the `Skeleton3D` whose `XRHandModifier3D.hand_tracker` is the same path.
- `XRHandModifier3D.bone_update`: `Full` follows the real hand's size and can scrunch badly weighted meshes (test with players
  of all sizes); `Rotation Only` keeps the mesh's bone lengths.
- Where the data comes from: `XRServer.get_tracker('/user/hand_tracker/left')` is null when the runtime has no hand tracking;
  `XRHandTracker.has_tracking_data` false means the hand is out of view, a controller is held or it is off;
  `XRHandTracker.hand_tracking_source` is optical, controller-inferred or unknown (`XRHandTracker.HAND_TRACKING_SOURCE_UNKNOWN`:
  when it is unknown, the manual assumes controller-based tracking on SteamVR and optical on other runtimes).
- Gestures reach the action map through the hand interaction profile (pinch, grasp, poke), which few runtimes have yet. Without
  it, the game recognizes pinches and fists itself.
- XR Tools ships rigged hands that bend their fingers on the trigger and grip of a controller: the manual calls that "a reliable
  alternative". Its hand models are CC0.

## 3. Passthrough and AR

Set the blend mode on the interface; the interface applies the platform's method (video passthrough or see-through).

| Goal | Do |
|---|---|
| VR | `XRInterface.environment_blend_mode` to `XRInterface.XR_ENV_BLEND_MODE_OPAQUE` (turns passthrough off) |
| AR on video passthrough | `XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND` with `Viewport.transparent_bg` true |
| AR on see-through glasses | `XRInterface.XR_ENV_BLEND_MODE_ADDITIVE`, black background |

Ask `XRInterface.get_supported_environment_blend_modes()` first and fall back. The background then adds no light: set
ambient light by colour. A Quest or HTC Elite export needs the OpenXR vendors plugin 3.0.0 or later and its passthrough
setting. Nothing about passthrough ran here.

## 4. Godot XR Tools

[GodotVR/godot-xr-tools](https://github.com/GodotVR/godot-xr-tools): "Code in this repository is licensed under the MIT
license. Images are licensed under CC0 unless otherwise specified." MIT asks for the copyright line in the game's credits
(`credits`, `asset-pipeline`); the add-on's `plugin.cfg` read 4.6.0 and its README's table gave Godot 4.4 as the lowest
for the 4.5 line. Whether it runs on 4.7.2 was not tried (`docs/xr.md`); try it in a copy of the game first (`godot-addons`).

It provides, as scenes to instance under the origin or a controller: `PlayerBody`; movement (`movement_direct`, `movement_turn`
snap or smooth, `function_teleport`, jump, sprint, crouch, climb, flight, glide, grapple, wall walk, world grab); pickup
(`function_pickup`, `pickable`, snap zones, snap paths); pointers (`function_pointer`, `function_gaze_pointer`); interactables
(button, hinge, slider, joystick); hands; an `XRToolsVignette` and a fade; a pose detector; a user settings scene (snap turning,
dead zones, haptics scale, player height); and an on-screen keyboard. Take what a game needs and keep the rest out: each
scene is code to maintain. It is GDScript, which a C# game can call.

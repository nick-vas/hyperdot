---
name: animation
description: Use when a Godot character or object needs animation states, blending, attacks that must not be cut short, root motion, when an animation feels stiff, floaty or unreadable, or when designing reward screens, score callouts, jackpot or mode-intro animations and attract loops.
---

# Animation in Godot 4

`AnimationPlayer` holds the clips; `AnimationTree` decides which play and how they blend (both are `AnimationMixer`s). Notes,
tests and sources: `${CLAUDE_PLUGIN_ROOT}/docs/art.md`.

## 1. A state machine with rules

A tree whose root is an `AnimationNodeStateMachine`: Idle, Walk, Run, Jump, Fall, Attack. Each
`AnimationNodeStateMachineTransition` has:

| Property | Use |
|---|---|
| `SwitchMode` | `Immediate`; `Sync` (switch now, keep the play position: walk to run); `AtEnd` (wait for the clip to end) |
| `AdvanceMode` | `Disabled` (never used); `Enabled` (only by `Travel`); `Auto` (taken by itself when its condition holds) |
| `AdvanceCondition` | a bool parameter, `parameters/conditions/<name>`; true only, so "not moving" is its own condition |
| `AdvanceExpression` | an expression on `AdvanceExpressionBaseNode` (point it at the character), e.g. `is_on_floor()` |
| `XfadeTime`, `XfadeCurve` | the blend between the two; 0.1 to 0.2 s for most moves |
| `Priority` | lower wins when several auto transitions are open |

```csharp
var playback = _tree.Get("parameters/playback").As<AnimationNodeStateMachinePlayback>();
_tree.Set("parameters/conditions/moving", Velocity.Length() > 0.1f);
if (attackPressed) playback.Travel("Attack");
```

Interruption rules, tested in 4.7.2:

- `Travel(x)` follows a path over transitions that are not `Disabled`, ignoring conditions; each step keeps its own switch
  mode. So a travel requested mid-attack waits when every edge out of Attack is `AtEnd`.
- With no path, `Travel` jumps straight there, cutting an attack short. Wire every state you travel to.
- `Start(x)` always cuts in at once: for death, stagger, cutscenes, never for ordinary input.
- A cancel window: an `Attack -> Dodge` edge with `Immediate`, `Auto` and a `can_cancel` condition that the attack clip's
  method track switches on and off.
- A new state machine already has `Start` and `End`; connect `Start -> Idle` with `Auto`, or call `Start("Idle")` before the
  first `Travel`.

## 2. Blending

- `AnimationNodeBlendSpace1D` (speed: idle, walk, run) and `AnimationNodeBlendSpace2D` (strafe), set through
  `parameters/<Name>/blend_position`. Name each blend point (`AddBlendPoint(node, pos, -1, "walk")`): 4.7 warns without one.
  `SyncMode = CyclicMutable` keeps footsteps in phase (`Sync` is deprecated in 4.7). `BlendMode = Discrete` for frame-by-frame
  2D sprites.
- In a blend tree: `OneShot` for an upper-body attack or flinch over locomotion
  (`parameters/<Shot>/request` = `(int)AnimationNodeOneShot.OneShotRequest.Fire`), `Transition`, `Blend2`, `TimeScale`.

## 3. Root motion or in place

| | In place (code moves the body) | Root motion (the clip moves it) |
|---|---|---|
| Feet | can slide; match speeds by hand | never slide |
| Control | tune speed, acceleration and turning in code | tied to the clips; re-author to change |
| Attacks, dodges, climbs | distance drifts from the art | exactly the authored distance |
| Online play | simple to predict and reconcile | the server must run the same tree, deterministically |

Use in-place locomotion and root motion only for short committed actions (lunges, dodges, vaults). Unreal's own guidance is
the same: root motion from montages only for networked games. In Godot set `RootMotionTrack` (e.g.
`"Skeleton3D:Root"`), `CallbackModeProcess = Physics`, and apply it in `_PhysicsProcess`:

```csharp
// RootMotionLocal = true on the tree.
Quaternion *= _tree.GetRootMotionRotation();
var velocity = Quaternion * _tree.GetRootMotionPosition() / (float)delta;
velocity.Y = Velocity.Y + (IsOnFloor() ? 0f : GetGravity().Y * (float)delta);   // gravity stays yours
Velocity = velocity;
MoveAndSlide();
```

## 4. The twelve principles, for games

From Thomas and Johnston's *The Illusion of Life*; review a key animation (an attack, a jump) against each.

| Principle | In a game |
|---|---|
| Squash and stretch | jump take-off and landing, hit reactions, a pressed button; keep the volume |
| Anticipation | the wind-up of a heavy attack is the player's dodge window; longer wind-up, bigger hit |
| Staging | boss telegraphs: pose, colour flash, ground marker, camera; effects never hide the silhouette |
| Straight ahead, pose to pose | pose to pose for gameplay clips with exact hit frames; straight ahead for fire and smoke |
| Follow through, overlap | capes, hair, tails, a weapon trail that lingers, a recovery pose after the swing |
| Slow in and slow out | `Tween` easing, `XfadeCurve`, camera moves |
| Arcs | swings, lobs, jumps and head turns follow curves |
| Secondary action | breathing, blinks (a `OneShot`), footstep dust, weapon sway |
| Timing | frame counts for startup, active and recovery; hit-stop on big hits (its length: `game-juice`) |
| Exaggeration | bigger flashes, knockback and poses than reality, so they read at gameplay zoom |
| Solid drawing | weight and volume; no perfectly mirrored poses |
| Appeal | a distinct silhouette for the player, each enemy and each boss |

The free references are Wikipedia's "Twelve basic principles of animation" and Alan Becker's video series; the book is *The
Animator's Survival Kit*.

## 5. Reward screens and callouts

A jackpot, combo, mode start or level clear is a micro-story told while the player is still watching the action (a pinball
ball, a horde): the event, an answer on the same frame (`game-juice`), a short build, the payout (the word and the number),
and back to play. Most last 0.25 to 2 s, so they must read at a glance. Motion-graphics rules, more than character animation:

- **One thing moves at a time** (staging). The payout holds still and large long enough to read; everything before it leads
  the eye there (hierarchy, eye direction). Weak callouts fail by moving everything at once.
- **Energy curve:** a fast impact in (overshoot, a flash frame), a hold, a quick exit. Ease with a `Tween`
  (`TransitionType.Back` for the pop) on a `Label` or `Control` in a `CanvasLayer`, with `MouseFilter = Ignore`; never pause
  gameplay for it.
- **Many short pieces, not a few long ones.** A library of one-second callouts reused with different text beats a long
  cinematic. Longer sequences only where play has stopped: attract loops, a wizard-mode intro, the end of a ball, and those
  are skippable.
- **A stack, not a free-for-all.** Pinball's Mission Pinball Framework gives every slide a priority (the mode's, adjusted
  per event) and an optional expiry; the highest shows, and when it goes the next shows. Its expiry timer runs even while
  a slide is covered, so a covered callout can vanish unseen. If every reward must be seen, let only the one on screen use
  up its time:

```csharp
// Pure C#: the highest priority callout shows; equal priorities wait their turn; only the one on screen uses up its time.
// Advance from _Process with the game delta, so slow motion and test -FixedFps see the same timing.
public sealed class CalloutStack
{
    private sealed class Entry { public string Name = ""; public int Priority; public double Left; }
    private readonly List<Entry> _entries = new();   // highest priority first, equal priority in arrival order

    public string? Current => _entries.Count > 0 ? _entries[0].Name : null;

    public void Push(string name, int priority, double seconds)
    {
        int i = _entries.FindIndex(e => e.Priority < priority);
        _entries.Insert(i < 0 ? _entries.Count : i, new Entry { Name = name, Priority = priority, Left = seconds });
    }

    public void Advance(double delta)
    {
        while (delta > 0 && _entries.Count > 0)
        {
            var top = _entries[0];
            double used = Math.Min(delta, top.Left);
            top.Left -= used;
            delta -= used;
            if (top.Left <= 0) _entries.RemoveAt(0);
        }
    }

    public void Remove(string name) => _entries.RemoveAll(e => e.Name == name);   // a callout no longer true (the mode ended)
}
```

- **Low-resolution displays** (a 128x32 or 192x64 dot-matrix look): design at the native size with the `viewport` stretch
  mode and integer scaling (`retro`), a pixel font sized for it (`typography`), and one idea per frame; Michael Azzi's
  *Pixel Logic* covers readability at that size.
- **Study the frames.** Pause videos of recent commercial machines' jackpot and multiball screens frame by frame, and the
  reward and mission-complete screens collected on the Game UI Database: count the frames to the payout and how long it holds.

## 6. Prove it

- [ ] a test builds or loads the tree and checks every state and transition the GDD names exists
      (`AnimationNodeStateMachine.HasNode`, `HasTransition`), with each edge out of an attack set to `AtEnd`
- [ ] a flow or bot run presses attack then move, and asserts the attack finished (`GetCurrentNode()` in the log)
- [ ] the `juice` runner pairs each hit with its hit-stop and flash (`game-juice`)
- [ ] screenshots of key poses at gameplay zoom, judged with `look`
- [ ] a unit test on the callout stack: priority order, equal priorities in turn, a covered callout keeping its time, `Remove`
- [ ] a `juice.json` rule per reward event with its callout as the feedback, `withinMs` 100 (`game-juice`)

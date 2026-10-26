namespace Cinderloop;

using System;
using Godot;

/// <summary>
/// Follows the player's car from above. It looks ahead along the car's velocity, so more of the road to come shows, and
/// eases towards that at rates per second (exponential, so it moves the same at any frame rate and through a hitch);
/// however hard the car turns, the car never gets further than MaxLag from the middle of the view. It moves in
/// _Process, every drawn frame, following the car's interpolated position.
/// </summary>
public partial class ChaseCamera : Camera2D
{
    /// <summary>How quickly the view catches up with where it wants to be, per second.</summary>
    public const double FollowRate = 6.0;
    /// <summary>The look-ahead: this many seconds of the car's velocity, at most MaxLook pixels, eased at LookRate.</summary>
    public const float LookAhead = 0.35f;
    public const float MaxLook = 220f;
    public const double LookRate = 3.0;
    /// <summary>The car always stays within this many pixels of the middle of the view.</summary>
    public const float MaxLag = 240f;

    private Vector2 _look = Vector2.Zero;

    public ChaseCamera()
    {
        // With physics interpolation on, Godot moves a Camera2D's own update to physics ticks anyway; saying so up front
        // keeps it from warning. The view still follows every drawn frame: Follow() sets the position itself.
        ProcessCallback = Camera2DProcessCallback.Physics;
    }

    /// <summary>The point the view is centred on.</summary>
    public Vector2 Focus { get; private set; } = Vector2.Zero;

    /// <summary>Jumps straight to the car, at the start of a race.</summary>
    public void ResetTo(Vector2 target)
    {
        Focus = target;
        _look = Vector2.Zero;
        Position = Focus;
        ResetSmoothing();
    }

    public void Follow(Vector2 target, Vector2 velocity, double delta)
    {
        Vector2 look = (velocity * LookAhead).LimitLength(MaxLook);
        _look = _look.Lerp(look, (float)Math.Min(LookRate * delta, 1.0));
        Focus = Focus.Lerp(target + _look, (float)Math.Min(FollowRate * delta, 1.0));
        Vector2 behind = target - Focus;
        if (behind.Length() > MaxLag)
            Focus = target - behind.LimitLength(MaxLag);
        Position = Focus;
    }
}

namespace Glimmerpit;

using System;
using System.Collections.Generic;
using Godot;

/// <summary>
/// One tick of a player's or a bot's wishes: moving (-1, 0 or 1 on each axis), aiming, firing, dashing, and which slot
/// the player's screen showed the shot hitting (-1 for none). On the wire it is a dictionary with the same keys as the
/// GDScript version's: seq, mx, my, ax, ay, fire, dash and claim.
/// </summary>
public sealed class SimInput
{
    public int Seq { get; set; }
    public int Mx { get; set; }
    public int My { get; set; }
    public int Ax { get; set; }
    public int Ay { get; set; }
    public bool Fire { get; set; }
    public bool Dash { get; set; }
    public int Claim { get; set; } = -1;

    public Dictionary<string, object?> ToWire() => new()
    {
        ["seq"] = Seq, ["mx"] = Mx, ["my"] = My, ["ax"] = Ax, ["ay"] = Ay, ["fire"] = Fire, ["dash"] = Dash, ["claim"] = Claim,
    };
}

/// <summary>Where a shot ends, and the slot it hit (-1 for none).</summary>
public readonly record struct Shot(int Target, int X, int Y);

/// <summary>
/// The movement and shooting code the server and every client share. A client predicts its own glimmer with Step(), the
/// server applies the same inputs with Step(), and because both run the same whole-number arithmetic the prediction is
/// exactly what the server will say: a reconciled client never corrects anything (godot-multiplayer).
/// </summary>
public static class Sim
{
    /// <summary>The simulation runs at the physics rate: 30 ticks a second.</summary>
    public const int TickRate = 30;
    /// <summary>Pixels a tick moving along one axis.</summary>
    public const int Speed = 8;
    /// <summary>Pixels a tick along each axis moving diagonally (8 / sqrt(2), rounded).</summary>
    public const int Diagonal = 6;
    /// <summary>A dash multiplies the speed for a few ticks, then needs a rest.</summary>
    public const int DashFactor = 3;
    public const int DashTicks = 5;
    public const int DashCooldown = 45;
    /// <summary>Ticks between two shots.</summary>
    public const int FireCooldown = 12;
    /// <summary>A shot is a ray this long.</summary>
    public const double Range = 1000.0;
    /// <summary>A fighter is a circle this big to a shot.</summary>
    public const double Radius = 18.0;

    /// <summary>An input that does nothing: a bot with nothing to do, or a player whose input has not arrived.</summary>
    public static SimInput Idle() => new();

    /// <summary>Clamps what a client sent to what an input can be: a server never trusts the wire.</summary>
    public static SimInput Sanitize(Dictionary<string, object?> raw)
    {
        var input = Idle();
        input.Seq = Wire.Int(Wire.Get(raw, "seq"), 0);
        input.Mx = Math.Clamp(Wire.Int(Wire.Get(raw, "mx"), 0), -1, 1);
        input.My = Math.Clamp(Wire.Int(Wire.Get(raw, "my"), 0), -1, 1);
        input.Ax = Math.Clamp(Wire.Int(Wire.Get(raw, "ax"), 0), -10000, 10000);
        input.Ay = Math.Clamp(Wire.Int(Wire.Get(raw, "ay"), 0), -10000, 10000);
        input.Fire = Wire.Flag(Wire.Get(raw, "fire"));
        input.Dash = Wire.Flag(Wire.Get(raw, "dash"));
        input.Claim = Wire.Int(Wire.Get(raw, "claim"), -1);
        return input;
    }

    /// <summary>
    /// One tick of a fighter under an input: timers, aim, dash and movement. Returns true when the input fires a shot (the
    /// caller traces it; the cooldown is already set).
    /// </summary>
    public static bool Step(Fighter f, SimInput input, Court court)
    {
        if (!f.Alive)
            return false;
        f.Cooldown = Math.Max(f.Cooldown - 1, 0);
        f.DashCooldown = Math.Max(f.DashCooldown - 1, 0);
        if (input.Ax != 0 || input.Ay != 0)
        {
            f.Ax = input.Ax;
            f.Ay = input.Ay;
        }
        if (input.Dash && f.DashCooldown == 0 && f.DashTicks == 0)
        {
            f.DashTicks = DashTicks;
            f.DashCooldown = DashCooldown;
        }
        int mx = input.Mx;
        int my = input.My;
        int speed = mx != 0 && my != 0 ? Diagonal : Speed;
        if (f.DashTicks > 0)
        {
            speed *= DashFactor;
            f.DashTicks -= 1;
        }
        Vector2I moved = court.Slide(new Vector2I(f.X, f.Y), mx * speed, my * speed);
        f.X = moved.X;
        f.Y = moved.Y;
        if (input.Fire && f.Cooldown == 0)
        {
            f.Cooldown = FireCooldown;
            return true;
        }
        return false;
    }

    /// <summary>The shot a fighter fires along its aim: the first living fighter the ray meets before a wall, and where it ends.</summary>
    public static Shot Trace(Court court, IReadOnlyList<Fighter> fighters, int shooter)
    {
        Fighter from = fighters[shooter];
        Vector2 origin = from.Position();
        Vector2 dir = from.Aim();
        double reach = court.RayLength(origin, dir, Range);
        int target = -1;
        foreach (Fighter other in fighters)
        {
            if (other.Slot == shooter || !other.Alive)
                continue;
            double t = RayCircle(origin, dir, other.Position(), Radius);
            if (t >= 0.0 && t < reach)
            {
                reach = t;
                target = other.Slot;
            }
        }
        Vector2 end = origin + dir * (float)reach;
        return new Shot(target, (int)end.X, (int)end.Y);
    }

    // Distance along the ray to the circle, -1 when it misses or lies behind.
    private static double RayCircle(Vector2 origin, Vector2 dir, Vector2 center, double radius)
    {
        Vector2 toCenter = center - origin;
        double along = toCenter.Dot(dir);
        if (along < 0.0)
            return -1.0;
        double miss = toCenter.LengthSquared() - along * along;
        if (miss > radius * radius)
            return -1.0;
        return Math.Max(along - Math.Sqrt(radius * radius - miss), 0.0);
    }
}

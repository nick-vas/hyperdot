namespace Glimmerpit;

using System;
using Godot;

/// <summary>
/// A bot that fills an empty slot, so a match always has four glimmers and needs no second machine. It keeps a fighting
/// distance from the nearest rival it can see, circles it, aims with a seeded error and fires when it has a line. The
/// server's bots read the true match; a client's bot (--autoplay) reads the client's copy, as a player would see it.
/// </summary>
/// <remarks>
/// Its draws come from the engine's seeded RandomNumberGenerator in the same order as the GDScript bot's, and its
/// distances are taken from 32-bit vectors and compared as doubles as there, so a seed plays the same match in both.
/// </remarks>
public sealed class Bot
{
    /// <summary>Pixels it tries to keep from its target.</summary>
    public const double Near = 220.0;
    public const double Far = 420.0;
    /// <summary>Ticks between changes of its circling direction.</summary>
    public const int ThinkTicks = 24;
    /// <summary>The most its aim is off, in pixels at the target.</summary>
    public const int AimError = 26;
    /// <summary>Chance of firing on a tick it can.</summary>
    public const double Trigger = 0.35;

    private int _circle = 1;
    private int _ticks;

    public Bot(int slot = 0, long seed = 1)
    {
        Slot = slot;
        Rng.Seed = unchecked((ulong)seed);
    }

    public int Slot { get; set; }
    public RandomNumberGenerator Rng { get; } = new();

    /// <summary>The input for this tick. <paramref name="me"/> is the fighter to steer (a client passes its predicted one); the match's by default.</summary>
    public SimInput Decide(ArenaMatch arena, Fighter? me = null)
    {
        var input = Sim.Idle();
        me ??= arena.Fighters[Slot];
        if (arena.State != MatchState.Round || !me.Alive)
            return input;
        _ticks++;
        if (_ticks % ThinkTicks == 0 && Rng.Randf() < 0.4)
            _circle = -_circle;
        Fighter? target = PickTarget(arena, me);
        if (target == null)
            return input;
        Vector2 here = me.Position();
        Vector2 there = target.Position();
        bool seen = arena.Court.ClearLine(here, there);
        Vector2 to = there - here;
        double distance = to.Length();
        Vector2 move;
        if (!seen || distance > Far)
            move = to;
        else if (distance < Near)
            move = -to;
        else
            move = new Vector2(-to.Y, to.X) * _circle;
        Vector2I step = FreeDirection(arena.Court, me, move);
        input.Mx = step.X;
        input.My = step.Y;
        input.Ax = (int)to.X + Rng.RandiRange(-AimError, AimError);
        input.Ay = (int)to.Y + Rng.RandiRange(-AimError, AimError);
        input.Fire = seen && me.Cooldown <= 1 && Rng.Randf() < Trigger;
        input.Dash = !seen && distance > Far && Rng.Randf() < 0.02;
        return input;
    }

    // The nearest living rival, one in sight first.
    private static Fighter? PickTarget(ArenaMatch arena, Fighter me)
    {
        Fighter? best = null;
        double bestScore = double.PositiveInfinity;
        foreach (Fighter other in arena.Fighters)
        {
            if (other.Slot == me.Slot || !other.Alive)
                continue;
            double score = me.Position().DistanceTo(other.Position());
            if (!arena.Court.ClearLine(me.Position(), other.Position()))
                score += 2000.0;
            if (score < bestScore)
            {
                bestScore = score;
                best = other;
            }
        }
        return best;
    }

    // The eight-way step closest to the wanted direction that the court lets it take; turning left or right of a pillar.
    private Vector2I FreeDirection(Court court, Fighter me, Vector2 wanted)
    {
        var first = new Vector2I(AxisSign(wanted.X, wanted.Y), AxisSign(wanted.Y, wanted.X));
        Vector2I[] tries =
        {
            first, new Vector2I(first.X, 0), new Vector2I(0, first.Y),
            new Vector2I(-first.Y, first.X) * _circle, new Vector2I(first.Y, -first.X) * _circle,
        };
        foreach (Vector2I d in tries)
        {
            if (d == Vector2I.Zero)
                continue;
            if (court.BoxFree(me.X + d.X * Sim.Speed, me.Y + d.Y * Sim.Speed))
                return d;
        }
        return Vector2I.Zero;
    }

    /// <summary>-1, 0 or 1 for one axis of a direction: 0 when the axis is under half the other, so moves are eight-way.</summary>
    public static int AxisSign(double value, double other)
    {
        // 0.00001 is the engine's own is_zero_approx margin.
        if (Math.Abs(value) < 0.00001 || Math.Abs(value) < Math.Abs(other) * 0.5)
            return 0;
        return value > 0.0 ? 1 : -1;
    }
}

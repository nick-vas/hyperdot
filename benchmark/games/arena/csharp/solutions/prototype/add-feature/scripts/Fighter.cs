namespace Glimmerpit;

using System.Collections;
using System.Collections.Generic;
using Godot;

/// <summary>
/// One glimmer in the pit: where it is, where it aims, its health and its timers. The server holds the true ones; a
/// client holds copies from snapshots, and predicts its own.
/// </summary>
public sealed class Fighter
{
    public int Slot { get; set; }
    public int X { get; set; }
    public int Y { get; set; }
    /// <summary>The last direction aimed, as a vector of whole numbers (any length).</summary>
    public int Ax { get; set; } = 1;
    public int Ay { get; set; }
    public int Hp { get; set; } = 3;
    public bool Alive { get; set; }
    /// <summary>Ticks until it can fire again.</summary>
    public int Cooldown { get; set; }
    /// <summary>Ticks of dash left.</summary>
    public int DashTicks { get; set; }
    /// <summary>Ticks until the next dash.</summary>
    public int DashCooldown { get; set; }

    public Vector2 Position() => new(X, Y);

    public Vector2 Aim()
    {
        var v = new Vector2(Ax, Ay);
        return v.Length() > 0.0f ? v / v.Length() : Vector2.Right;
    }

    public Fighter Copy() => FromArray(ToArray());

    /// <summary>The wire form: a flat array of whole numbers, small in a snapshot.</summary>
    public List<object?> ToArray() => new() { Slot, X, Y, Ax, Ay, Hp, Alive ? 1 : 0, Cooldown, DashTicks, DashCooldown };

    public static Fighter FromArray(IList data) => new()
    {
        Slot = Wire.Int(data[0]),
        X = Wire.Int(data[1]),
        Y = Wire.Int(data[2]),
        Ax = Wire.Int(data[3]),
        Ay = Wire.Int(data[4]),
        Hp = Wire.Int(data[5]),
        Alive = Wire.Int(data[6]) == 1,
        Cooldown = Wire.Int(data[7]),
        DashTicks = Wire.Int(data[8]),
        DashCooldown = Wire.Int(data[9]),
    };
}

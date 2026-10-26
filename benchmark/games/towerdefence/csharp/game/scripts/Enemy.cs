namespace Bramblegate;

using System.Collections.Generic;
using Godot;

/// <summary>
/// One pest on the field. Positions are in cells: (0.5, 0.5) is the middle of the top-left cell. A pest walks from cell
/// centre to cell centre along its path, the cell it is heading to first.
/// </summary>
/// <remarks>
/// Pos is a Godot Vector2 (32-bit floats) and the rest are doubles, as in the GDScript version, so both versions move a
/// pest by the same numbers to the last bit.
/// </remarks>
public sealed class Enemy
{
    /// <summary>How long a slowing hit lasts, in ticks.</summary>
    public const int SlowTime = 60;

    public int Uid { get; set; }
    public string Id { get; set; } = "";
    public int Hp { get; set; } = 1;
    public int MaxHp { get; set; } = 1;
    /// <summary>Cells per tick.</summary>
    public double Speed { get; set; }
    public int Reward { get; set; }
    public int Leak { get; set; } = 1;
    public Vector2 Pos { get; set; }
    public List<Vector2I> Path { get; set; } = new();
    public bool Alive { get; set; } = true;
    /// <summary>The share of its speed a slowing hit takes, while SlowTicks lasts.</summary>
    public double Slow { get; set; }
    public int SlowTicks { get; set; }

    public static Vector2 Centre(Vector2I cell) => new Vector2(cell.X, cell.Y) + new Vector2(0.5f, 0.5f);

    public Vector2I Cell() => new(Mathf.FloorToInt(Pos.X), Mathf.FloorToInt(Pos.Y));

    /// <summary>The cell it is heading to; its own cell once it has nowhere to go.</summary>
    public Vector2I Target() => Path.Count > 0 ? Path[0] : Cell();

    /// <summary>How far it still has to walk, in cells: what towers compare to find the pest closest to the store.</summary>
    public double Remaining()
    {
        if (Path.Count == 0)
            return 0.0;
        return Pos.DistanceTo(Centre(Path[0])) + (double)(Path.Count - 1);
    }

    /// <summary>How far it walks this tick.</summary>
    public double Pace() => SlowTicks > 0 ? Speed * (1.0 - Slow) : Speed;
}

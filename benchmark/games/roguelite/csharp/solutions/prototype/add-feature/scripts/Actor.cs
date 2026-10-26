namespace Wickerdeep;

using Godot;

/// <summary>
/// One creature on a floor's grid: the wick (the player) or an enemy. Plain data that World moves one cell at a time;
/// the game only draws it, sliding it from the cell it left to the one it stands on.
/// </summary>
public sealed class Actor
{
    public string Kind { get; set; } = "";
    public Vector2I Cell { get; set; }
    /// <summary>The cell it left on its last step and the tick it stepped, for the game's slide.</summary>
    public Vector2I FromCell { get; set; }
    public int MovedAt { get; set; } = -1000;
    public int Hp { get; set; } = 1;
    public int MaxHp { get; set; } = 1;
    public int Damage { get; set; } = 1;
    /// <summary>Ticks between two steps, and between two blows.</summary>
    public int MoveTicks { get; set; } = 10;
    public int AttackTicks { get; set; } = 40;
    /// <summary>How far it sees, in cells.</summary>
    public int Sight { get; set; } = 5;
    /// <summary>What snuffing it gives the wick's run.</summary>
    public int Embers { get; set; }
    public int MoveCooldown { get; set; }
    public int AttackCooldown { get; set; }
    public Vector2I Facing { get; set; } = Vector2I.Down;
    /// <summary>Ticks an enemy goes on hunting the wick after losing sight of it; 0 while it wanders.</summary>
    public int Alert { get; set; }
    /// <summary>Ticks the wick cannot be hurt again after a hurt.</summary>
    public int Mercy { get; set; }
    /// <summary>The tick it was last struck, for the game's flash.</summary>
    public int HitAt { get; set; } = -1000;

    /// <summary>An enemy of a kind of data/enemies.json, standing on a cell.</summary>
    public static Actor FromKind(EnemyStats stats, Vector2I at) => new()
    {
        Kind = stats.Id,
        Cell = at,
        FromCell = at,
        Hp = stats.Hp,
        MaxHp = stats.Hp,
        Damage = stats.Damage,
        MoveTicks = stats.MoveTicks,
        AttackTicks = stats.AttackTicks,
        Sight = stats.Sight,
        Embers = stats.Embers,
    };
}

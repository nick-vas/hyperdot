namespace Wickerdeep;

using System;
using System.Text.Json.Nodes;

/// <summary>
/// One descent: its seed, the floor it is on, and what the wick carries from floor to floor. Every floor of a run is
/// generated from the run's seed and the floor's number alone, so a saved run is these few numbers.
/// </summary>
public sealed class Run
{
    public Run()
        : this(0, 5)
    {
    }

    public Run(long seed, int wickHp)
    {
        Seed = seed;
        Hp = wickHp;
        MaxHp = wickHp;
    }

    public long Seed { get; set; }
    public int FloorNumber { get; set; } = 1;
    public int Hp { get; set; }
    public int MaxHp { get; set; }
    /// <summary>Embers gathered so far in this run; Meta banks them when it ends.</summary>
    public int Embers { get; set; }

    /// <summary>The seed of the current floor: its dungeon and its enemies' choices.</summary>
    public long FloorSeed() => Seed * 1009 + FloorNumber;

    public JsonObject ToDict() => new()
    {
        ["seed"] = Seed,
        ["floor"] = FloorNumber,
        ["hp"] = Hp,
        ["max_hp"] = MaxHp,
        ["embers"] = Embers,
    };

    public static Run FromDict(JsonObject data)
    {
        var run = new Run((long)JsonData.Number(data["seed"], 0), JsonData.Int(data["max_hp"], 5));
        run.FloorNumber = Math.Max(1, JsonData.Int(data["floor"], 1));
        run.Hp = Math.Clamp(JsonData.Int(data["hp"], run.MaxHp), 1, Math.Max(1, run.MaxHp));
        run.Embers = Math.Max(0, JsonData.Int(data["embers"], 0));
        return run;
    }
}

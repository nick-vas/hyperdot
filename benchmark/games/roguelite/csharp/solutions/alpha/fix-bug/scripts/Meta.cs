namespace Wickerdeep;

using System;

/// <summary>What outlasts a run: the save's meta progress.</summary>
public sealed class MetaProgress
{
    /// <summary>Embers banked over every run.</summary>
    public int Embers { get; set; }
    /// <summary>Levels bought at the shrine, each one more hp for the wick.</summary>
    public int Vigor { get; set; }
    /// <summary>The deepest floor reached.</summary>
    public int BestFloor { get; set; }
    public int Runs { get; set; }
}

/// <summary>
/// What outlasts a run, kept in the save's meta: embers banked over every run, vigor bought with them at the shrine
/// (each level one more hp for the wick), the deepest floor reached and the runs played.
/// </summary>
public static class Meta
{
    public const int BaseHp = 5;
    public const int VigorMax = 3;

    public static int MaxHp(SaveData save) => BaseHp + save.Meta.Vigor;

    /// <summary>Embers the next level of vigor costs: 5, 10, then 15.</summary>
    public static int VigorCost(int level) => 5 * (level + 1);

    /// <summary>Spends banked embers on a level of vigor; false when there are too few or vigor is full.</summary>
    public static bool BuyVigor(SaveData save)
    {
        MetaProgress meta = save.Meta;
        int level = meta.Vigor;
        if (level >= VigorMax || meta.Embers < VigorCost(level))
            return false;
        meta.Embers -= VigorCost(level);
        meta.Vigor = level + 1;
        return true;
    }

    /// <summary>A run ended on floorReached: its embers join the bank (half of them, rounded down, after a death).</summary>
    public static void Bank(SaveData save, int runEmbers, int floorReached, bool won)
    {
        MetaProgress meta = save.Meta;
        if (won)
            meta.Embers = meta.Embers + runEmbers;
        else
            meta.Embers = meta.Embers + runEmbers / 2;
        meta.BestFloor = Math.Max(meta.BestFloor, floorReached);
        meta.Runs += 1;
    }
}

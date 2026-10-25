namespace Lanternfen;

using System.Collections.Generic;
using System.Text.Json.Nodes;

/// <summary>A wisp standing in a lane: its card, its power, and the guard it has left.</summary>
public sealed record Wisp
{
    public Wisp(string id, int power, int guard)
    {
        Id = id;
        Power = power;
        Guard = guard;
    }

    public string Id { get; }
    public int Power { get; }
    public int Guard { get; set; }

    /// <summary>A fresh wisp of a card, its guard whole.</summary>
    public static Wisp Of(Card card) => new(card.Id, card.Power, card.Guard);
}

/// <summary>
/// One side of a duel: its light (lose it all and the duel is lost), the kindling it can spend this turn, and its cards:
/// the deck it draws from (the first card is the top), the hand, the discard pile (the last card is the newest) and the
/// row of three lanes where its wisps stand.
/// </summary>
public sealed class Keeper
{
    public const int Lanes = 3;

    public int Light { get; set; } = 20;
    /// <summary>The light it started with; mending never goes above it.</summary>
    public int MaxLight { get; set; } = 20;
    public int Kindling { get; set; }
    /// <summary>How many turns it has begun: its kindling each turn is that, up to Duel.MaxKindling.</summary>
    public int Turns { get; set; }
    /// <summary>How many times it drew from an empty deck; the nth such draw costs n light.</summary>
    public int Fatigue { get; set; }
    public List<string> Deck { get; set; } = new();
    public List<string> Hand { get; set; } = new();
    public List<string> Discard { get; set; } = new();
    /// <summary>A wisp per lane, or null.</summary>
    public Wisp?[] Row { get; set; } = new Wisp?[Lanes];

    public int WispCount()
    {
        int count = 0;
        foreach (Wisp? wisp in Row)
        {
            if (wisp != null)
                count += 1;
        }
        return count;
    }

    /// <summary>The first empty lane, -1 when the row is full.</summary>
    public int FreeLane()
    {
        for (int lane = 0; lane < Lanes; lane++)
        {
            if (Row[lane] == null)
                return lane;
        }
        return -1;
    }

    /// <summary>Everything a saved duel needs to put this keeper back as it was.</summary>
    public JsonObject ToDict()
    {
        var row = new JsonArray();
        foreach (Wisp? wisp in Row)
            row.Add(wisp == null ? null : new JsonObject { ["id"] = wisp.Id, ["power"] = wisp.Power, ["guard"] = wisp.Guard });
        return new JsonObject
        {
            ["light"] = Light,
            ["max_light"] = MaxLight,
            ["kindling"] = Kindling,
            ["turns"] = Turns,
            ["fatigue"] = Fatigue,
            ["deck"] = Pile(Deck),
            ["hand"] = Pile(Hand),
            ["discard"] = Pile(Sorted(Discard)),
            ["row"] = row,
        };
    }

    public static Keeper FromDict(JsonObject data)
    {
        var keeper = new Keeper();
        keeper.Light = JsonData.Int(data["light"], 20);
        keeper.MaxLight = JsonData.Int(data["max_light"], keeper.Light);
        keeper.Kindling = JsonData.Int(data["kindling"], 0);
        keeper.Turns = JsonData.Int(data["turns"], 0);
        keeper.Fatigue = JsonData.Int(data["fatigue"], 0);
        keeper.Deck = JsonData.Ids(data["deck"]);
        keeper.Hand = JsonData.Ids(data["hand"]);
        keeper.Discard = JsonData.Ids(data["discard"]);
        JsonArray? lanes = data["row"] as JsonArray;
        for (int lane = 0; lane < Lanes; lane++)
        {
            if (lanes != null && lane < lanes.Count && lanes[lane] is JsonObject wisp)
                keeper.Row[lane] = new Wisp(JsonData.Text(wisp["id"], ""), JsonData.Int(wisp["power"], 0), JsonData.Int(wisp["guard"], 1));
        }
        return keeper;
    }

    /// <summary>A pile in a fixed order, so two saves of the same duel are the same file.</summary>
    private static List<string> Sorted(List<string> pile)
    {
        var sorted = new List<string>(pile);
        sorted.Sort(string.CompareOrdinal);
        return sorted;
    }

    private static JsonArray Pile(List<string> pile)
    {
        var array = new JsonArray();
        foreach (string id in pile)
            array.Add(id);
        return array;
    }
}

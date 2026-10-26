namespace Lanternfen;

using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Nodes;

/// <summary>A rival of the ladder: its number, its name (a translation key), its deck, its light and its AI's weights.</summary>
public sealed record RivalRow(int Id, string Name, string Deck, int Light, double Aggression, double Caution);

/// <summary>
/// The ladder's rivals (data/rivals.json) and every deck (data/decks.json). The player's deck is the deck "keeper",
/// with KeeperLight.
/// </summary>
public sealed class Rivals
{
    public const string RivalsPath = "res://data/rivals.json";
    public const string DecksPath = "res://data/decks.json";
    public const string KeeperDeck = "keeper";
    public const int KeeperLight = 20;

    private readonly Dictionary<int, RivalRow> _rivals = new();
    private readonly Dictionary<string, List<string>> _decks = new();

    public static Rivals FromFiles(string rivalsPath = RivalsPath, string decksPath = DecksPath) =>
        Parse(JsonData.ReadFile(rivalsPath), JsonData.ReadFile(decksPath));

    public static Rivals Parse(string rivalsJson, string decksJson)
    {
        var rivals = new Rivals();
        foreach (JsonObject entry in Entries(decksJson))
            rivals._decks[JsonData.Text(entry["id"], "")] = JsonData.Ids(entry["cards"]);
        foreach (JsonObject entry in Entries(rivalsJson))
        {
            int id = JsonData.Int(entry["id"], 0);
            rivals._rivals[id] = new RivalRow(
                id,
                JsonData.Text(entry["name"], ""),
                JsonData.Text(entry["deck"], ""),
                JsonData.Int(entry["light"], KeeperLight),
                JsonData.Number(entry["aggression"], 1.0),
                JsonData.Number(entry["caution"], 1.0));
        }
        return rivals;
    }

    private static List<JsonObject> Entries(string json)
    {
        var entries = new List<JsonObject>();
        JsonNode? parsed = null;
        try
        {
            parsed = JsonNode.Parse(json);
        }
        catch (JsonException)
        {
        }
        if (parsed is not JsonArray array)
        {
            Godot.GD.PushError("Rivals: a table is not a JSON array");
            return entries;
        }
        foreach (JsonNode? entry in array)
        {
            if (entry is JsonObject found)
                entries.Add(found);
        }
        return entries;
    }

    /// <summary>Rivals are numbered 1 to Count, the ladder's order.</summary>
    public int Count => _rivals.Count;

    public bool HasRival(int id) => _rivals.ContainsKey(id);

    /// <summary>The rival with this number; null when there is none.</summary>
    public RivalRow? Rival(int id) => _rivals.TryGetValue(id, out RivalRow? row) ? row : null;

    public bool HasDeck(string id) => _decks.ContainsKey(id);

    /// <summary>A copy of a deck's cards; empty when there is no such deck.</summary>
    public List<string> DeckOf(string id) => _decks.TryGetValue(id, out List<string>? cards) ? new List<string>(cards) : new List<string>();

    /// <summary>The AI that plays a rival, with its weights.</summary>
    public Ai AiFor(int id)
    {
        RivalRow? row = Rival(id);
        return new Ai(row?.Aggression ?? 1.0, row?.Caution ?? 1.0);
    }

    /// <summary>A duel of the player's deck against a rival's.</summary>
    public Duel StartDuel(Cards catalogue, int id, long seed)
    {
        RivalRow? row = Rival(id);
        return Duel.Start(catalogue, new[] { DeckOf(KeeperDeck), DeckOf(row?.Deck ?? "") }, new[] { KeeperLight, row?.Light ?? KeeperLight }, seed);
    }
}

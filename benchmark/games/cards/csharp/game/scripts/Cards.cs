namespace Lanternfen;

using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Nodes;

/// <summary>A card of the catalogue: a wisp has power and guard, a rite an effect and its amount.</summary>
public sealed record Card(string Id, string Name, string Kind, int Cost, int Power, int Guard, string Effect, int Amount);

/// <summary>
/// The card catalogue, read from data/cards.json: every card a deck may hold. A wisp stands in a lane and strikes in the
/// Clash; a rite acts once, when played, and goes to the discard pile. Read-only while a duel runs.
/// </summary>
public sealed class Cards
{
    public const string FilePath = "res://data/cards.json";
    public const string Wisp = "wisp";
    public const string Rite = "rite";

    /// <summary>
    /// What a rite does: bolt burns the other keeper's light, mend restores one's own, draw draws cards, douse wounds the
    /// strongest wisp across, rekindle returns the wisp that fell last to the hand.
    /// </summary>
    public static readonly string[] Effects = { "bolt", "mend", "draw", "douse", "rekindle" };

    private readonly Dictionary<string, Card> _cards = new();
    private readonly List<string> _order = new();

    public static Cards FromFile(string path = FilePath) => Parse(JsonData.ReadFile(path));

    public static Cards Parse(string json)
    {
        var catalogue = new Cards();
        JsonNode? parsed = null;
        try
        {
            parsed = JsonNode.Parse(json);
        }
        catch (JsonException)
        {
        }
        if (parsed is not JsonArray entries)
        {
            Godot.GD.PushError("Cards: the catalogue is not a JSON array");
            return catalogue;
        }
        foreach (JsonNode? entry in entries)
        {
            if (entry is JsonObject card)
                catalogue.Add(card);
        }
        return catalogue;
    }

    /// <summary>Adds a card with every field present.</summary>
    public void Add(JsonObject entry)
    {
        string id = JsonData.Text(entry["id"], "");
        if (!_cards.ContainsKey(id))
            _order.Add(id);
        _cards[id] = new Card(
            id,
            JsonData.Text(entry["name"], id),
            JsonData.Text(entry["kind"], Wisp),
            JsonData.Int(entry["cost"], 0),
            JsonData.Int(entry["power"], 0),
            JsonData.Int(entry["guard"], 0),
            JsonData.Text(entry["effect"], ""),
            JsonData.Int(entry["amount"], 0));
    }

    public bool Has(string id) => _cards.ContainsKey(id);

    /// <summary>The card with this id; an unknown id gives an empty card of that id.</summary>
    public Card Get(string id) => _cards.TryGetValue(id, out Card? card) ? card : new Card(id, id, "", 0, 0, 0, "", 0);

    /// <summary>Card ids in the file's order.</summary>
    public List<string> Ids() => new(_order);
}

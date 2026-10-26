namespace Duskhive;

using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Nodes;

/// <summary>A producer as data/producers.json gives it: its first price, the factor each one owned raises it by, and glow a second.</summary>
public sealed record ProducerData(string Id, string Name, double Cost, double Growth, double Rate);

/// <summary>An upgrade as data/upgrades.json gives it: Target is a producer id, "all" (every producer) or "tap" (Gather).</summary>
public sealed record UpgradeData(string Id, string Name, string Target, double Multiplier, double Cost, int Needs);

/// <summary>
/// The game's numbers, all from data: producers (data/producers.json), upgrades (data/upgrades.json) and the economy's
/// settings (data/economy.json). The data runner checks their shape (data.json); the tests check what they mean.
/// </summary>
public sealed class Catalog
{
    public const string ProducersPath = "res://data/producers.json";
    public const string UpgradesPath = "res://data/upgrades.json";
    public const string EconomyPath = "res://data/economy.json";

    private readonly Dictionary<string, ProducerData> _producersById = new();
    private readonly Dictionary<string, UpgradeData> _upgradesById = new();
    private readonly Dictionary<string, double> _settings = new();

    /// <summary>Producers in shop order.</summary>
    public List<ProducerData> Producers { get; } = new();

    /// <summary>Upgrades in shop order.</summary>
    public List<UpgradeData> Upgrades { get; } = new();

    public static Catalog FromFiles() =>
        FromData(Read(ProducersPath, true), Read(UpgradesPath, false), Read(EconomyPath, true));

    public static Catalog FromData(JsonArray producerRows, JsonArray upgradeRows, JsonArray settingRows)
    {
        var catalog = new Catalog();
        foreach (JsonNode? node in producerRows)
        {
            if (node is not JsonObject row)
                continue;
            var producer = new ProducerData(
                JsonData.Text(row["id"], ""),
                JsonData.Text(row["name"], ""),
                JsonData.Number(row["cost"], 0.0),
                JsonData.Number(row["growth"], 1.0),
                JsonData.Number(row["rate"], 0.0));
            catalog.Producers.Add(producer);
            catalog._producersById[producer.Id] = producer;
        }
        foreach (JsonNode? node in upgradeRows)
        {
            if (node is not JsonObject row)
                continue;
            var upgrade = new UpgradeData(
                JsonData.Text(row["id"], ""),
                JsonData.Text(row["name"], ""),
                JsonData.Text(row["target"], ""),
                JsonData.Number(row["multiplier"], 1.0),
                JsonData.Number(row["cost"], 0.0),
                JsonData.Int(row["needs"], 0));
            catalog.Upgrades.Add(upgrade);
            catalog._upgradesById[upgrade.Id] = upgrade;
        }
        foreach (JsonNode? node in settingRows)
        {
            if (node is JsonObject row)
                catalog._settings[JsonData.Text(row["id"], "")] = JsonData.Number(row["value"], 0.0);
        }
        return catalog;
    }

    /// <summary>A table as an array; an optional one the game has not got yet (an early build) is empty.</summary>
    private static JsonArray Read(string path, bool required)
    {
        if (!Godot.FileAccess.FileExists(path))
        {
            if (required)
                Godot.GD.PushError($"Catalog: {path} is missing");
            return new JsonArray();
        }
        try
        {
            if (JsonNode.Parse(Godot.FileAccess.GetFileAsString(path)) is JsonArray rows)
                return rows;
        }
        catch (JsonException)
        {
        }
        Godot.GD.PushError($"Catalog: {path} is not a JSON array");
        return new JsonArray();
    }

    /// <summary>The producer with this id; null when the data has none.</summary>
    public ProducerData? Producer(string id) => _producersById.TryGetValue(id, out ProducerData? p) ? p : null;

    /// <summary>The upgrade with this id; null when the data has none.</summary>
    public UpgradeData? Upgrade(string id) => _upgradesById.TryGetValue(id, out UpgradeData? u) ? u : null;

    /// <summary>An economy setting by id (tap, milestone_every, dawn_base ...); 0 when the data lacks it.</summary>
    public double Setting(string id) => _settings.TryGetValue(id, out double value) ? value : 0.0;
}

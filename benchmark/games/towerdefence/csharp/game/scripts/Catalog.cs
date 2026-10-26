namespace Bramblegate;

using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Nodes;

/// <summary>A tower kind at level 1: what it costs and how it shoots.</summary>
public sealed record TowerRow(string Id, string Name, int Cost, double Range, int Damage, int Reload, double ShotSpeed, double Splash, double Slow);

/// <summary>What the upgrade to a level costs and what it changes.</summary>
public sealed record UpgradeRow(int Cost, int Damage, double Range, int Reload);

/// <summary>A tower's numbers at a level: the base row with each upgrade up to that level laid over it.</summary>
public sealed record TowerStats(double Range, int Damage, int Reload, double ShotSpeed, double Splash, double Slow);

/// <summary>A kind of pest. Speed is in cells a second.</summary>
public sealed record EnemyRow(string Id, string Name, int Hp, double Speed, int Reward, int Leak, double Size);

/// <summary>A map of the campaign: its rows of text (PathMap.FromRows), its sap and seeds at the start.</summary>
public sealed record MapRow(string Id, string Name, int Order, int Gold, int Lives, IReadOnlyList<string> Rows);

/// <summary>Pests of one kind in a wave: count of them, gap ticks apart, the first delay ticks after the wave starts.</summary>
public sealed record GroupRow(string Enemy, int Count, int Gap, int Delay);

/// <summary>A wave of a map: its number (from 1), the sap its clearing pays, and its groups.</summary>
public sealed class WaveRow
{
    public WaveRow(string id, int number, int bonus, List<GroupRow>? groups = null)
    {
        Id = id;
        Number = number;
        Bonus = bonus;
        Groups = groups ?? new List<GroupRow>();
    }

    public string Id { get; }
    public int Number { get; }
    public int Bonus { get; }
    public List<GroupRow> Groups { get; }

    /// <summary>A wave of one group, for tests and the bench.</summary>
    public static WaveRow Of(string enemy, int count, int gap, int bonus) => new("", 1, bonus, new List<GroupRow> { new(enemy, count, gap, 0) });
}

/// <summary>
/// The game's data: towers and their upgrades, pests, maps and their waves (data/*.json, checked by the data runner).
/// Read-only once loaded; a battle copies what it needs.
/// </summary>
public sealed class Catalog
{
    public const string DataDir = "res://data";

    /// <summary>Tower id -> its row; TowerIds keeps the file order.</summary>
    public Dictionary<string, TowerRow> Towers { get; } = new(StringComparer.Ordinal);
    public List<string> TowerIds { get; } = new();
    /// <summary>"tower:level" -> the upgrade row that buys that level.</summary>
    public Dictionary<string, UpgradeRow> Upgrades { get; } = new(StringComparer.Ordinal);
    /// <summary>Pest id -> its row; EnemyIds keeps the file order.</summary>
    public Dictionary<string, EnemyRow> Enemies { get; } = new(StringComparer.Ordinal);
    public List<string> EnemyIds { get; } = new();
    /// <summary>The maps in campaign order.</summary>
    public List<MapRow> Maps { get; } = new();
    /// <summary>Map id -> its waves in order.</summary>
    public Dictionary<string, List<WaveRow>> Waves { get; } = new(StringComparer.Ordinal);

    public static Catalog FromFiles(string dir = DataDir)
    {
        return FromTables(Read(dir + "/towers.json"), Read(dir + "/upgrades.json"), Read(dir + "/enemies.json"),
            Read(dir + "/maps.json"), Read(dir + "/waves.json"), Read(dir + "/groups.json"));
    }

    public static Catalog FromTables(JsonArray towerRows, JsonArray upgradeRows, JsonArray enemyRows, JsonArray mapRows, JsonArray waveRows, JsonArray groupRows)
    {
        var catalog = new Catalog();
        foreach (JsonObject row in Rows(towerRows))
        {
            string id = JsonData.Text(row["id"], "");
            catalog.Towers[id] = new TowerRow(id, JsonData.Text(row["name"], ""), JsonData.Int(row["cost"], 0), JsonData.Number(row["range"], 0.0),
                JsonData.Int(row["damage"], 0), JsonData.Int(row["reload"], 0), JsonData.Number(row["shot_speed"], 0.0),
                JsonData.Number(row["splash"], 0.0), JsonData.Number(row["slow"], 0.0));
            catalog.TowerIds.Add(id);
        }
        foreach (JsonObject row in Rows(upgradeRows))
        {
            catalog.Upgrades[UpgradeKey(JsonData.Text(row["tower"], ""), JsonData.Int(row["level"], 0))] = new UpgradeRow(
                JsonData.Int(row["cost"], 0), JsonData.Int(row["damage"], 0), JsonData.Number(row["range"], 0.0), JsonData.Int(row["reload"], 0));
        }
        foreach (JsonObject row in Rows(enemyRows))
        {
            string id = JsonData.Text(row["id"], "");
            catalog.Enemies[id] = new EnemyRow(id, JsonData.Text(row["name"], ""), JsonData.Int(row["hp"], 1), JsonData.Number(row["speed"], 0.0),
                JsonData.Int(row["reward"], 0), JsonData.Int(row["leak"], 1), JsonData.Number(row["size"], 0.25));
            catalog.EnemyIds.Add(id);
        }
        foreach (JsonObject row in Rows(mapRows))
        {
            catalog.Maps.Add(new MapRow(JsonData.Text(row["id"], ""), JsonData.Text(row["name"], ""), JsonData.Int(row["order"], 0),
                JsonData.Int(row["gold"], 0), JsonData.Int(row["lives"], 0), JsonData.Ids(row["rows"])));
        }
        // A stable sort, so maps of the same order keep the file's.
        var ordered = new List<MapRow>(catalog.Maps);
        catalog.Maps.Clear();
        catalog.Maps.AddRange(System.Linq.Enumerable.OrderBy(ordered, map => map.Order));
        var byId = new Dictionary<string, WaveRow>(StringComparer.Ordinal);
        var mapIds = new List<string>();
        foreach (JsonObject row in Rows(waveRows))
        {
            var wave = new WaveRow(JsonData.Text(row["id"], ""), JsonData.Int(row["number"], 0), JsonData.Int(row["bonus"], 0));
            byId[wave.Id] = wave;
            string mapId = JsonData.Text(row["map"], "");
            if (!catalog.Waves.TryGetValue(mapId, out List<WaveRow>? list))
            {
                list = new List<WaveRow>();
                catalog.Waves[mapId] = list;
                mapIds.Add(mapId);
            }
            list.Add(wave);
        }
        foreach (JsonObject row in Rows(groupRows))
        {
            if (byId.TryGetValue(JsonData.Text(row["wave"], ""), out WaveRow? wave))
            {
                wave.Groups.Add(new GroupRow(JsonData.Text(row["enemy"], ""), JsonData.Int(row["count"], 0), JsonData.Int(row["gap"], 1),
                    JsonData.Int(row["delay"], 0)));
            }
        }
        foreach (string mapId in mapIds)
        {
            List<WaveRow> list = catalog.Waves[mapId];
            var sorted = new List<WaveRow>(System.Linq.Enumerable.OrderBy(list, wave => wave.Number));
            list.Clear();
            list.AddRange(sorted);
        }
        return catalog;
    }

    private static JsonArray Read(string path)
    {
        string text = JsonData.ReadFile(path);
        try
        {
            if (JsonNode.Parse(text) is JsonArray rows)
                return rows;
        }
        catch (JsonException)
        {
        }
        Godot.GD.PushError($"Catalog: {path} is not a JSON array");
        return new JsonArray();
    }

    private static IEnumerable<JsonObject> Rows(JsonArray rows)
    {
        foreach (JsonNode? node in rows)
        {
            if (node is JsonObject row)
                yield return row;
        }
    }

    private static string UpgradeKey(string id, int level) => $"{id}:{level}";

    public bool HasTower(string id) => Towers.ContainsKey(id);

    public int Cost(string id) => Towers.TryGetValue(id, out TowerRow? row) ? row.Cost : 0;

    /// <summary>What the upgrade to a level costs; 0 when there is no such upgrade.</summary>
    public int UpgradeCost(string id, int level) => Upgrades.TryGetValue(UpgradeKey(id, level), out UpgradeRow? row) ? row.Cost : 0;

    public int MaxLevel(string id)
    {
        int level = 1;
        while (Upgrades.ContainsKey(UpgradeKey(id, level + 1)))
            level += 1;
        return level;
    }

    /// <summary>A tower's numbers at a level: the base row with each upgrade up to that level laid over it.</summary>
    public TowerStats Stats(string id, int level)
    {
        TowerRow row = Towers[id];
        var stats = new TowerStats(row.Range, row.Damage, row.Reload, row.ShotSpeed, row.Splash, row.Slow);
        for (int step = 2; step <= level; step++)
        {
            if (Upgrades.TryGetValue(UpgradeKey(id, step), out UpgradeRow? upgrade))
                stats = stats with { Damage = upgrade.Damage, Range = upgrade.Range, Reload = upgrade.Reload };
        }
        return stats;
    }

    public int MapCount => Maps.Count;

    /// <summary>The map at a place in the campaign, counted from 1; null when there is none.</summary>
    public MapRow? MapAt(int index) => index >= 1 && index <= Maps.Count ? Maps[index - 1] : null;

    public int MapIndex(string id)
    {
        for (int i = 0; i < Maps.Count; i++)
        {
            if (Maps[i].Id == id)
                return i + 1;
        }
        return 0;
    }

    public List<WaveRow> WavesFor(string mapId) => Waves.TryGetValue(mapId, out List<WaveRow>? list) ? list : new List<WaveRow>();
}

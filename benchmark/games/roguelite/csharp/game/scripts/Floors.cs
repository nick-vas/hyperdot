namespace Wickerdeep;

using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Nodes;

/// <summary>One kind of enemy, a row of data/enemies.json. A field the row leaves out takes the default here.</summary>
public sealed class EnemyStats
{
    public string Id { get; init; } = "";
    /// <summary>Its name's translation key.</summary>
    public string Name { get; init; } = "";
    public int Hp { get; init; } = 1;
    public int Damage { get; init; } = 1;
    /// <summary>Ticks between two steps, and between two blows.</summary>
    public int MoveTicks { get; init; } = 10;
    public int AttackTicks { get; init; } = 40;
    /// <summary>How far it sees, in cells.</summary>
    public int Sight { get; init; } = 5;
    /// <summary>What snuffing it gives the wick's run.</summary>
    public int Embers { get; init; } = 1;

    public static EnemyStats FromJson(JsonObject row) => new()
    {
        Id = JsonData.Text(row["id"], ""),
        Name = JsonData.Text(row["name"], ""),
        Hp = JsonData.Int(row["hp"], 1),
        Damage = JsonData.Int(row["damage"], 1),
        MoveTicks = JsonData.Int(row["move_ticks"], 10),
        AttackTicks = JsonData.Int(row["attack_ticks"], 40),
        Sight = JsonData.Int(row["sight"], 5),
        Embers = JsonData.Int(row["embers"], 1),
    };
}

/// <summary>
/// One floor's shape, a row of data/floors.json: its size, how many rooms and how big, the kinds of enemy on it
/// (repeats weigh more) and how many wait in each room. Each pair is [min, max].
/// </summary>
public sealed class FloorSpec
{
    public int Id { get; init; }
    /// <summary>Its name's translation key.</summary>
    public string Name { get; init; } = "";
    public int Width { get; init; }
    public int Height { get; init; }
    public int[] Rooms { get; init; } = { 1, 1 };
    public int[] RoomSize { get; init; } = { 3, 3 };
    public List<string> Enemies { get; init; } = new();
    public int[] PerRoom { get; init; } = { 0, 0 };

    public static FloorSpec FromJson(JsonObject row) => new()
    {
        Id = JsonData.Int(row["id"], 0),
        Name = JsonData.Text(row["name"], ""),
        Width = JsonData.Int(row["width"], 0),
        Height = JsonData.Int(row["height"], 0),
        Rooms = Pair(row["rooms"]),
        RoomSize = Pair(row["room_size"]),
        Enemies = JsonData.Ids(row["enemies"]),
        PerRoom = Pair(row["per_room"]),
    };

    private static int[] Pair(JsonNode? node)
    {
        if (node is JsonArray array && array.Count >= 2)
            return new[] { JsonData.Int(array[0], 0), JsonData.Int(array[1], 0) };
        return new[] { 0, 0 };
    }
}

/// <summary>
/// The crypt's floors (data/floors.json) and the kinds of enemy on them (data/enemies.json). A run goes down them in
/// order; clearing the last one is victory.
/// </summary>
public sealed class Floors
{
    public const string FloorsPath = "res://data/floors.json";
    public const string EnemiesPath = "res://data/enemies.json";

    private readonly Dictionary<string, EnemyStats> _kinds = new();
    private readonly Dictionary<int, FloorSpec> _floors = new();

    /// <summary>Enemy id -> its row of data/enemies.json.</summary>
    public IReadOnlyDictionary<string, EnemyStats> Kinds => _kinds;

    public static Floors FromFiles(string floorsPath = FloorsPath, string enemiesPath = EnemiesPath) =>
        Parse(JsonData.ReadFile(floorsPath), JsonData.ReadFile(enemiesPath));

    public static Floors Parse(string floorsJson, string enemiesJson)
    {
        var floors = new Floors();
        foreach (JsonObject row in Rows(enemiesJson, "enemies"))
            floors._kinds[JsonData.Text(row["id"], "")] = EnemyStats.FromJson(row);
        foreach (JsonObject row in Rows(floorsJson, "floors"))
            floors._floors[JsonData.Int(row["id"], 0)] = FloorSpec.FromJson(row);
        return floors;
    }

    private static List<JsonObject> Rows(string json, string what)
    {
        var rows = new List<JsonObject>();
        JsonNode? parsed = null;
        try
        {
            parsed = string.IsNullOrEmpty(json) ? null : JsonNode.Parse(json);
        }
        catch (JsonException)
        {
            parsed = null;
        }
        if (parsed is not JsonArray array)
        {
            Godot.GD.PushError($"Floors: the {what} file is not a JSON array");
            return rows;
        }
        foreach (JsonNode? item in array)
        {
            if (item is JsonObject row)
                rows.Add(row);
        }
        return rows;
    }

    public int Count => _floors.Count;

    public bool HasFloor(int number) => _floors.ContainsKey(number);

    /// <summary>A floor's row of data/floors.json; null when there is no such floor.</summary>
    public FloorSpec? Spec(int number) => _floors.TryGetValue(number, out FloorSpec? spec) ? spec : null;

    /// <summary>A kind of enemy; null when the data has none of that id.</summary>
    public EnemyStats? Kind(string id) => _kinds.TryGetValue(id, out EnemyStats? stats) ? stats : null;
}

namespace Lanternfen;

using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;

/// <summary>A rival's wins and losses.</summary>
public sealed class RivalRecord
{
    public int Wins { get; set; }
    public int Losses { get; set; }
}

/// <summary>What a save holds: the record against each rival, the duel in progress and the player's settings.</summary>
public sealed class SaveData
{
    /// <summary>Rival id, as text -> wins and losses.</summary>
    public SortedDictionary<string, RivalRecord> Record { get; } = new(StringComparer.Ordinal);
    /// <summary>The duel in progress (Duel.ToDict plus "rival"), kept so Continue can carry on; null when there is none.</summary>
    public JsonObject? Duel { get; set; }
    public double Volume { get; set; } = 1.0;
    public string Locale { get; set; } = "en";
}

/// <summary>
/// The player's save, JSON in user://save.json (Main passes its real path): version, record (rival id -> wins and
/// losses), duel (the duel in progress, or null) and settings (volume, locale).
/// Free of Godot types, so its tests run on plain files.
/// </summary>
public sealed class SaveStore
{
    public const int Version = 2;

    public SaveStore(string path)
    {
        Path = path;
    }

    public string Path { get; }

    /// <summary>Off with --no-save, so bot runs and tests never touch the player's save.</summary>
    public bool Enabled { get; set; } = true;

    /// <summary>The save as the current version, or the defaults when there is none or it cannot be read.</summary>
    public SaveData Read()
    {
        if (!File.Exists(Path))
            return new SaveData();
        try
        {
            // A damaged save is the player's loss, not an error: start from the defaults.
            return JsonNode.Parse(File.ReadAllText(Path)) is JsonObject raw ? Migrate(raw) : new SaveData();
        }
        catch (Exception e) when (e is JsonException or IOException or InvalidOperationException or FormatException)
        {
            return new SaveData();
        }
    }

    /// <summary>The saved data, with defaults for anything missing.</summary>
    public static SaveData Migrate(JsonObject raw)
    {
        var data = new SaveData();
        if (raw["record"] is JsonObject record)
        {
            foreach (KeyValuePair<string, JsonNode?> pair in record)
            {
                if (pair.Value is JsonObject entry)
                    data.Record[pair.Key] = new RivalRecord { Wins = JsonData.Int(entry["wins"], 0), Losses = JsonData.Int(entry["losses"], 0) };
            }
        }
        if (raw["duel"] is JsonObject duel)
            data.Duel = (JsonObject)duel.DeepClone();
        if (raw["settings"] is JsonObject settings)
        {
            data.Volume = Math.Clamp(JsonData.Number(settings["volume"], 1.0), 0.0, 1.0);
            data.Locale = JsonData.Text(settings["locale"], "en");
        }
        return data;
    }

    public bool Write(SaveData data)
    {
        if (!Enabled)
            return false;
        var record = new JsonObject();
        foreach (KeyValuePair<string, RivalRecord> pair in data.Record)
            record[pair.Key] = new JsonObject { ["wins"] = pair.Value.Wins, ["losses"] = pair.Value.Losses };
        var root = new JsonObject
        {
            ["version"] = Version,
            ["record"] = record,
            ["duel"] = data.Duel?.DeepClone(),
            ["settings"] = new JsonObject { ["volume"] = data.Volume, ["locale"] = data.Locale },
        };
        try
        {
            string? dir = System.IO.Path.GetDirectoryName(Path);
            if (!string.IsNullOrEmpty(dir))
                Directory.CreateDirectory(dir);
            File.WriteAllText(Path, root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        }
        catch (IOException)
        {
            return false;
        }
        return true;
    }
}

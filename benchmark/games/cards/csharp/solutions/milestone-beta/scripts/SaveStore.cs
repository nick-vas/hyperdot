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
/// Version 2 is current; version 1 kept only a list of the rivals beaten, and players still have such files.
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

    /// <summary>Any version's data as the current version.</summary>
    public static SaveData Migrate(JsonObject raw)
    {
        var data = new SaveData();
        int version = JsonData.Int(raw["version"], 1);
        if (version == 1)
        {
            // Version 1 kept no losses and no duel: each rival it lists was beaten once.
            foreach (string id in JsonData.Ids(raw["beaten"]))
                data.Record[id] = new RivalRecord { Wins = 1 };
            return data;
        }
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

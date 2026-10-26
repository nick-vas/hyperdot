namespace Bramblegate;

using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;

/// <summary>A cleared map's best result.</summary>
public sealed class MapResult
{
    public int Stars { get; set; }
    /// <summary>The seeds kept.</summary>
    public int Lives { get; set; }
}

/// <summary>What a save holds: each map's best result and the player's settings.</summary>
public sealed class SaveData
{
    /// <summary>Map id -> its best result.</summary>
    public SortedDictionary<string, MapResult> Progress { get; } = new(StringComparer.Ordinal);
    public double Volume { get; set; } = 1.0;
    public string Locale { get; set; } = "en";
}

/// <summary>
/// The player's save, JSON in user://save.json (Main passes its real path): version, progress (map id -> best stars and
/// seeds kept) and settings (volume, locale).
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
        if (raw["progress"] is JsonObject progress)
        {
            foreach (KeyValuePair<string, JsonNode?> pair in progress)
            {
                if (pair.Value is JsonObject entry)
                    data.Progress[pair.Key] = new MapResult { Stars = Math.Clamp(JsonData.Int(entry["stars"], 0), 0, 3), Lives = JsonData.Int(entry["lives"], 0) };
            }
        }
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
        var progress = new JsonObject();
        foreach (KeyValuePair<string, MapResult> pair in data.Progress)
            progress[pair.Key] = new JsonObject { ["stars"] = pair.Value.Stars, ["lives"] = pair.Value.Lives };
        var root = new JsonObject
        {
            ["version"] = Version,
            ["progress"] = progress,
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
            Godot.GD.PushWarning($"SaveStore: cannot write {Path}");
            return false;
        }
        return true;
    }
}

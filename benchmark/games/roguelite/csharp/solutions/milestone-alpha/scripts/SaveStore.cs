namespace Wickerdeep;

using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;

/// <summary>What a save holds: the meta progress, the run in progress and the player's settings.</summary>
public sealed class SaveData
{
    public MetaProgress Meta { get; set; } = new();
    /// <summary>The run in progress as Run.ToDict() gives it, kept at the start of each floor for Continue; null when there is none.</summary>
    public JsonObject? Run { get; set; }
    public double Volume { get; set; } = 1.0;
    public string Locale { get; set; } = "en";
}

/// <summary>
/// The player's save, JSON in user://save.json (Main passes its real path): version, meta (embers, vigor, best_floor,
/// runs), run (the run in progress, or null) and settings (volume, locale).
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
        if (raw["meta"] is JsonObject meta)
        {
            data.Meta.Embers = Math.Max(0, JsonData.Int(meta["embers"], 0));
            data.Meta.Vigor = Math.Clamp(JsonData.Int(meta["vigor"], 0), 0, Wickerdeep.Meta.VigorMax);
            data.Meta.BestFloor = Math.Max(0, JsonData.Int(meta["best_floor"], 0));
            data.Meta.Runs = Math.Max(0, JsonData.Int(meta["runs"], 0));
        }
        if (raw["run"] is JsonObject run)
            data.Run = (JsonObject)run.DeepClone();
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
        var root = new JsonObject
        {
            ["version"] = Version,
            ["meta"] = new JsonObject
            {
                ["embers"] = data.Meta.Embers,
                ["vigor"] = data.Meta.Vigor,
                ["best_floor"] = data.Meta.BestFloor,
                ["runs"] = data.Meta.Runs,
            },
            ["run"] = data.Run?.DeepClone(),
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

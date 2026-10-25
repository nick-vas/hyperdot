namespace SaltmereCrossing;

using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;

/// <summary>What a save holds: the story in progress, the endings found and the player's settings.</summary>
public sealed class SaveData
{
    /// <summary>The story in progress as Story.ToDict() gives it (node, flags, history), or null between stories.</summary>
    public JsonObject? Story { get; set; }
    /// <summary>The ids of the endings found, each once.</summary>
    public List<string> Endings { get; } = new();
    public double Volume { get; set; } = 1.0;
    public string Locale { get; set; } = "en";
}

/// <summary>
/// The player's save, JSON in user://save.json (Main passes its real path): version, story (the story in progress as
/// Story.ToDict(): node, flags and history, or null), endings (the ids of the endings found) and settings (volume,
/// locale). The story is saved at every node, so Continue carries on from the last line shown.
/// Version 2 is current; version 1 kept only the choices taken and the endings found, and players still have such files.
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
            // Version 1 kept the choices taken and the endings found: replaying the choices gives the node and the flags.
            data.Endings.AddRange(JsonData.UniqueIds(raw["found"]));
            List<string> taken = JsonData.UniqueIds(raw["choices"]);
            if (taken.Count > 0)
                data.Story = Story.Replay(StoryGraph.FromFiles(), taken).ToDict();
            return data;
        }
        if (raw["story"] is JsonObject story)
            data.Story = (JsonObject)story.DeepClone();
        data.Endings.AddRange(JsonData.UniqueIds(raw["endings"]));
        if (raw["settings"] is JsonObject settings)
        {
            data.Volume = Math.Clamp(JsonData.Number(settings["volume"], 1.0), 0.0, 1.0);
            data.Locale = JsonData.Text(settings["locale"], "en");
        }
        return data;
    }

    /// <summary>Adds an ending to those found, once.</summary>
    public static void RecordEnding(SaveData data, string endingId)
    {
        if (!data.Endings.Contains(endingId))
            data.Endings.Add(endingId);
    }

    public bool Write(SaveData data)
    {
        if (!Enabled)
            return false;
        var endings = new JsonArray();
        foreach (string id in data.Endings)
            endings.Add(JsonValue.Create(id));
        var root = new JsonObject
        {
            ["version"] = Version,
            ["story"] = data.Story?.DeepClone(),
            ["endings"] = endings,
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

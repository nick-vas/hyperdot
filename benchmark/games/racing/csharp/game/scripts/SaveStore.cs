namespace Cinderloop;

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;

/// <summary>What a save holds: the tracks open, each track's best lap and its ghost, the settings and the keys.</summary>
public sealed class SaveData
{
    /// <summary>The furthest track open.</summary>
    public int Unlocked { get; set; } = 1;
    /// <summary>Each track's best lap in milliseconds, by track id as text.</summary>
    public SortedDictionary<string, int> Best { get; set; } = new();
    /// <summary>Each track's best lap as Ghost.ToDict() gives it, by track id as text.</summary>
    public SortedDictionary<string, JsonObject> Ghosts { get; set; } = new();
    public double Volume { get; set; } = 1.0;
    public string Locale { get; set; } = "en";
    /// <summary>The rebound keys, as Controls.ToDict() gives them.</summary>
    public SortedDictionary<string, string> Controls { get; set; } = new();
}

/// <summary>
/// The player's save, JSON in user://save.json (Main passes its real path): version, unlocked (the furthest track
/// open), best (each track's best lap in milliseconds, by track id as text), ghosts (the best lap's Ghost.ToDict, by
/// track id), settings (volume, locale) and controls (Controls.ToDict). Version 2 is current; version 1 kept only each
/// track's best lap in seconds, and players still have such files. Free of Godot types, so its tests run on plain files.
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
        JsonObject? best = raw["best"] as JsonObject;
        if (version == 1)
        {
            // Version 1 timed laps in seconds and unlocked a track once the one before had a time.
            if (best != null)
            {
                foreach (KeyValuePair<string, JsonNode?> lap in best)
                {
                    int id = TrackId(lap.Key);
                    data.Best[id.ToString(CultureInfo.InvariantCulture)] = Maths.RoundI(JsonData.Number(lap.Value, 0.0) * 1000.0);
                    data.Unlocked = Math.Max(data.Unlocked, id + 1);
                }
            }
            return data;
        }
        data.Unlocked = Math.Max(1, JsonData.Int(raw["unlocked"], 1));
        if (best != null)
        {
            foreach (KeyValuePair<string, JsonNode?> lap in best)
                data.Best[lap.Key] = JsonData.Int(lap.Value, 0);
        }
        if (raw["ghosts"] is JsonObject ghosts)
        {
            foreach (KeyValuePair<string, JsonNode?> ghost in ghosts)
            {
                if (ghost.Value is JsonObject recording)
                    data.Ghosts[ghost.Key] = (JsonObject)recording.DeepClone();
            }
        }
        if (raw["settings"] is JsonObject settings)
        {
            data.Volume = Math.Clamp(JsonData.Number(settings["volume"], 1.0), 0.0, 1.0);
            data.Locale = JsonData.Text(settings["locale"], "en");
        }
        if (raw["controls"] is JsonObject controls)
        {
            foreach (KeyValuePair<string, JsonNode?> key in controls)
                data.Controls[key.Key] = JsonData.Text(key.Value, "");
        }
        return data;
    }

    /// <summary>A track id written as text, as int() reads it: 0 when it is not a number.</summary>
    private static int TrackId(string text) =>
        int.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out int id) ? id : 0;

    public bool Write(SaveData data)
    {
        if (!Enabled)
            return false;
        var best = new JsonObject();
        foreach (KeyValuePair<string, int> lap in data.Best)
            best[lap.Key] = lap.Value;
        var ghosts = new JsonObject();
        foreach (KeyValuePair<string, JsonObject> ghost in data.Ghosts)
            ghosts[ghost.Key] = ghost.Value.DeepClone();
        var controls = new JsonObject();
        foreach (KeyValuePair<string, string> key in data.Controls)
            controls[key.Key] = key.Value;
        var root = new JsonObject
        {
            ["version"] = Version,
            ["unlocked"] = data.Unlocked,
            ["best"] = best,
            ["ghosts"] = ghosts,
            ["settings"] = new JsonObject { ["volume"] = data.Volume, ["locale"] = data.Locale },
            ["controls"] = controls,
        };
        // Written beside the save and moved over it, so a crash mid-write never leaves half a file.
        string temp = Path + ".tmp";
        try
        {
            string? dir = System.IO.Path.GetDirectoryName(Path);
            if (!string.IsNullOrEmpty(dir))
                Directory.CreateDirectory(dir);
            File.WriteAllText(temp, root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
            File.Move(temp, Path, true);
        }
        catch (IOException)
        {
            return false;
        }
        return true;
    }

    /// <summary>Keeps a finished lap when it is the track's best: its time and its ghost. True when it was the best.</summary>
    public static bool RecordLap(SaveData data, int trackId, int lapMs, Ghost? ghost)
    {
        string key = trackId.ToString(CultureInfo.InvariantCulture);
        if (data.Best.TryGetValue(key, out int best) && best <= lapMs)
            return false;
        data.Best[key] = lapMs;
        if (ghost != null)
            data.Ghosts[key] = ghost.ToDict();
        return true;
    }
}

namespace Glimmerpit;

using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;
using Godot;

/// <summary>The player's settings and record: volume (0 to 1), locale, and matches played and won.</summary>
public sealed class SettingsData
{
    public int Version { get; set; } = SettingsStore.Version;
    public double Volume { get; set; } = 1.0;
    public string Locale { get; set; } = "en";
    public int Played { get; set; }
    public int Won { get; set; }
}

/// <summary>
/// The player's settings and record, JSON in user://settings.json (Main passes its real path): version, volume, locale,
/// played and won. The file is the GDScript version's, so either version of the game reads the other's.
/// </summary>
public sealed class SettingsStore
{
    public const int Version = 2;

    public SettingsStore(string path)
    {
        Path = path;
    }

    public string Path { get; }

    /// <summary>Off with --no-save, so bot runs and tests never touch the player's file.</summary>
    public bool Enabled { get; set; } = true;

    public static SettingsData Defaults() => new();

    /// <summary>The settings as the current version, or the defaults when there are none or they cannot be read.</summary>
    public SettingsData Read()
    {
        if (!File.Exists(Path))
            return Defaults();
        try
        {
            // A damaged file is the player's loss, not an error: start from the defaults.
            return JsonNode.Parse(File.ReadAllText(Path)) is JsonObject raw ? Migrate(raw) : Defaults();
        }
        catch (Exception e) when (e is JsonException or IOException or InvalidOperationException or FormatException)
        {
            return Defaults();
        }
    }

    /// <summary>The saved data, with defaults for anything missing.</summary>
    public static SettingsData Migrate(JsonObject raw)
    {
        var data = Defaults();
        data.Volume = Math.Clamp(Number(raw["volume"], 1.0), 0.0, 1.0);
        data.Locale = Text(raw["locale"], "en");
        data.Played = Math.Max((int)Number(raw["played"], 0), 0);
        data.Won = Math.Max((int)Number(raw["won"], 0), 0);
        return data;
    }

    public bool Write(SettingsData data)
    {
        if (!Enabled)
            return false;
        var root = new JsonObject
        {
            ["version"] = Version,
            ["volume"] = data.Volume,
            ["locale"] = data.Locale,
            ["played"] = data.Played,
            ["won"] = data.Won,
        };
        try
        {
            string? dir = System.IO.Path.GetDirectoryName(Path);
            if (!string.IsNullOrEmpty(dir))
                Directory.CreateDirectory(dir);
            File.WriteAllText(Path, root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            GD.PushWarning($"SettingsStore: cannot write {Path}");
            return false;
        }
        return true;
    }

    private static double Number(JsonNode? node, double fallback) =>
        node is JsonValue value && value.TryGetValue(out double number) ? number : fallback;

    private static string Text(JsonNode? node, string fallback) =>
        node is JsonValue value && value.TryGetValue(out string? text) && text != null ? text : fallback;
}

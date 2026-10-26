namespace Wickerdeep;

using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

/// <summary>
/// Reads the game's JSON leniently, as the GDScript version's int() and str() do: a number may come as an int or a
/// float (5 or 5.0), and a missing or mistyped field gives the fallback. Free of Godot types, so saves and tables are
/// read the same in tests and in the game.
/// </summary>
public static class JsonData
{
    public static double Number(JsonNode? node, double fallback)
    {
        if (node is not JsonValue value)
            return fallback;
        if (value.TryGetValue(out int i))
            return i;
        if (value.TryGetValue(out long l))
            return l;
        if (value.TryGetValue(out double d))
            return d;
        if (value.TryGetValue(out float f))
            return f;
        if (value.TryGetValue(out JsonElement e) && e.ValueKind == JsonValueKind.Number)
            return e.GetDouble();
        return fallback;
    }

    /// <summary>A whole number; a fraction is cut toward zero, as int() does.</summary>
    public static int Int(JsonNode? node, int fallback) => (int)Number(node, fallback);

    /// <summary>Text as str() gives it: a string as it is, a whole number without its ".0".</summary>
    public static string Text(JsonNode? node, string fallback)
    {
        if (node is not JsonValue value)
            return fallback;
        if (value.TryGetValue(out string? s))
            return s ?? fallback;
        double n = Number(node, double.NaN);
        if (!double.IsNaN(n))
            return n == System.Math.Floor(n) ? ((long)n).ToString(CultureInfo.InvariantCulture) : n.ToString(CultureInfo.InvariantCulture);
        return value.ToJsonString();
    }

    /// <summary>A list of ids; anything that is not a list gives an empty one.</summary>
    public static System.Collections.Generic.List<string> Ids(JsonNode? node)
    {
        var ids = new System.Collections.Generic.List<string>();
        if (node is JsonArray array)
        {
            foreach (JsonNode? item in array)
                ids.Add(Text(item, ""));
        }
        return ids;
    }

    /// <summary>The text of a file of the game (res:// paths too); "" with an error when it is missing.</summary>
    public static string ReadFile(string path)
    {
        if (!Godot.FileAccess.FileExists(path))
        {
            Godot.GD.PushError($"{path} is missing");
            return "";
        }
        return Godot.FileAccess.GetFileAsString(path);
    }
}

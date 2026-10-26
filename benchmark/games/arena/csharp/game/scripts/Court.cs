namespace Glimmerpit;

using System;
using System.Collections.Generic;
using System.Text.Json;
using Godot;

/// <summary>
/// A walled pit: its size, the pillars inside it and the four spawn points, from data/courts.json, data/walls.json and
/// data/spawns.json. Everything is in whole pixels, and fighters collide with walls as squares, so the server and every
/// client move a fighter to exactly the same place (no trigonometry, no rounding that could differ).
/// </summary>
public sealed class Court
{
    /// <summary>Half the side of a fighter's square against walls.</summary>
    public const int Half = 16;

    public string Id { get; set; } = "";
    public string NameKey { get; set; } = "";
    public int Width { get; set; } = 1200;
    public int Height { get; set; } = 640;
    /// <summary>The pillars.</summary>
    public List<Rect2I> Walls { get; } = new();
    /// <summary>The spawn points, one per slot.</summary>
    public List<Vector2I> Spawns { get; } = new();

    /// <summary>Every court in the data, in file order.</summary>
    public static List<Court> LoadAll(string dir = "res://data")
    {
        var courts = new List<Court>();
        List<JsonElement> walls = Read(dir.PathJoin("walls.json"));
        List<JsonElement> spawns = Read(dir.PathJoin("spawns.json"));
        foreach (JsonElement row in Read(dir.PathJoin("courts.json")))
        {
            var court = new Court
            {
                Id = Text(row, "id"),
                NameKey = Text(row, "name"),
                Width = Int(row, "width"),
                Height = Int(row, "height"),
            };
            foreach (JsonElement wall in walls)
            {
                if (Text(wall, "court") == court.Id)
                    court.Walls.Add(new Rect2I(Int(wall, "x"), Int(wall, "y"), Int(wall, "w"), Int(wall, "h")));
            }
            foreach (JsonElement spawn in spawns)
            {
                if (Text(spawn, "court") == court.Id)
                    court.Spawns.Add(new Vector2I(Int(spawn, "x"), Int(spawn, "y")));
            }
            courts.Add(court);
        }
        return courts;
    }

    private static List<JsonElement> Read(string path)
    {
        var rows = new List<JsonElement>();
        try
        {
            using JsonDocument doc = JsonDocument.Parse(Godot.FileAccess.GetFileAsString(path));
            if (doc.RootElement.ValueKind == JsonValueKind.Array)
            {
                foreach (JsonElement row in doc.RootElement.EnumerateArray())
                {
                    if (row.ValueKind == JsonValueKind.Object)
                        rows.Add(row.Clone());
                }
                return rows;
            }
        }
        catch (JsonException)
        {
            // Reported below, as for any file that is not an array.
        }
        GD.PushError($"Court: {path} is not a JSON array");
        return rows;
    }

    private static string Text(JsonElement row, string key) =>
        row.TryGetProperty(key, out JsonElement value) ? (value.ValueKind == JsonValueKind.String ? value.GetString() ?? "" : value.ToString()) : "";

    private static int Int(JsonElement row, string key) =>
        row.TryGetProperty(key, out JsonElement value) && value.ValueKind == JsonValueKind.Number ? (int)value.GetDouble() : 0;

    /// <summary>Whether a fighter's square centred at (x, y) is inside the court and clear of every pillar.</summary>
    public bool BoxFree(int x, int y)
    {
        if (x < Half || y < Half || x > Width - Half || y > Height - Half)
            return false;
        return WallAt(x, y) == null;
    }

    private Rect2I? WallAt(int x, int y)
    {
        var box = new Rect2I(x - Half, y - Half, Half * 2, Half * 2);
        foreach (Rect2I wall in Walls)
        {
            if (wall.Intersects(box))
                return wall;
        }
        return null;
    }

    /// <summary>Moves a square by (dx, dy), one axis after the other, stopping flush against the court's edge or a pillar.</summary>
    public Vector2I Slide(Vector2I from, int dx, int dy)
    {
        int x = Math.Clamp(from.X + dx, Half, Width - Half);
        Rect2I? wall = WallAt(x, from.Y);
        if (wall is Rect2I across)
            x = dx > 0 ? across.Position.X - Half : across.End.X + Half;
        int y = Math.Clamp(from.Y + dy, Half, Height - Half);
        wall = WallAt(x, y);
        if (wall is Rect2I along)
            y = dy > 0 ? along.Position.Y - Half : along.End.Y + Half;
        return new Vector2I(x, y);
    }

    /// <summary>How far a ray from <paramref name="from"/> along the unit vector <paramref name="dir"/> travels before it meets a pillar or the court's edge.</summary>
    public double RayLength(Vector2 from, Vector2 dir, double maxLength)
    {
        double best = maxLength;
        var bounds = new[]
        {
            new Rect2I(-10, -10, Width + 20, 10), new Rect2I(-10, Height, Width + 20, 10),
            new Rect2I(-10, 0, 10, Height), new Rect2I(Width, 0, 10, Height),
        };
        foreach (Rect2I wall in Walls)
            best = Nearer(best, RayRect(from, dir, wall));
        foreach (Rect2I wall in bounds)
            best = Nearer(best, RayRect(from, dir, wall));
        return best;
    }

    private static double Nearer(double best, double t) => t >= 0.0 && t < best ? t : best;

    /// <summary>Whether nothing stands between two points (bots use it to see).</summary>
    public bool ClearLine(Vector2 a, Vector2 b)
    {
        float length = a.DistanceTo(b);
        if (length < 0.001)
            return true;
        return RayLength(a, (b - a) / length, length) >= length - 0.001;
    }

    // The slab method: the distance along the ray to the rectangle, -1 when it misses. The vectors hold 32-bit floats
    // and the arithmetic is in doubles, as in the engine's own scripts, so both versions of the game see the same.
    private static double RayRect(Vector2 from, Vector2 dir, Rect2I rect)
    {
        double tMin = 0.0;
        double tMax = double.PositiveInfinity;
        for (int axis = 0; axis < 2; axis++)
        {
            double origin = axis == 0 ? from.X : from.Y;
            double d = axis == 0 ? dir.X : dir.Y;
            double low = axis == 0 ? rect.Position.X : rect.Position.Y;
            double high = axis == 0 ? rect.End.X : rect.End.Y;
            if (Math.Abs(d) < 0.000001)
            {
                if (origin < low || origin > high)
                    return -1.0;
                continue;
            }
            double t1 = (low - origin) / d;
            double t2 = (high - origin) / d;
            tMin = Math.Max(tMin, Math.Min(t1, t2));
            tMax = Math.Min(tMax, Math.Max(t1, t2));
            if (tMin > tMax)
                return -1.0;
        }
        return tMin;
    }
}

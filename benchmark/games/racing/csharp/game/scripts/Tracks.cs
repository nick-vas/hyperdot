namespace Cinderloop;

using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Nodes;
using Godot;

/// <summary>A row of data/tracks.json, with the defaults a row may leave out.</summary>
public sealed class TrackRow
{
    public int Id { get; set; }
    /// <summary>The track's name, as a translation key.</summary>
    public string Name { get; set; } = "";
    public int Laps { get; set; } = 2;
    public double Width { get; set; } = 150.0;
    /// <summary>The control points of the centre line.</summary>
    public List<Vector2> Points { get; set; } = new();
    /// <summary>The control points the gates stand at, in order; the first is the start line.</summary>
    public List<int> Checkpoints { get; set; } = new() { 0 };

    public static TrackRow FromJson(JsonObject row)
    {
        var track = new TrackRow
        {
            Id = JsonData.Int(row["id"], 0),
            Name = JsonData.Text(row["name"], ""),
            Laps = JsonData.Int(row["laps"], 2),
            Width = JsonData.Number(row["width"], 150.0),
        };
        if (row["points"] is JsonArray points)
        {
            foreach (JsonNode? p in points)
            {
                if (p is JsonArray xy && xy.Count >= 2)
                    track.Points.Add(new Vector2((float)JsonData.Number(xy[0], 0.0), (float)JsonData.Number(xy[1], 0.0)));
            }
        }
        if (row["checkpoints"] is JsonArray checkpoints)
        {
            track.Checkpoints = new List<int>();
            foreach (JsonNode? c in checkpoints)
                track.Checkpoints.Add(JsonData.Int(c, 0));
        }
        return track;
    }
}

/// <summary>A row of data/rivals.json.</summary>
public sealed class RivalRow
{
    public int Id { get; set; }
    public string Color { get; set; } = "#cccccc";
    /// <summary>1 drives the speed profile as planned; 0.9 takes every part of the lap at nine tenths.</summary>
    public double Pace { get; set; } = 0.9;
    /// <summary>Pixels to the right of the centre line it drives on.</summary>
    public double Line { get; set; }
}

/// <summary>The tracks and the rivals, read from data/tracks.json and data/rivals.json.</summary>
public sealed class Tracks
{
    public List<TrackRow> Rows { get; } = new();
    public List<RivalRow> Rivals { get; } = new();

    public static Tracks FromFiles(string tracksPath = "res://data/tracks.json", string rivalsPath = "res://data/rivals.json")
    {
        var tracks = new Tracks();
        foreach (JsonObject row in ReadArray(tracksPath))
            tracks.Rows.Add(TrackRow.FromJson(row));
        foreach (JsonObject row in ReadArray(rivalsPath))
        {
            tracks.Rivals.Add(new RivalRow
            {
                Id = JsonData.Int(row["id"], 0),
                Color = JsonData.Text(row["color"], "#cccccc"),
                Pace = JsonData.Number(row["pace"], 0.9),
                Line = JsonData.Number(row["line"], 0.0),
            });
        }
        return tracks;
    }

    /// <summary>The objects of a JSON array file; nothing when it is missing or not an array.</summary>
    private static List<JsonObject> ReadArray(string path)
    {
        var rows = new List<JsonObject>();
        try
        {
            if (JsonNode.Parse(JsonData.ReadFile(path)) is JsonArray array)
            {
                foreach (JsonNode? item in array)
                {
                    if (item is JsonObject row)
                        rows.Add(row);
                }
            }
        }
        catch (JsonException e)
        {
            GD.PushError($"{path}: {e.Message}");
        }
        return rows;
    }

    public int Count() => Rows.Count;

    /// <summary>The row of a track; null when the data has no such track.</summary>
    public TrackRow? Row(int id)
    {
        foreach (TrackRow row in Rows)
        {
            if (row.Id == id)
                return row;
        }
        return null;
    }

    public bool HasTrack(int id) => Row(id) != null;

    /// <summary>A track built from its row; one the data lacks is built from the defaults, and has no road.</summary>
    public Track Track(int id) => Cinderloop.Track.FromRow(Row(id) ?? new TrackRow());

    /// <summary>The drivers of a race: the player's (null, or a full-pace AI for the bot) and then rivalCount rivals.</summary>
    public List<AiDriver?> DriversFor(int rivalCount, long raceSeed, bool bot = false)
    {
        var drivers = new List<AiDriver?> { bot ? new AiDriver() : null };
        foreach (int k in GridOrder(rivalCount, raceSeed))
            drivers.Add(new AiDriver(Rivals[k].Pace, Rivals[k].Line));
        return drivers;
    }

    /// <summary>
    /// Which rival (an index into Rivals) drives each car after the player's: the data's rivals in turn, shuffled by the
    /// race's seed so the grid differs from race to race.
    /// </summary>
    public List<int> GridOrder(int rivalCount, long raceSeed)
    {
        var rng = new RandomNumberGenerator { Seed = unchecked((ulong)raceSeed) };
        var order = new List<int>();
        for (int i = 0; i < rivalCount; i++)
            order.Add(i % System.Math.Max(Rivals.Count, 1));
        for (int i = order.Count - 1; i > 0; i--)
        {
            int j = rng.RandiRange(0, i);
            (order[i], order[j]) = (order[j], order[i]);
        }
        return order;
    }
}

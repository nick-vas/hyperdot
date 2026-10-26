namespace Cinderloop;

using System.Collections.Generic;
using Godot;

/// <summary>Draws a track: the ash around it, the road along the path, the kerbs, the checkpoint gates and the chequered line.</summary>
public partial class TrackView : Node2D
{
    private static readonly Color Ground = new("#3a2f2a");
    private static readonly Color Road = new("#5b5f66");
    private static readonly Color Kerb = new("#c8553d");
    private static readonly Color KerbLight = new("#e8e0d0");
    private static readonly Color GateColor = new(1, 1, 1, 0.18f);
    private static readonly Color Cinder = new("#2a2220");
    private static readonly Color Ember = new("#7a3b22");

    private Track? _track;

    public void ShowTrack(Track shown)
    {
        _track = shown;
        QueueRedraw();
    }

    public override void _Draw()
    {
        if (_track == null || _track.PointCount() == 0)
            return;
        var box = new Rect2(_track.Path[0], Vector2.Zero);
        foreach (Vector2 p in _track.Path)
            box = box.Expand(p);
        DrawRect(box.Grow(1600f), Ground);
        DrawCinders(box.Grow(1600f));
        var loop = new List<Vector2>(_track.Path) { _track.Path[0] };
        float width = (float)_track.Width;
        for (int i = 0; i < _track.PointCount(); i++)
        {
            Color colour = (i / 2) % 2 == 0 ? Kerb : KerbLight;
            DrawLine(_track.Point(i), _track.Point(i + 1), colour, width + 14f);
            DrawCircle(_track.Point(i), width / 2f + 7f, colour);
        }
        DrawPolyline(loop.ToArray(), Road, width);
        foreach (Vector2 p in _track.Path)
            DrawCircle(p, width / 2f, Road);
        for (int gate = 1; gate < _track.GateCount(); gate++)
        {
            (Vector2 left, Vector2 right) = _track.GateEnds(gate);
            DrawLine(left, right, GateColor, 4f);
        }
        DrawLineChequers();
    }

    private void DrawLineChequers()
    {
        Track track = _track!;
        int i = track.GatePoints[0];
        Vector2 along = track.Tangent(i);
        Vector2 across = along.Orthogonal();
        const int squares = 10;
        float width = (float)track.Width;
        float size = width / squares;
        for (int row = 0; row < 2; row++)
        {
            for (int k = 0; k < squares; k++)
            {
                Vector2 corner = track.Point(i) + across * (k * size - width / 2f) + along * (row * size);
                Color colour = (k + row) % 2 == 0 ? Colors.White : Colors.Black;
                DrawColoredPolygon(new[] { corner, corner + across * size, corner + across * size + along * size, corner + along * size }, colour);
            }
        }
    }

    /// <summary>Scattered cinders and embers on the ground: the same every time (a fixed seed), and drawn once.</summary>
    private void DrawCinders(Rect2 area)
    {
        var rng = new RandomNumberGenerator { Seed = (ulong)(1234 + _track!.Id) };
        for (int k = 0; k < 900; k++)
        {
            var at = new Vector2(rng.RandfRange(area.Position.X, area.End.X), rng.RandfRange(area.Position.Y, area.End.Y));
            DrawCircle(at, rng.RandfRange(3f, 11f), k % 9 == 0 ? Ember : Cinder);
        }
    }
}

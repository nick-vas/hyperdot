namespace Cinderloop;

using System;
using System.Collections.Generic;
using Godot;
using static Cinderloop.Maths;

/// <summary>
/// A closed track: its centre line, the road's width and the checkpoint gates, built once from a row of
/// data/tracks.json. The control points are smoothed into a dense path (a Catmull-Rom spline through them, Sub points a
/// segment), which the cars, the AI and the camera all read. Everything is plain arithmetic on the path, so a race runs
/// the same without a scene.
/// </summary>
public sealed class Track
{
    /// <summary>Dense points per control segment.</summary>
    public const int Sub = 10;
    /// <summary>Gates reach this far past each edge of the road, so a car running wide over the line still crosses it.</summary>
    public const double GateMargin = 40.0;
    /// <summary>How many segments either side of a car's last segment its next nearest one is looked for.</summary>
    public const int SearchBack = 3;
    public const int SearchAhead = 8;
    /// <summary>The AI's speed limit through a bend: lateral grip and full lock both bound how tight the car can turn.</summary>
    public const double CornerSafety = 0.92;
    /// <summary>The braking the speed profile plans with, a little under the car's own.</summary>
    public const double PlannedBrake = 700.0;

    public int Id { get; private set; }
    public string NameKey { get; private set; } = "";
    public int Laps { get; private set; } = 2;
    public double Width { get; private set; } = 150.0;
    public List<Vector2> Path { get; } = new();
    /// <summary>Distance along the path to each point, from point 0; the last entry is the whole loop.</summary>
    public List<double> Lengths { get; } = new();
    /// <summary>The dense index of each gate; gate 0 is the start and finish line.</summary>
    public List<int> GatePoints { get; } = new();
    /// <summary>The fastest the AI plans to be at each point.</summary>
    public double[] SpeedProfile { get; private set; } = Array.Empty<double>();
    /// <summary>Segments examined by Nearest(), for the performance test.</summary>
    public int Lookups { get; set; }

    public static Track FromRow(TrackRow row)
    {
        var track = new Track { Id = row.Id, NameKey = row.Name, Laps = row.Laps, Width = row.Width };
        track.Build(row.Points);
        foreach (int c in row.Checkpoints)
            track.GatePoints.Add(c * Sub);
        track.PlanSpeeds();
        return track;
    }

    private void Build(List<Vector2> controls)
    {
        int n = controls.Count;
        for (int i = 0; i < n; i++)
        {
            Vector2 p0 = controls[(i - 1 + n) % n];
            Vector2 p1 = controls[i];
            Vector2 p2 = controls[(i + 1) % n];
            Vector2 p3 = controls[(i + 2) % n];
            for (int s = 0; s < Sub; s++)
            {
                double t = (double)s / Sub;
                double t2 = t * t;
                double t3 = t2 * t;
                Path.Add(0.5f * (2.0f * p1 + (p2 - p0) * (float)t + (2.0f * p0 - 5.0f * p1 + 4.0f * p2 - p3) * (float)t2 + (3.0f * p1 - p0 - 3.0f * p2 + p3) * (float)t3));
            }
        }
        double total = 0.0;
        for (int i = 0; i < Path.Count; i++)
        {
            Lengths.Add(total);
            total += Path[i].DistanceTo(Path[(i + 1) % Path.Count]);
        }
        Lengths.Add(total);
    }

    /// <summary>The AI's speed at each point: no faster than the bend there allows, and slow enough to brake for every bend ahead.</summary>
    private void PlanSpeeds()
    {
        int n = Path.Count;
        var safe = new double[n];
        for (int i = 0; i < n; i++)
        {
            double radius = RadiusAt(i);
            safe[i] = MinF(Math.Sqrt(Car.Grip * radius), radius * Car.TurnRate) * CornerSafety;
        }
        SpeedProfile = (double[])safe.Clone();
        // Twice round the loop backwards, so the bends just past the line limit the speed before it too.
        for (int pass = 0; pass < 2; pass++)
        {
            for (int k = 0; k < n; k++)
            {
                int i = n - 1 - k;
                int next = (i + 1) % n;
                double ds = SegmentLength(i);
                SpeedProfile[i] = MinF(SpeedProfile[i], Math.Sqrt(SpeedProfile[next] * SpeedProfile[next] + 2.0 * PlannedBrake * ds));
            }
        }
    }

    /// <summary>The radius of the circle through the points either side of i (a straight is very large).</summary>
    private double RadiusAt(int i)
    {
        int n = Path.Count;
        Vector2 a = Path[(i - 2 + n) % n];
        Vector2 b = Path[i];
        Vector2 c = Path[(i + 2) % n];
        double cross = Math.Abs((double)(b - a).Cross(c - b));
        if (cross < 0.0001)
            return 100000.0;
        return (double)a.DistanceTo(b) * b.DistanceTo(c) * a.DistanceTo(c) / (2.0 * cross);
    }

    public int PointCount() => Path.Count;

    public double Length() => Lengths[^1];

    public double SegmentLength(int i) => Lengths[i + 1] - Lengths[i];

    public Vector2 Point(int i) => Path[PosMod(i, Path.Count)];

    /// <summary>The direction of travel at a point.</summary>
    public Vector2 Tangent(int i) => (Point(i + 1) - Point(i - 1)).Normalized();

    /// <summary>
    /// The nearest segment to a position: the index of its first point. With a hint (the segment the car was on last tick)
    /// only the segments around it are looked at, and the whole loop only when that finds nothing on or near the road
    /// (a car placed somewhere new, or cutting across the grass).
    /// </summary>
    public int Nearest(Vector2 position, int hint = -1)
    {
        if (hint >= 0)
        {
            int best = -1;
            double bestDistance = double.PositiveInfinity;
            for (int k = -SearchBack; k <= SearchAhead; k++)
            {
                int i = PosMod(hint + k, Path.Count);
                double d = SegmentDistanceSquared(position, i);
                if (d < bestDistance)
                {
                    bestDistance = d;
                    best = i;
                }
            }
            if (bestDistance <= Width * Width)
                return best;
        }
        return NearestAnywhere(position);
    }

    private int NearestAnywhere(Vector2 position)
    {
        int best = 0;
        double bestDistance = double.PositiveInfinity;
        for (int i = 0; i < Path.Count; i++)
        {
            double d = SegmentDistanceSquared(position, i);
            if (d < bestDistance)
            {
                bestDistance = d;
                best = i;
            }
        }
        return best;
    }

    private double SegmentDistanceSquared(Vector2 position, int i)
    {
        Lookups += 1;
        Vector2 a = Path[i];
        Vector2 b = Path[(i + 1) % Path.Count];
        return position.DistanceSquaredTo(Geometry2D.GetClosestPointToSegment(position, a, b));
    }

    /// <summary>How far a position is from the centre line, measured on segment i.</summary>
    public double OffsetFromCentre(Vector2 position, int i)
    {
        Vector2 a = Point(i);
        Vector2 b = Point(i + 1);
        return position.DistanceTo(Geometry2D.GetClosestPointToSegment(position, a, b));
    }

    public bool IsOnRoad(Vector2 position, int i) => OffsetFromCentre(position, i) <= Width / 2.0;

    /// <summary>Distance along the loop of a position projected on segment i.</summary>
    public double DistanceAlong(Vector2 position, int i)
    {
        Vector2 a = Point(i);
        Vector2 b = Point(i + 1);
        Vector2 span = b - a;
        double t = ClampF((position - a).Dot(span) / MaxF(span.LengthSquared(), 0.0001), 0.0, 1.0);
        return Lengths[PosMod(i, Path.Count)] + t * span.Length();
    }

    public int GateCount() => GatePoints.Count;

    /// <summary>The two ends of a gate, across the road.</summary>
    public (Vector2 Left, Vector2 Right) GateEnds(int gate)
    {
        int i = GatePoints[gate];
        Vector2 across = Tangent(i).Orthogonal() * (float)(Width / 2.0 + GateMargin);
        return (Point(i) - across, Point(i) + across);
    }

    /// <summary>Whether a move from one position to the next crosses a gate in the direction of travel.</summary>
    public bool CrossesGate(int gate, Vector2 from, Vector2 to)
    {
        if ((to - from).Dot(Tangent(GatePoints[gate])) <= 0.0)
            return false;
        (Vector2 left, Vector2 right) = GateEnds(gate);
        return Geometry2D.SegmentIntersectsSegment(from, to, left, right).VariantType != Variant.Type.Nil;
    }

    /// <summary>A place on the starting grid behind the line: slot 0 is the front, each row two cars side by side.</summary>
    public CarState GridSlot(int slot)
    {
        if (Path.Count < 2 || GatePoints.Count == 0)
            return new CarState(Vector2.Zero, 0.0, 0.0);
        double back = 60.0 + 70.0 * (slot / 2);
        int j = GatePoints[0];
        double walked = 0.0;
        while (walked < back)
        {
            j = PosMod(j - 1, Path.Count);
            walked += SegmentLength(j);
        }
        Vector2 direction = Tangent(j);
        double side = (slot % 2 == 0 ? -1.0 : 1.0) * Width / 4.0;
        return new CarState(Point(j) + direction.Orthogonal() * (float)side, direction.Angle(), 0.0);
    }
}

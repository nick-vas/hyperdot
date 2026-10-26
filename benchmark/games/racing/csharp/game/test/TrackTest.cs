namespace Cinderloop.Tests;

using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Track: the path through the control points, the road, the gates and the grid.</summary>
[TestSuite]
[RequireGodotRuntime]
public class TrackTest
{
    private Tracks _tracks = null!;
    private Track _track = null!;

    [BeforeTest]
    public void Load()
    {
        _tracks = Tracks.FromFiles();
        _track = _tracks.Track(1);
    }

    [TestCase]
    public void The_path_passes_through_every_control_point()
    {
        TrackRow row = _tracks.Row(1)!;
        for (int i = 0; i < row.Points.Count; i++)
            AssertThat(_track.Point(i * Track.Sub).DistanceTo(row.Points[i])).IsEqualApprox(0f, 0.01f);
    }

    [TestCase]
    public void The_loop_length_adds_up_its_segments()
    {
        double total = 0.0;
        for (int i = 0; i < _track.PointCount(); i++)
            total += _track.Point(i).DistanceTo(_track.Point(i + 1));
        AssertThat(_track.Length()).IsEqualApprox(total, 0.5);
    }

    [TestCase]
    public void Nearest_with_a_hint_finds_what_a_full_search_finds()
    {
        for (int i = 0; i < _track.PointCount(); i += 7)
        {
            Vector2 near = _track.Point(i) + _track.Tangent(i).Orthogonal() * 30f + _track.Tangent(i) * 5f;
            AssertThat(_track.Nearest(near, Maths.PosMod(i - 2, _track.PointCount()))).OverrideFailureMessage($"point {i}").IsEqual(_track.Nearest(near));
        }
    }

    [TestCase]
    public void The_road_is_as_wide_as_the_data_says()
    {
        const int i = 33;
        Vector2 across = _track.Tangent(i).Orthogonal();
        AssertThat(_track.IsOnRoad(_track.Point(i) + across * (float)(_track.Width / 2.0 - 2.0), i)).IsTrue();
        AssertThat(_track.IsOnRoad(_track.Point(i) + across * (float)(_track.Width / 2.0 + 2.0), i)).IsFalse();
    }

    [TestCase]
    public void A_gate_counts_only_in_the_direction_of_travel()
    {
        int i = _track.GatePoints[1];
        Vector2 along = _track.Tangent(i) * 20f;
        AssertThat(_track.CrossesGate(1, _track.Point(i) - along, _track.Point(i) + along)).IsTrue();
        AssertThat(_track.CrossesGate(1, _track.Point(i) + along, _track.Point(i) - along)).IsFalse();
    }

    [TestCase]
    public void A_move_beside_the_gate_does_not_cross_it()
    {
        int i = _track.GatePoints[1];
        Vector2 along = _track.Tangent(i) * 20f;
        Vector2 beside = _track.Tangent(i).Orthogonal() * (float)(_track.Width / 2.0 + Track.GateMargin + 30.0);
        AssertThat(_track.CrossesGate(1, _track.Point(i) - along + beside, _track.Point(i) + along + beside)).IsFalse();
    }

    [TestCase]
    public void The_grid_is_on_the_road_behind_the_line()
    {
        double line = _track.Lengths[_track.GatePoints[0]];
        for (int slot = 0; slot < 4; slot++)
        {
            Vector2 at = _track.GridSlot(slot).Position;
            int i = _track.Nearest(at);
            AssertThat(_track.IsOnRoad(at, i)).OverrideFailureMessage($"slot {slot} on the road").IsTrue();
            double behind = Maths.FPosMod(line - _track.DistanceAlong(at, i), _track.Length());
            AssertThat(behind).OverrideFailureMessage($"slot {slot} behind the line").IsBetween(40.0, 400.0);
        }
    }

    [TestCase]
    public void Every_track_is_a_clean_loop()
    {
        foreach (TrackRow row in _tracks.Rows)
        {
            Track t = Track.FromRow(row);
            int n = t.PointCount();
            double clearance = double.PositiveInfinity;
            for (int i = 0; i < n; i++)
            {
                for (int j = i + 30; j < n - 30 + i; j++)
                    clearance = Maths.MinF(clearance, t.Point(i).DistanceTo(t.Point(j)));
            }
            AssertThat(clearance).OverrideFailureMessage($"track {t.Id} does not run into itself").IsGreater(t.Width + 60.0);
        }
    }
}

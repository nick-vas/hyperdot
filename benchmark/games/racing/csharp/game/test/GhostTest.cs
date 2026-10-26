namespace Cinderloop.Tests;

using System.Collections.Generic;
using System.Text.Json.Nodes;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Ghost: inputs kept in hundredths, saved and loaded, and a lap played back the way it was driven.</summary>
[TestSuite]
[RequireGodotRuntime]
public class GhostTest
{
    [TestCase]
    public void An_input_is_kept_in_hundredths()
    {
        AssertThat(Ghost.Quantize(0.123)).IsEqual(0.12);
        AssertThat(Ghost.Quantize(-0.987)).IsEqual(-0.99);
        AssertThat(Ghost.Quantize(3.0)).IsEqual(1.0);
    }

    [TestCase]
    public void A_recording_reads_back_its_inputs()
    {
        var ghost = new Ghost(new CarState(new Vector2(1, 2), 0.5, 10.0));
        ghost.Record(1.0, -0.5);
        ghost.Record(0.0, 0.25);
        AssertThat(ghost.Ticks()).IsEqual(2);
        AssertThat(ghost.InputAt(0)).IsEqual(new Vector2(1f, -0.5f));
        AssertThat(ghost.InputAt(1)).IsEqual(new Vector2(0f, 0.25f));
        AssertThat(ghost.InputAt(2)).OverrideFailureMessage("nothing after the end").IsEqual(Vector2.Zero);
    }

    [TestCase]
    public void Saved_and_loaded_it_is_the_same_ghost()
    {
        var ghost = new Ghost(new CarState(new Vector2(-512.25f, 300.5f), 1.25, 333.0), 60);
        for (int i = 0; i < 30; i++)
            ghost.Record(i % 3 != 0 ? 1.0 : -1.0, i % 2 != 0 ? 1.0 : 0.0);
        Ghost copy = Ghost.FromDict(JsonNode.Parse(ghost.ToDict().ToJsonString()))!;
        AssertThat(copy.Ticks()).IsEqual(30);
        AssertThat(copy.Start.Position).IsEqual(ghost.Start.Position);
        AssertThat(copy.Throttles).ContainsExactly(ghost.Throttles);
        AssertThat(copy.Steers).ContainsExactly(ghost.Steers);
    }

    [TestCase]
    public void Damaged_data_is_no_ghost()
    {
        AssertThat(Ghost.FromDict(JsonValue.Create("lap"))).IsNull();
        AssertThat(Ghost.FromDict(JsonNode.Parse("{\"start\": {}, \"throttle\": [1, 2], \"steer\": [1]}"))).IsNull();
    }

    /// <summary>A lap on the keys (full or nothing), the way a keyboard player drives it, replays exactly.</summary>
    [TestCase]
    public void A_lap_on_the_keys_replays_exactly()
    {
        var race = new Race(Tracks.FromFiles().Track(1), new List<AiDriver?> { null }, 60);
        var brain = new AiDriver();
        var path = new List<Vector2>();
        while (race.Trackers[0].Laps < 1 && race.Tick < 40 * 60)
        {
            Vector2 wish = brain.Decide(race.Cars[0], race.Track);
            race.Step(new Vector2((float)Maths.SignF(wish.X), (float)Maths.SignF(Maths.Snapped(wish.Y, 0.5))));
            path.Add(race.Cars[0].Position);
        }
        AssertThat(race.Trackers[0].Laps).IsEqual(1);
        List<Vector2> replayed = race.BestGhost!.Replay(race.Track);
        AssertThat(replayed.Count).IsEqual(path.Count);
        AssertThat(replayed[^1].DistanceTo(path[^1])).IsEqualApprox(0f, 0.01f);
    }
}

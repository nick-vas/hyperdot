namespace Glimmerpit.Tests;

using System.Collections.Generic;
using System.Linq;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>The courts in data/: every one loads with four spawns that are clear and out of each other's sight.</summary>
[TestSuite]
[RequireGodotRuntime]
public class CourtTest
{
    [TestCase]
    public void The_courts_load_in_order()
    {
        List<Court> courts = Court.LoadAll();
        AssertThat(courts.Select(c => c.Id).ToArray()).ContainsExactly("cinder_pit", "hollow_ring");
        foreach (Court court in courts)
        {
            AssertThat(court.Spawns.Count).OverrideFailureMessage(court.Id).IsEqual(ArenaMatch.Slots);
            AssertThat(court.Walls.Count).OverrideFailureMessage(court.Id).IsGreater(0);
        }
    }

    [TestCase]
    public void Every_spawn_is_free_and_sees_no_other()
    {
        foreach (Court court in Court.LoadAll())
        {
            foreach (Vector2I spawn in court.Spawns)
            {
                AssertThat(court.BoxFree(spawn.X, spawn.Y)).OverrideFailureMessage($"{court.Id} {spawn}").IsTrue();
                foreach (Vector2I other in court.Spawns)
                {
                    if (other != spawn)
                        AssertThat(court.ClearLine(spawn, other)).OverrideFailureMessage($"{court.Id}: {spawn} sees {other}").IsFalse();
                }
            }
        }
    }

    [TestCase]
    public void A_clear_line_and_a_blocked_one()
    {
        Court court = Court.LoadAll()[0];
        AssertThat(court.ClearLine(new Vector2(80, 80), new Vector2(400, 80))).IsTrue();
        AssertThat(court.ClearLine(new Vector2(400, 80), new Vector2(800, 80))).OverrideFailureMessage("the top pillar").IsFalse();
    }
}

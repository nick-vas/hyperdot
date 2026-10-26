namespace Glimmerpit.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the Hollow Ring (the alpha's add-content, and the beta milestone): the second court, played in the
/// second round, with four spawns that are clear, spread out and out of each other's sight, and matches on it that end.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenHollowRingTest
{
    private static Court? Ring()
    {
        foreach (Court court in Court.LoadAll())
        {
            if (court.Id == "hollow_ring")
                return court;
        }
        return null;
    }

    [TestCase]
    public void Hidden_the_ring_is_the_second_court()
    {
        List<Court> courts = Court.LoadAll();
        AssertThat(courts.Count).IsEqual(2);
        AssertThat(courts[1].Id).IsEqual("hollow_ring");
        AssertThat(courts[1].NameKey).IsEqual("COURT_HOLLOW_RING");
        AssertThat(TranslationServer.Translate("COURT_HOLLOW_RING").ToString()).OverrideFailureMessage("its name is translated").IsNotEqual("COURT_HOLLOW_RING");
    }

    [TestCase]
    public void Hidden_the_ring_has_four_fair_spawns()
    {
        Court? ring = Ring();
        AssertThat(ring).IsNotNull();
        if (ring == null)
            return;
        AssertThat(ring.Spawns.Count).IsEqual(4);
        AssertThat(ring.Walls.Count).OverrideFailureMessage("pillars to fight around").IsGreaterEqual(3);
        foreach (Vector2I spawn in ring.Spawns)
        {
            AssertThat(ring.BoxFree(spawn.X, spawn.Y)).OverrideFailureMessage($"spawn {spawn} is clear").IsTrue();
            foreach (Vector2I other in ring.Spawns)
            {
                if (other == spawn)
                    continue;
                AssertThat(ring.ClearLine(spawn, other)).OverrideFailureMessage($"{spawn} cannot see {other}").IsFalse();
                AssertThat((double)((Vector2)spawn).DistanceTo(other)).OverrideFailureMessage($"{spawn} is far from {other}").IsGreaterEqual(300.0);
            }
        }
    }

    [TestCase]
    public void Hidden_round_two_is_on_the_ring()
    {
        var arena = new ArenaMatch(Court.LoadAll());
        for (int i = 0; i < ArenaMatch.WarmupTicks; i++)
            arena.Advance();
        foreach (int slot in new[] { 1, 2, 3 })
        {
            for (int i = 0; i < ArenaMatch.Hp; i++)
                arena.DealDamage(0, slot);
        }
        for (int i = 0; i < ArenaMatch.IntermissionTicks; i++)
            arena.Advance();
        AssertThat(arena.RoundNumber).IsEqual(2);
        AssertThat(arena.Court.Id).IsEqual("hollow_ring");
        foreach (Fighter f in arena.Fighters)
            AssertThat(arena.Court.BoxFree(f.X, f.Y)).IsTrue();
    }

    [TestCase]
    public void Hidden_bot_rounds_on_the_ring_end()
    {
        Court? ring = Ring();
        AssertThat(ring).OverrideFailureMessage("no Hollow Ring").IsNotNull();
        if (ring == null)
            return;
        var onlyRing = new List<Court> { ring };
        foreach (long matchSeed in new long[] { 1, 2, 3, 4 })
        {
            var server = new ArenaServer(onlyRing, matchSeed);
            for (int i = 0; i < 150 * Sim.TickRate; i++)
            {
                server.Tick();
                if (server.Arena.State == MatchState.Over)
                    break;
            }
            AssertThat(server.Arena.State).OverrideFailureMessage($"seed {matchSeed}: a bot match on the ring ends within 150 s").IsEqual(MatchState.Over);
        }
    }
}

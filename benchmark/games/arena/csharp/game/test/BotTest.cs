namespace Glimmerpit.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Bots: a match of four bots ends, on both courts, and replays for a seed.</summary>
[TestSuite]
[RequireGodotRuntime]
public class BotTest
{
    private static ArenaServer PlayOut(long matchSeed, int maxTicks = 9000)
    {
        var server = new ArenaServer(Court.LoadAll(), matchSeed);
        for (int i = 0; i < maxTicks; i++)
        {
            server.Tick();
            if (server.Arena.State == MatchState.Over)
                break;
        }
        return server;
    }

    [TestCase]
    public void A_bot_match_ends_on_a_score()
    {
        ArenaServer server = PlayOut(1);
        AssertThat(server.Arena.State).IsEqual(MatchState.Over);
        AssertThat(server.Arena.Scores[server.Arena.Winner]).IsEqual(ArenaMatch.Target);
        AssertThat(server.Arena.RoundNumber).IsGreaterEqual(ArenaMatch.Target);
    }

    [TestCase]
    public void Bot_matches_take_under_three_minutes()
    {
        foreach (long matchSeed in new long[] { 2, 3, 4 })
        {
            ArenaServer server = PlayOut(matchSeed);
            AssertThat(server.Arena.State).OverrideFailureMessage($"seed {matchSeed} ends").IsEqual(MatchState.Over);
            AssertThat(server.Arena.Tick).OverrideFailureMessage($"seed {matchSeed}").IsBetween(15 * Sim.TickRate, 150 * Sim.TickRate);
        }
    }

    [TestCase]
    public void A_seed_replays_the_same_match()
    {
        ArenaServer a = PlayOut(7);
        ArenaServer b = PlayOut(7);
        AssertThat(a.Arena.Tick).IsEqual(b.Arena.Tick);
        AssertThat(a.Arena.Scores).ContainsExactly(b.Arena.Scores[0], b.Arena.Scores[1], b.Arena.Scores[2], b.Arena.Scores[3]);
        AssertThat(a.Arena.Winner).IsEqual(b.Arena.Winner);
    }
}

namespace Glimmerpit.Tests;

using System.Collections.Generic;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the beta's fix-playthrough: a glimmer that leaves the round (its player left, or a newcomer took a
/// bot's slot) ends the round the moment one is left standing, and at match point that ends the match.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenLeaveEndsRoundTest
{
    private ArenaServer _server = null!;
    private SimLink _link = null!;
    private ArenaClient _leaver = null!;

    [BeforeTest]
    public void Start()
    {
        List<Court> courts = Court.LoadAll();
        _server = new ArenaServer(courts, 3) { BotsEnabled = false };
        _link = new SimLink(_server);
        _leaver = new ArenaClient(courts);
        _link.Join(_leaver, 11);
        for (int i = 0; i < ArenaMatch.WarmupTicks + 2; i++)
            Tick();
    }

    private void Tick()
    {
        _link.Pump();
        _server.Tick();
        _link.Pump();
        _link.Advance();
    }

    private void Out(int slot)
    {
        for (int i = 0; i < ArenaMatch.Hp; i++)
            _server.Arena.DealDamage(3, slot);
    }

    [TestCase]
    public void Hidden_the_last_two_and_one_leaves()
    {
        AssertThat(_server.SlotOf(11)).IsEqual(0);
        Out(1);
        Out(2);
        _link.Leave(11);
        AssertThat(_server.Arena.State).OverrideFailureMessage("the round is over at once").IsEqual(MatchState.Intermission);
        AssertThat(_server.Arena.Scores[3]).OverrideFailureMessage("the one left standing wins it").IsEqual(1);
    }

    [TestCase]
    public void Hidden_leaving_at_match_point_ends_the_match()
    {
        _server.Arena.Scores[3] = ArenaMatch.Target - 1;
        Out(1);
        Out(2);
        _link.Leave(11);
        AssertThat(_server.Arena.State).IsEqual(MatchState.Over);
        AssertThat(_server.Arena.Winner).IsEqual(3);
    }

    [TestCase]
    public void Hidden_a_newcomer_taking_the_last_rivals_slot_ends_the_round()
    {
        Out(0);
        Out(1);
        // Slots 2 and 3 are bots, the last two standing; a newcomer takes slot 1, which is out, so nothing changes...
        var newcomer = new ArenaClient(Court.LoadAll());
        _link.Join(newcomer, 12);
        AssertThat(_server.Arena.State).IsEqual(MatchState.Round);
        // ...until the leaver goes too and a second newcomer takes slot 2, a standing bot's: slot 3 is left alone.
        _link.Leave(11);
        var second = new ArenaClient(Court.LoadAll());
        _link.Join(second, 13);
        AssertThat(_server.SlotOf(13)).IsEqual(0);
        _link.Leave(12);
        var third = new ArenaClient(Court.LoadAll());
        AssertThat(_link.Join(third, 14)).IsEqual(1);
        AssertThat(_server.Arena.State).IsEqual(MatchState.Round);
        var fourth = new ArenaClient(Court.LoadAll());
        AssertThat(_link.Join(fourth, 15)).IsEqual(2);
        AssertThat(_server.Arena.State).IsEqual(MatchState.Intermission);
        AssertThat(_server.Arena.Scores[3]).IsEqual(1);
    }

    [TestCase]
    public void Hidden_the_next_round_follows()
    {
        Out(1);
        Out(2);
        _link.Leave(11);
        for (int i = 0; i < ArenaMatch.IntermissionTicks + 2; i++)
            Tick();
        AssertThat(_server.Arena.RoundNumber).IsEqual(2);
        AssertThat(_server.Arena.AliveSlots().Count).IsEqual(4);
    }
}

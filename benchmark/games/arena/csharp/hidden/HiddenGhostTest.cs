namespace Glimmerpit.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the alpha's fix-bug: a player who leaves takes their glimmer with them. It leaves the round at once,
/// a bot takes the slot and plays it from the next round, and nothing of the player stays on the server.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenGhostTest
{
    private List<Court> _courts = null!;
    private ArenaServer _server = null!;
    private SimLink _link = null!;
    private ArenaClient _stayer = null!;
    private ArenaClient _leaver = null!;

    [BeforeTest]
    public void Start()
    {
        _courts = Court.LoadAll();
        _server = new ArenaServer(_courts, 9);
        _link = new SimLink(_server);
        _stayer = new ArenaClient(_courts);
        _leaver = new ArenaClient(_courts);
        _link.Join(_stayer, 10);
        _link.Join(_leaver, 11);
        for (int i = 0; i < ArenaMatch.WarmupTicks + 2; i++)
            Tick();
    }

    private void Tick()
    {
        if (_link.HasPeer(10))
            _stayer.Step(0, 0, 1, 0, false);
        if (_link.HasPeer(11))
            _leaver.Step(0, 0, 1, 0, false);
        _link.Pump();
        _server.Tick();
        _link.Pump();
        _link.Advance();
    }

    [TestCase]
    public void Hidden_the_leaver_leaves_the_round_at_once()
    {
        AssertThat(_server.SlotOf(11)).IsEqual(1);
        _link.Leave(11);
        AssertThat(_server.Arena.Fighters[1].Alive).OverrideFailureMessage("no ghost left standing").IsFalse();
        AssertThat(_server.Arena.IsBot(1)).OverrideFailureMessage("a bot holds the slot").IsTrue();
        AssertThat(_server.Arena.Scores[1]).IsEqual(0);
        Tick();
        Tick();
        Dictionary<string, object?> snap = _server.Arena.Snapshot();
        AssertThat(Wire.Ints(snap["owners"]).Contains(11)).OverrideFailureMessage("the snapshot no longer names the leaver").IsFalse();
    }

    [TestCase]
    public void Hidden_a_bot_plays_the_slot_from_the_next_round()
    {
        _link.Leave(11);
        foreach (int slot in new[] { 2, 3 })
        {
            for (int i = 0; i < ArenaMatch.Hp; i++)
                _server.Arena.DealDamage(0, slot);
        }
        AssertThat(_server.Arena.State).OverrideFailureMessage("the round ended without the ghost to shoot").IsEqual(MatchState.Intermission);
        for (int i = 0; i < ArenaMatch.IntermissionTicks + 2; i++)
            Tick();
        AssertThat(_server.Arena.RoundNumber).IsEqual(2);
        Fighter f = _server.Arena.Fighters[1];
        AssertThat(f.Alive).IsTrue();
        Vector2 start = f.Position();
        for (int i = 0; i < 60; i++)
            Tick();
        AssertThat(_server.Arena.Fighters[1].Position()).OverrideFailureMessage("the bot moves the slot's glimmer").IsNotEqual(start);
    }

    [TestCase]
    public void Hidden_the_leaver_can_come_back()
    {
        _link.Leave(11);
        var back = new ArenaClient(_courts);
        AssertThat(_link.Join(back, 12)).OverrideFailureMessage("the bot's slot is free to take").IsEqual(1);
        AssertThat(_server.PeerCount()).IsEqual(2);
    }
}

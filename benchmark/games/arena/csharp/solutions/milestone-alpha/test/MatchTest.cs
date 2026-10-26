namespace Glimmerpit.Tests;

using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>ArenaMatch: warm-up, rounds, points, the end of a match and slots changing hands.</summary>
[TestSuite]
[RequireGodotRuntime]
public class MatchTest
{
    private ArenaMatch _arena = null!;

    [BeforeTest]
    public void Start()
    {
        _arena = new ArenaMatch(Court.LoadAll());
        for (int i = 0; i < ArenaMatch.WarmupTicks; i++)
            _arena.Advance();
    }

    private void Out(int slot, int by)
    {
        for (int i = 0; i < ArenaMatch.Hp; i++)
            _arena.DealDamage(by, slot);
    }

    [TestCase]
    public void The_first_round_starts_after_the_warmup()
    {
        AssertThat(_arena.State).IsEqual(MatchState.Round);
        AssertThat(_arena.RoundNumber).IsEqual(1);
        AssertThat(_arena.AliveSlots()).ContainsExactly(0, 1, 2, 3);
        AssertThat(_arena.Court.Id).IsEqual("cinder_pit");
    }

    [TestCase]
    public void Five_hits_put_a_glimmer_out()
    {
        for (int i = 0; i < ArenaMatch.Hp - 1; i++)
            _arena.DealDamage(0, 1);
        AssertThat(_arena.Fighters[1].Alive).IsTrue();
        AssertThat(_arena.Fighters[1].Hp).IsEqual(1);
        _arena.DealDamage(0, 1);
        AssertThat(_arena.Fighters[1].Alive).IsFalse();
    }

    [TestCase]
    public void The_last_one_standing_wins_the_round()
    {
        Out(1, 0);
        Out(2, 0);
        AssertThat(_arena.State).IsEqual(MatchState.Round);
        Out(3, 0);
        AssertThat(_arena.State).IsEqual(MatchState.Intermission);
        AssertThat(_arena.Scores).ContainsExactly(1, 0, 0, 0);
    }

    [TestCase]
    public void Rounds_alternate_the_courts_and_the_spawns()
    {
        Out(1, 0);
        Out(2, 0);
        Out(3, 0);
        for (int i = 0; i < ArenaMatch.IntermissionTicks; i++)
            _arena.Advance();
        AssertThat(_arena.RoundNumber).IsEqual(2);
        AssertThat(_arena.Court.Id).IsEqual("cinder_pit");
        AssertThat(_arena.Fighters[0].Position()).IsEqual((Vector2)_arena.Court.Spawns[1]);
        AssertThat(_arena.AliveSlots().Count).IsEqual(4);
        AssertThat(_arena.Fighters[1].Hp).IsEqual(ArenaMatch.Hp);
    }

    [TestCase]
    public void Match_point_and_the_end_of_the_match()
    {
        _arena.Scores[2] = ArenaMatch.Target - 1;
        AssertThat(_arena.IsMatchPoint()).IsTrue();
        Out(0, 2);
        Out(1, 2);
        Out(3, 2);
        AssertThat(_arena.State).IsEqual(MatchState.Over);
        AssertThat(_arena.Winner).IsEqual(2);
        AssertThat(_arena.Matches).IsEqual(1);
    }

    [TestCase]
    public void A_new_owner_starts_from_nothing()
    {
        _arena.Scores[1] = 2;
        _arena.SetOwner(1, 77);
        AssertThat(_arena.Owners[1]).IsEqual(77);
        AssertThat(_arena.Scores[1]).IsEqual(0);
        AssertThat(_arena.Fighters[1].Alive).OverrideFailureMessage("back next round").IsFalse();
    }

    [TestCase]
    public void A_restart_keeps_the_owners_and_clears_the_scores()
    {
        _arena.SetOwner(1, 77);
        _arena.Scores[0] = 2;
        _arena.Restart();
        AssertThat(_arena.State).IsEqual(MatchState.Warmup);
        AssertThat(_arena.Scores).ContainsExactly(0, 0, 0, 0);
        AssertThat(_arena.Owners[1]).IsEqual(77);
    }

    [TestCase]
    public void A_snapshot_loads_into_another_match()
    {
        _arena.DealDamage(0, 2);
        var copy = new ArenaMatch(Court.LoadAll());
        copy.LoadSnapshot(_arena.Snapshot());
        AssertThat(copy.RoundNumber).IsEqual(1);
        AssertThat(copy.Fighters[2].Hp).IsEqual(ArenaMatch.Hp - 1);
        AssertThat(copy.Fighters[3].Position()).IsEqual(_arena.Fighters[3].Position());
        AssertThat(copy.State).IsEqual(MatchState.Round);
    }
}

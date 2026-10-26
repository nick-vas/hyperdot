namespace Glimmerpit.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// The rules a match is played by: damage and knock-outs, the cooldown, pillars against shots and glimmers, rounds and
/// the end of the match.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class MatchRulesTest
{
    private ArenaMatch _arena = null!;

    [BeforeTest]
    public void Start()
    {
        _arena = new ArenaMatch(Court.LoadAll());
        for (int i = 0; i < ArenaMatch.WarmupTicks; i++)
            _arena.Advance();
    }

    private void Place(int slot, int x, int y)
    {
        _arena.Fighters[slot].X = x;
        _arena.Fighters[slot].Y = y;
    }

    private void Fire(int slot, int ax, int ay)
    {
        _arena.Apply(slot, new SimInput { Ax = ax, Ay = ay, Fire = true });
    }

    private void Out(int slot, int by)
    {
        for (int i = 0; i < ArenaMatch.Hp; i++)
            _arena.DealDamage(by, slot);
    }

    [TestCase]
    public void A_shot_in_the_open_takes_one_health()
    {
        Place(0, 100, 220);
        Place(1, 400, 220);
        Fire(0, 1, 0);
        AssertThat(_arena.Fighters[1].Hp).IsEqual(ArenaMatch.Hp - 1);
    }

    [TestCase]
    public void A_pillar_takes_the_shot()
    {
        // The Cinder Pit's top pillar spans x 570 to 630 down to y 170.
        Place(0, 400, 100);
        Place(1, 800, 100);
        Fire(0, 1, 0);
        AssertThat(_arena.Fighters[1].Hp).IsEqual(ArenaMatch.Hp);
    }

    [TestCase]
    public void The_cooldown_holds_the_next_shot()
    {
        Place(0, 100, 220);
        Place(1, 400, 220);
        Fire(0, 1, 0);
        Fire(0, 1, 0);
        AssertThat(_arena.Fighters[1].Hp).IsEqual(ArenaMatch.Hp - 1);
        for (int i = 0; i < Sim.FireCooldown - 2; i++)
            _arena.Apply(0, Sim.Idle());
        Fire(0, 1, 0);
        AssertThat(_arena.Fighters[1].Hp).OverrideFailureMessage("ready again after the cooldown").IsEqual(ArenaMatch.Hp - 2);
    }

    [TestCase]
    public void The_last_hit_knocks_a_glimmer_out()
    {
        Out(1, 0);
        AssertThat(_arena.Fighters[1].Alive).IsFalse();
        AssertThat(_arena.AliveSlots()).ContainsExactly(0, 2, 3);
    }

    [TestCase]
    public void The_last_one_standing_scores_the_round()
    {
        Out(1, 0);
        Out(2, 0);
        Out(3, 0);
        AssertThat(_arena.State).IsEqual(MatchState.Intermission);
        AssertThat(_arena.Scores).ContainsExactly(1, 0, 0, 0);
    }

    [TestCase]
    public void The_target_ends_the_match()
    {
        _arena.Scores[3] = ArenaMatch.Target - 1;
        Out(0, 3);
        Out(1, 3);
        Out(2, 3);
        AssertThat(_arena.State).IsEqual(MatchState.Over);
        AssertThat(_arena.Winner).IsEqual(3);
    }

    [TestCase]
    public void A_pillar_stops_a_glimmer()
    {
        Place(0, 500, 320);
        for (int i = 0; i < 10; i++)
            _arena.Apply(0, new SimInput { Seq = i, Mx = 1 });
        AssertThat(_arena.Fighters[0].X).IsEqual(540 - Court.Half);
    }
}

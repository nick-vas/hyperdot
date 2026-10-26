namespace Glimmerpit.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Sim: the movement and shots the server and the clients share.</summary>
[TestSuite]
[RequireGodotRuntime]
public class SimTest
{
    private Court _court = null!;

    [BeforeTest]
    public void Load()
    {
        _court = Court.LoadAll()[0];
    }

    private static Fighter MakeFighter(int x, int y, int slot = 0) => new() { Slot = slot, X = x, Y = y, Alive = true };

    private static SimInput MakeInput(int mx, int my, bool fire = false, bool dash = false) => new() { Mx = mx, My = my, Fire = fire, Dash = dash };

    [TestCase]
    public void A_straight_step_moves_eight_pixels()
    {
        Fighter f = MakeFighter(100, 200);
        Sim.Step(f, MakeInput(1, 0), _court);
        AssertThat(new Vector2I(f.X, f.Y)).IsEqual(new Vector2I(108, 200));
    }

    [TestCase]
    public void A_diagonal_step_moves_six_on_each_axis()
    {
        Fighter f = MakeFighter(100, 200);
        Sim.Step(f, MakeInput(1, 1), _court);
        AssertThat(new Vector2I(f.X, f.Y)).IsEqual(new Vector2I(106, 206));
    }

    [TestCase]
    public void A_pillar_stops_a_fighter_flush_against_it()
    {
        // The Cinder Pit's core pillar starts at x 540: a 16-pixel half side stops the centre at 524.
        Fighter f = MakeFighter(520, 300);
        Sim.Step(f, MakeInput(1, 0), _court);
        AssertThat(f.X).IsEqual(524);
        Sim.Step(f, MakeInput(1, 0), _court);
        AssertThat(f.X).OverrideFailureMessage("no further").IsEqual(524);
    }

    [TestCase]
    public void The_court_edge_holds_a_fighter_in()
    {
        Fighter f = MakeFighter(20, 400);
        Sim.Step(f, MakeInput(-1, 0), _court);
        AssertThat(f.X).IsEqual(Court.Half);
    }

    [TestCase]
    public void A_dash_triples_the_speed_for_five_ticks_then_rests()
    {
        Fighter f = MakeFighter(100, 400);
        Sim.Step(f, MakeInput(0, 0, false, true), _court);
        AssertThat(f.DashTicks).IsEqual(Sim.DashTicks - 1);
        f = MakeFighter(100, 400);
        for (int i = 0; i < Sim.DashTicks; i++)
            Sim.Step(f, MakeInput(1, 0, false, i == 0), _court);
        AssertThat(f.X).IsEqual(100 + Sim.DashTicks * Sim.Speed * Sim.DashFactor);
        Sim.Step(f, MakeInput(1, 0, false, true), _court);
        AssertThat(f.X).OverrideFailureMessage("resting: a plain step").IsEqual(100 + Sim.DashTicks * Sim.Speed * Sim.DashFactor + Sim.Speed);
    }

    [TestCase]
    public void Firing_starts_the_cooldown()
    {
        Fighter f = MakeFighter(100, 400);
        AssertThat(Sim.Step(f, MakeInput(0, 0, true), _court)).IsTrue();
        AssertThat(f.Cooldown).IsEqual(Sim.FireCooldown);
        AssertThat(Sim.Step(f, MakeInput(0, 0, true), _court)).OverrideFailureMessage("cooling down").IsFalse();
    }

    [TestCase]
    public void A_dead_fighter_does_not_move()
    {
        Fighter f = MakeFighter(100, 400);
        f.Alive = false;
        AssertThat(Sim.Step(f, MakeInput(1, 0, true), _court)).IsFalse();
        AssertThat(f.X).IsEqual(100);
    }

    [TestCase]
    public void A_shot_hits_the_nearest_fighter_in_line()
    {
        Fighter[] fighters = { MakeFighter(100, 100, 0), MakeFighter(400, 100, 1), MakeFighter(300, 100, 2), MakeFighter(900, 600, 3) };
        Shot shot = Sim.Trace(_court, fighters, 0);
        AssertThat(shot.Target).IsEqual(2);
        AssertThat((double)shot.X).IsEqualApprox(300.0 - Sim.Radius, 1.0);
    }

    [TestCase]
    public void A_pillar_stops_a_shot()
    {
        // The top pillar (x 570 to 630) stands between them.
        Fighter[] fighters = { MakeFighter(400, 100, 0), MakeFighter(800, 100, 1), MakeFighter(100, 600, 2), MakeFighter(1100, 600, 3) };
        Shot shot = Sim.Trace(_court, fighters, 0);
        AssertThat(shot.Target).IsEqual(-1);
        AssertThat((double)shot.X).IsEqualApprox(570.0, 1.0);
    }

    [TestCase]
    public void Input_from_the_wire_is_clamped()
    {
        SimInput input = Sim.Sanitize(new Dictionary<string, object?> { ["seq"] = 4, ["mx"] = 5, ["my"] = -9, ["ax"] = 99999, ["fire"] = 1 });
        AssertThat(input.Mx).IsEqual(1);
        AssertThat(input.My).IsEqual(-1);
        AssertThat(input.Ax).IsEqual(10000);
        AssertThat(input.Fire).IsTrue();
        AssertThat(input.Claim).IsEqual(-1);
    }
}

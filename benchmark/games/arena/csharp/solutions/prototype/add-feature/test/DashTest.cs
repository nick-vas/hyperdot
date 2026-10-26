namespace Glimmerpit.Tests;

using System.Collections.Generic;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>The dash: three times the speed for five ticks, a rest of 45 from the press, and alike online.</summary>
[TestSuite]
[RequireGodotRuntime]
public class DashTest
{
    private Court _court = null!;

    [BeforeTest]
    public void Load()
    {
        _court = Court.LoadAll()[0];
    }

    [TestCase]
    public void A_dash_triples_the_speed_for_five_ticks_then_rests()
    {
        var f = new Fighter { X = 100, Y = 400, Alive = true };
        for (int i = 0; i < Sim.DashTicks; i++)
            Sim.Step(f, new SimInput { Mx = 1, Dash = i == 0 }, _court);
        AssertThat(f.X).IsEqual(100 + Sim.DashTicks * Sim.Speed * Sim.DashFactor);
        Sim.Step(f, new SimInput { Mx = 1, Dash = true }, _court);
        AssertThat(f.X).OverrideFailureMessage("resting: a plain step").IsEqual(100 + Sim.DashTicks * Sim.Speed * Sim.DashFactor + Sim.Speed);
    }

    [TestCase]
    public void The_dash_state_travels_in_snapshots()
    {
        var f = new Fighter { X = 100, Y = 400, Alive = true };
        Sim.Step(f, new SimInput { Mx = 1, Dash = true }, _court);
        Fighter copy = f.Copy();
        AssertThat(copy.DashTicks).IsEqual(Sim.DashTicks - 1);
        AssertThat(copy.DashCooldown).IsEqual(Sim.DashCooldown);
    }

    [TestCase]
    public void A_dash_online_corrects_nothing()
    {
        List<Court> courts = Court.LoadAll();
        var server = new ArenaServer(courts, 5) { BotsEnabled = false };
        var link = new SimLink(server, 3);
        var client = new ArenaClient(courts);
        link.Join(client, 10);
        for (int i = 0; i < ArenaMatch.WarmupTicks + 10; i++)
            Tick(client, link, server, 0, false);
        for (int i = 0; i < 60; i++)
            Tick(client, link, server, 1, i % 50 == 0);
        for (int i = 0; i < 10; i++)
            Tick(client, link, server, 0, false);
        AssertThat(client.Corrections).IsEqual(0);
        AssertThat(client.Predicted!.Position()).IsEqual(server.Arena.Fighters[0].Position());
    }

    private static void Tick(ArenaClient client, SimLink link, ArenaServer server, int mx, bool dash)
    {
        client.Step(mx, 0, 1, 0, false, dash);
        link.Pump();
        server.Tick();
        link.Pump();
        link.Advance();
    }
}

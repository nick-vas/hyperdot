namespace Glimmerpit.Tests;

using System.Collections.Generic;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the prototype's add-feature: the dash. Three times the speed for 5 ticks from the press, no new dash
/// for 45 ticks from the press, and the same on the server and in a client's prediction, so a dash online corrects nothing.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenDashTest
{
    private Court _court = null!;

    [BeforeTest]
    public void Load()
    {
        _court = Court.LoadAll()[0];
    }

    private static Fighter MakeFighter(int x, int y) => new() { X = x, Y = y, Alive = true };

    private static SimInput DashInput(int mx, bool dash)
    {
        SimInput input = Sim.Idle();
        input.Mx = mx;
        input.Dash = dash;
        return input;
    }

    private List<int> Xs(IEnumerable<bool> presses)
    {
        Fighter f = MakeFighter(100, 220);
        var xs = new List<int>();
        foreach (bool press in presses)
        {
            Sim.Step(f, DashInput(1, press), _court);
            xs.Add(f.X);
        }
        return xs;
    }

    [TestCase]
    public void Hidden_a_dash_is_three_times_as_fast_for_five_ticks()
    {
        AssertThat(Xs(new[] { true, false, false, false, false, false, false })).ContainsExactly(124, 148, 172, 196, 220, 228, 236);
    }

    [TestCase]
    public void Hidden_a_dash_waits_45_ticks_from_the_press()
    {
        var presses = new List<bool>();
        for (int i = 0; i < 46; i++)
            presses.Add(true);
        List<int> xs = Xs(presses);
        AssertThat(xs[5] - xs[4]).OverrideFailureMessage("no second dash at tick 6").IsEqual(8);
        AssertThat(xs[44] - xs[43]).OverrideFailureMessage("still resting at tick 45").IsEqual(8);
        AssertThat(xs[45] - xs[44]).OverrideFailureMessage("a new dash at tick 46").IsEqual(24);
    }

    [TestCase]
    public void Hidden_a_dash_without_moving_goes_nowhere()
    {
        Fighter f = MakeFighter(100, 220);
        Sim.Step(f, DashInput(0, true), _court);
        AssertThat(f.X).IsEqual(100);
    }

    [TestCase]
    public void Hidden_a_dash_stops_at_a_pillar()
    {
        Fighter f = MakeFighter(500, 320);
        for (int i = 0; i < 3; i++)
            Sim.Step(f, DashInput(1, i == 0), _court);
        AssertThat(f.X).IsEqual(540 - Court.Half);
    }

    [TestCase]
    public void Hidden_a_dash_online_needs_no_correction()
    {
        List<Court> courts = Court.LoadAll();
        var server = new ArenaServer(courts, 5) { BotsEnabled = false };
        var link = new SimLink(server, 3);
        var client = new ArenaClient(courts);
        link.Join(client, 10);
        for (int i = 0; i < ArenaMatch.WarmupTicks + 2; i++)
            OnlineTick(client, link, server);
        server.Arena.Fighters[0].X = 100;
        server.Arena.Fighters[0].Y = 220;
        for (int i = 0; i < 10; i++)
            OnlineTick(client, link, server);
        client.Corrections = 0;
        for (int i = 0; i < 120; i++)
        {
            // The client takes the dash as Step()'s sixth argument.
            client.Step(1, 0, 1, 0, false, i == 50 || i == 100);
            link.Pump();
            server.Tick();
            link.Pump();
            link.Advance();
        }
        for (int i = 0; i < 10; i++)
            OnlineTick(client, link, server);
        AssertThat(client.Corrections).IsEqual(0);
        AssertThat(client.Predicted!.Position()).IsEqual(server.Arena.Fighters[0].Position());
        AssertThat(server.Arena.Fighters[0].X).OverrideFailureMessage("two dashes carried it to the far edge").IsEqual(1200 - Court.Half);
    }

    private static void OnlineTick(ArenaClient client, SimLink link, ArenaServer server)
    {
        client.Step(0, 0, 1, 0, false);
        link.Pump();
        server.Tick();
        link.Pump();
        link.Advance();
    }
}

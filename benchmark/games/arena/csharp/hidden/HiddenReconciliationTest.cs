namespace Glimmerpit.Tests;

using System.Collections.Generic;
using System.Linq;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the beta's fix-bug: on a connection with a round trip of 100 ms or more, a player's own glimmer moves
/// a whole step every tick it is told to, never back, and no snapshot moves it: the prediction is reconciled, not reset.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenReconciliationTest
{
    private ArenaServer _server = null!;
    private SimLink _link = null!;
    private ArenaClient _client = null!;

    private void Setup(int delay, int jitter)
    {
        List<Court> courts = Court.LoadAll();
        _server = new ArenaServer(courts, 5) { BotsEnabled = false };
        _link = new SimLink(_server, delay, jitter, 11);
        _client = new ArenaClient(courts);
        _link.Join(_client, 10);
        for (int i = 0; i < ArenaMatch.WarmupTicks + 2 * delay + jitter + 4; i++)
            Tick(0, 0);
        _server.Arena.Fighters[0].X = 100;
        _server.Arena.Fighters[0].Y = 220;
        for (int i = 0; i < 2 * delay + jitter + 4; i++)
            Tick(0, 0);
    }

    private void Tick(int mx, int my)
    {
        _client.Step(mx, my, 1, 0, false);
        _link.Pump();
        _server.Tick();
        _link.Pump();
        _link.Advance();
    }

    // Moves right for half the ticks, then down, recording how far the predicted glimmer moved on each tick.
    private List<float> Steps(int ticks)
    {
        var steps = new List<float>();
        Vector2 last = _client.Predicted!.Position();
        for (int i = 0; i < ticks; i++)
        {
            if (i < ticks / 2)
                Tick(1, 0);
            else
                Tick(0, 1);
            Vector2 now = _client.Predicted!.Position();
            steps.Add(now.DistanceTo(last));
            last = now;
        }
        return steps;
    }

    [TestCase]
    public void Hidden_100_ms_moves_a_whole_step_every_tick()
    {
        Setup(SimLink.TicksForMs(100), 0);
        int corrections = _client.Corrections;
        List<float> steps = Steps(60);
        AssertThat(steps.Min()).OverrideFailureMessage("never held back").IsEqual((float)Sim.Speed);
        AssertThat(steps.Max()).OverrideFailureMessage("never thrown forward or back").IsEqual((float)Sim.Speed);
        AssertThat(_client.Corrections).OverrideFailureMessage("no snapshot moved it").IsEqual(corrections);
    }

    [TestCase]
    public void Hidden_250_ms_with_jitter_corrects_nothing()
    {
        Setup(SimLink.TicksForMs(250), 2);
        int corrections = _client.Corrections;
        List<float> steps = Steps(60);
        AssertThat(steps.Min()).IsEqual((float)Sim.Speed);
        AssertThat(steps.Max()).IsEqual((float)Sim.Speed);
        AssertThat(_client.Corrections).IsEqual(corrections);
    }

    [TestCase]
    public void Hidden_it_ends_where_the_server_says()
    {
        Setup(SimLink.TicksForMs(150), 1);
        Steps(40);
        for (int i = 0; i < 20; i++)
            Tick(0, 0);
        AssertThat(_client.Predicted!.Position()).IsEqual(_server.Arena.Fighters[0].Position());
    }
}

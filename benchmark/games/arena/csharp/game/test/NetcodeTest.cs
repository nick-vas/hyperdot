namespace Glimmerpit.Tests;

using System.Collections.Generic;
using System.Linq;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>The netcode core in one process: a server, clients on a SimLink, bots in the free slots.</summary>
[TestSuite]
[RequireGodotRuntime]
public class NetcodeTest
{
    private List<Court> _courts = null!;
    private ArenaServer _server = null!;
    private SimLink _link = null!;

    [BeforeTest]
    public void Start()
    {
        _courts = Court.LoadAll();
        _server = new ArenaServer(_courts, 5) { BotsEnabled = false };
        _link = new SimLink(_server);
    }

    private void Tick(IEnumerable<ArenaClient> clients, int mx = 1, int my = 0)
    {
        foreach (ArenaClient c in clients)
            c.Step(mx, my, 1, 0, false);
        _link.Pump();
        _server.Tick();
        _link.Pump();
        _link.Advance();
    }

    private void ToRound(params ArenaClient[] clients)
    {
        for (int i = 0; i < ArenaMatch.WarmupTicks + 2; i++)
            Tick(clients, 0, 0);
    }

    [TestCase]
    public void A_player_takes_the_first_bot_slot()
    {
        var client = new ArenaClient(_courts);
        AssertThat(_link.Join(client, 10)).IsEqual(0);
        _link.Pump();
        AssertThat(client.Slot).IsEqual(0);
        AssertThat(_server.Arena.IsBot(0)).IsFalse();
        AssertThat(_server.Arena.IsBot(1)).IsTrue();
    }

    [TestCase]
    public void A_fifth_player_is_told_the_pit_is_full()
    {
        foreach (int peer in new[] { 10, 11, 12, 13 })
            _link.Join(new ArenaClient(_courts), peer);
        var late = new ArenaClient(_courts);
        AssertThat(_link.Join(late, 14)).IsEqual(-1);
        _link.Pump();
        AssertThat(late.Full).IsTrue();
    }

    [TestCase]
    public void The_client_follows_the_server_with_no_delay()
    {
        var client = new ArenaClient(_courts);
        _link.Join(client, 10);
        ToRound(client);
        for (int i = 0; i < 20; i++)
            Tick(new[] { client }, 1, 0);
        Fighter truth = _server.Arena.Fighters[0];
        AssertThat(client.Predicted!.Position()).IsEqual(truth.Position());
        AssertThat(client.Corrections).IsEqual(0);
    }

    [TestCase]
    public void A_lagging_client_ends_where_the_server_says()
    {
        _link.DelayTicks = 3;
        var client = new ArenaClient(_courts);
        _link.Join(client, 10);
        for (int i = 0; i < 10; i++)
            Tick(new[] { client }, 0, 0);
        ToRound(client);
        for (int i = 0; i < 30; i++)
            Tick(new[] { client }, 1, 1);
        for (int i = 0; i < 12; i++)
            Tick(new[] { client }, 0, 0);
        AssertThat(client.Predicted!.Position()).IsEqual(_server.Arena.Fighters[0].Position());
        AssertThat(client.Pending.Count).OverrideFailureMessage("only the inputs still on their way").IsLessEqual(2 * _link.DelayTicks + 1);
    }

    [TestCase]
    public void The_server_keeps_its_own_counsel_on_hits()
    {
        var client = new ArenaClient(_courts);
        _link.Join(client, 10);
        ToRound(client);
        int refused = _server.Arena.RefusedClaims;
        var input = new SimInput { Seq = client.Seq + 1, Ax = 1, Fire = true, Claim = 3 };
        client.Send!(new Dictionary<string, object?> { ["t"] = "input", ["inputs"] = new List<object?> { input.ToWire() } });
        _link.Pump();
        _server.Tick();
        AssertThat(_server.Arena.RefusedClaims).IsEqual(refused + 1);
    }

    [TestCase]
    public void A_leaver_loses_the_slot()
    {
        var client = new ArenaClient(_courts);
        _link.Join(client, 10);
        ToRound(client);
        _link.Leave(10);
        AssertThat(_server.SlotOf(10)).IsEqual(-1);
        AssertThat(_server.PeerCount()).IsEqual(0);
    }

    [TestCase]
    public void Another_players_glimmer_moves_evenly_on_a_lagging_screen()
    {
        _link.DelayTicks = 3;
        var mover = new ArenaClient(_courts);
        var watcher = new ArenaClient(_courts);
        _link.Join(mover, 10);
        _link.Join(watcher, 11);
        ToRound(mover, watcher);
        Vector2 last = watcher.ShownFighters()[0].Position();
        var steps = new List<float>();
        for (int i = 0; i < 30; i++)
        {
            mover.Step(1, 0, 1, 0, false);
            watcher.Step(0, 0, 1, 0, false);
            _link.Pump();
            _server.Tick();
            _link.Pump();
            _link.Advance();
            Vector2 now = watcher.ShownFighters()[0].Position();
            steps.Add(now.DistanceTo(last));
            last = now;
        }
        AssertThat(steps.Skip(12).Max()).OverrideFailureMessage("never more than a tick's step at once").IsLessEqual(Sim.Speed + 1.0f);
        AssertThat(steps.Skip(12).Min()).OverrideFailureMessage("never standing still between snapshots").IsGreater(0.0f);
    }
}

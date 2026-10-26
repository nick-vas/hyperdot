namespace Glimmerpit.Tests;

using System.Collections.Generic;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the prototype's fix-bug: hits are decided by the server's own trace. Whatever slot a client claims
/// to have hit, a pillar still stops the shot and a glimmer the shot never reached keeps its health.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenClaimsTest
{
    private ArenaServer _server = null!;
    private SimLink _link = null!;
    private ArenaClient _client = null!;

    [BeforeTest]
    public void Start()
    {
        List<Court> courts = Court.LoadAll();
        _server = new ArenaServer(courts, 5) { BotsEnabled = false };
        _link = new SimLink(_server);
        _client = new ArenaClient(courts);
        _link.Join(_client, 10);
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

    private void Place(int slot, int x, int y)
    {
        _server.Arena.Fighters[slot].X = x;
        _server.Arena.Fighters[slot].Y = y;
    }

    // An input as a client sends it, straight to the server, with whatever claim it likes.
    private void Send(int ax, int ay, bool fire, int claim)
    {
        _client.Seq++;
        var input = new Dictionary<string, object?>
        {
            ["seq"] = _client.Seq, ["mx"] = 0, ["my"] = 0, ["ax"] = ax, ["ay"] = ay, ["fire"] = fire, ["claim"] = claim,
        };
        _server.Receive(10, new Dictionary<string, object?> { ["t"] = "input", ["inputs"] = new List<object?> { input } });
        Tick();
    }

    // A shot, then the inputs that let the cooldown run out.
    private void Shoot(int ax, int ay, int claim)
    {
        Send(ax, ay, true, claim);
        for (int i = 0; i < Sim.FireCooldown + 1; i++)
            Send(0, 0, false, -1);
    }

    [TestCase]
    public void Hidden_a_claim_through_a_pillar_scores_nothing()
    {
        // The Cinder Pit's top pillar (x 570 to 630, y 0 to 170) stands between them.
        Place(0, 400, 100);
        Place(1, 800, 100);
        Shoot(1, 0, 1);
        AssertThat(_server.Arena.Fighters[1].Hp).IsEqual(ArenaMatch.Hp);
    }

    [TestCase]
    public void Hidden_a_claim_on_someone_out_of_line_scores_nothing()
    {
        Place(0, 100, 220);
        Place(2, 400, 220);
        Place(3, 300, 560);
        Shoot(1, 0, 3);
        AssertThat(_server.Arena.Fighters[3].Hp).OverrideFailureMessage("never in the line of fire").IsEqual(ArenaMatch.Hp);
        AssertThat(_server.Arena.Fighters[2].Hp).OverrideFailureMessage("the one the shot reached").IsEqual(ArenaMatch.Hp - 1);
    }

    [TestCase]
    public void Hidden_claims_cannot_knock_out_from_across_the_pit()
    {
        Place(0, 80, 80);
        Place(1, 1120, 560);
        for (int i = 0; i < ArenaMatch.Hp + 1; i++)
            Shoot(0, -1, 1);
        AssertThat(_server.Arena.Fighters[1].Alive).IsTrue();
        AssertThat(_server.Arena.Scores).ContainsExactly(0, 0, 0, 0);
    }

    [TestCase]
    public void Hidden_an_honest_shot_in_the_open_hits()
    {
        Place(0, 100, 220);
        Place(1, 400, 220);
        Shoot(1, 0, 1);
        AssertThat(_server.Arena.Fighters[1].Hp).IsEqual(ArenaMatch.Hp - 1);
        Shoot(1, 0, -1);
        AssertThat(_server.Arena.Fighters[1].Hp).OverrideFailureMessage("no claim needed").IsEqual(ArenaMatch.Hp - 2);
    }
}

namespace Glimmerpit.Tests;

using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden acceptance for the prototype-to-alpha milestone: the netcode over real ENet through a NetSession, server and
/// client in one Godot, each in its own branch with its own SceneMultiplayer (the whole game's own ENet test).
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenEnetTest
{
    private const int Port = 24652;

    private readonly List<Node> _branches = new();
    private NetSession _hostSession = null!;
    private NetSession _joinSession = null!;
    private ArenaServer _server = null!;
    private ArenaClient _client = null!;

    private static SceneTree Tree => (SceneTree)Engine.GetMainLoop();

    [BeforeTest]
    public void Connect()
    {
        List<Court> courts = Court.LoadAll();
        _server = new ArenaServer(courts, 3);
        _client = new ArenaClient(courts);
        _hostSession = Branch("Host");
        _joinSession = Branch("Joiner");
        AssertThat(_hostSession.Host(Port)).IsEqual(Error.Ok);
        _hostSession.Serve(_server);
        AssertThat(_joinSession.Join("127.0.0.1", Port, _client)).IsEqual(Error.Ok);
    }

    [AfterTest]
    public void Disconnect()
    {
        _hostSession.Close();
        _joinSession.Close();
        foreach (Node branch in _branches)
            branch.QueueFree();
        _branches.Clear();
    }

    private NetSession Branch(string name)
    {
        var branch = new Node { Name = name };
        Tree.Root.AddChild(branch);
        _branches.Add(branch);
        Tree.SetMultiplayer(new SceneMultiplayer(), branch.GetPath());
        var session = new NetSession();
        branch.AddChild(session);
        return session;
    }

    private static async Task<bool> WaitFor(Func<bool> condition, int frames = 300)
    {
        for (int i = 0; i < frames; i++)
        {
            if (condition())
                return true;
            await Tree.ToSignal(Tree, SceneTree.SignalName.ProcessFrame);
        }
        return condition();
    }

    [TestCase]
    public async Task Hidden_a_client_joins_plays_and_leaves_over_enet()
    {
        AssertThat(await WaitFor(() => _client.IsPlaying())).OverrideFailureMessage("welcomed").IsTrue();
        AssertThat(_client.Slot).IsEqual(0);
        AssertThat(_server.PeerCount()).IsEqual(1);
        for (int i = 0; i < 60; i++)
        {
            _client.Step(1, 0, 1, 0, false);
            _server.Tick();
            await Tree.ToSignal(Tree, SceneTree.SignalName.ProcessFrame);
        }
        AssertThat(await WaitFor(() => _client.Snapshots > 20)).OverrideFailureMessage("snapshots arrive").IsTrue();
        _joinSession.Close();
        AssertThat(await WaitFor(() => _server.PeerCount() == 0)).OverrideFailureMessage("the server saw it leave").IsTrue();
    }
}

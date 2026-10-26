namespace Glimmerpit;

using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Godot;

/// <summary>
/// The game without a screen: a dedicated server (--server, or soak's --soak-role=server) that plays match after match
/// with bots in the empty slots, or a soak client (--soak-role=client) whose bot plays through ENet and leaves and
/// rejoins every few seconds, as players do. Both take part in <c>hyperdot.ps1 soak</c> through its printed lines: [soak]
/// ready, [soak] metric &lt;name&gt; &lt;value&gt; every few seconds, and [soak] fail &lt;reason&gt; when the game finds something wrong.
/// </summary>
/// <remarks>
/// The server stops the way a host stops it: on SIGTERM it refuses new players, closes the connections and quits with 0.
/// Godot has no handler of its own, so without this it would die at once with 143.
/// </remarks>
public partial class Headless : Node
{
    /// <summary>Seconds between metric lines.</summary>
    public const double MetricSeconds = 5.0;
    /// <summary>A soak client stays this long plus its id in seconds, then leaves.</summary>
    public const int StaySeconds = 4;
    /// <summary>Ticks a soak client stays away before it joins again.</summary>
    public const int RejoinTicks = 30;

    private Bot? _bot;
    private int _ticks;
    private int _connectedTicks;
    private int _away = -1;
    private bool _readySaid;
    private int _joins;
    private PosixSignalRegistration? _term;
    private volatile bool _stopRequested;
    private bool _stopping;

    public LaunchOptions? Options { get; private set; }
    public List<Court> Courts { get; private set; } = new();
    public ArenaServer? Server { get; private set; }
    public ArenaClient? Client { get; private set; }
    public NetSession Session { get; private set; } = null!;

    public void Setup(LaunchOptions options)
    {
        Options = options;
    }

    public override void _Ready()
    {
        Options ??= LaunchOptions.FromCommandLine();
        // Headless Godot would run as fast as it can; a server needs no more frames than ticks.
        Engine.MaxFps = 60;
        Courts = Court.LoadAll();
        Session = new NetSession { Name = "Net" };
        AddChild(Session);
        if (Options.Server)
        {
            Serve();
        }
        else
        {
            _bot = new Bot(0, Math.Max(Options.SoakId, 1) * 104729L);
            Session.Connected += OnConnected;
            Session.Disconnected += OnDisconnected;
            JoinServer();
        }
    }

    private void Serve()
    {
        Server = new ArenaServer(Courts, Options!.RunSeed > 0 ? Options.RunSeed : 1) { LoopMatches = true };
        Error err = Session.Host(Options.Port);
        if (err != Error.Ok)
        {
            GD.Print($"[soak] fail the server could not listen on {Options.Port}: {err}");
            return;
        }
        Session.Serve(Server);
        try
        {
            // The handler runs on a thread-pool thread: it only sets a flag; the tick acts on it.
            _term = PosixSignalRegistration.Create(PosixSignal.SIGTERM, context =>
            {
                context.Cancel = true;
                _stopRequested = true;
            });
        }
        catch (PlatformNotSupportedException)
        {
            // No SIGTERM to catch here; the host stops the process its own way.
        }
        GD.Print($"[Server] listening on {Options.Port}");
        GD.Print("[soak] ready");
    }

    private void JoinServer()
    {
        Client = new ArenaClient(Courts);
        Error err = Session.Join("127.0.0.1", Options!.Port, Client);
        if (err != Error.Ok)
            GD.Print($"[soak] fail could not connect: {err}");
    }

    private void OnConnected()
    {
        _joins++;
        _connectedTicks = 0;
        if (!_readySaid)
        {
            _readySaid = true;
            GD.Print("[soak] ready");
        }
    }

    private void OnDisconnected(string reason)
    {
        GD.Print($"[soak] fail the connection to the server was {reason}");
    }

    public override void _PhysicsProcess(double delta)
    {
        if (_stopRequested)
        {
            Stop();
            return;
        }
        _ticks++;
        if (Server != null)
        {
            Server.Tick();
        }
        else if (_away > 0)
        {
            _away--;
            if (_away == 0)
                JoinServer();
        }
        else if (Client != null && Client.IsPlaying())
        {
            _bot!.Slot = Client.Slot;
            SimInput input = _bot.Decide(Client.View, Client.Predicted);
            Client.Step(input.Mx, input.My, input.Ax, input.Ay, input.Fire, input.Dash);
            Client.Events.Clear();
            _connectedTicks++;
            if (_connectedTicks >= (StaySeconds + Options!.SoakId) * Sim.TickRate)
            {
                Session.Close();
                Client = null;
                _away = RejoinTicks;
            }
        }
        if (_ticks % (int)(MetricSeconds * Sim.TickRate) == 0)
            Metrics();
        // Every message is a few small objects, and left alone the runtime lets them pile up to its first-generation
        // budget (tens of MB on a machine with a large cache) before it collects any: resident memory that climbs for
        // minutes, which is what a leak looks like to soak. A first-generation collection a second keeps a process that
        // runs for days where it settles, and costs well under a millisecond with so little alive.
        if (_ticks % Sim.TickRate == 0)
            GC.Collect(0, GCCollectionMode.Forced, true);
    }

    private void Metrics()
    {
        if (Server != null)
        {
            GD.Print($"[soak] metric players {Server.PeerCount()}");
            GD.Print($"[soak] metric peer_records {Server.RecordCount()}");
            GD.Print($"[soak] metric matches {Server.Arena.Matches}");
            GD.Print($"[soak] metric refused_claims {Server.Arena.RefusedClaims}");
            // Whatever the server keeps per peer must go when the peer goes: more records than peers is a leak.
            if (Server.RecordCount() > Server.PeerCount())
                GD.Print($"[soak] fail the server keeps {Server.RecordCount()} peer records for {Server.PeerCount()} players");
        }
        else
        {
            GD.Print($"[soak] metric joins {_joins}");
            if (Client != null)
            {
                GD.Print($"[soak] metric snapshots {Client.Snapshots}");
                GD.Print($"[soak] metric corrections {Client.Corrections}");
            }
        }
    }

    // A server asked to stop: no new players, the players told by the connection closing, and a clean exit.
    private void Stop()
    {
        if (_stopping)
            return;
        _stopping = true;
        GD.Print("[Server] stopping");
        Session.Close();
        GetTree().Quit(0);
    }

    public override void _ExitTree()
    {
        _term?.Dispose();
    }
}

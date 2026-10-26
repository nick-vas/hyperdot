namespace Glimmerpit;

using System;
using System.Collections.Generic;
using Godot;

/// <summary>
/// Clients and a server in one process, with a delay each way in ticks and an optional jitter from its own seeded
/// generator. Local play runs over it with no delay; --lag=MS and the netcode tests give it one, since ENet has no lag
/// of its own to simulate. Every message is turned into bytes and back, as the wire would, so nothing is shared.
/// </summary>
public sealed class SimLink
{
    private readonly record struct InFlight(int At, int Peer, byte[] Bytes);

    private int _tick;
    private readonly Dictionary<int, ArenaClient> _clients = new();
    private readonly List<InFlight> _toServer = new();
    private readonly List<InFlight> _toClient = new();
    /// <summary>"s&lt;peer&gt;" / "c&lt;peer&gt;" to the arrival tick of the newest message, kept in order.</summary>
    private readonly Dictionary<string, int> _lastAt = new();

    public SimLink(ArenaServer server, int delay = 0, int jitter = 0, long seed = 1)
    {
        Server = server;
        DelayTicks = delay;
        JitterTicks = jitter;
        Rng.Seed = unchecked((ulong)seed);
        server.Send = Deliver;
    }

    public ArenaServer Server { get; }
    /// <summary>Ticks each way.</summary>
    public int DelayTicks { get; set; }
    /// <summary>The most a message may arrive later than the delay (never earlier, never out of order).</summary>
    public int JitterTicks { get; set; }
    public RandomNumberGenerator Rng { get; } = new();

    /// <summary>Delay in ticks for a round trip of <paramref name="ms"/> milliseconds.</summary>
    public static int TicksForMs(int ms) => (int)Math.Round(ms / 2.0 * Sim.TickRate / 1000.0, MidpointRounding.AwayFromZero);

    /// <summary>Connects a client as <paramref name="peer"/>; the server takes it in at once, its welcome arrives after the delay.</summary>
    public int Join(ArenaClient client, int peer)
    {
        _clients[peer] = client;
        client.Send = message => Queue(_toServer, peer, message, $"s{peer}");
        return Server.PeerJoined(peer);
    }

    /// <summary>Disconnects a client: the server forgets it now, and whatever was on its way is lost.</summary>
    public void Leave(int peer)
    {
        if (!_clients.TryGetValue(peer, out ArenaClient? client))
            return;
        client.Send = null;
        _clients.Remove(peer);
        _toServer.RemoveAll(m => m.Peer == peer);
        _toClient.RemoveAll(m => m.Peer == peer);
        _lastAt.Remove($"s{peer}");
        _lastAt.Remove($"c{peer}");
        Server.PeerLeft(peer);
    }

    public bool HasPeer(int peer) => _clients.ContainsKey(peer);

    /// <summary>A message from the server to a client of this link.</summary>
    public void Deliver(int peer, Dictionary<string, object?> message)
    {
        if (_clients.ContainsKey(peer))
            Queue(_toClient, peer, message, $"c{peer}");
    }

    private void Queue(List<InFlight> queue, int peer, Dictionary<string, object?> message, string lane)
    {
        int at = _tick + DelayTicks + (JitterTicks > 0 ? Rng.RandiRange(0, JitterTicks) : 0);
        at = Math.Max(at, _lastAt.TryGetValue(lane, out int last) ? last : 0);
        _lastAt[lane] = at;
        queue.Add(new InFlight(at, peer, Wire.Encode(message)));
    }

    /// <summary>Delivers what is due by now: inputs to the server, snapshots to the clients.</summary>
    public void Pump()
    {
        foreach (InFlight m in Due(_toServer))
            Server.Receive(m.Peer, Wire.Decode(m.Bytes));
        foreach (InFlight m in Due(_toClient))
        {
            if (_clients.TryGetValue(m.Peer, out ArenaClient? client))
                client.Receive(Wire.Decode(m.Bytes));
        }
    }

    // Takes the messages due by now out of a queue, in the order they were sent.
    private List<InFlight> Due(List<InFlight> queue)
    {
        List<InFlight> due = queue.FindAll(m => m.At <= _tick);
        if (due.Count > 0)
            queue.RemoveAll(m => m.At <= _tick);
        return due;
    }

    /// <summary>The link's clock: one tick later.</summary>
    public void Advance()
    {
        _tick++;
    }
}

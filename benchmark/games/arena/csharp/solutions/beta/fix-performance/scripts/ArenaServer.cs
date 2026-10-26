namespace Glimmerpit;

using System;
using System.Collections;
using System.Collections.Generic;
using Godot;

/// <summary>
/// The authoritative server, with no transport of its own: peers join and leave, their inputs come in with Receive(),
/// and every SnapshotEvery ticks each peer gets a snapshot through Send (peer id, message). The game runs it in-process
/// over a SimLink for local play; NetSession carries it over ENet for hosting and as the dedicated server soak runs.
/// Players hold slots; bots play the rest, so a match is always four glimmers.
/// </summary>
/// <remarks>What it keeps per peer is in sorted dictionaries, so it visits peers in id order on every run and machine.</remarks>
public sealed class ArenaServer
{
    public const int SnapshotEvery = 2;
    /// <summary>A peer's queue beyond this many inputs is worked down two a tick, so a burst after a stall does not add lag for good.</summary>
    public const int Backlog = 4;
    /// <summary>Inputs kept per peer in its log.</summary>
    public const int LogSize = 64;

    /// <summary>Peer id to its slot.</summary>
    private readonly SortedDictionary<int, int> _peers = new();
    /// <summary>Peer id to the inputs received and not applied yet, oldest first.</summary>
    private readonly SortedDictionary<int, List<SimInput>> _queues = new();
    /// <summary>Peer id to the sequence number of its last applied input (acknowledged in its snapshots).</summary>
    private readonly SortedDictionary<int, int> _lastSeq = new();
    /// <summary>Peer id to its last LogSize applied inputs, so a desync or cheat report can replay what the server did.</summary>
    private readonly SortedDictionary<int, List<SimInput>> _inputLog = new();

    public ArenaServer(List<Court> courts, long matchSeed = 1)
    {
        Arena = new ArenaMatch(courts);
        for (int slot = 0; slot < ArenaMatch.Slots; slot++)
            Bots.Add(new Bot(slot, matchSeed * 7919 + slot));
    }

    public ArenaMatch Arena { get; }
    public List<Bot> Bots { get; } = new();
    /// <summary>(peer, message): how a message reaches a peer.</summary>
    public Action<int, Dictionary<string, object?>>? Send { get; set; }
    /// <summary>Off in tests that want the bots' glimmers to stand still.</summary>
    public bool BotsEnabled { get; set; } = true;
    /// <summary>A dedicated server starts the next match when one is over.</summary>
    public bool LoopMatches { get; set; }

    public int PeerCount() => _peers.Count;

    public int SlotOf(int peer) => _peers.TryGetValue(peer, out int slot) ? slot : -1;

    /// <summary>The most records the server keeps for any one kind of per-peer state; never more than the peers connected.</summary>
    public int RecordCount() => Math.Max(Math.Max(_peers.Count, _queues.Count), Math.Max(_lastSeq.Count, _inputLog.Count));

    /// <summary>A peer connected: it takes the first slot a bot holds, or is told the pit is full. Returns its slot, or -1.</summary>
    public int PeerJoined(int peer)
    {
        if (_peers.ContainsKey(peer))
            return SlotOf(peer);
        int slot = -1;
        for (int s = 0; s < ArenaMatch.Slots; s++)
        {
            if (Arena.IsBot(s))
            {
                slot = s;
                break;
            }
        }
        if (slot < 0)
        {
            SendTo(peer, new Dictionary<string, object?> { ["t"] = "full" });
            return -1;
        }
        _peers[peer] = slot;
        _queues[peer] = new List<SimInput>();
        _lastSeq[peer] = 0;
        _inputLog[peer] = new List<SimInput>();
        Arena.SetOwner(slot, peer);
        GD.Print($"[Net] peer {peer} joined slot {slot}");
        SendTo(peer, new Dictionary<string, object?> { ["t"] = "welcome", ["slot"] = slot, ["snap"] = Arena.Snapshot() });
        return slot;
    }

    /// <summary>A peer disconnected (or timed out): its slot goes back to a bot, and nothing of it is kept.</summary>
    public void PeerLeft(int peer)
    {
        if (!_peers.ContainsKey(peer))
            return;
        int slot = SlotOf(peer);
        GD.Print($"[Net] peer {peer} left slot {slot}");
        Arena.SetOwner(slot, ArenaMatch.Bot);
        _peers.Remove(peer);
        _queues.Remove(peer);
        _lastSeq.Remove(peer);
        _inputLog.Remove(peer);
    }

    /// <summary>A message from a peer. Only inputs are accepted, each sequence number once, in order.</summary>
    public void Receive(int peer, object? message)
    {
        if (!_peers.ContainsKey(peer) || Wire.Map(message) is not Dictionary<string, object?> dict || Wire.Text(Wire.Get(dict, "t")) != "input")
            return;
        if (Wire.List(Wire.Get(dict, "inputs")) is not IList inputs)
            return;
        List<SimInput> queue = _queues[peer];
        foreach (object? raw in inputs)
        {
            if (Wire.Map(raw) is not Dictionary<string, object?> fields)
                continue;
            SimInput input = Sim.Sanitize(fields);
            int newest = queue.Count > 0 ? queue[^1].Seq : _lastSeq[peer];
            if (input.Seq > newest)
                queue.Add(input);
        }
    }

    /// <summary>
    /// One server tick: every slot's input applied, the match moved on, snapshots out. A player whose input has not
    /// arrived is left as it is, not given a made-up one.
    /// </summary>
    public void Tick()
    {
        for (int slot = 0; slot < ArenaMatch.Slots; slot++)
        {
            SimInput? input = NextInput(slot);
            if (input != null)
                Arena.Apply(slot, input);
            int owner = Arena.Owners[slot];
            if (owner != ArenaMatch.Bot && _queues.TryGetValue(owner, out List<SimInput>? queue) && queue.Count > Backlog)
            {
                SimInput? extra = NextInput(slot);
                if (extra != null)
                    Arena.Apply(slot, extra);
            }
        }
        Arena.Advance();
        if (LoopMatches && Arena.State == MatchState.Over && Arena.StateTicks >= ArenaMatch.OverTicks)
            Arena.Restart();
        TrimLogs();
        if (Arena.Tick % SnapshotEvery == 0)
            Broadcast(Arena.TakeEvents());
    }

    private SimInput? NextInput(int slot)
    {
        int owner = Arena.Owners[slot];
        if (owner == ArenaMatch.Bot)
            return BotsEnabled ? Bots[slot].Decide(Arena) : Sim.Idle();
        if (!_queues.TryGetValue(owner, out List<SimInput>? queue) || queue.Count == 0)
        {
            // Starved: nothing is applied this tick (not even its timers run), so the client's prediction still holds.
            return null;
        }
        SimInput input = queue[0];
        queue.RemoveAt(0);
        _lastSeq[owner] = input.Seq;
        _inputLog[owner].Add(input);
        return input;
    }

    private void TrimLogs()
    {
        foreach (List<SimInput> entries in _inputLog.Values)
        {
            if (entries.Count > LogSize)
                entries.RemoveAt(0);
        }
    }

    private void Broadcast(List<MatchEvent> events)
    {
        Dictionary<string, object?> snap = Arena.Snapshot();
        var wire = new List<object?>();
        foreach (MatchEvent e in events)
            wire.Add(e.ToWire());
        snap["events"] = wire;
        foreach (KeyValuePair<int, int> peer in _peers)
        {
            SendTo(peer.Key, new Dictionary<string, object?>
            {
                ["t"] = "snap", ["ack"] = _lastSeq[peer.Key], ["slot"] = peer.Value, ["snap"] = snap,
            });
        }
    }

    private void SendTo(int peer, Dictionary<string, object?> message) => Send?.Invoke(peer, message);
}

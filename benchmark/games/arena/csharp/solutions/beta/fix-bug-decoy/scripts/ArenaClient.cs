namespace Glimmerpit;

using System;
using System.Collections;
using System.Collections.Generic;
using Godot;

/// <summary>
/// A player's side of the netcode, with no transport of its own. Its own glimmer is predicted: each input is applied at
/// once with the server's own Sim.Step and kept until a snapshot acknowledges it. A snapshot is the truth as of the last
/// input the server applied, so the client takes it and replays the inputs the server has not seen yet; with the same
/// code on both sides that lands exactly where the prediction was, and nothing visibly corrects. Other glimmers are drawn
/// InterpTicks behind the newest snapshot, between the two snapshots around that moment, so they move evenly.
/// </summary>
public sealed class ArenaClient
{
    /// <summary>Ticks other glimmers are shown in the past: two snapshot intervals and a little more.</summary>
    public const int InterpTicks = 5;
    /// <summary>Each input message repeats the newest inputs not yet acknowledged, so one lost packet loses nothing.</summary>
    public const int Redundant = 3;
    /// <summary>Snapshots kept for interpolation.</summary>
    public const int History = 8;

    private readonly List<(int Tick, Fighter[] Fighters)> _history = new();
    private double _renderTick;

    public ArenaClient(List<Court> courts)
    {
        View = new ArenaMatch(courts);
    }

    /// <summary>How a message reaches the server.</summary>
    public Action<Dictionary<string, object?>>? Send { get; set; }
    public int Slot { get; private set; } = -1;
    public bool Full { get; private set; }
    /// <summary>The match as the last snapshot told it, with this client's glimmer replaced by its prediction.</summary>
    public ArenaMatch View { get; }
    public Fighter? Predicted { get; private set; }
    public int Seq { get; set; }
    /// <summary>Inputs sent and not acknowledged yet, oldest first.</summary>
    public List<SimInput> Pending { get; } = new();
    /// <summary>How many snapshots moved the predicted glimmer.</summary>
    public int Corrections { get; set; }
    /// <summary>By how much the last snapshot moved it, in pixels.</summary>
    public double LastCorrection { get; private set; }
    public int Snapshots { get; private set; }
    /// <summary>Events from the server not taken by the game yet.</summary>
    public List<MatchEvent> Events { get; } = new();

    public bool IsPlaying() => Slot >= 0 && Predicted != null;

    /// <summary>A message from the server.</summary>
    public void Receive(object? message)
    {
        if (Wire.Map(message) is not Dictionary<string, object?> dict)
            return;
        switch (Wire.Text(Wire.Get(dict, "t")))
        {
            case "welcome":
                Slot = Wire.Int(Wire.Get(dict, "slot"), -1);
                Pending.Clear();
                TakeSnapshot(Wire.Map(Wire.Get(dict, "snap"))!, Seq);
                break;
            case "snap":
                if (Slot >= 0)
                    TakeSnapshot(Wire.Map(Wire.Get(dict, "snap"))!, Wire.Int(Wire.Get(dict, "ack")));
                break;
            case "full":
                Full = true;
                break;
        }
    }

    private void TakeSnapshot(Dictionary<string, object?> snap, int ack)
    {
        Snapshots++;
        int roundBefore = View.RoundNumber;
        View.LoadSnapshot(snap);
        if (Wire.List(Wire.Get(snap, "events")) is IList events)
        {
            foreach (object? e in events)
            {
                if (Wire.Map(e) is Dictionary<string, object?> fields)
                    Events.Add(MatchEvent.FromWire(fields));
            }
        }
        _history.Add((View.Tick, View.Fighters.ToArray()));
        if (_history.Count > History)
            _history.RemoveAt(0);
        // The clock others are drawn at follows the snapshots: set on the first, and again whenever it drifts (a stall,
        // a burst), so they are always InterpTicks behind the newest.
        if (Snapshots == 1 || Math.Abs(_renderTick - (View.Tick - InterpTicks)) > 3.0)
            _renderTick = View.Tick - InterpTicks;
        Fighter? before = Predicted;
        while (Pending.Count > 0 && Pending[0].Seq <= ack)
            Pending.RemoveAt(0);
        Predicted = View.Fighters[Slot].Copy();
        if (View.State == MatchState.Round && before != null)
        {
            // Ease towards the server's word instead of jumping to it, so a correction never shows as a snap.
            Predicted.X = (int)Math.Round(before.X + (Predicted.X - before.X) * 0.25, MidpointRounding.AwayFromZero);
            Predicted.Y = (int)Math.Round(before.Y + (Predicted.Y - before.Y) * 0.25, MidpointRounding.AwayFromZero);
        }
        if (before != null && View.RoundNumber == roundBefore && View.State == MatchState.Round)
        {
            LastCorrection = before.Position().DistanceTo(Predicted.Position());
            if (LastCorrection > 0.01)
                Corrections++;
        }
        View.Fighters[Slot] = Predicted;
    }

    /// <summary>
    /// One client tick: the player's input, applied at once and sent. Returns true when it fires (the game shows the shot
    /// at once; the server decides whether it hits).
    /// </summary>
    public bool Step(int mx, int my, int ax, int ay, bool fire, bool dash = false)
    {
        _renderTick += 1.0;
        if (!IsPlaying())
            return false;
        Seq++;
        var input = new SimInput { Seq = Seq, Mx = mx, My = my, Ax = ax, Ay = ay, Fire = fire, Dash = dash, Claim = -1 };
        bool fired = false;
        if (View.State == MatchState.Round)
        {
            fired = Sim.Step(Predicted!, input, View.Court);
            if (fired)
            {
                // What this screen shows the shot hitting; the server keeps its own counsel.
                input.Claim = Sim.Trace(View.Court, ShownFighters(), Slot).Target;
            }
        }
        Pending.Add(input);
        if (Send != null)
        {
            var inputs = new List<object?>();
            for (int i = Math.Max(Pending.Count - Redundant, 0); i < Pending.Count; i++)
                inputs.Add(Pending[i].ToWire());
            Send(new Dictionary<string, object?> { ["t"] = "input", ["inputs"] = inputs });
        }
        return fired;
    }

    /// <summary>The fighters as this screen shows them: its own predicted, the others interpolated in the past.</summary>
    public List<Fighter> ShownFighters()
    {
        var shown = new List<Fighter>();
        for (int s = 0; s < ArenaMatch.Slots; s++)
            shown.Add(s == Slot && Predicted != null ? Predicted : Interpolated(s));
        return shown;
    }

    private Fighter Interpolated(int s)
    {
        if (_history.Count == 0)
            return View.Fighters[s];
        Fighter newest = _history[^1].Fighters[s];
        for (int i = _history.Count - 1; i > 0; i--)
        {
            var a = _history[i - 1];
            var b = _history[i];
            if (a.Tick <= _renderTick && _renderTick <= b.Tick)
            {
                Fighter fa = a.Fighters[s];
                Fighter fb = b.Fighters[s];
                Fighter shown = fb.Copy();
                if (fa.Alive && fb.Alive && b.Tick > a.Tick)
                {
                    double t = (_renderTick - a.Tick) / (b.Tick - a.Tick);
                    // Rounded half away from zero, as the engine's round() does.
                    shown.X = (int)Math.Round(fa.X + (fb.X - fa.X) * t, MidpointRounding.AwayFromZero);
                    shown.Y = (int)Math.Round(fa.Y + (fb.Y - fa.Y) * t, MidpointRounding.AwayFromZero);
                }
                return shown;
            }
        }
        return newest;
    }
}

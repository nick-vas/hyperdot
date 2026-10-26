namespace Cinderloop;

using System.Collections.Generic;
using Godot;

/// <summary>
/// Counts one car's laps: the gates must be crossed in order, each in the direction of travel, and a lap is done when
/// the start line is crossed after the last gate. A gate crossed out of turn counts for nothing, so cutting across the
/// grass past a checkpoint never shortens a lap. Lap times are in ticks, from the start (lap 1) or the last line.
/// </summary>
public sealed class LapTracker
{
    public enum Crossing
    {
        None,
        Gate,
        Lap,
    }

    /// <summary>The gate to cross next; 0 is the start line.</summary>
    public int NextGate { get; set; }
    /// <summary>Whether the car has crossed the start line once: the grid is behind it.</summary>
    public bool Armed { get; set; }
    public int Laps { get; set; }
    public int LapStartTick { get; set; }
    public List<int> LapTimes { get; } = new();
    /// <summary>The fastest lap so far in ticks, -1 before the first.</summary>
    public int BestLap { get; set; } = -1;

    /// <summary>The checkpoints crossed in the lap in progress, whatever their order.</summary>
    private readonly HashSet<int> _passed = new();

    public Crossing Update(Track track, Vector2 from, Vector2 to, int tick)
    {
        var crossed = new List<int>();
        for (int gate = 0; gate < track.GateCount(); gate++)
        {
            if (track.CrossesGate(gate, from, to))
                crossed.Add(gate);
        }
        if (crossed.Count == 0)
            return Crossing.None;
        if (!crossed.Contains(0))
        {
            foreach (int gate in crossed)
                _passed.Add(gate);
            NextGate = _passed.Count == track.GateCount() - 1 ? 0 : NextGate + 1;
            return Crossing.Gate;
        }
        if (Armed && _passed.Count < track.GateCount() - 1)
            return Crossing.None;
        _passed.Clear();
        NextGate = 1 % track.GateCount();
        if (!Armed)
        {
            Armed = true;
            return Crossing.Gate;
        }
        int time = tick - LapStartTick;
        LapTimes.Add(time);
        LapStartTick = tick;
        Laps += 1;
        if (BestLap < 0 || time < BestLap)
            BestLap = time;
        return Crossing.Lap;
    }

    /// <summary>How many gates of the lap in progress are behind the car (the start line counts once armed).</summary>
    public int GatesPassed(Track track)
    {
        if (!Armed)
            return 0;
        return NextGate == 0 ? track.GateCount() : NextGate;
    }

    public int LastLap() => LapTimes.Count > 0 ? LapTimes[^1] : -1;
}

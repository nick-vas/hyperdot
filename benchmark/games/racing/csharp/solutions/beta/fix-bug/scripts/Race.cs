namespace Cinderloop;

using System;
using System.Collections.Generic;
using Godot;
using static Cinderloop.Maths;

/// <summary>
/// One race on a track: the cars, their drivers and lap trackers, the finishing order and the player's ghost. Car 0 is
/// the player's: driven by the input given to Step(), or by its own driver when it has one (the bot, or after the
/// flag). Every tick steps the cars in order with quantised inputs, so a race replays exactly from its grid and inputs.
/// </summary>
public sealed class Race
{
    /// <summary>drivers: car 0 first (null when the player drives it); the grid puts car 0 last and the others in the given order.</summary>
    public Race(Track track, IReadOnlyList<AiDriver?> drivers, int ticksPerSecond = 60)
    {
        Track = track;
        Drivers = new List<AiDriver?>(drivers);
        Rate = ticksPerSecond;
        int count = Drivers.Count;
        for (int i = 0; i < count; i++)
        {
            int slot = i == 0 ? count - 1 : i - 1;
            Car car = Car.At(track.GridSlot(slot));
            car.Index = track.Nearest(car.Position);
            Cars.Add(car);
            Trackers.Add(new LapTracker());
        }
        Ghost = new Ghost(Cars[0].State(), Rate);
    }

    /// <summary>A lap done: the car, its laps so far and the lap's ticks.</summary>
    public event Action<int, int, int>? LapCompleted;
    /// <summary>A car took the flag: the car and its place.</summary>
    public event Action<int, int>? CarFinished;

    public Track Track { get; }
    public List<Car> Cars { get; } = new();
    public List<LapTracker> Trackers { get; } = new();
    /// <summary>An AiDriver for each car, or null for the player's.</summary>
    public List<AiDriver?> Drivers { get; }
    public int Tick { get; private set; }
    public int Rate { get; }
    /// <summary>Car indices in the order they took the flag.</summary>
    public List<int> FinishOrder { get; set; } = new();
    /// <summary>The fastest lap of car 0 as inputs.</summary>
    public Ghost? BestGhost { get; private set; }
    /// <summary>The lap of car 0 being recorded now.</summary>
    public Ghost Ghost { get; private set; }

    public void Step() => Step(Vector2.Zero);

    public void Step(Vector2 playerInput)
    {
        Tick += 1;
        double dt = 1.0 / Rate;
        for (int i = 0; i < Cars.Count; i++)
        {
            Car car = Cars[i];
            AiDriver? driver = Drivers[i];
            Vector2 input = driver != null ? driver.Decide(car, Track) : playerInput;
            double throttle = Ghost.Quantize(input.X);
            double steer = Ghost.Quantize(input.Y);
            if (i == 0)
                Ghost.Record(throttle, steer);
            Vector2 from = car.Position;
            car.Step(throttle, steer, dt, Track.IsOnRoad(car.Position, car.Index));
            car.Index = Track.Nearest(car.Position, car.Index);
            if (Trackers[i].Update(Track, from, car.Position, Tick) == LapTracker.Crossing.Lap)
                LapDone(i);
        }
    }

    private void LapDone(int i)
    {
        LapTracker tracker = Trackers[i];
        if (i == 0)
        {
            if (BestGhost == null || tracker.LastLap() < BestGhost.Ticks())
                BestGhost = Ghost;
            Ghost = new Ghost(Cars[0].State(), Rate);
        }
        LapCompleted?.Invoke(i, tracker.Laps, tracker.LastLap());
        if (tracker.Laps == Track.Laps && !FinishOrder.Contains(i))
        {
            FinishOrder.Add(i);
            CarFinished?.Invoke(i, FinishOrder.Count);
        }
    }

    public bool IsFinished(int i) => FinishOrder.Contains(i);

    /// <summary>
    /// Car indices from first to last: those that took the flag in that order, then by laps done, gates passed in the lap
    /// and the distance left to the next gate; level cars by index.
    /// </summary>
    public List<int> Standings()
    {
        var order = new List<int>();
        for (int i = 0; i < Cars.Count; i++)
            order.Add(i);
        order.Sort((a, b) => a == b ? 0 : Ahead(a, b) ? -1 : 1);
        return order;
    }

    /// <summary>1 for the leader.</summary>
    public int PositionOf(int i) => Standings().IndexOf(i) + 1;

    private bool Ahead(int a, int b)
    {
        int fa = FinishOrder.IndexOf(a);
        int fb = FinishOrder.IndexOf(b);
        if (fa >= 0 || fb >= 0)
        {
            if (fa < 0 || fb < 0)
                return fa >= 0;
            return fa < fb;
        }
        LapTracker ta = Trackers[a];
        LapTracker tb = Trackers[b];
        if (ta.Laps != tb.Laps)
            return ta.Laps > tb.Laps;
        int ga = ta.GatesPassed(Track);
        int gb = tb.GatesPassed(Track);
        if (ga != gb)
            return ga > gb;
        double da = ToNextGate(a);
        double db = ToNextGate(b);
        if (!IsEqualApprox(da, db))
            return da < db;
        return a < b;
    }

    /// <summary>How far car i has to go along the track to its next gate.</summary>
    private double ToNextGate(int i)
    {
        Car car = Cars[i];
        double gateAt = Track.Lengths[Track.GatePoints[Trackers[i].NextGate]];
        return FPosMod(gateAt - Track.DistanceAlong(car.Position, car.Index), Track.Length());
    }

    /// <summary>A time in milliseconds as minutes, seconds and thousandths: 83456 is 1:23.456.</summary>
    public static string FormatMs(int ms) => $"{ms / 60000}:{ms / 1000 % 60:00}.{ms % 1000:000}";
}

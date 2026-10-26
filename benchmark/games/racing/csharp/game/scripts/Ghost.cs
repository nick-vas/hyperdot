namespace Cinderloop;

using System.Collections.Generic;
using System.Text.Json.Nodes;
using Godot;
using static Cinderloop.Maths;

/// <summary>
/// A lap as its inputs: the car's state where the lap began and the throttle and steering of every tick after it, in
/// hundredths. Played back through Car on the same track, it drives the lap again exactly, because Race quantises every
/// input before a car uses it: what the ghost keeps is what the car was given. A recording is small (two numbers a
/// tick) and is saved with the best lap.
/// </summary>
public sealed class Ghost
{
    public Ghost(CarState start = default, int rate = 60)
    {
        Start = start;
        Rate = rate;
    }

    public CarState Start { get; }
    /// <summary>The tick rate it was recorded at: a ghost plays back only at the same rate.</summary>
    public int Rate { get; }
    public List<int> Throttles { get; } = new();
    public List<int> Steers { get; } = new();

    /// <summary>An input as the car gets it: hundredths, so a recording holds it exactly.</summary>
    public static double Quantize(double value) => RoundI(ClampF(value, -1.0, 1.0) * 100.0) / 100.0;

    public void Record(double throttle, double steer)
    {
        Throttles.Add(RoundI(ClampF(throttle, -1.0, 1.0) * 100.0));
        Steers.Add(RoundI(ClampF(steer, -1.0, 1.0) * 100.0));
    }

    public int Ticks() => Throttles.Count;

    public Vector2 InputAt(int tick)
    {
        if (tick < 0 || tick >= Throttles.Count)
            return Vector2.Zero;
        return new Vector2((float)(Throttles[tick] / 100.0), (float)(Steers[tick] / 100.0));
    }

    /// <summary>A car at the lap's start, to step with InputAt(0), InputAt(1)...</summary>
    public Car StartCar() => Car.At(Start);

    /// <summary>Steps a car through the recording on a track and returns where it was after each tick.</summary>
    public List<Vector2> Replay(Track track)
    {
        Car car = StartCar();
        car.Index = track.Nearest(car.Position);
        var positions = new List<Vector2>();
        for (int t = 0; t < Ticks(); t++)
        {
            Drive(car, t, track);
            positions.Add(car.Position);
        }
        return positions;
    }

    /// <summary>Steps a car one tick through the recording: the input of that tick, on the track.</summary>
    public void Drive(Car car, int tick, Track track)
    {
        Vector2 input = InputAt(tick);
        car.Step(input.X, input.Y, 1.0 / Rate, track.IsOnRoad(car.Position, car.Index));
        car.Index = track.Nearest(car.Position, car.Index);
    }

    public JsonObject ToDict()
    {
        var throttles = new JsonArray();
        foreach (int value in Throttles)
            throttles.Add(value);
        var steers = new JsonArray();
        foreach (int value in Steers)
            steers.Add(value);
        return new JsonObject
        {
            ["rate"] = Rate,
            ["start"] = new JsonObject
            {
                ["x"] = (double)Start.Position.X,
                ["y"] = (double)Start.Position.Y,
                ["heading"] = Start.Heading,
                ["speed"] = Start.Speed,
            },
            ["throttle"] = throttles,
            ["steer"] = steers,
        };
    }

    /// <summary>A ghost from saved data; null when it is damaged.</summary>
    public static Ghost? FromDict(JsonNode? data)
    {
        if (data is not JsonObject dict)
            return null;
        JsonNode? rawStart = dict.ContainsKey("start") ? dict["start"] : new JsonObject();
        JsonNode? rawThrottle = dict.ContainsKey("throttle") ? dict["throttle"] : new JsonArray();
        JsonNode? rawSteer = dict.ContainsKey("steer") ? dict["steer"] : new JsonArray();
        if (rawStart is not JsonObject start || rawThrottle is not JsonArray throttles || rawSteer is not JsonArray steers || throttles.Count != steers.Count)
            return null;
        var state = new CarState(
            new Vector2((float)JsonData.Number(start["x"], 0.0), (float)JsonData.Number(start["y"], 0.0)),
            JsonData.Number(start["heading"], 0.0),
            JsonData.Number(start["speed"], 0.0));
        var ghost = new Ghost(state, JsonData.Int(dict["rate"], 60));
        foreach (JsonNode? value in throttles)
            ghost.Throttles.Add(JsonData.Int(value, 0));
        foreach (JsonNode? value in steers)
            ghost.Steers.Add(JsonData.Int(value, 0));
        return ghost;
    }
}

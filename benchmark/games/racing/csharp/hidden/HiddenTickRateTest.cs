namespace Cinderloop.Tests;

using System.Collections.Generic;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the beta's fix-playthrough: the handling is the same at any physics tick rate. A straight run tops
/// out at Accel / Drag, and a driver's laps take the same time, at 30, 60, 120 and 144 ticks a second.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenTickRateTest
{
    private Tracks _tracks = null!;

    [BeforeTest]
    public void Load()
    {
        _tracks = Tracks.FromFiles();
    }

    private static double TopSpeed(int rate)
    {
        var car = new Car();
        for (int i = 0; i < 10 * rate; i++)
            car.Step(1.0, 0.0, 1.0 / rate);
        return car.Speed;
    }

    /// <summary>Seconds a full-pace driver alone takes for the track's laps at a tick rate.</summary>
    private double RaceSeconds(int trackId, int rate)
    {
        var race = new Race(_tracks.Track(trackId), new List<AiDriver?> { new AiDriver() }, rate);
        while (race.FinishOrder.Count == 0 && race.Tick < 150 * rate)
            race.Step();
        return race.Tick / (double)rate;
    }

    [TestCase]
    public void Hidden_the_top_speed_is_the_same_at_every_tick_rate()
    {
        foreach (int rate in new[] { 30, 60, 120, 144 })
            AssertThat(TopSpeed(rate)).OverrideFailureMessage($"{rate} ticks a second").IsEqualApprox(Car.Accel / Car.Drag, Car.Accel / Car.Drag * 0.01);
    }

    [TestCase]
    public void Hidden_a_race_takes_the_same_time_at_30_and_144_ticks()
    {
        foreach (int trackId in new[] { 1, 3 })
        {
            double at60 = RaceSeconds(trackId, 60);
            foreach (int rate in new[] { 30, 120, 144 })
                AssertThat(RaceSeconds(trackId, rate)).OverrideFailureMessage($"track {trackId} at {rate} ticks against 60").IsEqualApprox(at60, at60 * 0.015);
        }
    }

    [TestCase]
    public void Hidden_the_car_is_as_quick_as_designed()
    {
        // The three laps of Ashfall Oval take a full-pace driver about 28 s at the designed handling.
        AssertThat(RaceSeconds(1, 120)).IsBetween(26.0, 30.0);
    }
}

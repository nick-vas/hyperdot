namespace Cinderloop.Tests;

using System.Collections.Generic;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Race.Standings: who leads, from the flag back to the cars on their first lap.</summary>
[TestSuite]
[RequireGodotRuntime]
public class StandingsTest
{
    private Tracks _tracks = null!;

    [BeforeTest]
    public void Load()
    {
        _tracks = Tracks.FromFiles();
    }

    private Race Grid() => new(_tracks.Track(1), _tracks.DriversFor(3, 5), 60);

    [TestCase]
    public void On_the_grid_the_front_row_leads()
    {
        Race race = Grid();
        AssertThat(race.Standings()).ContainsExactly(1, 2, 3, 0);
        AssertThat(race.PositionOf(0)).IsEqual(4);
    }

    [TestCase]
    public void A_car_a_lap_ahead_leads()
    {
        Race race = Grid();
        race.Trackers[0].Armed = true;
        race.Trackers[0].Laps = 1;
        AssertThat(race.PositionOf(0)).IsEqual(1);
    }

    [TestCase]
    public void A_car_past_more_gates_leads()
    {
        Race race = Grid();
        race.Trackers[3].Armed = true;
        race.Trackers[3].NextGate = 2;
        race.Trackers[2].Armed = true;
        race.Trackers[2].NextGate = 1;
        AssertThat(race.Standings().GetRange(0, 2)).ContainsExactly(3, 2);
    }

    [TestCase]
    public void Those_who_took_the_flag_lead_in_their_order()
    {
        Race race = Grid();
        race.FinishOrder = new List<int> { 2, 0 };
        race.Trackers[1].Laps = 5;
        AssertThat(race.Standings().GetRange(0, 2)).ContainsExactly(2, 0);
    }

    [TestCase]
    public void The_bot_climbs_from_the_back_in_a_race()
    {
        var race = new Race(_tracks.Track(1), _tracks.DriversFor(3, 5, true), 60);
        for (int i = 0; i < 20 * 60; i++)
            race.Step();
        AssertThat(race.PositionOf(0)).IsEqual(1);
    }
}

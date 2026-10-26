namespace Duskhive.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Offline progress: the time since the save is paid at the rate saved, up to the cap.</summary>
[TestSuite]
[RequireGodotRuntime]
public class OfflineTest
{
    private Economy _economy = null!;

    [BeforeTest]
    public void Start()
    {
        _economy = new Economy(Catalog.FromFiles());
        _economy.SetCount("glow_snail", 5);
    }

    [TestCase]
    public void An_hour_away_pays_an_hour()
    {
        TimeAway away = Offline.Apply(_economy, 1000.0, 1000.0 + 3600.0);
        AssertThat(away.Seconds).IsEqual(3600.0);
        AssertThat(away.Glow).IsEqualApprox(3600.0 * 20.0, 1e-6);
        AssertThat(_economy.Glow).IsEqualApprox(3600.0 * 20.0, 1e-6);
    }

    [TestCase]
    public void Time_away_is_capped_at_eight_hours()
    {
        TimeAway away = Offline.Apply(_economy, 0.0, 30.0 * 86400.0);
        AssertThat(away.Seconds).IsEqual(28800.0);
        AssertThat(_economy.Glow).IsEqualApprox(28800.0 * 20.0, 1e-6);
    }

    [TestCase]
    public void No_time_no_glow()
    {
        TimeAway away = Offline.Apply(_economy, 5000.0, 5000.0);
        AssertThat(away.Glow).IsEqual(0.0);
    }
}

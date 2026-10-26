namespace Glimmerpit.Tests;

using System;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>LaunchOptions: the flags bot runs, servers and soak pass after "--".</summary>
[TestSuite]
public class LaunchOptionsTest
{
    [TestCase]
    public void The_flags_are_read()
    {
        LaunchOptions options = LaunchOptions.Parse(new[] { "--seed=7", "--no-save", "--lag=120", "--port=24660" });
        AssertThat(options.RunSeed).IsEqual(7L);
        AssertThat(options.NoSave).IsTrue();
        AssertThat(options.LagMs).IsEqual(120);
        AssertThat(options.Port).IsEqual(24660);
        AssertThat(options.Server).IsFalse();
    }

    [TestCase]
    public void Soak_roles()
    {
        LaunchOptions server = LaunchOptions.Parse(new[] { "--soak-role=server", "--soak-port=24661" });
        AssertThat(server.Server).IsTrue();
        AssertThat(server.Port).IsEqual(24661);
        LaunchOptions client = LaunchOptions.Parse(new[] { "--soak-role=client", "--soak-port=24661", "--soak-id=3" });
        AssertThat(client.Server).IsFalse();
        AssertThat(client.SoakId).IsEqual(3);
    }

    [TestCase]
    public void No_flags()
    {
        LaunchOptions options = LaunchOptions.Parse(Array.Empty<string>());
        AssertThat(options.Autoplay).IsFalse();
        AssertThat(options.RunSeed).IsEqual(0L);
        AssertThat(options.LagMs).IsEqual(0);
        AssertThat(options.Port).IsEqual(LaunchOptions.DefaultPort);
        AssertThat(options.MatchSeed(1)).IsEqual(0L);
    }

    [TestCase]
    public void Match_seeds_follow_the_run_seed()
    {
        LaunchOptions options = LaunchOptions.Parse(new[] { "--seed=2" });
        AssertThat(options.MatchSeed(1)).IsEqual(2019L);
        AssertThat(options.MatchSeed(2)).IsEqual(2020L);
    }
}

namespace Duskhive.Tests;

using System;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>LaunchOptions: the flags runs and tests pass after "--".</summary>
[TestSuite]
public class LaunchOptionsTest
{
    [TestCase]
    public void The_flags_are_read()
    {
        LaunchOptions options = LaunchOptions.Parse(new[] { "--no-save", "--speed=60" });
        AssertThat(options.NoSave).IsTrue();
        AssertThat(options.Speed).IsEqual(60.0);
    }

    [TestCase]
    public void Without_flags_the_game_plays_at_its_own_pace()
    {
        LaunchOptions options = LaunchOptions.Parse(Array.Empty<string>());
        AssertThat(options.NoSave).IsFalse();
        AssertThat(options.Speed).IsEqual(1.0);
    }

    [TestCase]
    public void The_speed_is_kept_within_bounds()
    {
        AssertThat(LaunchOptions.Parse(new[] { "--speed=0" }).Speed).IsEqual(1.0);
        AssertThat(LaunchOptions.Parse(new[] { "--speed=99999" }).Speed).IsEqual(600.0);
    }
}

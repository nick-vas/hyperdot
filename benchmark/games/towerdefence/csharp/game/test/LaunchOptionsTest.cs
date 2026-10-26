namespace Bramblegate.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>LaunchOptions: the flags bot runs and tests pass after "--".</summary>
[TestSuite]
public class LaunchOptionsTest
{
    [TestCase]
    public void Every_flag_is_read()
    {
        LaunchOptions options = LaunchOptions.Parse(new[] { "--autoplay", "--seed=7", "--no-save", "--map=3", "--speed=2" });
        AssertThat(options.Autoplay).IsTrue();
        AssertThat(options.RunSeed).IsEqual(7);
        AssertThat(options.NoSave).IsTrue();
        AssertThat(options.Map).IsEqual(3);
        AssertThat(options.Speed).IsEqual(2);
    }

    [TestCase]
    public void No_flags_give_the_defaults()
    {
        LaunchOptions options = LaunchOptions.Parse(System.Array.Empty<string>());
        AssertThat(options.Autoplay).IsFalse();
        AssertThat(options.RunSeed).IsEqual(0);
        AssertThat(options.NoSave).IsFalse();
        AssertThat(options.Map).IsEqual(1);
        AssertThat(options.Speed).IsEqual(1);
    }

    [TestCase]
    public void A_bot_run_plays_fast_unless_told_otherwise()
    {
        AssertThat(LaunchOptions.Parse(new[] { "--autoplay" }).Speed).IsEqual(3);
        AssertThat(LaunchOptions.Parse(new[] { "--autoplay", "--speed=1" }).Speed).IsEqual(1);
    }
}

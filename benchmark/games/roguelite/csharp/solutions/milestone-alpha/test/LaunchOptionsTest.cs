namespace Wickerdeep.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>LaunchOptions: the flags runs and tests pass after "--".</summary>
[TestSuite]
public class LaunchOptionsTest
{
    [TestCase]
    public void Every_flag_is_read()
    {
        LaunchOptions options = LaunchOptions.Parse(new[] { "--seed=7", "--no-save", "--floor=3", "--swarm=200" });
        AssertThat(options.RunSeed).IsEqual(7L);
        AssertThat(options.NoSave).IsTrue();
        AssertThat(options.FloorNumber).IsEqual(3);
        AssertThat(options.Swarm).IsEqual(200);
    }

    [TestCase]
    public void No_flags_is_a_normal_game()
    {
        LaunchOptions options = LaunchOptions.Parse(new string[0]);
        AssertThat(options.NoSave).IsFalse();
        AssertThat(options.RunSeed).IsEqual(0L);
        AssertThat(options.FloorNumber).IsEqual(1);
        AssertThat(options.Swarm).IsEqual(0);
    }
}

namespace Lanternfen.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>LaunchOptions: the flags bot runs and tests pass after "--".</summary>
[TestSuite]
public class LaunchOptionsTest
{
    [TestCase]
    public void Every_flag_is_read()
    {
        LaunchOptions options = LaunchOptions.Parse(new[] { "--autoplay", "--seed=7", "--no-save", "--rival=3" });
        AssertThat(options.Autoplay).IsTrue();
        AssertThat(options.RunSeed).IsEqual(7L);
        AssertThat(options.NoSave).IsTrue();
        AssertThat(options.Rival).IsEqual(3);
    }

    [TestCase]
    public void No_flags_is_a_normal_game()
    {
        LaunchOptions options = LaunchOptions.Parse(System.Array.Empty<string>());
        AssertThat(options.Autoplay).IsFalse();
        AssertThat(options.NoSave).IsFalse();
        AssertThat(options.RunSeed).IsEqual(0L);
        AssertThat(options.Rival).IsEqual(1);
    }
}

namespace Cinderloop.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>LaunchOptions: the flags runs and tests pass after "--".</summary>
[TestSuite]
public class LaunchOptionsTest
{
    [TestCase]
    public void Every_flag_is_read()
    {
        LaunchOptions options = LaunchOptions.Parse(new[] { "--seed=7", "--no-save", "--track=3", "--rivals=7" });
        AssertThat(options.RunSeed).IsEqual(7L);
        AssertThat(options.NoSave).IsTrue();
        AssertThat(options.Track).IsEqual(3);
        AssertThat(options.Rivals).IsEqual(7);
    }

    [TestCase]
    public void No_flags_is_a_normal_game()
    {
        LaunchOptions options = LaunchOptions.Parse(System.Array.Empty<string>());
        AssertThat(options.NoSave).IsFalse();
        AssertThat(options.Track).IsEqual(1);
        AssertThat(options.Rivals).IsEqual(3);
    }

    [TestCase]
    public void Out_of_range_values_are_held_in_range()
    {
        LaunchOptions options = LaunchOptions.Parse(new[] { "--track=0", "--rivals=99" });
        AssertThat(options.Track).IsEqual(1);
        AssertThat(options.Rivals).IsEqual(31);
    }
}

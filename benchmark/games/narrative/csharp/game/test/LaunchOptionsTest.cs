namespace SaltmereCrossing.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>LaunchOptions: the flags bot runs and tests pass after "--".</summary>
[TestSuite]
public class LaunchOptionsTest
{
    [TestCase]
    public void The_flags_are_read()
    {
        LaunchOptions options = LaunchOptions.Parse(new[] { "--autoplay", "--no-save" });
        AssertThat(options.Autoplay).IsTrue();
        AssertThat(options.NoSave).IsTrue();
    }

    [TestCase]
    public void Nothing_given_is_a_player_session()
    {
        LaunchOptions options = LaunchOptions.Parse(System.Array.Empty<string>());
        AssertThat(options.Autoplay).IsFalse();
        AssertThat(options.NoSave).IsFalse();
    }
}

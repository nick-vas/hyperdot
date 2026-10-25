namespace Bramblegate.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>LaunchOptions: the flags runs and tests pass after "--".</summary>
[TestSuite]
public class LaunchOptionsTest
{
    [TestCase]
    public void Every_flag_is_read()
    {
        LaunchOptions options = LaunchOptions.Parse(new[] { "--seed=7", "--no-save", "--map=3", "--speed=2" });
        AssertThat(options.RunSeed).IsEqual(7);
        AssertThat(options.NoSave).IsTrue();
        AssertThat(options.Map).IsEqual(3);
        AssertThat(options.Speed).IsEqual(2);
    }

    [TestCase]
    public void No_flags_give_the_defaults()
    {
        LaunchOptions options = LaunchOptions.Parse(System.Array.Empty<string>());
        AssertThat(options.RunSeed).IsEqual(0);
        AssertThat(options.NoSave).IsFalse();
        AssertThat(options.Map).IsEqual(1);
        AssertThat(options.Speed).IsEqual(1);
    }
}

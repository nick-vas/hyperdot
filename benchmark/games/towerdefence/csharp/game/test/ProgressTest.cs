namespace Bramblegate.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Progress: stars for a cleared map, the best result kept, and which maps are open.</summary>
[TestSuite]
[RequireGodotRuntime]
public class ProgressTest
{
    private Catalog _catalog = null!;

    [BeforeTest]
    public void Load() => _catalog = Catalog.FromFiles();

    [TestCase]
    public void Stars_follow_the_seeds_kept()
    {
        AssertThat(Progress.StarsFor(20, 20)).IsEqual(3);
        AssertThat(Progress.StarsFor(10, 20)).IsEqual(2);
        AssertThat(Progress.StarsFor(9, 20)).IsEqual(1);
        AssertThat(Progress.StarsFor(1, 20)).IsEqual(1);
    }

    [TestCase]
    public void A_cleared_map_opens_the_next()
    {
        var save = new SaveData();
        AssertThat(Progress.IsUnlocked(save, _catalog, 1)).IsTrue();
        AssertThat(Progress.IsUnlocked(save, _catalog, 2)).IsFalse();
        Progress.Record(save, "meadow", 12, 20);
        AssertThat(Progress.IsCleared(save, "meadow")).IsTrue();
        AssertThat(Progress.Stars(save, "meadow")).IsEqual(2);
        AssertThat(Progress.IsUnlocked(save, _catalog, 2)).IsTrue();
        AssertThat(Progress.IsUnlocked(save, _catalog, 3)).IsFalse();
    }

    [TestCase]
    public void A_better_replay_raises_the_stars()
    {
        var save = new SaveData();
        Progress.Record(save, "meadow", 5, 20);
        Progress.Record(save, "meadow", 20, 20);
        AssertThat(Progress.Stars(save, "meadow")).IsEqual(3);
        AssertThat(Progress.TotalStars(save)).IsEqual(3);
    }
}

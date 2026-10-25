namespace SaltmereCrossing.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the beta's fix-playthrough: every ending can be reached again, and the shore still asks for trust
/// and a calm ferrywoman, while the fog still frightens.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenShoreTest
{
    private StoryGraph _graph = null!;

    [BeforeTest]
    public void Load()
    {
        _graph = StoryGraph.FromFiles();
    }

    private Story AtFarBank(int trust, int afraid)
    {
        Story story = Story.Replay(_graph, new[] { "dock_silent", "toll_true", "launch_row", "fog_hurry", "cross_on" });
        AssertThat(story.NodeId).IsEqual("far_bank");
        story.Flags["trust"] = trust;
        story.Flags["afraid"] = afraid;
        return story;
    }

    [TestCase]
    public void Hidden_every_ending_can_be_reached()
    {
        StorySearch found = StoryCheck.Search(_graph);
        foreach (string id in new[] { "shore", "return", "bell" })
            AssertThat(found.Endings.Contains(id)).OverrideFailureMessage(id).IsTrue();
        AssertThat(StoryCheck.Problems(_graph)).IsEmpty();
    }

    [TestCase]
    public void Hidden_the_fog_still_frightens()
    {
        Story story = Story.Replay(_graph, new[] { "dock_silent", "toll_true", "launch_row" });
        AssertThat(story.NodeId).IsEqual("fog");
        AssertThat(story.Flag("afraid")).IsEqual(1);
    }

    [TestCase]
    public void Hidden_steadying_yourself_calms_the_fear()
    {
        Story story = Story.Replay(_graph, new[] { "dock_greet", "toll_true", "launch_row", "fog_steady" });
        AssertThat(story.NodeId).IsEqual("crossing");
        AssertThat(story.Flag("afraid")).IsEqual(0);
        AssertThat(story.Choose("cross_on")).IsTrue();
        AssertThat(story.CanChoose("land")).IsTrue();
    }

    [TestCase]
    public void Hidden_the_shore_still_asks_for_trust_and_calm()
    {
        AssertThat(AtFarBank(3, 1).CanChoose("land")).OverrideFailureMessage("afraid").IsFalse();
        AssertThat(AtFarBank(1, 0).CanChoose("land")).OverrideFailureMessage("not trusted enough").IsFalse();
        AssertThat(AtFarBank(2, 0).CanChoose("land")).IsTrue();
    }
}

namespace SaltmereCrossing.Tests;

using System.Collections.Generic;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden acceptance for the alpha-to-beta milestone: the drowned bell is the third ending, reached only by those who
/// asked about it, and the story check is clean.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenThreeEndingsTest
{
    [TestCase]
    public void Hidden_three_endings_each_reached()
    {
        StoryGraph graph = StoryGraph.FromFiles();
        AssertThat(new List<string>(graph.EndingIds)).ContainsExactly("shore", "return", "bell");
        AssertThat(graph.EndingAt("end_bell")).IsEqual("bell");
        StorySearch found = StoryCheck.Search(graph);
        foreach (string id in graph.EndingIds)
            AssertThat(found.Endings.Contains(id)).OverrideFailureMessage(id).IsTrue();
        AssertThat(StoryCheck.Problems(graph)).IsEmpty();
    }

    [TestCase]
    public void Hidden_the_tower_needs_the_tale()
    {
        StoryGraph graph = StoryGraph.FromFiles();
        Story story = Story.Replay(graph, new[] { "dock_silent", "toll_true", "launch_row", "fog_hurry", "cross_on" });
        AssertThat(story.CanChoose("to_tower")).IsFalse();
        story = Story.Replay(graph, new[] { "dock_silent", "toll_true", "launch_row", "fog_hurry", "ask_bell" });
        AssertThat(story.NodeId).IsEqual("bell_tale");
        AssertThat(story.Flag("knows_bell")).IsEqual(1);
        List<Choice> open = story.Available();
        AssertThat(open.Count > 0 && story.Choose(open[0].Id)).IsTrue();
        AssertThat(story.Choose("cross_on")).IsTrue();
        AssertThat(story.Choose("to_tower")).IsTrue();
        AssertThat(story.Choose("ring_bell")).IsTrue();
        AssertThat(story.Ending()).IsEqual("bell");
    }
}

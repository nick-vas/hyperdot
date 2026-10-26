namespace SaltmereCrossing.Tests;

using System.Collections.Generic;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>StoryGraph: the story's tables as the game reads them.</summary>
[TestSuite]
[RequireGodotRuntime]
public class StoryGraphTest
{
    private StoryGraph _graph = null!;

    [BeforeTest]
    public void Load()
    {
        _graph = StoryGraph.FromFiles();
    }

    [TestCase]
    public void The_story_starts_at_the_first_node()
    {
        AssertThat(_graph.Start).IsEqual("dock");
        AssertThat(_graph.Node("dock")!.Speaker).IsEqual("narrator");
        AssertThat(_graph.Node("dock")!.Chapter).IsEqual(1);
    }

    [TestCase]
    public void Choices_out_of_a_node_come_in_file_order()
    {
        var ids = new List<string>();
        foreach (Choice choice in _graph.ChoicesFrom("toll"))
            ids.Add(choice.Id);
        AssertThat(ids).ContainsExactly("toll_true", "toll_lie");
        AssertThat(_graph.Choice("toll_lie")!.Set).ContainsExactly("lied");
    }

    [TestCase]
    public void Each_ending_is_a_node_of_the_story()
    {
        AssertThat(_graph.EndingIds.Count).OverrideFailureMessage("more than one ending").IsGreater(1);
        foreach (string id in _graph.EndingIds)
        {
            string at = _graph.Ending(id)!.Node;
            AssertThat(_graph.HasNode(at)).OverrideFailureMessage(at).IsTrue();
            AssertThat(_graph.EndingAt(at)).IsEqual(id);
        }
        AssertThat(_graph.EndingAt("dock")).IsEqual("");
    }
}

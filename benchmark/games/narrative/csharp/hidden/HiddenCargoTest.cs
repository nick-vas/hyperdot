namespace SaltmereCrossing.Tests;

using System.Collections.Generic;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the prototype's fix-bug: asking about the stranger's bag leads to her answer and on, every choice of
/// the story leads to a node, and every node can be reached.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenCargoTest
{
    private StoryGraph _graph = null!;

    [BeforeTest]
    public void Load()
    {
        _graph = StoryGraph.FromFiles();
    }

    private Story AtCrossing() => Story.Replay(_graph, new[] { "dock_silent", "toll_true", "launch_row", "fog_hurry" });

    [TestCase]
    public void Hidden_asking_about_the_bag_leads_to_her_answer()
    {
        Story story = AtCrossing();
        AssertThat(story.NodeId).IsEqual("crossing");
        AssertThat(story.CanChoose("ask_cargo")).OverrideFailureMessage("the question is offered").IsTrue();
        AssertThat(story.Choose("ask_cargo")).IsTrue();
        AssertThat(_graph.HasNode(story.NodeId)).OverrideFailureMessage("a node of the story").IsTrue();
        AssertThat(story.Current()?.Text ?? "").IsEqual("N_CARGO");
    }

    [TestCase]
    public void Hidden_her_answer_leads_back_to_the_crossing()
    {
        Story story = AtCrossing();
        story.Choose("ask_cargo");
        List<Choice> open = story.Available();
        AssertThat(open.Count).IsEqual(1);
        if (open.Count == 1)
        {
            AssertThat(story.Choose(open[0].Id)).IsTrue();
            AssertThat(story.NodeId).IsEqual("crossing");
        }
    }

    [TestCase]
    public void Hidden_every_choice_leads_to_a_node()
    {
        foreach (string id in _graph.ChoiceIds)
        {
            string to = _graph.Choice(id)!.To;
            AssertThat(_graph.HasNode(to)).OverrideFailureMessage($"{id} -> {to}").IsTrue();
        }
    }

    [TestCase]
    public void Hidden_every_node_can_be_reached()
    {
        var seen = new HashSet<string> { _graph.Start };
        var queue = new Queue<string>();
        queue.Enqueue(_graph.Start);
        while (queue.Count > 0)
        {
            string at = queue.Dequeue();
            foreach (Choice choice in _graph.ChoicesFrom(at))
            {
                if (seen.Add(choice.To))
                    queue.Enqueue(choice.To);
            }
        }
        foreach (string id in _graph.NodeIds)
            AssertThat(seen.Contains(id)).OverrideFailureMessage(id).IsTrue();
    }
}

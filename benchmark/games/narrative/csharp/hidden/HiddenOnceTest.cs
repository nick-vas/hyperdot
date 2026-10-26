namespace SaltmereCrossing.Tests;

using System.Collections.Generic;
using System.Text.Json.Nodes;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Hidden check for the prototype's add-feature: once-only choices, on a story of its own and on the game's questions.</summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenOnceTest
{
    private static StoryGraph Hub()
    {
        return StoryGraph.FromJson(
            """[{"id": "hub"}, {"id": "answer"}, {"id": "end"}]""",
            """
            [
                {"id": "ask", "from": "hub", "to": "answer", "raise": ["asked"], "once": true},
                {"id": "look", "from": "hub", "to": "answer"},
                {"id": "leave", "from": "hub", "to": "end", "needs": "asked>=0"},
                {"id": "back", "from": "answer", "to": "hub"}
            ]
            """,
            """[{"id": "asked", "kind": "count"}]""",
            """[{"id": "end", "node": "end"}]""");
    }

    private static List<string> Ids(Story story)
    {
        var ids = new List<string>();
        foreach (Choice choice in story.Available())
            ids.Add(choice.Id);
        return ids;
    }

    [TestCase]
    public void Hidden_the_graph_reads_once()
    {
        StoryGraph hub = Hub();
        AssertThat(hub.Choice("ask")!.Once).IsTrue();
        AssertThat(hub.Choice("look")!.Once).IsFalse();
    }

    [TestCase]
    public void Hidden_a_once_choice_is_offered_until_taken()
    {
        var story = new Story(Hub());
        AssertThat(Ids(story)).ContainsExactly("ask", "look", "leave");
        AssertThat(story.Choose("ask")).IsTrue();
        AssertThat(story.Choose("back")).IsTrue();
        AssertThat(Ids(story)).ContainsExactly("look", "leave");
        AssertThat(story.Choose("ask")).IsFalse();
        AssertThat(story.Flags["asked"]).IsEqual(1);
    }

    [TestCase]
    public void Hidden_other_choices_can_be_taken_again()
    {
        var story = new Story(Hub());
        for (int i = 0; i < 3; i++)
        {
            AssertThat(story.Choose("look")).IsTrue();
            AssertThat(story.Choose("back")).IsTrue();
        }
        AssertThat(story.CanChoose("ask")).IsTrue();
    }

    [TestCase]
    public void Hidden_a_new_story_offers_it_again()
    {
        StoryGraph hub = Hub();
        Story.Replay(hub, new[] { "ask", "back" });
        AssertThat(new Story(hub).CanChoose("ask")).IsTrue();
    }

    [TestCase]
    public void Hidden_a_story_carried_on_remembers_it()
    {
        StoryGraph hub = Hub();
        Story story = Story.Replay(hub, new[] { "ask", "back" });
        var data = (JsonObject)JsonNode.Parse(story.ToDict().ToJsonString())!;
        Story back = Story.FromDict(hub, data);
        AssertThat(back.CanChoose("ask")).IsFalse();
        AssertThat(back.CanChoose("look")).IsTrue();
    }

    [TestCase]
    public void Hidden_the_stranger_answers_each_question_once()
    {
        StoryGraph graph = StoryGraph.FromFiles();
        AssertThat(graph.Choice("ask_name")!.Once).OverrideFailureMessage("ask_name").IsTrue();
        AssertThat(graph.Choice("ask_cargo")!.Once).OverrideFailureMessage("ask_cargo").IsTrue();
        Story story = Story.Replay(graph, new[] { "dock_silent", "toll_true", "launch_row", "fog_hurry", "ask_name", "name_back" });
        AssertThat(story.CanChoose("ask_name")).IsFalse();
        AssertThat(story.CanChoose("ask_cargo")).IsTrue();
        AssertThat(story.CanChoose("cross_on")).IsTrue();
        AssertThat(story.Flags["trust"]).IsEqual(2);
    }
}

namespace SaltmereCrossing.Tests;

using System.Collections.Generic;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// The rules of Story on a small story of its own: needs, the three effects, the history, moving on, and choices that
/// are not offered.
/// </summary>
[TestSuite]
public class StoryRulesTest
{
    private StoryGraph _graph = null!;

    [BeforeTest]
    public void MakeGraph()
    {
        _graph = StoryGraph.FromJson(
            """[{"id": "a"}, {"id": "b"}, {"id": "c"}, {"id": "end"}]""",
            """
            [
                {"id": "kind", "from": "a", "to": "b", "raise": ["trust"]},
                {"id": "scare", "from": "a", "to": "b", "set": ["afraid"]},
                {"id": "calm", "from": "b", "to": "c", "clear": ["afraid"]},
                {"id": "again", "from": "b", "to": "a"},
                {"id": "rush", "from": "b", "to": "c"},
                {"id": "trusted", "from": "c", "to": "end", "needs": "trust>=2;!afraid"},
                {"id": "back", "from": "c", "to": "a"}
            ]
            """,
            """[{"id": "trust", "kind": "count"}, {"id": "afraid", "kind": "switch"}]""",
            """[{"id": "only", "node": "end"}]""");
    }

    private Story Replay(params string[] ids) => Story.Replay(_graph, ids);

    private static List<string> Ids(Story story)
    {
        var ids = new List<string>();
        foreach (Choice choice in story.Available())
            ids.Add(choice.Id);
        return ids;
    }

    [TestCase]
    public void Raise_adds_one_each_time()
    {
        Story story = Replay("kind", "again", "kind");
        AssertThat(story.Flags["trust"]).IsEqual(2);
    }

    [TestCase]
    public void Set_makes_a_flag_one_and_clear_makes_it_zero()
    {
        Story story = Replay("scare");
        AssertThat(story.Flags["afraid"]).IsEqual(1);
        AssertThat(story.Choose("calm")).IsTrue();
        AssertThat(story.Flags["afraid"]).IsEqual(0);
    }

    [TestCase]
    public void A_choice_is_offered_only_when_every_need_holds()
    {
        Story low = Replay("kind", "calm");
        AssertThat(Ids(low)).OverrideFailureMessage("trust 1 is not enough").ContainsExactly("back");
        Story afraid = Replay("kind", "again", "kind", "again", "scare", "rush");
        AssertThat(afraid.NodeId).IsEqual("c");
        AssertThat(Ids(afraid)).OverrideFailureMessage("trust 2 but afraid").ContainsExactly("back");
        Story trusted = Replay("kind", "again", "kind", "calm");
        AssertThat(Ids(trusted)).ContainsExactly("trusted", "back");
    }

    [TestCase]
    public void A_choice_taken_moves_the_story_and_joins_the_history()
    {
        var story = new Story(_graph);
        AssertThat(story.Choose("kind")).IsTrue();
        AssertThat(story.NodeId).IsEqual("b");
        AssertThat(story.Choose("calm")).IsTrue();
        AssertThat(story.NodeId).IsEqual("c");
        AssertThat(story.History).ContainsExactly("kind", "calm");
    }

    [TestCase]
    public void A_choice_not_offered_cannot_be_taken()
    {
        var story = new Story(_graph);
        AssertThat(story.Choose("trusted")).OverrideFailureMessage("not out of this node").IsFalse();
        story = Replay("kind", "calm");
        AssertThat(story.Choose("trusted")).OverrideFailureMessage("its needs do not hold").IsFalse();
        AssertThat(story.NodeId).IsEqual("c");
        AssertThat(story.Flags["trust"]).IsEqual(1);
        AssertThat(story.History).ContainsExactly("kind", "calm");
    }

    [TestCase]
    public void An_ending_is_reached_and_offers_nothing()
    {
        Story story = Replay("kind", "again", "kind", "calm", "trusted");
        AssertThat(story.NodeId).IsEqual("end");
        AssertThat(story.IsOver()).IsTrue();
        AssertThat(story.Ending()).IsEqual("only");
        AssertThat(Ids(story)).IsEmpty();
    }
}

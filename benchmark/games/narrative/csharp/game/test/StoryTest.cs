namespace SaltmereCrossing.Tests;

using System.Collections.Generic;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Story: one playthrough of the game's story, without a scene.</summary>
[TestSuite]
[RequireGodotRuntime]
public class StoryTest
{
    private StoryGraph _graph = null!;

    [BeforeTest]
    public void Load()
    {
        _graph = StoryGraph.FromFiles();
    }

    private Story Replay(params string[] ids) => Story.Replay(_graph, ids);

    [TestCase]
    public void Three_kind_words_give_three_trust()
    {
        Story story = Replay("dock_greet", "toll_true", "launch_row", "fog_steady", "ask_name");
        AssertThat(story.NodeId).IsEqual("name");
        AssertThat(story.Flags["trust"]).IsEqual(3);
    }

    [TestCase]
    public void A_story_begins_at_the_dock_with_every_flag_at_zero()
    {
        var story = new Story(_graph);
        AssertThat(story.NodeId).IsEqual("dock");
        foreach (string flag in _graph.FlagIds)
            AssertThat(story.Flags[flag]).OverrideFailureMessage(flag).IsEqual(0);
        AssertThat(story.History).IsEmpty();
    }

    [TestCase]
    public void The_dock_offers_its_two_choices_in_order()
    {
        var ids = new List<string>();
        foreach (Choice choice in new Story(_graph).Available())
            ids.Add(choice.Id);
        AssertThat(ids).ContainsExactly("dock_greet", "dock_silent");
    }

    [TestCase]
    public void A_choice_moves_the_story_and_is_remembered()
    {
        var story = new Story(_graph);
        AssertThat(story.Choose("dock_silent")).IsTrue();
        AssertThat(story.NodeId).IsEqual("toll");
        AssertThat(story.History).ContainsExactly("dock_silent");
    }

    [TestCase]
    public void A_lie_is_set_and_a_confession_clears_it()
    {
        Story story = Replay("dock_silent", "toll_lie", "launch_row", "fog_hurry");
        AssertThat(story.Flags["lied"]).IsEqual(1);
        AssertThat(story.Choose("confess")).IsTrue();
        AssertThat(story.Flags["lied"]).IsEqual(0);
    }

    [TestCase]
    public void A_confession_is_offered_only_after_a_lie()
    {
        Story honest = Replay("dock_silent", "toll_true", "launch_row", "fog_hurry");
        AssertThat(honest.NodeId).IsEqual("crossing");
        AssertThat(honest.CanChoose("confess")).IsFalse();
        Story liar = Replay("dock_silent", "toll_lie", "launch_row", "fog_hurry");
        AssertThat(liar.CanChoose("confess")).IsTrue();
    }

    [TestCase]
    public void A_choice_not_offered_is_refused_and_changes_nothing()
    {
        var story = new Story(_graph);
        AssertThat(story.Choose("land")).IsFalse();
        AssertThat(story.Choose("no_such_choice")).IsFalse();
        AssertThat(story.NodeId).IsEqual("dock");
        AssertThat(story.History).IsEmpty();
    }

    [TestCase]
    public void An_ending_offers_nothing()
    {
        Story story = Replay("dock_silent", "toll_true", "launch_row", "fog_hurry", "cross_on", "turn_back");
        AssertThat(story.IsOver()).IsTrue();
        AssertThat(story.Ending()).IsEqual("return");
        AssertThat(story.Available()).IsEmpty();
    }

    [TestCase]
    public void Events_tell_the_node_and_the_ending()
    {
        Story story = Replay("dock_silent", "toll_true", "launch_row", "fog_hurry", "cross_on");
        var entered = new List<string>();
        var ended = new List<string>();
        story.NodeEntered += entered.Add;
        story.Ended += ended.Add;
        AssertThat(story.Choose("turn_back")).IsTrue();
        AssertThat(entered).ContainsExactly("end_return");
        AssertThat(ended).ContainsExactly("return");
    }
}

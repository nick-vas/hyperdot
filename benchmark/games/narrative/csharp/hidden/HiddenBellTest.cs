namespace SaltmereCrossing.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Hidden check for the alpha's add-content: the drowned bell, a third ending reached only by those who asked about it.</summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenBellTest
{
    private StoryGraph _graph = null!;

    [BeforeTest]
    public void Load()
    {
        _graph = StoryGraph.FromFiles();
    }

    private static List<string> Offered(Story story)
    {
        var ids = new List<string>();
        foreach (Choice choice in story.Available())
            ids.Add(choice.Id);
        return ids;
    }

    [TestCase]
    public void Hidden_the_bell_is_an_ending_of_its_own()
    {
        AssertThat(new List<string>(_graph.EndingIds)).Contains("bell");
        AssertThat(_graph.Ending("bell")?.Node ?? "").IsEqual("end_bell");
        AssertThat(_graph.Ending("bell")?.Title ?? "").IsEqual("ENDING_BELL");
        AssertThat(_graph.EndingAt("end_bell")).IsEqual("bell");
        AssertThat(new List<string>(_graph.EndingIds)).Contains("shore", "return");
    }

    [TestCase]
    public void Hidden_the_way_to_the_bell()
    {
        Story story = Story.Replay(_graph, new[] { "dock_silent", "toll_true", "launch_row", "fog_hurry" });
        AssertThat(story.CanChoose("ask_bell")).OverrideFailureMessage("the question is offered at the crossing").IsTrue();
        AssertThat(story.Choose("ask_bell")).IsTrue();
        AssertThat(story.NodeId).IsEqual("bell_tale");
        AssertThat(story.Flag("knows_bell")).IsEqual(1);
        AssertThat(Offered(story).Count).OverrideFailureMessage("one way on from her tale").IsEqual(1);
        AssertThat(story.Choose(Offered(story)[0])).IsTrue();
        AssertThat(story.NodeId).IsEqual("crossing");
        AssertThat(story.CanChoose("ask_bell")).OverrideFailureMessage("asked once").IsFalse();
        AssertThat(story.Choose("cross_on")).IsTrue();
        AssertThat(story.Choose("to_tower")).IsTrue();
        AssertThat(story.NodeId).IsEqual("bell_tower");
        AssertThat(Offered(story).Count).OverrideFailureMessage("ring the bell, or row back").IsEqual(2);
        AssertThat(story.Choose("ring_bell")).IsTrue();
        AssertThat(story.Ending()).IsEqual("bell");
    }

    [TestCase]
    public void Hidden_only_those_who_asked_find_the_tower()
    {
        Story story = Story.Replay(_graph, new[] { "dock_silent", "toll_true", "launch_row", "fog_hurry", "cross_on" });
        AssertThat(story.NodeId).IsEqual("far_bank");
        AssertThat(story.CanChoose("to_tower")).IsFalse();
        Story back = Story.Replay(_graph, new[] { "dock_silent", "toll_true", "launch_row", "fog_hurry", "ask_bell" });
        List<string> fromTale = Offered(back);
        if (fromTale.Count > 0)
            back.Choose(fromTale[0]);
        back.Choose("cross_on");
        back.Choose("to_tower");
        string rowBack = "";
        foreach (string id in Offered(back))
        {
            if (id != "ring_bell")
                rowBack = id;
        }
        AssertThat(back.Choose(rowBack)).IsTrue();
        AssertThat(back.NodeId).IsEqual("far_bank");
    }

    [TestCase]
    public void Hidden_the_story_check_passes_and_every_ending_is_reached()
    {
        AssertThat(StoryCheck.Problems(_graph)).IsEmpty();
        StorySearch found = StoryCheck.Search(_graph);
        foreach (string id in new[] { "shore", "return", "bell" })
            AssertThat(found.Endings.Contains(id)).OverrideFailureMessage(id).IsTrue();
    }

    [TestCase]
    public void Hidden_the_new_text_is_written()
    {
        var keys = new List<string>
        {
            "ENDING_BELL",
            _graph.Node("bell_tale")?.Text ?? "?",
            _graph.Node("bell_tower")?.Text ?? "?",
            _graph.Node("end_bell")?.Text ?? "?",
            _graph.Choice("ask_bell")?.Text ?? "?",
            _graph.Choice("to_tower")?.Text ?? "?",
            _graph.Choice("ring_bell")?.Text ?? "?",
        };
        foreach (string key in keys)
            AssertThat(TranslationServer.Translate(key).ToString()).OverrideFailureMessage(key).IsNotEqual(key);
    }
}

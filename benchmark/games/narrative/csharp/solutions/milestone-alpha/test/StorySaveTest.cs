namespace SaltmereCrossing.Tests;

using System;
using System.IO;
using System.Text.Json.Nodes;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>A story kept in the save comes back where it was: the node, the switches set and cleared, and the history.</summary>
[TestSuite]
[RequireGodotRuntime]
public class StorySaveTest
{
    private string _path = "";
    private StoryGraph _graph = null!;

    [BeforeTest]
    public void Prepare()
    {
        _path = Path.Combine(Path.GetTempPath(), $"saltmere-{Guid.NewGuid():N}.json");
        _graph = StoryGraph.FromFiles();
    }

    [AfterTest]
    public void RemoveFile()
    {
        File.Delete(_path);
    }

    private Story ThroughTheSave(Story story)
    {
        var store = new SaveStore(_path);
        var data = new SaveData { Story = story.ToDict() };
        AssertThat(store.Write(data)).IsTrue();
        return Story.FromDict(_graph, store.Read().Story!);
    }

    [TestCase]
    public void The_node_and_the_history_come_back()
    {
        Story story = Story.Replay(_graph, new[] { "dock_silent", "toll_lie", "launch_row" });
        Story back = ThroughTheSave(story);
        AssertThat(back.NodeId).IsEqual("fog");
        AssertThat(back.History).ContainsExactly(story.History.ToArray());
    }

    [TestCase]
    public void A_lie_told_before_the_save_can_still_be_confessed()
    {
        Story story = Story.Replay(_graph, new[] { "dock_silent", "toll_lie", "launch_row", "fog_hurry" });
        Story back = ThroughTheSave(story);
        AssertThat(back.Flags["lied"]).IsEqual(1);
        AssertThat(back.Flags["afraid"]).IsEqual(1);
        AssertThat(back.CanChoose("confess")).IsTrue();
    }

    [TestCase]
    public void A_saved_node_the_story_lost_starts_over()
    {
        Story back = Story.FromDict(_graph, new JsonObject { ["node"] = "gone", ["flags"] = new JsonObject(), ["history"] = new JsonArray() });
        AssertThat(back.NodeId).IsEqual("dock");
    }
}

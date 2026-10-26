namespace SaltmereCrossing.Tests;

using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the alpha's fix-bug: a story kept in the save comes back with every flag at its value, so trust won
/// and a lie told before quitting still count after Continue.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenFlagsSavedTest
{
    private string _path = "";
    private StoryGraph _graph = null!;

    [BeforeTest]
    public void Prepare()
    {
        _path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"saltmere-hidden-{Guid.NewGuid():N}.json");
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
        AssertThat(store.Write(new SaveData { Story = story.ToDict() })).IsTrue();
        return Story.FromDict(_graph, store.Read().Story!);
    }

    [TestCase]
    public void Hidden_every_flag_comes_back_at_its_value()
    {
        Story story = Story.Replay(_graph, new[] { "dock_greet", "toll_lie", "launch_row", "fog_steady", "ask_name" });
        AssertThat(story.Flag("trust")).IsEqual(2);
        Story back = ThroughTheSave(story);
        foreach (string flag in _graph.FlagIds)
            AssertThat(back.Flags.TryGetValue(flag, out int value) ? value : -1).OverrideFailureMessage(flag).IsEqual(story.Flag(flag));
    }

    [TestCase]
    public void Hidden_trust_won_before_the_save_lets_the_boat_land()
    {
        Story story = Story.Replay(_graph, new[] { "dock_greet", "toll_true", "launch_row", "fog_steady", "cross_on" });
        Story back = ThroughTheSave(story);
        AssertThat(back.NodeId).IsEqual("far_bank");
        AssertThat(back.CanChoose("land")).IsTrue();
        AssertThat(back.Choose("land")).IsTrue();
        AssertThat(back.Ending()).IsEqual("shore");
    }

    [TestCase]
    public void Hidden_three_trust_stays_three()
    {
        Story story = Story.Replay(_graph, new[] { "dock_greet", "toll_true", "launch_row", "fog_hurry", "ask_name" });
        AssertThat(story.Flag("trust")).IsEqual(3);
        AssertThat(ThroughTheSave(story).Flag("trust")).IsEqual(3);
    }

    [TestCase]
    public async Task Hidden_the_story_scene_carries_on_with_the_flags()
    {
        Story story = Story.Replay(_graph, new[] { "dock_greet", "toll_lie", "launch_row", "fog_steady" });
        var store = new SaveStore(_path);
        store.Write(new SaveData { Story = story.ToDict() });
        var scene = GD.Load<PackedScene>("res://story/story.tscn").Instantiate<StoryScene>();
        scene.Setup(_graph, LaunchOptions.Parse(System.Array.Empty<string>()), new List<string>(), store.Read().Story);
        var tree = (SceneTree)Engine.GetMainLoop();
        tree.Root.AddChild(scene);
        try
        {
            for (int i = 0; i < 2; i++)
                await scene.ToSignal(tree, SceneTree.SignalName.PhysicsFrame);
            AssertThat(scene.node).IsEqual("crossing");
            AssertThat(scene.story!.Flag("trust")).IsEqual(1);
            AssertThat(scene.story.Flag("lied")).IsEqual(1);
            AssertThat(scene.story.CanChoose("confess")).IsTrue();
        }
        finally
        {
            scene.QueueFree();
        }
    }
}

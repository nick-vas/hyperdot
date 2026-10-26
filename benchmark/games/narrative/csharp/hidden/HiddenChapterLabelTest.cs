namespace SaltmereCrossing.Tests;

using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Hidden check for the alpha's fix-architecture: the chapter label follows the story, set by the story itself.</summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenChapterLabelTest
{
    private static async Task PhysicsFrames(Node node, int count)
    {
        for (int i = 0; i < count; i++)
            await node.ToSignal(node.GetTree(), SceneTree.SignalName.PhysicsFrame);
    }

    private static async Task<StoryScene> Start(ISceneRunner runner)
    {
        var scene = (StoryScene)runner.Scene();
        await PhysicsFrames(scene, 2);
        return scene;
    }

    private static string Label(StoryScene scene) => scene.GetNode<Label>("HUD/ChapterLabel").Text;

    [TestCase]
    public async Task Hidden_the_label_shows_the_first_chapter()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://story/story.tscn");
        StoryScene scene = await Start(runner);
        AssertThat(Label(scene)).IsEqual("Chapter 1: The Landing");
    }

    [TestCase]
    public async Task Hidden_the_label_follows_the_story_into_the_fog()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://story/story.tscn");
        StoryScene scene = await Start(runner);
        scene.resume(Story.Replay(scene.graph, new[] { "dock_silent", "toll_true" }).ToDict());
        scene.reveal_all();
        await PhysicsFrames(scene, 3);
        AssertThat(Label(scene)).IsEqual("Chapter 1: The Landing");
        AssertThat(scene.choose_id("launch_row")).IsTrue();
        await PhysicsFrames(scene, StoryScene.TurnTicks + 1);
        AssertThat(scene.node).IsEqual("fog");
        AssertThat(Label(scene)).IsEqual("Chapter 2: The Crossing");
    }

    [TestCase]
    public async Task Hidden_the_label_follows_a_story_carried_on_and_a_new_one()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://story/story.tscn");
        StoryScene scene = await Start(runner);
        scene.resume(Story.Replay(scene.graph, new[] { "dock_silent", "toll_true", "launch_row", "fog_hurry", "cross_on" }).ToDict());
        await PhysicsFrames(scene, 1);
        AssertThat(Label(scene)).IsEqual("Chapter 3: The Far Bank");
        scene.start_new();
        await PhysicsFrames(scene, 1);
        AssertThat(Label(scene)).IsEqual("Chapter 1: The Landing");
    }
}

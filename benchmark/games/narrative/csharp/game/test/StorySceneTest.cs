namespace SaltmereCrossing.Tests;

using System.Text.Json.Nodes;
using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>The story scene: a line typed out, its choices as buttons, the page turning, the ending panel and the history.</summary>
[TestSuite]
[RequireGodotRuntime]
public class StorySceneTest
{
    /// <summary>Waits for whole physics ticks, which is what the scene counts in.</summary>
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

    private static async Task UntilState(StoryScene scene, string state)
    {
        for (int i = 0; i < 300 && scene.state != state; i++)
            await PhysicsFrames(scene, 1);
    }

    [TestCase]
    public async Task The_line_is_typed_out_then_the_choices_appear()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://story/story.tscn");
        StoryScene scene = await Start(runner);
        AssertThat(scene.state).IsEqual("reading");
        AssertThat(scene.GetNode("Choices").GetChildCount()).IsEqual(0);
        await UntilState(scene, "choosing");
        AssertThat(scene.GetNode<Label>("Panel/Text").VisibleCharacters).IsEqual(-1);
        AssertThat(scene.GetNode("Choices").GetChildCount()).IsEqual(2);
        AssertThat(scene.GetNode<Button>("Choices/Choice0").Text).IsEqual("Good evening. Where are you going?");
    }

    [TestCase]
    public async Task A_click_on_the_text_shows_it_whole()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://story/story.tscn");
        StoryScene scene = await Start(runner);
        scene.reveal_all();
        await PhysicsFrames(scene, 2);
        AssertThat(scene.state).IsEqual("choosing");
    }

    [TestCase]
    public async Task A_choice_button_turns_the_page_to_its_node()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://story/story.tscn");
        StoryScene scene = await Start(runner);
        await UntilState(scene, "choosing");
        scene.GetNode<Button>("Choices/Choice1").EmitSignal(BaseButton.SignalName.Pressed);
        AssertThat(scene.state).IsEqual("turning");
        AssertThat(scene.node).OverrideFailureMessage("the page turns first").IsEqual("dock");
        await PhysicsFrames(scene, StoryScene.TurnTicks + 2);
        AssertThat(scene.node).IsEqual("toll");
        AssertThat(scene.story!.History).ContainsExactly("dock_silent");
    }

    [TestCase]
    public async Task Every_line_shown_is_a_checkpoint()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://story/story.tscn");
        StoryScene scene = await Start(runner);
        JsonObject? data = null;
        scene.Checkpoint += saved => data = saved;
        await UntilState(scene, "choosing");
        scene.choose_id("dock_greet");
        await PhysicsFrames(scene, StoryScene.TurnTicks + 2);
        AssertThat(data).IsNotNull();
        AssertThat(JsonData.Text(data!["node"], "")).IsEqual("toll");
        AssertThat(JsonData.Int(data["flags"]!["trust"], 0)).IsEqual(1);
    }

    [TestCase]
    public async Task An_ending_opens_the_ending_panel()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://story/story.tscn");
        StoryScene scene = await Start(runner);
        scene.resume(Story.Replay(scene.graph, new[] { "dock_silent", "toll_true", "launch_row", "fog_hurry", "cross_on" }).ToDict());
        await UntilState(scene, "choosing");
        AssertThat(scene.choose_id("turn_back")).IsTrue();
        await UntilState(scene, "ended");
        AssertThat(scene.state).IsEqual("ended");
        AssertThat(scene.GetNode<CanvasLayer>("EndingMenu").Visible).IsTrue();
        AssertThat(scene.GetNode<Label>("EndingMenu/Box/Title").Text).IsEqual("The Empty Seat");
        AssertThat(scene.found).Contains("return");
    }

    [TestCase]
    public async Task The_history_lists_the_lines_and_the_choices()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://story/story.tscn");
        StoryScene scene = await Start(runner);
        await UntilState(scene, "choosing");
        scene.choose_id("dock_silent");
        await PhysicsFrames(scene, StoryScene.TurnTicks + 2);
        scene.GetNode<Button>("HUD/HistoryButton").EmitSignal(BaseButton.SignalName.Pressed);
        AssertThat(scene.GetNode<CanvasLayer>("History").Visible).IsTrue();
        string text = scene.GetNode<Label>("History/Box/Scroll/Lines").Text;
        AssertThat(text).Contains("Night on the Hensmouth landing.");
        AssertThat(text).Contains("» Nod, and untie the boat.");
        scene.GetNode<Button>("History/Box/CloseButton").EmitSignal(BaseButton.SignalName.Pressed);
        AssertThat(scene.GetNode<CanvasLayer>("History").Visible).IsFalse();
    }
}

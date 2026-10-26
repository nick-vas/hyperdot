namespace SaltmereCrossing.Tests;

using System.Collections.Generic;
using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the beta's fix-performance: the choices are worked out once per line, not every frame, and the
/// buttons shown stay the same while the player thinks.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenChoiceChecksTest
{
    private static async Task PhysicsFrames(Node node, int count)
    {
        for (int i = 0; i < count; i++)
            await node.ToSignal(node.GetTree(), SceneTree.SignalName.PhysicsFrame);
    }

    /// <summary>The story scene as a player sees it: no bot, whatever the command line says.</summary>
    private static async Task<StoryScene> Start()
    {
        var scene = GD.Load<PackedScene>("res://story/story.tscn").Instantiate<StoryScene>();
        scene.Setup(StoryGraph.FromFiles(), LaunchOptions.Parse(System.Array.Empty<string>()), new List<string>());
        ((SceneTree)Engine.GetMainLoop()).Root.AddChild(scene);
        await PhysicsFrames(scene, 2);
        return scene;
    }

    private static async Task UntilChoosing(StoryScene scene)
    {
        for (int i = 0; i < 300 && scene.state != "choosing"; i++)
            await PhysicsFrames(scene, 1);
    }

    [TestCase]
    public async Task Hidden_an_idle_player_costs_no_work()
    {
        StoryScene scene = await Start();
        try
        {
            await UntilChoosing(scene);
            int before = scene.choice_checks;
            Node button = scene.GetNode("Choices/Choice0");
            await PhysicsFrames(scene, 120);
            AssertThat(scene.choice_checks - before).OverrideFailureMessage("worked out at most once more over 120 idle frames").IsLessEqual(1);
            AssertThat(GodotObject.IsInstanceValid(button) && button.IsInsideTree()).OverrideFailureMessage("the same button is still shown").IsTrue();
            AssertThat(scene.GetNode("Choices").GetChildCount()).IsEqual(2);
        }
        finally
        {
            scene.QueueFree();
        }
    }

    [TestCase]
    public async Task Hidden_each_line_works_its_choices_out_once()
    {
        StoryScene scene = await Start();
        try
        {
            await UntilChoosing(scene);
            int before = scene.choice_checks;
            AssertThat(scene.choose_id("dock_greet")).IsTrue();
            await PhysicsFrames(scene, 2);
            await UntilChoosing(scene);
            await PhysicsFrames(scene, 30);
            AssertThat(scene.node).IsEqual("toll");
            AssertThat(scene.choice_checks - before).IsBetween(1, 2);
            AssertThat(scene.GetNode<Button>("Choices/Choice1").Text).IsEqual("Three coppers. The river is high tonight.");
        }
        finally
        {
            scene.QueueFree();
        }
    }
}

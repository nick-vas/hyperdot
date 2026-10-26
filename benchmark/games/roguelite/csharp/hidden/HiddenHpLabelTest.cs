namespace Wickerdeep.Tests;

using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Hidden check for the alpha's fix-architecture: the wick's hp on the HUD follows a hurt, a new floor and a new run.</summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenHpLabelTest
{
    private static async Task PhysicsFrames(Node node, int count)
    {
        for (int i = 0; i < count; i++)
            await node.ToSignal(node.GetTree(), SceneTree.SignalName.PhysicsFrame);
    }

    private static async Task<Game> Start(ISceneRunner runner)
    {
        var game = (Game)runner.Scene();
        await PhysicsFrames(game, 2);
        game.start_run(7);
        await PhysicsFrames(game, 2);
        return game;
    }

    [TestCase]
    public async Task Hidden_the_label_follows_a_hurt()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        var label = game.GetNode<Label>("HUD/HpLabel");
        AssertThat(label.Text).IsEqual("Wick: 5 / 5");
        game.world!.HurtWick(2);
        await PhysicsFrames(game, 2);
        AssertThat(label.Text).IsEqual("Wick: 3 / 5");
    }

    [TestCase]
    public async Task Hidden_the_label_follows_a_new_floor_and_a_new_run()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        var label = game.GetNode<Label>("HUD/HpLabel");
        game.run!.Hp = 2;
        game.start_floor(2);
        await PhysicsFrames(game, 2);
        AssertThat(label.Text).IsEqual("Wick: 2 / 5");
        game.start_run(8);
        await PhysicsFrames(game, 2);
        AssertThat(label.Text).IsEqual("Wick: 5 / 5");
    }
}

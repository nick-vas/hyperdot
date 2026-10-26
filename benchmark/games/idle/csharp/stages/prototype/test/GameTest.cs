namespace Duskhive.Tests;

using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>The game scene: Gather, the producer rows and the buy mode.</summary>
[TestSuite]
[RequireGodotRuntime]
public class GameTest
{
    /// <summary>Waits for whole physics ticks, which is what the game counts in.</summary>
    private static async Task PhysicsFrames(Node node, int count)
    {
        for (int i = 0; i < count; i++)
            await node.ToSignal(node.GetTree(), SceneTree.SignalName.PhysicsFrame);
    }

    private static async Task<Game> Start(ISceneRunner runner)
    {
        var game = (Game)runner.Scene();
        await PhysicsFrames(game, 2);
        return game;
    }

    private static Node Row(Game game, string id) => game.GetNode($"Safe/Column/ProducerPage/List/{id.ToPascalCase()}Row");

    private static void Press(Node button) => button.EmitSignal(BaseButton.SignalName.Pressed);

    [TestCase]
    public async Task Gather_adds_glow()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        Press(game.GetNode("Safe/Column/GatherButton"));
        AssertThat(game.economy.Glow).IsEqual(1.0);
    }

    [TestCase]
    public async Task A_row_buys_its_producer()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        game.add_glow(10.0);
        var button = Row(game, "wick_moth").GetNode<Button>("Box/BuyButton");
        AssertThat(button.Disabled).IsFalse();
        Press(button);
        AssertThat(game.economy.Count("wick_moth")).IsEqual(1);
        AssertThat(Row(game, "wick_moth").GetNode<Label>("Box/Info/DetailLabel").Text).Contains("1 owned");
    }

    [TestCase]
    public async Task A_row_is_disabled_without_the_price()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        await PhysicsFrames(game, 1);
        AssertThat(Row(game, "glow_snail").GetNode<Button>("Box/BuyButton").Disabled).IsTrue();
    }

    [TestCase]
    public async Task The_mode_button_switches_between_one_and_ten()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        var mode = game.GetNode<Button>("Safe/Column/Header/BuyModeButton");
        AssertThat(game.buy_mode).IsEqual(1);
        Press(mode);
        AssertThat(game.buy_mode).IsEqual(10);
        AssertThat(mode.Text).IsEqual("Buy 10");
        game.add_glow(1000.0);
        Press(Row(game, "wick_moth").GetNode("Box/BuyButton"));
        AssertThat(game.economy.Count("wick_moth")).IsEqual(10);
    }

    [TestCase]
    public async Task Production_runs_in_physics_ticks()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        game.economy.SetCount("glow_snail", 3);
        await PhysicsFrames(game, 60);
        AssertThat(game.economy.Glow).IsBetween(11.0, 13.0);
    }
}

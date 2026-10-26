namespace Duskhive.Tests;

using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the alpha's fix-architecture: the producer rows still follow the economy, a buy, the buy mode and
/// a dawn, and a row shows what it is given wherever it sits in the tree.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenRowsFollowTest
{
    private static async Task Frames(Node node, int count)
    {
        for (int i = 0; i < count; i++)
            await node.ToSignal(node.GetTree(), SceneTree.SignalName.ProcessFrame);
    }

    private static async Task<Game> Start(ISceneRunner runner)
    {
        var game = (Game)runner.Scene();
        for (int i = 0; i < 2; i++)
            await game.ToSignal(game.GetTree(), SceneTree.SignalName.PhysicsFrame);
        return game;
    }

    private static Node Row(Game game, string id) => game.GetNode($"Safe/Column/ProducerPage/List/{id.ToPascalCase()}Row");

    [TestCase]
    public async Task Hidden_a_row_lights_up_once_it_can_be_paid_for()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        AssertThat(Row(game, "wick_moth").GetNode<Button>("Box/BuyButton").Disabled).IsTrue();
        game.add_glow(10.0);
        await Frames(game, 2);
        AssertThat(Row(game, "wick_moth").GetNode<Button>("Box/BuyButton").Disabled).IsFalse();
    }

    [TestCase]
    public async Task Hidden_a_row_counts_what_is_bought()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        game.add_glow(1000.0);
        game.buy("glow_snail");
        await Frames(game, 2);
        AssertThat(Row(game, "glow_snail").GetNode<Label>("Box/Info/DetailLabel").Text).Contains("1 owned");
        AssertThat(Row(game, "glow_snail").GetNode<Button>("Box/BuyButton").Text).Contains("138");
    }

    [TestCase]
    public async Task Hidden_a_row_follows_the_buy_mode()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        game.next_mode();
        await Frames(game, 2);
        AssertThat(Row(game, "wick_moth").GetNode<Button>("Box/BuyButton").Text).Contains("Buy 10");
    }

    [TestCase]
    public async Task Hidden_a_dawn_empties_the_rows()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        game.add_glow(1000.0);
        game.buy("wick_moth");
        game.add_glow(1e6);
        game.confirm_dawn();
        await Frames(game, 2);
        AssertThat(Row(game, "wick_moth").GetNode<Label>("Box/Info/DetailLabel").Text).Contains("0 owned");
    }

    [TestCase]
    public async Task Hidden_a_row_alone_shows_what_it_is_given()
    {
        var economy = new Economy(Catalog.FromFiles());
        economy.SetCount("moon_lily", 3);
        var row = new ProducerRow();
        row.Setup(economy.Catalog.Producer("moon_lily")!);
        var tree = (SceneTree)Engine.GetMainLoop();
        tree.Root.AddChild(row);
        try
        {
            row.Refresh(economy, 1);
            await Frames(row, 2);
            AssertThat(row.GetNode<Label>("Box/Info/DetailLabel").Text).Contains("3 owned");
            AssertThat(row.GetNode<Button>("Box/BuyButton").Text).Contains("Buy 1");
        }
        finally
        {
            row.QueueFree();
        }
    }
}

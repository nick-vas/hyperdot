namespace Duskhive.Tests;

using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>The game scene: Gather, the producer rows, the buy mode, the upgrade page and the dawn's panel.</summary>
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
        await PhysicsFrames(game, 1);
        var button = Row(game, "wick_moth").GetNode<Button>("Box/BuyButton");
        AssertThat(button.Disabled).IsFalse();
        Press(button);
        AssertThat(game.economy.Count("wick_moth")).IsEqual(1);
        await PhysicsFrames(game, 1);
        AssertThat(Row(game, "wick_moth").GetNode<Label>("Box/Info/DetailLabel").Text).Contains("1");
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
    public async Task The_mode_button_steps_through_one_ten_and_max()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        Node mode = game.GetNode("Safe/Column/Header/BuyModeButton");
        AssertThat(game.buy_mode).IsEqual(1);
        Press(mode);
        AssertThat(game.buy_mode).IsEqual(10);
        game.add_glow(1000.0);
        Press(Row(game, "wick_moth").GetNode("Box/BuyButton"));
        AssertThat(game.economy.Count("wick_moth")).IsEqual(10);
        Press(mode);
        AssertThat(game.buy_mode).IsEqual(0);
        Press(mode);
        AssertThat(game.buy_mode).IsEqual(1);
    }

    [TestCase]
    public async Task The_upgrade_page_shows_what_is_on_offer()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        Press(game.GetNode("Safe/Column/Bar/UpgradesTab"));
        AssertThat(game.GetNode<Control>("Safe/Column/UpgradePage").Visible).IsTrue();
        AssertThat(game.GetNode<Control>("Safe/Column/ProducerPage").Visible).IsFalse();
        await PhysicsFrames(game, 1);
        AssertThat(game.GetNode<Control>("Safe/Column/UpgradePage/List/WarmHandsRow").Visible).IsTrue();
        AssertThat(game.GetNode<Control>("Safe/Column/UpgradePage/List/TwinWicksRow").Visible).IsFalse();
    }

    [TestCase]
    public async Task The_dawn_asks_first()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        var dawn = game.GetNode<Button>("Safe/Column/Bar/DawnButton");
        await PhysicsFrames(game, 1);
        AssertThat(dawn.Disabled).IsTrue();
        game.add_glow(4e6);
        await PhysicsFrames(game, 1);
        AssertThat(dawn.Disabled).IsFalse();
        Press(dawn);
        AssertThat(game.GetNode<Control>("DawnPanel").Visible).IsTrue();
        Press(game.GetNode("DawnPanel/Box/ConfirmButton"));
        AssertThat(game.GetNode<Control>("DawnPanel").Visible).IsFalse();
        AssertThat(game.economy.Embers).IsEqual(2.0);
        AssertThat(game.economy.Glow).IsEqual(0.0);
    }

    [TestCase]
    public async Task Time_away_is_shown_and_collected()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        game.show_welcome(7500.0, 12345.0);
        await PhysicsFrames(game, 1);
        AssertThat(game.GetNode<Control>("WelcomePanel").Visible).IsTrue();
        AssertThat(game.GetNode<Label>("WelcomePanel/Box/MessageLabel").Text).Contains("2 h 05 min");
        AssertThat(game.GetNode<Label>("WelcomePanel/Box/MessageLabel").Text).Contains("12.3K");
        Press(game.GetNode("WelcomePanel/Box/CollectButton"));
        AssertThat(game.GetNode<Control>("WelcomePanel").Visible).IsFalse();
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

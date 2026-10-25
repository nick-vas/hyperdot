namespace Bramblegate.Tests;

using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>The game scene: a battle fed ticks on the field, building from the HUD, the next wave, and the result panel.</summary>
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

    /// <summary>The game scene on the Meadow, seed 7.</summary>
    private static async Task<Game> Start(ISceneRunner runner)
    {
        var game = (Game)runner.Scene();
        await PhysicsFrames(game, 2);
        game.start_map(1, 7);
        await PhysicsFrames(game, 2);
        return game;
    }

    [TestCase]
    public async Task A_map_starts_with_its_sap_and_seeds()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        AssertThat(game.level).IsEqual(1);
        AssertThat(game.phase).IsEqual("Build");
        AssertThat(game.gold).IsEqual(120);
        AssertThat(game.GetNode<Label>("HUD/GoldLabel").Text).IsEqual("Sap: 120");
        AssertThat(game.GetNode<Label>("HUD/LivesLabel").Text).IsEqual("Seeds: 20");
    }

    [TestCase]
    public async Task A_tower_button_then_a_cell_builds_that_tower()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        game.GetNode<Button>("HUD/Towers/PuffButton").EmitSignal(BaseButton.SignalName.Pressed);
        AssertThat(game.building).IsEqual("puff");
        AssertThat(game.place_at(5, 2)).IsTrue();
        AssertThat(game.battle!.Towers[new Vector2I(5, 2)].Id).IsEqual("puff");
        AssertThat(game.GetNode<Label>("HUD/GoldLabel").Text).IsEqual("Sap: 50");
    }

    [TestCase]
    public async Task A_built_tower_can_be_selected_and_sold()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        game.place_at(5, 2);
        AssertThat(game.place_at(5, 2)).OverrideFailureMessage("a second click selects it").IsFalse();
        AssertThat(game.selected).IsEqual(new Vector2I(5, 2));
        AssertThat(game.GetNode<Button>("HUD/SellButton").Disabled).IsFalse();
        game.GetNode<Button>("HUD/SellButton").EmitSignal(BaseButton.SignalName.Pressed);
        AssertThat(game.battle!.Towers.Has(new Vector2I(5, 2))).IsFalse();
        AssertThat(game.gold).IsGreater(120 - 50);
    }

    [TestCase]
    public async Task Next_wave_starts_the_wave_at_once()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        game.GetNode<Button>("HUD/NextWaveButton").EmitSignal(BaseButton.SignalName.Pressed);
        AssertThat(game.wave).IsEqual(1);
        AssertThat(game.phase).IsEqual("Wave");
        await PhysicsFrames(game, 3);
        AssertThat(game.GetNode<Label>("HUD/WaveLabel").Text).IsEqual("Wave 1 / 4");
    }

    [TestCase]
    public async Task A_lost_map_shows_the_result_panel()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        game.battle!.Lives = 1;
        game.speed = 8;
        game.next_wave();
        for (int i = 0; i < 1200; i++)
        {
            await PhysicsFrames(game, 1);
            if (game.state == "over")
                break;
        }
        AssertThat(game.state).IsEqual("over");
        AssertThat(game.battle.Phase).IsEqual(Phase.Lost);
        AssertThat(game.GetNode<CanvasLayer>("ResultMenu").Visible).IsTrue();
        AssertThat(game.GetNode<Button>("ResultMenu/Box/NextButton").Visible).IsFalse();
    }
}

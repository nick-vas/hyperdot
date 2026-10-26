namespace Glimmerpit.Tests;

using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>The game scene on its own: a local match against three bots, the HUD and pause.</summary>
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

    [TestCase]
    public async Task The_player_holds_slot_one_against_three_bots()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        AssertThat(game.my_slot).IsEqual(0);
        AssertThat(game.mode).IsEqual("local");
        AssertThat(game.GetNode<Label>("HUD/Scores/Slot0Label").Text).IsEqual("P1 (you): 0");
        AssertThat(game.GetNode<Label>("HUD/Scores/Slot1Label").Text).IsEqual("P2 (bot): 0");
    }

    [TestCase]
    public async Task The_round_starts_after_the_warmup()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        AssertThat(game.state).IsEqual("warmup");
        await PhysicsFrames(game, ArenaMatch.WarmupTicks + 4);
        AssertThat(game.state).IsEqual("round");
        AssertThat(game.GetNode<Label>("HUD/RoundLabel").Text).IsEqual("Round 1");
        AssertThat(game.GetNode<Label>("HUD/HealthLabel").Text).IsEqual("Health: 5");
    }

    [TestCase]
    public async Task Pause_stops_the_local_match()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        await PhysicsFrames(game, ArenaMatch.WarmupTicks + 4);
        game.GetNode<Button>("HUD/PauseButton").EmitSignal(BaseButton.SignalName.Pressed);
        AssertThat(game.GetTree().Paused).IsTrue();
        AssertThat(game.GetNode<CanvasLayer>("PauseMenu").Visible).IsTrue();
        game.GetNode<Button>("PauseMenu/ResumeButton").EmitSignal(BaseButton.SignalName.Pressed);
        AssertThat(game.GetTree().Paused).IsFalse();
    }
}

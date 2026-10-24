namespace Lanternfen.Tests;

using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>The game scene: a duel paced on the table, the player's hand, End turn and the result panel.</summary>
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

    /// <summary>The game scene with a duel against rival 1, seed 7, waiting in the player's first Main phase.</summary>
    private static async Task<Game> Start(ISceneRunner runner)
    {
        var game = (Game)runner.Scene();
        await PhysicsFrames(game, 2);
        game.start_rival(1, 7);
        await PhysicsFrames(game, 30);
        return game;
    }

    private static int Playable(Game game)
    {
        for (int index = 0; index < game.duel!.Keepers[0].Hand.Count; index++)
        {
            if (game.duel.CanPlay(0, index))
                return index;
        }
        return -1;
    }

    [TestCase]
    public async Task The_duel_waits_for_the_player_in_main()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        AssertThat(game.phase).IsEqual("Main");
        AssertThat(game.active).IsEqual(0);
        AssertThat(game.GetNode("HUD/Hand").GetChildCount()).IsEqual(game.duel!.Keepers[0].Hand.Count);
        AssertThat(game.GetNode<Button>("HUD/EndTurnButton").Disabled).IsFalse();
        await PhysicsFrames(game, 60);
        AssertThat(game.phase).OverrideFailureMessage("still waiting").IsEqual("Main");
    }

    [TestCase]
    public async Task A_card_button_plays_its_card()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        int index = Playable(game);
        AssertThat(index).OverrideFailureMessage("something to play").IsGreaterEqual(0);
        int before = game.duel!.Keepers[0].Hand.Count;
        game.GetNode<Button>($"HUD/Hand/Card{index}").EmitSignal(BaseButton.SignalName.Pressed);
        AssertThat(game.duel.Keepers[0].Hand.Count).IsEqual(before - 1);
        AssertThat(game.GetNode("HUD/Hand").GetChildCount()).IsEqual(before - 1);
    }

    [TestCase]
    public async Task End_turn_passes_to_the_rival_and_back()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        game.GetNode<Button>("HUD/EndTurnButton").EmitSignal(BaseButton.SignalName.Pressed);
        AssertThat(game.phase).IsNotEqual("Main");
        for (int i = 0; i < 600; i++)
        {
            await PhysicsFrames(game, 1);
            if (game.active == 0 && game.phase == "Main")
                break;
        }
        AssertThat(game.turn).IsEqual(3);
        AssertThat(game.phase).IsEqual("Main");
    }

    [TestCase]
    public async Task A_lost_duel_shows_the_result_panel()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        game.duel!.Keepers[0].Light = 1;
        game.duel.Keepers[1].Row[0] = new Wisp("lantern_heron", 5, 5);
        game.end_turn();
        for (int i = 0; i < 600; i++)
        {
            await PhysicsFrames(game, 1);
            if (game.state == "over")
                break;
        }
        AssertThat(game.state).IsEqual("over");
        AssertThat(game.duel.Winner).IsEqual(1);
        AssertThat(game.GetNode<CanvasLayer>("ResultMenu").Visible).IsTrue();
        AssertThat(game.GetNode<Button>("ResultMenu/Box/NextButton").Visible).IsFalse();
    }
}

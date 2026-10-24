namespace Lanternfen.Tests;

using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the beta's fix-performance: the AI is asked for the player's suggestion once per change, not every
/// frame, and the suggestion is still the card the AI would play.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenSuggestChecksTest
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
    public async Task Hidden_an_idle_turn_asks_at_most_once()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        AssertThat(game.phase).IsEqual("Main");
        int before = game.suggest_checks;
        await PhysicsFrames(game, 120);
        AssertThat(game.suggest_checks - before).IsLessEqual(1);
    }

    [TestCase]
    public async Task Hidden_a_play_asks_once_or_twice()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        game.duel!.Keepers[0].Kindling = 6;
        int index = Playable(game);
        AssertThat(index).IsGreaterEqual(0);
        int before = game.suggest_checks;
        AssertThat(game.play_card(index)).IsTrue();
        await PhysicsFrames(game, 10);
        AssertThat(game.suggest_checks - before).IsBetween(1, 2);
    }

    [TestCase]
    public async Task Hidden_the_suggestion_is_still_shown()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        game.duel!.Keepers[0].Kindling = 6;
        game.play_card(Playable(game));
        await PhysicsFrames(game, 2);
        AssertThat(game.suggested).IsEqual(new Ai().Choose(game.duel, 0));
        if (game.suggested >= 0)
            AssertThat(game.GetNode<Button>($"HUD/Hand/Card{game.suggested}").Modulate).IsEqual(new Color(1f, 0.92f, 0.55f));
    }

    [TestCase]
    public async Task Hidden_the_rivals_turn_asks_little()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        int before = game.suggest_checks;
        game.end_turn();
        for (int i = 0; i < 900; i++)
        {
            await PhysicsFrames(game, 1);
            if (game.turn == 3 && game.phase == "Main")
                break;
        }
        AssertThat(game.turn).IsEqual(3);
        AssertThat(game.suggest_checks - before).IsLessEqual(3);
    }
}

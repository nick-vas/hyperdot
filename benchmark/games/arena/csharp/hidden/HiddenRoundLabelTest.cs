namespace Glimmerpit.Tests;

using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the alpha's fix-architecture: the HUD's round label still follows the round, kept up to date by
/// the game rather than looked up every frame.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenRoundLabelTest
{
    private static async Task PhysicsFrames(Node node, int count)
    {
        for (int i = 0; i < count; i++)
            await node.ToSignal(node.GetTree(), SceneTree.SignalName.PhysicsFrame);
    }

    private static async Task<Game> Start(ISceneRunner runner)
    {
        var game = (Game)runner.Scene();
        await PhysicsFrames(game, ArenaMatch.WarmupTicks + 4);
        return game;
    }

    private static void OutAllButOne(Game game)
    {
        foreach (int slot in new[] { 1, 2, 3 })
        {
            for (int i = 0; i < ArenaMatch.Hp; i++)
                game.server!.Arena.DealDamage(0, slot);
        }
    }

    [TestCase]
    public async Task Hidden_the_label_shows_the_first_round()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        AssertThat(game.state).IsEqual("round");
        AssertThat(game.GetNode<Label>("HUD/RoundLabel").Text).IsEqual("Round 1");
    }

    [TestCase]
    public async Task Hidden_the_label_follows_the_next_round()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        OutAllButOne(game);
        await PhysicsFrames(game, ArenaMatch.IntermissionTicks + 6);
        AssertThat(game.round_number).IsEqual(2);
        AssertThat(game.GetNode<Label>("HUD/RoundLabel").Text).IsEqual("Round 2");
    }

    [TestCase]
    public async Task Hidden_the_label_follows_a_new_match()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        OutAllButOne(game);
        await PhysicsFrames(game, ArenaMatch.IntermissionTicks + 6);
        game.start_match(7);
        await PhysicsFrames(game, 3);
        AssertThat(game.GetNode<Label>("HUD/RoundLabel").Text).IsEqual("Round 0");
        await PhysicsFrames(game, ArenaMatch.WarmupTicks + 4);
        AssertThat(game.GetNode<Label>("HUD/RoundLabel").Text).IsEqual("Round 1");
    }
}

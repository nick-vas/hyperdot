namespace Cinderloop.Tests;

using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the alpha's fix-architecture: the HUD's lap counter follows the player's laps, a restart and a new
/// track, as it did before.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenLapLabelTest
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
        return game;
    }

    private static string LapText(Game game) => game.GetNode<Label>("HUD/LapLabel").Text;

    /// <summary>The player's car driven by a full-pace AI through its first lap.</summary>
    private static async Task FirstLap(Game game)
    {
        game.race!.Drivers[0] = new AiDriver();
        game.state = "racing";
        while (game.race.Trackers[0].Laps < 1)
            await PhysicsFrames(game, 5);
    }

    [TestCase]
    public async Task Hidden_the_lap_counter_starts_at_lap_1()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        AssertThat(LapText(game)).IsEqual("Lap 1/3");
    }

    [TestCase]
    public async Task Hidden_the_lap_counter_follows_a_lap()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        await FirstLap(game);
        await PhysicsFrames(game, 1);
        AssertThat(LapText(game)).IsEqual("Lap 2/3");
    }

    [TestCase]
    public async Task Hidden_a_restart_and_a_new_track_reset_it()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        await FirstLap(game);
        game.restart();
        await PhysicsFrames(game, 1);
        AssertThat(LapText(game)).IsEqual("Lap 1/3");
        game.start_track(2);
        await PhysicsFrames(game, 1);
        AssertThat(LapText(game)).IsEqual("Lap 1/2");
    }

    [TestCase]
    public async Task Hidden_the_counter_is_right_without_the_cars_drawn()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        foreach (Node view in game.GetNode("Cars").GetChildren())
            view.ProcessMode = Node.ProcessModeEnum.Disabled;
        await FirstLap(game);
        await PhysicsFrames(game, 1);
        AssertThat(LapText(game)).IsEqual("Lap 2/3");
    }
}

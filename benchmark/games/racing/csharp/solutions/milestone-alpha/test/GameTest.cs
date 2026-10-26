namespace Cinderloop.Tests;

using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>The race scene: the countdown, the player's car on the keys, the HUD, the ghost after a lap, and pause.</summary>
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

    private static int Seconds(double s) => Maths.RoundI(s * Engine.PhysicsTicksPerSecond);

    private static async Task<Game> Start(ISceneRunner runner)
    {
        var game = (Game)runner.Scene();
        await PhysicsFrames(game, 2);
        return game;
    }

    [AfterTest]
    public void Release()
    {
        Input.ActionRelease("accelerate");
        Input.ActionRelease("steer_right");
        ((SceneTree)Engine.GetMainLoop()).Paused = false;
    }

    [TestCase]
    public async Task The_race_waits_for_the_countdown()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        AssertThat(game.state).IsEqual("countdown");
        Vector2 start = game.race!.Cars[1].Position;
        await PhysicsFrames(game, Seconds(1.0));
        AssertThat(game.race.Cars[1].Position).OverrideFailureMessage("nobody moves before the start").IsEqual(start);
        await PhysicsFrames(game, Seconds(2.5));
        AssertThat(game.state).IsEqual("racing");
        AssertThat(game.race.Cars[1].Position).IsNotEqual(start);
    }

    [TestCase]
    public async Task The_accelerate_key_drives_the_players_car()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        await PhysicsFrames(game, Seconds(3.0) + 1);
        Input.ActionPress("accelerate");
        await PhysicsFrames(game, Seconds(1.0));
        AssertThat(game.race!.Cars[0].Speed).IsGreater(200.0);
    }

    [TestCase]
    public async Task The_hud_shows_the_lap_and_the_place()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        AssertThat(game.GetNode<Label>("HUD/LapLabel").Text).IsEqual("Lap 1/3");
        AssertThat(game.GetNode<Label>("HUD/PositionLabel").Text).IsEqual("P4/4");
        AssertThat(game.GetNode<Label>("HUD/TrackLabel").Text).IsEqual("Ashfall Oval");
    }

    [TestCase]
    public async Task After_a_lap_the_ghost_drives_it_again()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        game.race!.Drivers[0] = new AiDriver();
        game.state = "racing";
        while (game.race.Trackers[0].Laps < 1)
            await PhysicsFrames(game, 10);
        AssertThat(game.lap).IsEqual(2);
        AssertThat(game.GetNode<Node2D>("Ghost").Visible).IsTrue();
        AssertThat(game.GetNode<Label>("HUD/LapLabel").Text).IsEqual("Lap 2/3");
    }

    [TestCase]
    public async Task The_pause_menu_stops_the_race()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        game.GetNode<Button>("HUD/PauseButton").EmitSignal(BaseButton.SignalName.Pressed);
        AssertThat(game.GetTree().Paused).IsTrue();
        game.GetNode<Button>("PauseMenu/ResumeButton").EmitSignal(BaseButton.SignalName.Pressed);
        AssertThat(game.GetTree().Paused).IsFalse();
    }
}

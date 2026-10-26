namespace Wickerdeep.Tests;

using System.Collections.Generic;
using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>The game scene: a floor drawn and played from the input, the HUD, the next floor, and the panel at the end of a run.</summary>
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

    /// <summary>The game scene with a run of seed 7 on floor 1.</summary>
    private static async Task<Game> Start(ISceneRunner runner)
    {
        var game = (Game)runner.Scene();
        await PhysicsFrames(game, 2);
        game.start_run(7);
        await PhysicsFrames(game, 2);
        return game;
    }

    [TestCase]
    public async Task A_run_starts_on_floor_1()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        AssertThat(game.floor_number).IsEqual(1);
        AssertThat(game.state).IsEqual("playing");
        AssertThat(game.wick_cell).IsEqual(game.world!.Dungeon.Start);
        AssertThat(game.GetNode<Label>("HUD/FloorLabel").Text).IsEqual("Floor 1: The Wax Cellar");
        AssertThat(game.GetNode<Label>("HUD/HpLabel").Text).IsEqual("Wick: 5 / 5");
    }

    [TestCase]
    public async Task The_wick_walks_where_the_player_holds()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        Vector2I start = game.wick_cell;
        Vector2I dir = Vector2I.Zero;
        foreach (Vector2I candidate in Dungeon.Dirs)
        {
            if (game.world!.Dungeon.IsFloor(start + candidate))
            {
                dir = candidate;
                break;
            }
        }
        var actions = new Dictionary<Vector2I, string>
        {
            [Vector2I.Up] = "move_up",
            [Vector2I.Right] = "move_right",
            [Vector2I.Down] = "move_down",
            [Vector2I.Left] = "move_left",
        };
        Input.ActionPress(actions[dir]);
        await PhysicsFrames(game, 3);
        Input.ActionRelease(actions[dir]);
        AssertThat(game.wick_cell).IsEqual(start + dir);
    }

    [TestCase]
    public async Task A_hurt_shows_on_the_hud()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        game.world!.HurtWick(2);
        AssertThat(game.GetNode<Label>("HUD/HpLabel").Text).IsEqual("Wick: 3 / 5");
    }

    [TestCase]
    public async Task The_open_stairs_lead_to_floor_2()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        World world = game.world!;
        foreach (Actor enemy in new List<Actor>(world.Enemies))
        {
            enemy.Hp = 1;
            world.Wick.AttackCooldown = 0;
            world.Wick.Facing = Vector2I.Zero;
            world.Place(enemy, world.Wick.Cell + Vector2I.Up);
            world.Step(Vector2I.Zero, true);
        }
        AssertThat(world.StairsOpen).IsTrue();
        AssertThat(game.GetNode<Label>("HUD/EnemiesLabel").Text).IsEqual("The stairs are open");
        world.Wick.Cell = world.Dungeon.Stairs;
        await PhysicsFrames(game, Game.NextFloorTicks + 5);
        AssertThat(game.floor_number).IsEqual(2);
        AssertThat(game.GetNode<Label>("HUD/FloorLabel").Text).IsEqual("Floor 2: The Ossuary");
    }

    [TestCase]
    public async Task A_snuffed_wick_ends_the_run_with_the_panel()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        game.world!.Wick.Hp = 1;
        game.world.HurtWick(1);
        await PhysicsFrames(game, 2);
        AssertThat(game.state).IsEqual("over");
        AssertThat(game.GetNode<CanvasLayer>("RunOverMenu").Visible).IsTrue();
        AssertThat(game.GetNode<Label>("RunOverMenu/Box/Title").Text).IsEqual("The wick is out");
        game.GetNode<Button>("RunOverMenu/Box/AgainButton").EmitSignal(BaseButton.SignalName.Pressed);
        AssertThat(game.state).IsEqual("playing");
        AssertThat(game.floor_number).IsEqual(1);
    }
}

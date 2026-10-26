namespace Bramblegate.Tests;

using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Hidden check for the alpha's fix-architecture: the sap line still follows a placement, a fallen pest, a sale and a new map.</summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenGoldLabelTest
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
        game.start_map(1, 7);
        await PhysicsFrames(game, 2);
        return game;
    }

    private static string Label(Game game) => game.GetNode<Label>("HUD/GoldLabel").Text;

    [TestCase]
    public async Task Hidden_a_placement_shows()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        game.place_at(3, 3);
        await PhysicsFrames(game, 2);
        AssertThat(Label(game)).IsEqual("Sap: 70");
    }

    [TestCase]
    public async Task Hidden_a_fallen_pest_shows()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        game.place_at(3, 3);
        Enemy pest = game.battle!.SpawnAt("aphid", new Vector2I(3, 4));
        pest.Speed = 0.0;
        pest.Hp = 1;
        for (int i = 0; i < 60; i++)
        {
            await PhysicsFrames(game, 1);
            if (!pest.Alive)
                break;
        }
        await PhysicsFrames(game, 2);
        AssertThat(pest.Alive).IsFalse();
        AssertThat(Label(game)).IsEqual($"Sap: {70 + game.Catalog.Enemies["aphid"].Reward}");
    }

    [TestCase]
    public async Task Hidden_a_sale_and_a_new_map_show()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        game.place_at(3, 3);
        game.place_at(3, 3);
        game.sell_selected();
        await PhysicsFrames(game, 2);
        AssertThat(Label(game)).IsEqual($"Sap: {game.battle!.Gold}");
        AssertThat(game.battle.Gold).IsGreater(70);
        game.start_map(2, 3);
        await PhysicsFrames(game, 2);
        AssertThat(Label(game)).IsEqual($"Sap: {game.Catalog.MapAt(2)!.Gold}");
    }
}

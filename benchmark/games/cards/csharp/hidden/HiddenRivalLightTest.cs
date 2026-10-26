namespace Lanternfen.Tests;

using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Hidden check for the alpha's fix-architecture: the HUD's rival light follows a Flare, a Clash and a new duel.</summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenRivalLightTest
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

    private static string LightText(Game game) => game.GetNode<Label>("HUD/RivalLight").Text;

    [TestCase]
    public async Task Hidden_the_rival_light_follows_a_flare()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        AssertThat(game.phase).IsEqual("Main");
        game.duel!.Keepers[0].Hand.Add("flare");
        game.duel.Keepers[0].Kindling = 2;
        AssertThat(game.play_card(game.duel.Keepers[0].Hand.Count - 1)).IsTrue();
        await PhysicsFrames(game, 2);
        AssertThat(LightText(game)).IsEqual("Light: 9");
    }

    [TestCase]
    public async Task Hidden_the_rival_light_follows_a_clash()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        game.duel!.Keepers[0].Row[0] = new Wisp("lantern_heron", 5, 5);
        game.end_turn();
        await PhysicsFrames(game, 30);
        AssertThat(game.duel.Keepers[1].Light).IsEqual(7);
        AssertThat(LightText(game)).IsEqual("Light: 7");
    }

    [TestCase]
    public async Task Hidden_a_new_duel_shows_its_rivals_light()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        game.start_rival(2, 3);
        await PhysicsFrames(game, 2);
        AssertThat(LightText(game)).IsEqual("Light: 15");
    }
}

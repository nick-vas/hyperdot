namespace Duskhive.Tests;

using System;
using System.IO;
using System.Text.Json.Nodes;
using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Main: the save read at start and the time away paid, and the save written again.</summary>
[TestSuite]
[RequireGodotRuntime]
public class MainTest
{
    private string _path = "";
    private double _now = 1761000000.0;
    private Main? _main;

    [BeforeTest]
    public void MakePath()
    {
        _path = Path.Combine(Path.GetTempPath(), $"duskhive-main-{Guid.NewGuid():N}.json");
        _now = 1761000000.0;
    }

    [AfterTest]
    public void CleanUp()
    {
        _main?.QueueFree();
        _main = null;
        File.Delete(_path);
    }

    /// <summary>Main with the test's save file and clock, as Main is set up before it enters the tree.</summary>
    private async Task<Main> Start()
    {
        var main = GD.Load<PackedScene>("res://main.tscn").Instantiate<Main>();
        main.save_path = _path;
        main.clock = () => _now;
        var tree = (SceneTree)Engine.GetMainLoop();
        tree.Root.AddChild(main);
        _main = main;
        await main.ToSignal(tree, SceneTree.SignalName.PhysicsFrame);
        return main;
    }

    private void Write(JsonObject economy, double savedAt)
    {
        new SaveStore(_path).Write(new SaveData { Economy = economy, SavedAt = savedAt });
    }

    [TestCase]
    public async Task A_first_start_is_a_new_hive()
    {
        Main main = await Start();
        AssertThat(main.game.economy.Glow).IsEqual(0.0);
        AssertThat(main.GetNode<Control>("Game/WelcomePanel").Visible).IsFalse();
    }

    [TestCase]
    public async Task Time_away_is_paid_and_shown()
    {
        Write(new JsonObject { ["glow"] = 10.0, ["owned"] = new JsonObject { ["glow_snail"] = 5 } }, _now - 3600.0);
        Main main = await Start();
        AssertThat(main.game.economy.Glow).IsEqualApprox(10.0 + 3600.0 * 20.0, 1.0);
        AssertThat(main.GetNode<Control>("Game/WelcomePanel").Visible).IsTrue();
    }

    [TestCase]
    public async Task The_save_keeps_the_game_and_the_time()
    {
        Main main = await Start();
        main.game.add_glow(500.0);
        _now += 60.0;
        AssertThat(main.save_now()).IsTrue();
        SaveData data = new SaveStore(_path).Read();
        AssertThat(JsonData.Number(data.Economy["glow"], -1.0)).IsEqual(main.game.economy.Glow);
        AssertThat(data.SavedAt).IsEqual(_now);
    }

    [TestCase]
    public async Task A_dawn_is_saved_at_once()
    {
        Main main = await Start();
        main.game.add_glow(1e6);
        main.game.economy.Dawn();
        SaveData data = new SaveStore(_path).Read();
        AssertThat(JsonData.Number(data.Economy["prestige"]?["embers"], -1.0)).IsEqual(1.0);
    }
}

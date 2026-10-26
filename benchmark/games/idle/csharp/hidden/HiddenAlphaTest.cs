namespace Duskhive.Tests;

using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden acceptance for the prototype-to-alpha milestone: the Moon Lily, Buy max, upgrades on their own page, the
/// dawn, and a save that Main reads at start, paying the time away up to eight hours and nothing for a clock set back.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenAlphaTest
{
    private readonly List<Main> _opened = new();
    private string _path = "";
    private double _now;

    [BeforeTest]
    public void MakePath()
    {
        _path = Path.Combine(Path.GetTempPath(), $"duskhive-hidden-alpha-{Guid.NewGuid():N}.json");
        _now = 1761000000.0;
    }

    [AfterTest]
    public void CleanUp()
    {
        foreach (Main main in _opened)
        {
            if (GodotObject.IsInstanceValid(main) && main.IsInsideTree())
                main.QueueFree();
        }
        _opened.Clear();
        File.Delete(_path);
    }

    private async Task<Main> Open()
    {
        var main = GD.Load<PackedScene>("res://main.tscn").Instantiate<Main>();
        main.save_path = _path;
        main.clock = () => _now;
        var tree = (SceneTree)Engine.GetMainLoop();
        tree.Root.AddChild(main);
        _opened.Add(main);
        await main.ToSignal(tree, SceneTree.SignalName.PhysicsFrame);
        main.game.SetPhysicsProcess(false);
        return main;
    }

    private static void Close(Main main)
    {
        main.GetParent().RemoveChild(main);
        main.QueueFree();
    }

    [TestCase]
    public void Hidden_four_producers_and_their_upgrades()
    {
        Catalog catalog = Catalog.FromFiles();
        var ids = new List<string>();
        foreach (ProducerData p in catalog.Producers)
            ids.Add(p.Id);
        AssertThat(string.Join(",", ids.GetRange(0, Math.Min(4, ids.Count)))).IsEqual("wick_moth,glow_snail,firefly_choir,moon_lily");
        var economy = new Economy(catalog);
        economy.SetCount("wick_moth", 10);
        economy.Glow = 1e4;
        double before = economy.ProducerRate("wick_moth");
        AssertThat(economy.BuyUpgrade("twin_wicks")).IsTrue();
        AssertThat(economy.ProducerRate("wick_moth")).IsEqualApprox(before * 2.0, 1e-9);
    }

    [TestCase]
    public void Hidden_buy_max()
    {
        var economy = new Economy(Catalog.FromFiles()) { Glow = 100.0 };
        AssertThat(economy.MaxAffordable("wick_moth")).IsEqual(6);
        AssertThat(economy.BuyMax("wick_moth")).IsEqual(6);
    }

    [TestCase]
    public void Hidden_the_dawn()
    {
        var economy = new Economy(Catalog.FromFiles());
        economy.Earn(9e6);
        economy.Buy("wick_moth");
        AssertThat(economy.Dawn()).IsEqual(3.0);
        AssertThat(economy.Glow).IsEqual(0.0);
        AssertThat(economy.Owned.Count).IsEqual(0);
        economy.SetCount("wick_moth", 2);
        AssertThat(economy.Rate()).IsEqualApprox(2 * 0.5 * 1.3, 1e-9);
    }

    [TestCase]
    public async Task Hidden_a_save_comes_back_with_the_time_away()
    {
        Main main = await Open();
        main.game.economy.SetCount("glow_snail", 5);
        main.game.economy.Embers = 2.0;
        main.game.economy.Glow = 1e20;
        main.save_now();
        Close(main);
        _now += 3600.0;
        main = await Open();
        AssertThat(main.game.economy.Count("glow_snail")).IsEqual(5);
        AssertThat(main.game.economy.Embers).IsEqual(2.0);
        AssertThat(Numbers.Close(main.game.economy.Glow, 1e20 + 3600.0 * 20.0 * 1.2, 1e-12)).IsTrue();
        AssertThat(main.GetNode<Control>("Game/WelcomePanel").Visible).IsTrue();
    }

    [TestCase]
    public async Task Hidden_time_away_is_capped_and_a_clock_set_back_pays_nothing()
    {
        Main main = await Open();
        main.game.economy.SetCount("glow_snail", 5);
        main.save_now();
        Close(main);
        _now -= 86400.0;
        main = await Open();
        AssertThat(main.game.economy.Glow).IsEqualApprox(0.0, 1.0);
        Close(main);
        _now += 40.0 * 86400.0;
        main = await Open();
        AssertThat(main.game.economy.Glow).IsEqualApprox(28800.0 * 20.0, 1.0);
    }

    [TestCase]
    public async Task Hidden_settings_open_and_close()
    {
        Main main = await Open();
        var tree = (SceneTree)Engine.GetMainLoop();
        main.GetNode("Game/Safe/Column/Bar/SettingsButton").EmitSignal(BaseButton.SignalName.Pressed);
        await main.ToSignal(tree, SceneTree.SignalName.ProcessFrame);
        AssertThat(main.GetNodeOrNull("Settings") != null).OverrideFailureMessage("a Settings screen").IsTrue();
        main.GetNode("Settings/Safe/Box/BackButton").EmitSignal(BaseButton.SignalName.Pressed);
        for (int i = 0; i < 2; i++)
            await main.ToSignal(tree, SceneTree.SignalName.ProcessFrame);
        AssertThat(main.GetNodeOrNull("Settings") == null).OverrideFailureMessage("Back closes it").IsTrue();
        AssertThat(main.GetNode<Control>("Game").Visible).IsTrue();
    }
}

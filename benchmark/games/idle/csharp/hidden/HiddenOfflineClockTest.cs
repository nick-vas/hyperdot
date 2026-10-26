namespace Duskhive.Tests;

using System;
using System.IO;
using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the alpha's fix-bug: time away through Main with a clock the test sets. A clock set back pays
/// nothing, the time paid is capped, and a clock put right again pays only for the time really away, once.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenOfflineClockTest
{
    private const double Day = 86400.0;

    private readonly System.Collections.Generic.List<Main> _opened = new();
    private string _path = "";
    private double _now;

    [BeforeTest]
    public void MakePath()
    {
        _path = Path.Combine(Path.GetTempPath(), $"duskhive-hidden-clock-{Guid.NewGuid():N}.json");
        _now = 1761000000.0;
    }

    [AfterTest]
    public void RemoveFile()
    {
        // A check that failed halfway leaves its game open: close it, so it cannot save over the next test's.
        foreach (Main main in _opened)
        {
            if (GodotObject.IsInstanceValid(main) && main.IsInsideTree())
                main.QueueFree();
        }
        _opened.Clear();
        File.Delete(_path);
    }

    /// <summary>Starts the game as a player opening it at the current clock; production stops after the first tick.</summary>
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
        main.save_now();
        main.GetParent().RemoveChild(main);
        main.QueueFree();
    }

    /// <summary>A hive of 5 glow snails (20 glow a second) saved at the current clock, with no glow.</summary>
    private void SavedHive()
    {
        var economy = new Economy(Catalog.FromFiles());
        economy.SetCount("glow_snail", 5);
        new SaveStore(_path).Write(new SaveData { Economy = economy.ToDict(), SavedAt = _now });
    }

    [TestCase]
    public async Task Hidden_an_hour_away_pays_an_hour()
    {
        SavedHive();
        _now += 3600.0;
        Main main = await Open();
        AssertThat(main.game.economy.Glow).IsEqualApprox(3600.0 * 20.0, 1.0);
        Close(main);
    }

    [TestCase]
    public async Task Hidden_a_clock_set_back_pays_nothing()
    {
        SavedHive();
        _now -= Day;
        Main main = await Open();
        AssertThat(main.game.economy.Glow).IsEqualApprox(0.0, 1.0);
        AssertThat(main.GetNode<Control>("Game/WelcomePanel").Visible).IsFalse();
        Close(main);
    }

    [TestCase]
    public async Task Hidden_a_month_away_pays_eight_hours()
    {
        SavedHive();
        _now += 30.0 * Day;
        Main main = await Open();
        AssertThat(main.game.economy.Glow).IsEqualApprox(28800.0 * 20.0, 1.0);
        Close(main);
    }

    [TestCase]
    public async Task Hidden_a_clock_put_right_again_pays_only_once()
    {
        SavedHive();
        double truth = _now;
        // The clock goes back a day; the player plays for ten minutes and closes the game.
        _now = truth - Day;
        Main main = await Open();
        _now += 600.0;
        Close(main);
        // The next morning the clock is right again, an hour after the first save.
        _now = truth + 3600.0;
        main = await Open();
        AssertThat(main.game.economy.Glow).OverrideFailureMessage("only the hour since the save, not the day the clock was back")
            .IsEqualApprox(3600.0 * 20.0, 5.0);
        Close(main);
        // And opening it again a minute later pays a minute, not the night again.
        double glow = JsonData.Number(new SaveStore(_path).Read().Economy["glow"], -1.0);
        _now += 60.0;
        main = await Open();
        AssertThat(main.game.economy.Glow - glow).IsEqualApprox(60.0 * 20.0, 5.0);
        Close(main);
    }
}

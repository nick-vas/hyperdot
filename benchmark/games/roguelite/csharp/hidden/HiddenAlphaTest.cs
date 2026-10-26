namespace Wickerdeep.Tests;

using System;
using System.IO;
using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden acceptance for the prototype-to-alpha milestone: two floors with shades and cinder bats, Meta's bank and
/// vigor, and a SaveStore that keeps the meta progress and the run in progress, which Continue carries on.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenAlphaTest
{
    private string _path = "";
    private Floors _floors = null!;

    [BeforeTest]
    public void Load()
    {
        _path = Path.Combine(Path.GetTempPath(), $"wickerdeep-hidden-alpha-{Guid.NewGuid():N}.json");
        _floors = Floors.FromFiles();
    }

    [AfterTest]
    public void RemoveFile()
    {
        File.Delete(_path);
    }

    [TestCase]
    public void Hidden_two_floors_with_bats()
    {
        AssertThat(_floors.HasFloor(1)).IsTrue();
        AssertThat(_floors.HasFloor(2)).IsTrue();
        AssertThat(_floors.Spec(2)!.Enemies).Contains("bat");
        EnemyStats bat = _floors.Kind("bat")!;
        AssertThat(bat.Hp).IsEqual(1);
        AssertThat(bat.MoveTicks).IsLess(_floors.Kind("shade")!.MoveTicks);
        for (int seed = 1; seed <= 30; seed++)
            AssertThat(Dungeon.Generate(seed * 1009 + 2, _floors.Spec(2)!).UnreachableCells()).IsEqual(0);
    }

    [TestCase]
    public void Hidden_meta_banks_and_buys()
    {
        var save = new SaveData();
        Meta.Bank(save, 10, 2, true);
        Meta.Bank(save, 7, 1, false);
        AssertThat(save.Meta.Embers).IsEqual(13);
        AssertThat(save.Meta.BestFloor).IsEqual(2);
        AssertThat(save.Meta.Runs).IsEqual(2);
        AssertThat(Meta.BuyVigor(save)).IsTrue();
        AssertThat(save.Meta.Embers).IsEqual(8);
        AssertThat(Meta.BuyVigor(save)).OverrideFailureMessage("the second level costs 10").IsFalse();
        Meta.Bank(save, 8, 1, true);
        AssertThat(Meta.BuyVigor(save)).IsTrue();
        AssertThat(save.Meta.Embers).IsEqual(6);
        AssertThat(save.Meta.Vigor).IsEqual(2);
        AssertThat(Meta.MaxHp(save)).IsEqual(7);
    }

    [TestCase]
    public void Hidden_the_save_keeps_meta_and_the_run()
    {
        var store = new SaveStore(_path);
        var save = new SaveData();
        Meta.Bank(save, 12, 2, true);
        AssertThat(Meta.BuyVigor(save)).IsTrue();
        var run = new Run(31, Meta.MaxHp(save)) { FloorNumber = 2, Hp = 4, Embers = 3 };
        save.Run = run.ToDict();
        AssertThat(store.Write(save)).IsTrue();
        SaveData back = new SaveStore(_path).Read();
        AssertThat(back.Meta.Embers).IsEqual(7);
        AssertThat(back.Meta.Vigor).IsEqual(1);
        Run resumed = Run.FromDict(back.Run!);
        AssertThat(resumed.FloorNumber).IsEqual(2);
        AssertThat(resumed.Hp).IsEqual(4);
        AssertThat(resumed.MaxHp).IsEqual(6);
        AssertThat(resumed.FloorSeed()).IsEqual(run.FloorSeed());
    }

    [TestCase]
    public async Task Hidden_continue_carries_on_the_run()
    {
        var game = GD.Load<PackedScene>("res://game/game.tscn").Instantiate<Game>();
        var run = new Run(31, 6) { FloorNumber = 2, Hp = 4 };
        game.Setup(_floors, LaunchOptions.Parse(Array.Empty<string>()), 6, run.ToDict());
        var tree = (SceneTree)Engine.GetMainLoop();
        tree.Root.AddChild(game);
        try
        {
            for (int i = 0; i < 2; i++)
                await game.ToSignal(tree, SceneTree.SignalName.PhysicsFrame);
            AssertThat(game.floor_number).IsEqual(2);
            AssertThat(game.hp).IsEqual(4);
            AssertThat(game.world!.Dungeon.ToText()).IsEqual(Dungeon.Generate(run.FloorSeed(), _floors.Spec(2)!).ToText());
        }
        finally
        {
            game.QueueFree();
        }
    }
}

namespace Bramblegate.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Selling a tower: the cell is free again, some sap comes back, and the route takes the way it opens.</summary>
[TestSuite]
[RequireGodotRuntime]
public class SellingTest
{
    private Catalog _catalog = null!;

    [BeforeTest]
    public void Load() => _catalog = Catalog.FromFiles();

    [TestCase]
    public void Selling_frees_the_cell_and_pays_some_sap_back()
    {
        Battle battle = Battle.Custom(_catalog, new[] { "S...G", "....." }, 200, 5, new List<WaveRow>());
        battle.Place("thorn", new Vector2I(2, 1));
        int before = battle.Gold;
        int back = battle.Sell(new Vector2I(2, 1));
        AssertThat(back).IsGreater(0);
        AssertThat(battle.Gold).IsEqual(before + back);
        AssertThat(battle.Towers.Has(new Vector2I(2, 1))).IsFalse();
        AssertThat(battle.Map.IsOpen(new Vector2I(2, 1))).IsTrue();
    }

    [TestCase]
    public void Selling_a_tower_on_the_old_route_shortens_it()
    {
        Battle battle = Battle.Custom(_catalog, new[] { "S...G", ".....", "....." }, 200, 5, new List<WaveRow>());
        battle.Place("thorn", new Vector2I(2, 0));
        AssertThat(battle.Map.Route.Count).IsEqual(7);
        battle.Sell(new Vector2I(2, 0));
        AssertThat(battle.Map.Route.Count).IsEqual(5);
    }

    [TestCase]
    public void Nothing_to_sell_on_an_empty_cell()
    {
        Battle battle = Battle.Custom(_catalog, new[] { "S...G", "....." }, 200, 5, new List<WaveRow>());
        AssertThat(battle.Sell(new Vector2I(1, 1))).IsEqual(0);
        AssertThat(battle.Gold).IsEqual(200);
    }
}

namespace Bramblegate.Tests;

using System;
using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the prototype's add-feature: Battle.Sell(cell) gives back 70% of everything paid for the tower,
/// rounded down, frees the cell, and the route and the pests on the field take the way it opens.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenSellTest
{
    private static readonly string[] FieldRows = { "S...G", ".....", "....." };

    private Catalog _catalog = null!;

    [BeforeTest]
    public void Load() => _catalog = Catalog.FromFiles();

    private Battle NewBattle(int gold) => Battle.Custom(_catalog, FieldRows, gold, 5, new List<WaveRow>());

    [TestCase]
    public void Hidden_a_new_tower_gives_back_70_percent()
    {
        Battle battle = NewBattle(200);
        battle.Place("thorn", new Vector2I(2, 1));
        AssertThat(battle.Sell(new Vector2I(2, 1))).IsEqual(35);
        AssertThat(battle.Gold).IsEqual(200 - 50 + 35);
        AssertThat(battle.Towers.Has(new Vector2I(2, 1))).IsFalse();
        AssertThat(battle.Map.IsOpen(new Vector2I(2, 1))).IsTrue();
    }

    [TestCase]
    public void Hidden_upgrades_count_towards_the_refund()
    {
        Battle battle = NewBattle(1000);
        battle.Place("acorn", new Vector2I(2, 2));
        battle.Upgrade(new Vector2I(2, 2));
        int paid = _catalog.Cost("acorn") + _catalog.UpgradeCost("acorn", 2);
        AssertThat(battle.Sell(new Vector2I(2, 2))).IsEqual((int)Math.Floor(paid * 0.7));
        battle.Place("thorn", new Vector2I(1, 2));
        battle.Upgrade(new Vector2I(1, 2));
        battle.Upgrade(new Vector2I(1, 2));
        AssertThat(battle.Sell(new Vector2I(1, 2))).OverrideFailureMessage("70% of 50 + 40 + 70").IsEqual(112);
    }

    [TestCase]
    public void Hidden_selling_never_makes_sap()
    {
        foreach (string id in _catalog.TowerIds)
        {
            foreach (int level in new[] { 1, 2, 3 })
            {
                Battle battle = NewBattle(2000);
                battle.Place(id, new Vector2I(2, 1));
                for (int i = 0; i < level - 1; i++)
                    battle.Upgrade(new Vector2I(2, 1));
                battle.Sell(new Vector2I(2, 1));
                AssertThat(battle.Gold).OverrideFailureMessage($"{id} level {level}").IsLess(2000);
            }
        }
    }

    [TestCase]
    public void Hidden_the_route_and_the_pests_take_the_opened_way()
    {
        Battle battle = NewBattle(500);
        battle.Place("thorn", new Vector2I(2, 0));
        Enemy pest = battle.SpawnAt("beetle", new Vector2I(1, 1));
        pest.Speed = 0.0;
        AssertThat(battle.Map.Route.Count).IsEqual(7);
        battle.Sell(new Vector2I(2, 0));
        AssertThat(battle.Map.Route.Count).IsEqual(5);
        AssertThat(pest.Path.Count).IsEqual(battle.Map.PathFrom(pest.Target()).Count);
        AssertThat(pest.Path[^1]).IsEqual(battle.Map.Store);
    }

    [TestCase]
    public void Hidden_nothing_to_sell_gives_nothing()
    {
        Battle battle = NewBattle(200);
        AssertThat(battle.Sell(new Vector2I(1, 1))).IsEqual(0);
        AssertThat(battle.Gold).IsEqual(200);
        battle.Place("thorn", new Vector2I(1, 1));
        battle.Phase = Phase.Won;
        AssertThat(battle.Sell(new Vector2I(1, 1))).IsEqual(0);
        AssertThat(battle.Towers.Has(new Vector2I(1, 1))).IsTrue();
    }
}

namespace Bramblegate.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Battle's rules: what towers cost, what pests pay and take, losing the map, and which pest a tower shoots.</summary>
[TestSuite]
[RequireGodotRuntime]
public class BattleRulesTest
{
    private static readonly string[] FieldRows = { "S.......", "........", ".......G" };

    private Catalog _catalog = null!;

    [BeforeTest]
    public void Load() => _catalog = Catalog.FromFiles();

    private Battle NewBattle(int gold = 300, int lives = 10) => Battle.Custom(_catalog, FieldRows, gold, lives, new List<WaveRow>());

    /// <summary>A pest that stays where it is put and does not fall to one shot.</summary>
    private static Enemy Still(Battle battle, string id, Vector2I cell)
    {
        Enemy enemy = battle.SpawnAt(id, cell);
        enemy.Speed = 0.0;
        enemy.Hp = 1000;
        return enemy;
    }

    [TestCase]
    public void A_tower_costs_its_price()
    {
        Battle battle = NewBattle(300);
        AssertThat(battle.Place("acorn", new Vector2I(3, 1))).IsTrue();
        AssertThat(battle.Gold).IsEqual(300 - _catalog.Cost("acorn"));
    }

    [TestCase]
    public void A_tower_dearer_than_the_sap_left_cannot_be_placed()
    {
        Battle battle = NewBattle(_catalog.Cost("puff") - 1);
        AssertThat(battle.CanPlace("puff", new Vector2I(3, 1))).IsFalse();
        AssertThat(battle.Place("puff", new Vector2I(3, 1))).IsFalse();
        AssertThat(battle.Towers.Count).IsEqual(0);
        battle.Gold = _catalog.Cost("puff");
        AssertThat(battle.Place("puff", new Vector2I(3, 1))).IsTrue();
        AssertThat(battle.Gold).IsEqual(0);
    }

    [TestCase]
    public void A_fallen_pest_pays_its_reward()
    {
        Battle battle = NewBattle(200);
        battle.Place("thorn", new Vector2I(2, 1));
        Enemy pest = battle.SpawnAt("beetle", new Vector2I(2, 0));
        pest.Speed = 0.0;
        pest.Hp = 1;
        int before = battle.Gold;
        for (int i = 0; i < 30; i++)
            battle.Step();
        AssertThat(pest.Alive).IsFalse();
        AssertThat(battle.Kills).IsEqual(1);
        AssertThat(battle.Gold).IsEqual(before + _catalog.Enemies["beetle"].Reward);
    }

    [TestCase]
    public void A_pest_at_the_store_takes_its_own_number_of_seeds()
    {
        Battle battle = NewBattle(0, 10);
        battle.SpawnAt("beetle", new Vector2I(6, 2));
        for (int i = 0; i < 120; i++)
            battle.Step();
        AssertThat(battle.Leaks).IsEqual(1);
        AssertThat(battle.Lives).IsEqual(10 - _catalog.Enemies["beetle"].Leak);
        AssertThat(_catalog.Enemies["beetle"].Leak).IsEqual(2);
    }

    [TestCase]
    public void The_map_is_lost_when_the_last_seed_goes()
    {
        Battle battle = NewBattle(0, 2);
        var over = new List<bool>();
        battle.BattleOver += won => over.Add(won);
        battle.SpawnAt("beetle", new Vector2I(6, 2));
        for (int i = 0; i < 120; i++)
            battle.Step();
        AssertThat(battle.Lives).IsEqual(0);
        AssertThat(battle.Phase).IsEqual(Phase.Lost);
        AssertThat(over).ContainsExactly(false);
    }

    [TestCase]
    public void A_tower_shoots_only_within_its_range()
    {
        Battle battle = NewBattle();
        battle.Place("thorn", new Vector2I(0, 2));
        Still(battle, "aphid", new Vector2I(3, 2));
        for (int i = 0; i < 10; i++)
            battle.Step();
        AssertThat(battle.Shots.Count).OverrideFailureMessage("3 cells away, past a range of 2.5").IsEqual(0);
        Still(battle, "aphid", new Vector2I(2, 2));
        for (int i = 0; i < 5; i++)
            battle.Step();
        AssertThat(battle.Shots.Count).OverrideFailureMessage("2 cells away").IsEqual(1);
    }

    [TestCase]
    public void A_tower_shoots_the_pest_closest_to_the_store()
    {
        Battle battle = NewBattle();
        battle.Place("thorn", new Vector2I(4, 0));
        Enemy ahead = Still(battle, "aphid", new Vector2I(5, 1));
        Still(battle, "aphid", new Vector2I(2, 1));
        battle.Step();
        AssertThat(battle.Shots.Count).IsEqual(1);
        AssertThat(ReferenceEquals(battle.Shots[0].Target, ahead)).OverrideFailureMessage("the pest ahead is shot").IsTrue();
    }

    [TestCase]
    public void A_splash_hits_every_pest_near_where_it_lands()
    {
        Battle battle = NewBattle();
        battle.Place("acorn", new Vector2I(3, 0));
        Enemy a = Still(battle, "beetle", new Vector2I(5, 2));
        Enemy b = Still(battle, "beetle", new Vector2I(5, 2));
        b.Pos -= new Vector2(0.5f, 0f);
        for (int i = 0; i < 60; i++)
            battle.Step();
        AssertThat(a.Hp).IsLess(1000);
        AssertThat(b.Hp).IsLess(1000);
    }

    [TestCase]
    public void A_puff_slows_the_pests_it_hits()
    {
        Battle battle = NewBattle();
        battle.Place("puff", new Vector2I(3, 0));
        Enemy pest = Still(battle, "beetle", new Vector2I(3, 1));
        pest.Speed = 0.01;
        for (int i = 0; i < 60; i++)
            battle.Step();
        AssertThat(pest.SlowTicks).IsGreater(0);
        AssertThat(pest.Pace()).IsEqualApprox(0.01 * (1.0 - _catalog.Towers["puff"].Slow), 0.0001);
    }
}

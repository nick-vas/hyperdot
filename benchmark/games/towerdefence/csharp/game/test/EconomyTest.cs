namespace Bramblegate.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>The sap: what pests pay when they fall, what a wave pays when it is cleared, and what upgrades cost.</summary>
[TestSuite]
[RequireGodotRuntime]
public class EconomyTest
{
    private Catalog _catalog = null!;

    [BeforeTest]
    public void Load() => _catalog = Catalog.FromFiles();

    [TestCase]
    public void Clearing_a_wave_pays_its_bonus()
    {
        Battle battle = Battle.Custom(_catalog, new[] { "S...G" }, 100, 5, new List<WaveRow> { WaveRow.Of("aphid", 1, 30, 15) });
        battle.StartWave();
        while (battle.Phase == Phase.Wave && battle.Ticks < 2000)
            battle.Step();
        AssertThat(battle.Lives).OverrideFailureMessage("the aphid got to the store").IsEqual(4);
        AssertThat(battle.Gold).IsEqual(115);
    }

    [TestCase]
    public void A_fallen_pest_pays_its_reward()
    {
        Battle battle = Battle.Custom(_catalog, new[] { "S...G" }, 100, 5, new List<WaveRow> { WaveRow.Of("aphid", 1, 30, 0) });
        var paid = new List<int>();
        battle.EnemyKilled += enemy => paid.Add(enemy.Reward);
        battle.StartWave();
        battle.Step();
        battle.Enemies[0].Hp = 1;
        battle.Wound(battle.Enemies[0], 3, 0.0);
        AssertThat(paid).ContainsExactly(_catalog.Enemies["aphid"].Reward);
        AssertThat(battle.Gold).IsEqual(100 + _catalog.Enemies["aphid"].Reward);
    }

    [TestCase]
    public void An_upgrade_costs_its_price_and_raises_the_tower()
    {
        Battle battle = Battle.Custom(_catalog, new[] { "S...G", "....." }, 300, 5, new List<WaveRow>());
        battle.Place("thorn", new Vector2I(1, 1));
        int price = _catalog.UpgradeCost("thorn", 2);
        AssertThat(battle.Upgrade(new Vector2I(1, 1))).IsTrue();
        AssertThat(battle.Gold).IsEqual(300 - _catalog.Cost("thorn") - price);
        AssertThat(battle.Towers[new Vector2I(1, 1)].Level).IsEqual(2);
        AssertThat(_catalog.Stats("thorn", 2).Damage).IsGreater(_catalog.Stats("thorn", 1).Damage);
    }

    [TestCase]
    public void No_upgrade_past_the_last_level_or_without_the_sap()
    {
        Battle battle = Battle.Custom(_catalog, new[] { "S...G", "....." }, 1000, 5, new List<WaveRow>());
        battle.Place("puff", new Vector2I(1, 1));
        AssertThat(battle.Upgrade(new Vector2I(1, 1))).IsTrue();
        AssertThat(battle.Upgrade(new Vector2I(1, 1))).IsTrue();
        AssertThat(battle.Upgrade(new Vector2I(1, 1))).OverrideFailureMessage("level 3 is the last").IsFalse();
        Battle poor = Battle.Custom(_catalog, new[] { "S...G", "....." }, _catalog.Cost("acorn"), 5, new List<WaveRow>());
        poor.Place("acorn", new Vector2I(1, 1));
        AssertThat(poor.Upgrade(new Vector2I(1, 1))).IsFalse();
        AssertThat(poor.Gold).IsEqual(0);
    }
}

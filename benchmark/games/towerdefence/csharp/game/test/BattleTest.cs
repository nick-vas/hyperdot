namespace Bramblegate.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Battle: building, waves and their schedule, the end of a map, and the seed.</summary>
[TestSuite]
[RequireGodotRuntime]
public class BattleTest
{
    private Catalog _catalog = null!;

    [BeforeTest]
    public void Load() => _catalog = Catalog.FromFiles();

    private Battle Field(int gold = 200, List<WaveRow>? waves = null) =>
        Battle.Custom(_catalog, new[] { "S.......", "........", ".......G" }, gold, 10, waves ?? new List<WaveRow>());

    private static void RunWave(Battle battle, int limit = 6000)
    {
        int start = battle.Wave;
        battle.StartWave();
        while (battle.Wave == start + 1 && battle.Phase == Phase.Wave && battle.Ticks < limit)
            battle.Step();
    }

    [TestCase]
    public void Placing_a_tower_spends_its_cost()
    {
        Battle battle = Field(200);
        AssertThat(battle.Place("thorn", new Vector2I(3, 1))).IsTrue();
        AssertThat(battle.Gold).IsEqual(200 - _catalog.Cost("thorn"));
        AssertThat(battle.Towers[new Vector2I(3, 1)].Level).IsEqual(1);
    }

    [TestCase]
    public void A_tower_cannot_go_on_rocks_the_gate_the_store_or_another_tower()
    {
        Battle battle = Battle.Custom(_catalog, new[] { "S.#.", "....", "...G" }, 500, 10, new List<WaveRow>());
        AssertThat(battle.Place("thorn", new Vector2I(2, 0))).OverrideFailureMessage("a rock").IsFalse();
        AssertThat(battle.Place("thorn", new Vector2I(0, 0))).OverrideFailureMessage("the gate").IsFalse();
        AssertThat(battle.Place("thorn", new Vector2I(3, 2))).OverrideFailureMessage("the store").IsFalse();
        AssertThat(battle.Place("thorn", new Vector2I(1, 1))).IsTrue();
        AssertThat(battle.Place("puff", new Vector2I(1, 1))).OverrideFailureMessage("a tower already").IsFalse();
        AssertThat(battle.Place("bramble", new Vector2I(3, 0))).OverrideFailureMessage("no such tower").IsFalse();
    }

    [TestCase]
    public void A_tower_on_the_route_sends_it_round()
    {
        Battle battle = Field();
        Vector2I cell = battle.Map.Route[3];
        AssertThat(battle.Place("thorn", cell)).IsTrue();
        AssertThat(battle.Map.Route).NotContains(cell);
        AssertThat(battle.Map.Route[0]).IsEqual(battle.Map.Gate);
        AssertThat(battle.Map.Route[^1]).IsEqual(battle.Map.Store);
    }

    [TestCase]
    public void No_tower_on_a_cell_a_pest_is_heading_to()
    {
        Battle battle = Field(500, new List<WaveRow> { WaveRow.Of("beetle", 1, 30, 10) });
        battle.StartWave();
        for (int i = 0; i < 80; i++)
            battle.Step();
        Enemy pest = battle.Enemies[0];
        AssertThat(battle.Place("thorn", pest.Target())).IsFalse();
        AssertThat(battle.Place("thorn", pest.Cell())).IsFalse();
    }

    [TestCase]
    public void A_wave_sends_its_pests_on_schedule_from_the_gate()
    {
        Battle battle = Field(100, new List<WaveRow> { WaveRow.Of("aphid", 3, 20, 10) });
        AssertThat(battle.StartWave()).IsTrue();
        battle.Step();
        AssertThat(battle.Enemies.Count).IsEqual(1);
        AssertThat(battle.Enemies[0].Cell()).IsEqual(battle.Map.Gate);
        for (int i = 0; i < 20; i++)
            battle.Step();
        AssertThat(battle.Enemies.Count).IsEqual(2);
        for (int i = 0; i < 20; i++)
            battle.Step();
        AssertThat(battle.Enemies.Count).IsEqual(3);
        AssertThat(battle.Pending()).IsEqual(0);
    }

    [TestCase]
    public void A_wave_cannot_start_while_one_is_under_way()
    {
        Battle battle = Field(100, new List<WaveRow> { WaveRow.Of("aphid", 3, 30, 10), WaveRow.Of("aphid", 3, 30, 10) });
        AssertThat(battle.StartWave()).IsTrue();
        AssertThat(battle.StartWave()).IsFalse();
        AssertThat(battle.Wave).IsEqual(1);
    }

    [TestCase]
    public void The_next_wave_starts_by_itself_after_the_break()
    {
        Battle battle = Field(100, new List<WaveRow> { WaveRow.Of("aphid", 1, 30, 10), WaveRow.Of("aphid", 1, 30, 10) });
        RunWave(battle);
        AssertThat(battle.Phase).IsEqual(Phase.Build);
        AssertThat(battle.BreakLeft).IsEqual(Battle.BreakTicks);
        for (int i = 0; i < Battle.BreakTicks; i++)
            battle.Step();
        AssertThat(battle.Wave).IsEqual(2);
        AssertThat(battle.Phase).IsEqual(Phase.Wave);
    }

    [TestCase]
    public void Clearing_the_last_wave_wins_the_map()
    {
        Battle battle = Field(100, new List<WaveRow> { WaveRow.Of("aphid", 2, 30, 10) });
        var over = new List<bool>();
        battle.BattleOver += won => over.Add(won);
        RunWave(battle);
        AssertThat(battle.Phase).IsEqual(Phase.Won);
        AssertThat(over).ContainsExactly(true);
        AssertThat(battle.Place("thorn", new Vector2I(3, 1))).OverrideFailureMessage("nothing is built once it is over").IsFalse();
    }

    [TestCase]
    public void The_same_seed_plays_the_same_battle()
    {
        Battle a = Battle.Create(_catalog, "meadow", 7)!;
        Battle b = Battle.Create(_catalog, "meadow", 7)!;
        foreach (Battle battle in new[] { a, b })
        {
            battle.Place("thorn", new Vector2I(3, 3));
            battle.StartWave();
            for (int i = 0; i < 400; i++)
                battle.Step();
        }
        AssertThat(a.Enemies.Count).IsEqual(b.Enemies.Count);
        for (int i = 0; i < a.Enemies.Count; i++)
            AssertThat(a.Enemies[i].Pos).IsEqual(b.Enemies[i].Pos);
        AssertThat(a.Gold).IsEqual(b.Gold);
    }

    [TestCase]
    public void Seeds_vary_the_pests_speeds()
    {
        Battle a = Battle.Create(_catalog, "meadow", 1)!;
        Battle b = Battle.Create(_catalog, "meadow", 2)!;
        foreach (Battle battle in new[] { a, b })
        {
            battle.StartWave();
            battle.Step();
        }
        AssertThat(a.Enemies[0].Speed).IsNotEqual(b.Enemies[0].Speed);
    }
}

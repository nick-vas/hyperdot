namespace Wickerdeep.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// World over time: the wick's pace, enemies hunting it round corners, embers, a swarm, and a floor that plays the same
/// twice from one seed.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class WorldTest
{
    private Floors _floors = null!;

    [BeforeTest]
    public void Load()
    {
        _floors = Floors.FromFiles();
    }

    private World MakeWorld(int hp, params string[] rows) => World.Create(Dungeon.FromText(rows), _floors.Kinds, 1, hp, hp);

    [TestCase]
    public void The_wick_steps_once_every_few_ticks()
    {
        World world = MakeWorld(5, "############", "#S.........#", "############");
        for (int i = 0; i < World.WickMoveTicks * 3; i++)
            world.Step(Vector2I.Right, false);
        AssertThat(world.Wick.Cell).IsEqual(new Vector2I(4, 1));
        AssertThat(world.Wick.Facing).IsEqual(Vector2I.Right);
    }

    [TestCase]
    public void Snuffed_enemies_leave_their_embers()
    {
        // Kinds of their own, so the count does not move with the data.
        var kinds = new Dictionary<string, EnemyStats>
        {
            ["brute"] = new EnemyStats { Id = "brute", Hp = 1, Damage = 1, Embers = 3 },
            ["shade"] = new EnemyStats { Id = "shade", Hp = 1, Damage = 1, Embers = 1 },
        };
        World world = World.Create(Dungeon.FromText("#####", "##B##", "#BSs#", "##B##", "#####"), kinds, 1, 20, 20);
        for (int i = 0; i < World.WickAttackTicks * 4; i++)
            world.Step(Vector2I.Zero, true);
        AssertThat(world.Enemies.Count).IsEqual(0);
        AssertThat(world.Embers).IsEqual(10);
    }

    [TestCase]
    public void An_enemy_that_sees_the_wick_hunts_it_round_a_corner()
    {
        World world = MakeWorld(20,
            "#########",
            "#S......#",
            "#.#######",
            "#b......#",
            "#########");
        Actor bat = world.Enemies[0];
        world.Step(Vector2I.Zero, false);
        AssertThat(bat.Alert).OverrideFailureMessage("it saw the wick").IsGreater(0);
        for (int i = 0; i < World.WickMoveTicks * 6; i++)
            world.Step(Vector2I.Right, false);
        AssertThat(world.Wick.Cell).IsEqual(new Vector2I(7, 1));
        for (int i = 0; i < 200; i++)
            world.Step(Vector2I.Zero, false);
        AssertThat(World.Adjacent(bat.Cell, world.Wick.Cell)).OverrideFailureMessage("it followed the wick round the corner").IsTrue();
    }

    [TestCase]
    public void A_swarm_hunts_from_afar()
    {
        World world = World.Create(Dungeon.Generate(7, _floors.Spec(1)!), _floors.Kinds, 7, 5, 5);
        int before = world.Enemies.Count;
        world.AddSwarm(50, _floors.Kind("bat")!);
        AssertThat(world.Enemies.Count).IsEqual(before + 50);
        int[] field = world.Dungeon.DistanceField(world.Wick.Cell);
        for (int i = before; i < world.Enemies.Count; i++)
        {
            Actor bat = world.Enemies[i];
            AssertThat(field[world.Dungeon.Index(bat.Cell)]).OverrideFailureMessage("far from the wick").IsGreaterEqual(6);
            AssertThat(bat.Alert).OverrideFailureMessage("already hunting").IsGreater(0);
        }
    }

    [TestCase]
    public void A_floor_plays_the_same_twice_from_one_seed()
    {
        var runs = new List<string>();
        for (int attempt = 0; attempt < 2; attempt++)
        {
            World world = World.Create(Dungeon.Generate(5 * 1009 + 1, _floors.Spec(1)!), _floors.Kinds, 5 * 1009 + 1, 5, 5);
            var bot = new Bot();
            for (int i = 0; i < 900; i++)
            {
                BotChoice choice = bot.Choose(world);
                world.Step(choice.Move, choice.Attack);
            }
            var cells = new List<string>();
            foreach (Actor enemy in world.Enemies)
                cells.Add(enemy.Cell.ToString());
            runs.Add($"{world.Wick.Cell} {world.Wick.Hp} {world.Embers} {string.Join(",", cells)}");
        }
        AssertThat(runs[1]).IsEqual(runs[0]);
    }
}

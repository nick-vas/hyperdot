namespace Wickerdeep.Tests;

using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// World's rules on small floors drawn by hand: walls and creatures block a step, an enemy sees only so far and never
/// through a wall, strikes only from beside the wick, the wick's blow wounds and snuffs, and the stairs wait for the last
/// enemy.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class WorldRulesTest
{
    private Floors _floors = null!;

    [BeforeTest]
    public void Load()
    {
        _floors = Floors.FromFiles();
    }

    private World MakeWorld(int hp, params string[] rows) => World.Create(Dungeon.FromText(rows), _floors.Kinds, 1, hp, hp);

    private static void Steps(World world, int ticks, Vector2I move, bool attack = false)
    {
        for (int i = 0; i < ticks; i++)
            world.Step(move, attack);
    }

    [TestCase]
    public void A_wall_stops_the_wick()
    {
        World world = MakeWorld(5, "#####", "#S..#", "#####");
        Steps(world, 20, Vector2I.Up);
        AssertThat(world.Wick.Cell).IsEqual(new Vector2I(1, 1));
        Steps(world, 20, Vector2I.Left);
        AssertThat(world.Wick.Cell).IsEqual(new Vector2I(1, 1));
    }

    [TestCase]
    public void The_wick_cannot_step_onto_an_enemy()
    {
        World world = MakeWorld(5, "#######", "#S.s.>#", "#######");
        Steps(world, 40, Vector2I.Right);
        AssertThat(world.Wick.Cell).IsEqual(new Vector2I(2, 1));
        AssertThat(world.Enemies[0].Cell).IsEqual(new Vector2I(3, 1));
    }

    [TestCase]
    public void An_enemy_does_not_see_through_a_wall()
    {
        World world = MakeWorld(5,
            "#########",
            "#S..#..s#",
            "#.......#",
            "#.......#",
            "#########");
        Actor shade = world.Enemies[0];
        AssertThat(world.Sees(shade)).OverrideFailureMessage("the wall is between them").IsFalse();
        shade.Cell = new Vector2I(6, 2);
        AssertThat(world.Sees(shade)).OverrideFailureMessage("a clear line").IsTrue();
    }

    [TestCase]
    public void An_enemy_sees_no_further_than_its_sight()
    {
        World world = MakeWorld(5, "##########", "#S.......#", "##########");
        Actor shade = Actor.FromKind(_floors.Kind("shade")!, new Vector2I(8, 1));
        world.AddEnemy(shade);
        AssertThat(shade.Sight).IsEqual(6);
        AssertThat(world.Sees(shade)).OverrideFailureMessage("seven cells away").IsFalse();
        shade.Cell = new Vector2I(7, 1);
        AssertThat(world.Sees(shade)).OverrideFailureMessage("six cells away").IsTrue();
    }

    [TestCase]
    public void An_enemy_strikes_from_beside_the_wick_not_from_a_diagonal()
    {
        AssertThat(World.Adjacent(new Vector2I(2, 2), new Vector2I(3, 2))).IsTrue();
        AssertThat(World.Adjacent(new Vector2I(2, 2), new Vector2I(2, 1))).IsTrue();
        AssertThat(World.Adjacent(new Vector2I(2, 2), new Vector2I(3, 3))).IsFalse();
        AssertThat(World.Adjacent(new Vector2I(2, 2), new Vector2I(4, 2))).IsFalse();
        World world = MakeWorld(5, "#####", "#Ss.#", "#####");
        Steps(world, World.WindupTicks + 5, Vector2I.Zero);
        AssertThat(world.Wick.Hp).IsEqual(5 - _floors.Kind("shade")!.Damage);
    }

    [TestCase]
    public void The_blow_wounds_the_enemy_the_wick_faces()
    {
        World world = MakeWorld(5, "######", "#.Ss.#", "#.s..#", "######");
        Actor facing = world.Enemies[0];
        world.Step(Vector2I.Right, false);
        AssertThat(world.Wick.Cell).OverrideFailureMessage("the shade is in the way").IsEqual(new Vector2I(2, 1));
        world.Step(Vector2I.Zero, true);
        AssertThat(facing.Hp).OverrideFailureMessage("it faces this shade").IsEqual(_floors.Kind("shade")!.Hp - 1);
        AssertThat(world.Enemies[1].Hp).OverrideFailureMessage("the shade below is spared").IsEqual(_floors.Kind("shade")!.Hp);
    }

    [TestCase]
    public void An_enemy_at_no_hp_is_snuffed()
    {
        World world = MakeWorld(5, "######", "#Ss..#", "#..s.#", "#...>#", "######");
        Actor shade = world.Enemies[0];
        shade.Hp = 1;
        world.Step(Vector2I.Zero, true);
        AssertThat(world.Enemies.Count).IsEqual(1);
        AssertThat(world.Enemies.Contains(shade)).IsFalse();
        AssertThat(world.Embers).IsEqual(_floors.Kind("shade")!.Embers);
        AssertThat(world.EnemyAt(new Vector2I(2, 1))).OverrideFailureMessage("its cell is free").IsNull();
    }

    [TestCase]
    public void The_stairs_open_only_when_every_enemy_is_gone()
    {
        World world = MakeWorld(20,
            "#######",
            "#.bS>.#",
            "#.....#",
            "#b....#",
            "#######");
        AssertThat(world.StairsOpen).IsFalse();
        world.Step(Vector2I.Zero, true);
        AssertThat(world.Enemies.Count).OverrideFailureMessage("the bat beside the wick is snuffed").IsEqual(1);
        AssertThat(world.StairsOpen).OverrideFailureMessage("one bat left").IsFalse();
        Steps(world, 5, Vector2I.Right);
        AssertThat(world.Wick.Cell).OverrideFailureMessage("on the stairs").IsEqual(new Vector2I(4, 1));
        AssertThat(world.Done).OverrideFailureMessage("the stairs are shut").IsFalse();
        world.Enemies[0].Hp = 1;
        for (int i = 0; i < 300; i++)
        {
            world.Step(Vector2I.Zero, true);
            if (world.Enemies.Count == 0)
                break;
        }
        AssertThat(world.StairsOpen).IsTrue();
        world.Step(Vector2I.Zero, false);
        AssertThat(world.Done).OverrideFailureMessage("the wick stands on the open stairs").IsTrue();
    }
}

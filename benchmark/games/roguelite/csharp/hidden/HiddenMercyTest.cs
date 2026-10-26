namespace Wickerdeep.Tests;

using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the prototype's add-feature: mercy. A hurt that lands gives the wick World.MercyTicks (30) ticks of
/// mercy, counted down by World.Step; hurts during mercy take nothing, from HurtWick or from enemies' blows.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenMercyTest
{
    private Floors _floors = null!;

    [BeforeTest]
    public void Load()
    {
        _floors = Floors.FromFiles();
    }

    private World MakeWorld(params string[] rows) => World.Create(Dungeon.FromText(rows), _floors.Kinds, 1, 5, 5);

    [TestCase]
    public void Hidden_mercy_lasts_thirty_ticks()
    {
        AssertThat(World.MercyTicks).IsEqual(30);
        World world = MakeWorld("#####", "#S.>#", "#####");
        AssertThat(world.Wick.Mercy).IsEqual(0);
        world.HurtWick(1);
        AssertThat(world.Wick.Hp).IsEqual(4);
        AssertThat(world.Wick.Mercy).IsEqual(30);
        for (int i = 0; i < 29; i++)
            world.Step(Vector2I.Zero, false);
        world.HurtWick(1);
        AssertThat(world.Wick.Hp).OverrideFailureMessage("tick 29: still mercy").IsEqual(4);
        world.Step(Vector2I.Zero, false);
        AssertThat(world.Wick.Mercy).IsEqual(0);
        world.HurtWick(2);
        AssertThat(world.Wick.Hp).OverrideFailureMessage("mercy is over").IsEqual(2);
    }

    [TestCase]
    public void Hidden_a_hurt_that_misses_gives_no_new_mercy()
    {
        World world = MakeWorld("#####", "#S.>#", "#####");
        world.HurtWick(1);
        for (int i = 0; i < 10; i++)
            world.Step(Vector2I.Zero, false);
        world.HurtWick(1);
        AssertThat(world.Wick.Mercy).OverrideFailureMessage("the second hurt did not start mercy again").IsEqual(20);
    }

    [TestCase]
    public void Hidden_blows_respect_mercy()
    {
        World world = MakeWorld("#######", "#.sSs.#", "#..s..#", "#######");
        for (int i = 0; i < World.WindupTicks + 5; i++)
            world.Step(Vector2I.Zero, false);
        AssertThat(world.Wick.Hp).OverrideFailureMessage("three shades strike together, one blow lands").IsEqual(4);
        for (int i = 0; i < 45; i++)
            world.Step(Vector2I.Zero, false);
        AssertThat(world.Wick.Hp).OverrideFailureMessage("after mercy, blows land again").IsLess(4);
    }
}

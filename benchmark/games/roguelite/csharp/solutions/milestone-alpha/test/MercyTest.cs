namespace Wickerdeep.Tests;

using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Mercy: after a hurt the wick cannot be hurt again for World.MercyTicks ticks, so a crowd cannot drain it in one go.</summary>
[TestSuite]
[RequireGodotRuntime]
public class MercyTest
{
    private Floors _floors = null!;

    [BeforeTest]
    public void Load()
    {
        _floors = Floors.FromFiles();
    }

    [TestCase]
    public void A_hurt_gives_mercy_for_a_while()
    {
        World world = World.Create(Dungeon.FromText("#####", "#S.>#", "#####"), _floors.Kinds, 1, 5, 5);
        world.HurtWick(1);
        world.HurtWick(1);
        AssertThat(world.Wick.Hp).OverrideFailureMessage("the second hurt came during mercy").IsEqual(4);
        for (int i = 0; i < World.MercyTicks; i++)
            world.Step(Vector2I.Zero, false);
        world.HurtWick(1);
        AssertThat(world.Wick.Hp).OverrideFailureMessage("mercy is over").IsEqual(3);
    }

    [TestCase]
    public void Two_enemies_beside_the_wick_hurt_it_once_at_first()
    {
        World world = World.Create(Dungeon.FromText("#####", "#sSs#", "#####"), _floors.Kinds, 1, 5, 5);
        for (int i = 0; i < World.WindupTicks + 5; i++)
            world.Step(Vector2I.Zero, false);
        AssertThat(world.Wick.Hp).IsEqual(4);
    }
}

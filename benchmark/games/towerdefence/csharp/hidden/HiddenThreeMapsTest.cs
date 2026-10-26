namespace Bramblegate.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Hidden acceptance for the alpha-to-beta milestone: the Briar Maze and its slug queen, the moth, and three fair maps.</summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenThreeMapsTest
{
    private Catalog _catalog = null!;

    [BeforeTest]
    public void Load() => _catalog = Catalog.FromFiles();

    [TestCase]
    public void Hidden_the_briar_maze_ends_with_the_slug_queen()
    {
        AssertThat(_catalog.MapCount).IsEqual(3);
        AssertThat(_catalog.MapAt(3)!.Id).IsEqual("briar");
        var waves = _catalog.WavesFor("briar");
        AssertThat(waves.Count).IsEqual(6);
        bool found = false;
        foreach (GroupRow group in waves[5].Groups)
            found = found || group.Enemy == "slug_queen";
        AssertThat(found).IsTrue();
        AssertThat(_catalog.Enemies["slug_queen"].Hp).IsBetween(600, 2400);
        AssertThat(_catalog.Enemies["slug_queen"].Leak).IsEqual(20);
    }

    [TestCase]
    public void Hidden_the_moth_is_the_fastest_pest()
    {
        foreach (string id in _catalog.EnemyIds)
        {
            if (id != "moth")
                AssertThat(_catalog.Enemies[id].Speed).OverrideFailureMessage(id).IsLess(_catalog.Enemies["moth"].Speed);
        }
    }

    [TestCase]
    public void Hidden_every_map_is_fair()
    {
        foreach (MapRow row in _catalog.Maps)
        {
            foreach (int seed in new[] { 1, 2, 3 })
            {
                Battle battle = Battle.Create(_catalog, row.Id, seed)!;
                AssertThat(Bot.Play(battle)).OverrideFailureMessage($"{row.Id}, seed {seed}: lost at wave {battle.Wave}").IsTrue();
            }
            AssertThat(Bot.Idle(Battle.Create(_catalog, row.Id, 1)!)).OverrideFailureMessage(row.Id).IsFalse();
        }
    }
}

namespace Bramblegate.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the beta's fix-playthrough: the slug queen is a boss the bot can beat, not a wall, and not a
/// pushover; the Briar Maze stays fair.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenQueenTest
{
    private Catalog _catalog = null!;

    [BeforeTest]
    public void Load() => _catalog = Catalog.FromFiles();

    [TestCase]
    public void Hidden_the_queen_is_the_toughest_pest_within_reason()
    {
        EnemyRow queen = _catalog.Enemies["slug_queen"];
        AssertThat(queen.Hp).IsBetween(600, 2400);
        foreach (string id in _catalog.EnemyIds)
        {
            if (id != "slug_queen")
                AssertThat(queen.Hp).OverrideFailureMessage(id).IsGreater(_catalog.Enemies[id].Hp * 5);
        }
    }

    [TestCase]
    public void Hidden_the_queen_ends_the_briar_maze()
    {
        var waves = _catalog.WavesFor("briar");
        AssertThat(waves.Count).IsEqual(6);
        bool found = false;
        foreach (GroupRow group in waves[5].Groups)
            found = found || group.Enemy == "slug_queen";
        AssertThat(found).IsTrue();
    }

    [TestCase]
    public void Hidden_the_briar_maze_is_fair()
    {
        foreach (int seed in new[] { 1, 2, 3 })
        {
            Battle battle = Battle.Create(_catalog, "briar", seed)!;
            AssertThat(Bot.Play(battle)).OverrideFailureMessage($"seed {seed}: lost at wave {battle.Wave}").IsTrue();
        }
        AssertThat(Bot.Idle(Battle.Create(_catalog, "briar", 1)!)).IsFalse();
    }
}
